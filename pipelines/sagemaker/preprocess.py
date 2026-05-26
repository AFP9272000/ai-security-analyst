"""
SageMaker preprocessing step.

Reads raw CloudTrail data dropped into /opt/ml/processing/input (parquet
or CSV), splits it into train (80%) and validation (20%) sets, and
writes parquet output for the training step to consume.

, this is intentionally simple, just a clean split with
no further transformation. Future iterations could:
- Filter to specific account_ids or event sources
- Apply class balancing
- Add synthetic anomalies for evaluation

The training step itself runs feature engineering, so don't do that
here. Keeping raw events in the train/val sets makes the feature
contract a single-source-of-truth thing.
"""
from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import pandas as pd

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


INPUT_DIR = Path("/opt/ml/processing/input")
TRAIN_DIR = Path("/opt/ml/processing/train")
VALIDATION_DIR = Path("/opt/ml/processing/validation")
RANDOM_STATE = 42
VALIDATION_FRACTION = 0.2


def main() -> int:
    TRAIN_DIR.mkdir(parents=True, exist_ok=True)
    VALIDATION_DIR.mkdir(parents=True, exist_ok=True)

    files = list(INPUT_DIR.glob("**/*"))
    parquet_files = [f for f in files if f.suffix == ".parquet" and f.is_file()]
    csv_files = [f for f in files if f.suffix == ".csv" and f.is_file()]

    if not parquet_files and not csv_files:
        logger.error("No input files found in %s", INPUT_DIR)
        return 1

    frames = []
    for path in parquet_files:
        logger.info("Loading %s", path)
        frames.append(pd.read_parquet(path))
    for path in csv_files:
        logger.info("Loading %s", path)
        frames.append(pd.read_csv(path))

    df = pd.concat(frames, ignore_index=True)
    logger.info("Total rows: %d, columns: %s", len(df), list(df.columns))

    # Shuffle and split
    df = df.sample(frac=1.0, random_state=RANDOM_STATE).reset_index(drop=True)
    split_idx = int(len(df) * (1.0 - VALIDATION_FRACTION))
    train_df = df.iloc[:split_idx]
    val_df = df.iloc[split_idx:]

    train_path = TRAIN_DIR / "train.parquet"
    val_path = VALIDATION_DIR / "validation.parquet"
    train_df.to_parquet(train_path, index=False)
    val_df.to_parquet(val_path, index=False)

    logger.info("Wrote %d train rows to %s", len(train_df), train_path)
    logger.info("Wrote %d validation rows to %s", len(val_df), val_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
