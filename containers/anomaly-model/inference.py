"""
SageMaker inference handler.

Loaded by the SageMaker multi-model server when the container is invoked
as an endpoint. Four contract functions:

    model_fn(model_dir)       -> the loaded model
    input_fn(body, content_type)  -> deserialized input
    predict_fn(input, model)  -> raw model output
    output_fn(output, accept) -> serialized response

We expect JSON input shaped like:
    {"events": [{... CloudTrail event ...}, ...]}

Output:
    {"predictions": [{"score": -0.123, "is_anomaly": true}, ...]}
"""
from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import joblib
import pandas as pd

sys.path.insert(0, "/opt/ml/code")
from feature_engineering import extract_features  # noqa: E402

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


CONTENT_TYPE_JSON = "application/json"


def model_fn(model_dir: str):
    """Load the model + feature schema from the model artifact directory."""
    model_path = Path(model_dir) / "model.joblib"
    schema_path = Path(model_dir) / "feature_columns.json"

    model = joblib.load(model_path)
    feature_columns = json.loads(schema_path.read_text())
    logger.info("Loaded model with %d features", len(feature_columns))

    return {"model": model, "feature_columns": feature_columns}


def input_fn(request_body: str, request_content_type: str) -> pd.DataFrame:
    """Deserialize JSON into a DataFrame ready for feature engineering."""
    if request_content_type != CONTENT_TYPE_JSON:
        raise ValueError(f"Unsupported content type: {request_content_type}")

    payload = json.loads(request_body)
    events = payload.get("events", [])
    if not events:
        raise ValueError("Request payload must contain 'events' array")

    return pd.DataFrame(events)


def predict_fn(input_df: pd.DataFrame, model_bundle: dict) -> dict:
    """Run features through IsolationForest. Returns scores + classifications."""
    model = model_bundle["model"]
    features = extract_features(input_df)

    # IsolationForest.decision_function: higher = more normal, lower = more anomalous
    scores = model.decision_function(features)
    predictions = model.predict(features)  # 1 = normal, -1 = anomaly

    return {
        "scores": scores.tolist(),
        "predictions": predictions.tolist(),
    }


def output_fn(prediction: dict, response_content_type: str) -> str:
    """Serialize predictions to JSON."""
    if response_content_type != CONTENT_TYPE_JSON:
        raise ValueError(f"Unsupported accept type: {response_content_type}")

    output = {
        "predictions": [
            {
                "score": float(score),
                "is_anomaly": bool(pred == -1),
            }
            for score, pred in zip(prediction["scores"], prediction["predictions"])
        ]
    }
    return json.dumps(output)
