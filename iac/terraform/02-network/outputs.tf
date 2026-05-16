# Workload VPC outputs

output "workload_vpc_id" {
  value = module.workload_vpc.vpc_id
}

output "workload_vpc_cidr" {
  value = module.workload_vpc.vpc_cidr_block
}

output "workload_public_subnet_ids" {
  value = module.workload_vpc.public_subnet_ids
}

output "workload_private_subnet_ids" {
  value = module.workload_vpc.private_subnet_ids
}

output "workload_database_subnet_ids" {
  value = module.workload_vpc.database_subnet_ids
}

output "workload_endpoint_sg_id" {
  value = aws_security_group.workload_endpoints.id
}

# Security Tooling VPC outputs

output "security_tooling_vpc_id" {
  value = module.security_tooling_vpc.vpc_id
}

output "security_tooling_vpc_cidr" {
  value = module.security_tooling_vpc.vpc_cidr_block
}

output "security_tooling_private_subnet_ids" {
  value = module.security_tooling_vpc.private_subnet_ids
}

output "security_tooling_endpoint_sg_id" {
  value = aws_security_group.security_tooling_endpoints.id
}

# Summary

output "interface_endpoint_count" {
  description = "Total interface endpoints (informational; main cost driver in this layer)"
  value = (
    length(local.security_tooling_interface_endpoints) +
    length(local.workload_interface_endpoints)
  )
}
