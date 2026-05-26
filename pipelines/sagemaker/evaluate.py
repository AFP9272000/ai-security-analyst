"""
SageMaker evaluation step.

Loads the trained model from /opt/ml/processing/model (the model.tar.gz
extracted by SageMaker), runs predictions on the validation set, and
writes evaluation.json with metrics the conditional register step reads.

Key metric: `anomaly_rate`, fraction of validation rows flagged anomalous.
The pipeline registers the model only if this is below the configured
threshold (default 5%). Higher rates suggest the contamination
hyperparameter was set too aggressively or the data has fundamental
quality issues.
"""
from __future__ import annotations

import json
import logging
import sys
import tarfile
from pathlib import Path

import joblib
import pandas as pd

# Add the model code dir so we can import feature_engineering
sys.path.insert(0, "/opt/ml/processing/model")
sys.path.insert(0, "/opt/ml/code")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


MODEL_DIR = Path("/opt/ml/processing/model")
VALIDATION_DIR = Path("/opt/ml/processing/validation")
OUTPUT_DIR = Path("/opt/ml/processing/evaluation")


def extract_model_tarball() -> Path:
    """SageMaker delivers the model as model.tar.gz; extract it."""
    tarball = MODEL_DIR / "model.tar.gz"
    if tarball.exists():
        logger.info("Extracting %s", tarball)
        with tarfile.open(tarball) as tar:
            tar.extractall(MODEL_DIR)
    # Look for the joblib in the extracted contents
    candidates = list(MODEL_DIR.rglob("model.joblib"))
    if not candidates:
        raise FileNotFoundError(f"No model.joblib found in {MODEL_DIR}")
    return candidates[0]


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Load model
    model_path = extract_model_tarball()
    model = joblib.load(model_path)
    logger.info("Loaded model from %s", model_path)

    # Make feature_engineering importable - it should have been packaged
    # into the model directory by train.py via SageMaker source-dir
    sys.path.insert(0, str(model_path.parent))
    try:
        from feature_engineering import extract_features
    except ImportError:
        # Fallback: feature_engineering may be packaged inside the tarball
        # at a different relative path
        candidates = list(MODEL_DIR.rglob("feature_engineering.py"))
        if candidates:
            sys.path.insert(0, str(candidates[0].parent))
            from feature_engineering import extract_features  # type: ignore
        else:
            raise

    # Load validation
    val_files = list(VALIDATION_DIR.glob("*.parquet"))
    if not val_files:
        logger.error("No validation parquet found in %s", VALIDATION_DIR)
        return 1

    val_df = pd.concat([pd.read_parquet(f) for f in val_files], ignore_index=True)
    logger.info("Loaded %d validation rows", len(val_df))

    # Run inference
    features = extract_features(val_df)
    predictions = model.predict(features)
    scores = model.decision_function(features)

    n_anomalies = int((predictions == -1).sum())
    anomaly_rate = float(n_anomalies / len(predictions))
    mean_score = float(scores.mean())
    min_score = float(scores.min())
    max_score = float(scores.max())

    report = {
        "anomaly_rate": anomaly_rate,
        "anomalies_detected": n_anomalies,
        "total_validation_rows": int(len(predictions)),
        "score_statistics": {
            "mean": mean_score,
            "min": min_score,
            "max": max_score,
        },
    }

    report_path = OUTPUT_DIR / "evaluation.json"
    report_path.write_text(json.dumps(report, indent=2))
    logger.info("Wrote evaluation report: %s", report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
