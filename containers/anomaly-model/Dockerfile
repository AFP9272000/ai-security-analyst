# SageMaker-compatible scikit-learn container.
#
# Base: sagemaker-distribution (CPU). Provides Python 3.10 + sklearn +
# the /opt/ml directory conventions and model server.
#
# IMPORTANT: this base image runs as a NON-root user (sagemaker-user)
# by default. SageMaker pre-creates processing/training output dirs
# (/opt/ml/processing/*, /opt/ml/model) owned by root, so a non-root
# process gets PermissionError on write. We switch to USER root so the
# container can write its outputs. SageMaker's own framework containers
# run as root for the same reason.
#
# Build:
#   docker build -t ai-sec-analyst-anomaly:latest .

FROM public.ecr.aws/sagemaker/sagemaker-distribution:1.10.1-cpu

# Need root to install packages and to write SageMaker's root-owned
# input/output mounts at job runtime.
USER root

# Install extra dependencies beyond the base image's sklearn stack
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# SageMaker training/inference code conventions:
#   /opt/ml/code/   - script source code
#   /opt/ml/input/  - training data + hyperparameters (read-only)
#   /opt/ml/model/  - trained model output
#   /opt/ml/output/ - failure logs and metadata
ENV SAGEMAKER_PROGRAM=train.py
ENV SAGEMAKER_SUBMIT_DIRECTORY=/opt/ml/code
ENV PATH="/opt/ml/code:${PATH}"

COPY train.py /opt/ml/code/train.py
COPY inference.py /opt/ml/code/inference.py
COPY feature_engineering.py /opt/ml/code/feature_engineering.py

# Default to training mode; SageMaker overrides this with "serve" when
# the container is invoked as an inference endpoint, and ScriptProcessor
# overrides it entirely for the preprocess/evaluate steps.
ENTRYPOINT ["python", "/opt/ml/code/train.py"]
