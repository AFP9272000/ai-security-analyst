"""
SageMaker training entrypoint for the CloudTrail anomaly detection model.

SageMaker invokes this as `python train.py` inside the container. By
convention, training data is at /opt/ml/input/data/<channel>/, hyperparameters
at /opt/ml/input/config/hyperparameters.json, and the trained model goes
to /opt/ml/model/. SageMaker tars /opt/ml/model after training and uploads
to S3.

Hyperparameters (from /opt/ml/input/config/hyperparameters.json):
    n_estimators: number of trees (default 100)
    contamination: expected fraction of anomalies (default 0.01)
    random_state: RNG seed (default 42)
    max_samples: subsample size per tree (default 256)
"""
from __future__ import annotations

import json
import logging
import os
import sys
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import IsolationForest

# Make feature module importable when SageMaker runs this script
sys.path.insert(0, "/opt/ml/code")
from feature_engineering import FEATURE_COLUMNS, extract_features  # noqa: E402

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


# SageMaker conventions
TRAINING_DIR = Path(os.environ.get("SM_CHANNEL_TRAINING", "/opt/ml/input/data/training"))
MODEL_DIR = Path(os.environ.get("SM_MODEL_DIR", "/opt/ml/model"))
HYPERPARAMETERS_PATH = Path("/opt/ml/input/config/hyperparameters.json")
OUTPUT_FAILURE_PATH = Path("/opt/ml/output/failure")


def load_hyperparameters() -> dict:
    """Read SageMaker hyperparameters JSON, with defaults for local testing."""
    defaults = {
        "n_estimators": 100,
        "contamination": 0.01,
        "random_state": 42,
        "max_samples": 256,
    }
    if not HYPERPARAMETERS_PATH.exists():
        logger.info("No hyperparameters file; using defaults")
        return defaults

    raw = json.loads(HYPERPARAMETERS_PATH.read_text())
    # SageMaker passes all values as strings; coerce types
    coerced = {**defaults}
    for key, default_value in defaults.items():
        if key in raw:
            try:
                coerced[key] = type(default_value)(raw[key])
            except (TypeError, ValueError):
                logger.warning("Could not coerce %s=%r; using default %r",
                               key, raw[key], default_value)
    logger.info("Hyperparameters: %s", coerced)
    return coerced


def load_training_data() -> pd.DataFrame:
    """Concatenate all parquet/csv files from the training channel."""
    files = sorted(TRAINING_DIR.glob("**/*"))
    parquet_files = [f for f in files if f.suffix == ".parquet"]
    csv_files = [f for f in files if f.suffix == ".csv"]

    if not parquet_files and not csv_files:
        raise RuntimeError(f"No training files found in {TRAINING_DIR}")

    frames = []
    for path in parquet_files:
        logger.info("Loading %s", path)
        frames.append(pd.read_parquet(path))
    for path in csv_files:
        logger.info("Loading %s", path)
        frames.append(pd.read_csv(path))

    df = pd.concat(frames, ignore_index=True)
    logger.info("Training data shape: %s", df.shape)
    return df


def train(df: pd.DataFrame, hyperparameters: dict) -> IsolationForest:
    """Engineer features and fit the IsolationForest."""
    logger.info("Engineering features for %d rows", len(df))
    features = extract_features(df)
    logger.info("Feature matrix shape: %s", features.shape)

    if features.empty:
        raise RuntimeError("Feature engineering produced empty dataframe")

    model = IsolationForest(
        n_estimators=hyperparameters["n_estimators"],
        contamination=hyperparameters["contamination"],
        random_state=hyperparameters["random_state"],
        max_samples=min(hyperparameters["max_samples"], len(features)),
        n_jobs=-1,
    )
    logger.info("Fitting IsolationForest")
    model.fit(features)

    # Quick sanity check: predict on training data, log anomaly distribution
    predictions = model.predict(features)
    n_anomalies = (predictions == -1).sum()
    logger.info("Training distribution: %d anomalies out of %d (%.2f%%)",
                n_anomalies, len(predictions), 100.0 * n_anomalies / len(predictions))

    return model


def save_model(model: IsolationForest) -> None:
    """Persist the model + feature schema for inference."""
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    model_path = MODEL_DIR / "model.joblib"
    joblib.dump(model, model_path)
    logger.info("Saved model to %s", model_path)

    # Save feature contract alongside the model. Inference loads this to
    # validate that incoming records produce the expected feature schema.
    schema_path = MODEL_DIR / "feature_columns.json"
    schema_path.write_text(json.dumps(FEATURE_COLUMNS))
    logger.info("Saved feature schema to %s", schema_path)


def main() -> int:
    try:
        hyperparameters = load_hyperparameters()
        df = load_training_data()
        model = train(df, hyperparameters)
        save_model(model)
        logger.info("Training complete")
        return 0
    except Exception as exc:  # noqa: BLE001
        logger.exception("Training failed")
        OUTPUT_FAILURE_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_FAILURE_PATH.write_text(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
