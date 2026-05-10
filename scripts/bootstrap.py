#!/usr/bin/env python3
"""
Phase 1.0 bootstrap for ai-security-analyst.

Provisions one-time foundation resources in the AWS Management account:
  - KMS CMK for Terraform state encryption
  - S3 bucket for Terraform state (versioned, encrypted, TLS-only)
  - DynamoDB table for Terraform state locking
  - GitHub OIDC identity provider
  - IAM role assumable by GitHub Actions for IaC deployments

Run ONCE with admin credentials in the Management account.
Idempotent: safe to re-run; existing resources are detected and reused.

Usage:
    pip install -r requirements.txt
    aws configure --profile bootstrap   # use the bootstrap admin user creds
    AWS_PROFILE=bootstrap python3 scripts/bootstrap.py
"""

import json
import sys
from typing import Dict

import boto3
from botocore.exceptions import ClientError

# CONFIG
PROJECT = "ai-sec-analyst"
REGION = "us-east-2"
GITHUB_ORG = "AFP9272000"
GITHUB_REPO = "ai-security-analyst"

# Allowed GitHub Actions contexts that can assume the role.
# Format reference: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#example-subject-claims
ALLOWED_REFS = [
    f"repo:{GITHUB_ORG}/{GITHUB_REPO}:ref:refs/heads/main",
    f"repo:{GITHUB_ORG}/{GITHUB_REPO}:environment:prod",
    f"repo:{GITHUB_ORG}/{GITHUB_REPO}:pull_request",
]

# Derived names

KMS_ALIAS = f"alias/{PROJECT}-tfstate"
LOCK_TABLE = f"{PROJECT}-tflocks"
OIDC_URL = "https://token.actions.githubusercontent.com"
OIDC_AUDIENCE = "sts.amazonaws.com"
ROLE_NAME = "gha-bootstrap-role"

COMMON_TAGS = [
    {"Key": "Project", "Value": PROJECT},
    {"Key": "Layer", "Value": "00-bootstrap"},
    {"Key": "ManagedBy", "Value": "bootstrap-script"},
    {"Key": "Environment", "Value": "prod"},
    {"Key": "CostCenter", "Value": "portfolio"},
]


def log(msg: str) -> None:
    print(f"[bootstrap] {msg}", flush=True)


def get_account_id() -> str:
    return boto3.client("sts").get_caller_identity()["Account"]


# KMS CMK for state encryption

def create_kms_key(account_id: str) -> str:
    kms = boto3.client("kms", region_name=REGION)

    try:
        resp = kms.describe_key(KeyId=KMS_ALIAS)
        log(f"KMS key already exists: {resp['KeyMetadata']['Arn']}")
        return resp["KeyMetadata"]["Arn"]
    except ClientError as e:
        if e.response["Error"]["Code"] != "NotFoundException":
            raise

    log("Creating KMS CMK for state encryption...")
    key_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "EnableRoot",
                "Effect": "Allow",
                "Principal": {"AWS": f"arn:aws:iam::{account_id}:root"},
                "Action": "kms:*",
                "Resource": "*",
            }
        ],
    }

    resp = kms.create_key(
        Description=f"Terraform state encryption for {PROJECT}",
        KeyUsage="ENCRYPT_DECRYPT",
        KeySpec="SYMMETRIC_DEFAULT",
        Policy=json.dumps(key_policy),
        Tags=[{"TagKey": t["Key"], "TagValue": t["Value"]} for t in COMMON_TAGS],
    )
    key_arn = resp["KeyMetadata"]["Arn"]
    key_id = resp["KeyMetadata"]["KeyId"]

    kms.create_alias(AliasName=KMS_ALIAS, TargetKeyId=key_id)
    kms.enable_key_rotation(KeyId=key_id)
    log(f"Created KMS key: {key_arn}")
    return key_arn


# S3 state bucket

def create_state_bucket(account_id: str, kms_key_arn: str) -> str:
    s3 = boto3.client("s3", region_name=REGION)
    bucket_name = f"{PROJECT}-tfstate-{account_id}"

    try:
        s3.head_bucket(Bucket=bucket_name)
        log(f"State bucket already exists: {bucket_name}")
        return bucket_name
    except ClientError as e:
        if e.response["Error"]["Code"] not in ("404", "NoSuchBucket"):
            if e.response["Error"]["Code"] != "403":
                raise

    log(f"Creating state bucket: {bucket_name}")
    if REGION == "us-east-1":
        s3.create_bucket(Bucket=bucket_name)
    else:
        s3.create_bucket(
            Bucket=bucket_name,
            CreateBucketConfiguration={"LocationConstraint": REGION},
        )

    s3.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration={
            "BlockPublicAcls": True,
            "IgnorePublicAcls": True,
            "BlockPublicPolicy": True,
            "RestrictPublicBuckets": True,
        },
    )

    s3.put_bucket_versioning(
        Bucket=bucket_name,
        VersioningConfiguration={"Status": "Enabled"},
    )

    s3.put_bucket_encryption(
        Bucket=bucket_name,
        ServerSideEncryptionConfiguration={
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": kms_key_arn,
                    },
                    "BucketKeyEnabled": True,
                }
            ]
        },
    )

    bucket_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DenyInsecureTransport",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    f"arn:aws:s3:::{bucket_name}",
                    f"arn:aws:s3:::{bucket_name}/*",
                ],
                "Condition": {"Bool": {"aws:SecureTransport": "false"}},
            },
            {
                "Sid": "DenyUnencryptedPuts",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:PutObject",
                "Resource": f"arn:aws:s3:::{bucket_name}/*",
                "Condition": {
                    "StringNotEquals": {
                        "s3:x-amz-server-side-encryption": "aws:kms"
                    }
                },
            },
        ],
    }
    s3.put_bucket_policy(Bucket=bucket_name, Policy=json.dumps(bucket_policy))

    s3.put_bucket_tagging(
        Bucket=bucket_name,
        Tagging={"TagSet": COMMON_TAGS},
    )

    log(f"Created and hardened state bucket: {bucket_name}")
    return bucket_name


# DynamoDB lock table

def create_lock_table() -> str:
    ddb = boto3.client("dynamodb", region_name=REGION)

    try:
        ddb.describe_table(TableName=LOCK_TABLE)
        log(f"Lock table already exists: {LOCK_TABLE}")
        return LOCK_TABLE
    except ClientError as e:
        if e.response["Error"]["Code"] != "ResourceNotFoundException":
            raise

    log(f"Creating DynamoDB lock table: {LOCK_TABLE}")
    ddb.create_table(
        TableName=LOCK_TABLE,
        AttributeDefinitions=[{"AttributeName": "LockID", "AttributeType": "S"}],
        KeySchema=[{"AttributeName": "LockID", "KeyType": "HASH"}],
        BillingMode="PAY_PER_REQUEST",
        SSESpecification={"Enabled": True},
        Tags=COMMON_TAGS,
    )

    ddb.get_waiter("table_exists").wait(TableName=LOCK_TABLE)
    log(f"Lock table ready: {LOCK_TABLE}")
    return LOCK_TABLE


# GitHub OIDC provider

def create_oidc_provider(account_id: str) -> str:
    iam = boto3.client("iam")
    expected_arn = (
        f"arn:aws:iam::{account_id}:oidc-provider/token.actions.githubusercontent.com"
    )

    try:
        iam.get_open_id_connect_provider(OpenIDConnectProviderArn=expected_arn)
        log(f"OIDC provider already exists: {expected_arn}")
        return expected_arn
    except ClientError as e:
        if e.response["Error"]["Code"] != "NoSuchEntity":
            raise

    log("Creating GitHub OIDC provider...")
    # AWS now manages thumbprint validation for the GitHub OIDC provider,
    # but the API still requires a value. The thumbprint below is the
    # historical GitHub Actions thumbprint and is no longer enforced.
    resp = iam.create_open_id_connect_provider(
        Url=OIDC_URL,
        ClientIDList=[OIDC_AUDIENCE],
        ThumbprintList=["6938fd4d98bab03faadb97b34396831e3780aea1"],
        Tags=COMMON_TAGS,
    )
    log(f"Created OIDC provider: {resp['OpenIDConnectProviderArn']}")
    return resp["OpenIDConnectProviderArn"]


# IAM role for GitHub Actions

def create_bootstrap_role(account_id: str, oidc_arn: str) -> str:
    iam = boto3.client("iam")

    trust_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Federated": oidc_arn},
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                    "StringEquals": {
                        "token.actions.githubusercontent.com:aud": OIDC_AUDIENCE,
                    },
                    "StringLike": {
                        "token.actions.githubusercontent.com:sub": ALLOWED_REFS,
                    },
                },
            }
        ],
    }

    try:
        iam.get_role(RoleName=ROLE_NAME)
        log(f"Role exists, updating trust policy: {ROLE_NAME}")
        iam.update_assume_role_policy(
            RoleName=ROLE_NAME,
            PolicyDocument=json.dumps(trust_policy),
        )
    except ClientError as e:
        if e.response["Error"]["Code"] != "NoSuchEntity":
            raise
        log(f"Creating role: {ROLE_NAME}")
        iam.create_role(
            RoleName=ROLE_NAME,
            AssumeRolePolicyDocument=json.dumps(trust_policy),
            Description=f"GitHub Actions execution role for {PROJECT}",
            MaxSessionDuration=3600,
            Tags=COMMON_TAGS,
        )

    # AdministratorAccess for now. Phase 1.5 replaces this with
    # layer-scoped policies and per-account assume-role chains.
    iam.attach_role_policy(
        RoleName=ROLE_NAME,
        PolicyArn="arn:aws:iam::aws:policy/AdministratorAccess",
    )

    role_arn = f"arn:aws:iam::{account_id}:role/{ROLE_NAME}"
    log(f"Role ready: {role_arn}")
    return role_arn

# Backend config emitter

def emit_backend_config(outputs: Dict[str, str]) -> str:
    """Generate the backend.hcl content for Terraform layers."""
    return f"""# Generated by bootstrap.py - commit this file to the repo.
# Each TF layer references it via:
#   terraform init -backend-config=../backend.hcl -backend-config="key=<layer>/terraform.tfstate"

bucket         = "{outputs['bucket']}"
region         = "{outputs['region']}"
dynamodb_table = "{outputs['lock_table']}"
encrypt        = true
kms_key_id     = "{outputs['kms_key_arn']}"
"""


# Main

def main() -> int:
    log("Starting bootstrap...")

    try:
        account_id = get_account_id()
    except ClientError as e:
        log("ERROR: Cannot get caller identity. Are AWS credentials configured?")
        log(f"  {e}")
        return 1

    log(f"Operating in Management account: {account_id}")
    log(f"Region: {REGION}")
    log(f"GitHub repo: {GITHUB_ORG}/{GITHUB_REPO}")
    log("")

    kms_key_arn = create_kms_key(account_id)
    bucket_name = create_state_bucket(account_id, kms_key_arn)
    table_name = create_lock_table()
    oidc_arn = create_oidc_provider(account_id)
    role_arn = create_bootstrap_role(account_id, oidc_arn)

    outputs = {
        "account_id": account_id,
        "region": REGION,
        "kms_key_arn": kms_key_arn,
        "bucket": bucket_name,
        "lock_table": table_name,
        "oidc_arn": oidc_arn,
        "role_arn": role_arn,
    }

    backend_hcl = emit_backend_config(outputs)
    with open("backend.hcl", "w") as f:
        f.write(backend_hcl)

    log("")
    log("=" * 60)
    log("BOOTSTRAP COMPLETE")
    log("=" * 60)
    for k, v in outputs.items():
        log(f"  {k:<14} {v}")
    log("")
    log("Wrote backend.hcl - move it to iac/terraform/backend.hcl and commit.")
    log("")
    log("Next steps:")
    log("  1. Move backend.hcl into iac/terraform/ and commit.")
    log("  2. Set GitHub repo secret AWS_GHA_ROLE_ARN to:")
    log(f"       {role_arn}")
    log("  3. Delete the bootstrap IAM user's access keys you used to run this.")
    log("  4. Proceed to Phase 1.1 (Organizations).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
