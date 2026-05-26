# SageMaker-compatible scikit-learn container.
#
# Uses the official AWS sklearn base image which provides:
#   - /opt/ml/ directory structure that SageMaker expects
#   - the multi-model server that handles invocation requests
#   - Python 3.10 + scikit-learn pre-installed
#
#  Add training script and the inference handler on top.
#
# Build:
#   docker build -t ai-sec-analyst-anomaly:latest .
# Run training locally:
#   docker run --rm -v $(pwd)/mock-data:/opt/ml ai-sec-analyst-anomaly:latest train

FROM public.ecr.aws/sagemaker/sagemaker-distribution:1.10.1-cpu

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
# the container is invoked as an inference endpoint.
ENTRYPOINT ["python", "/opt/ml/code/train.py"]
