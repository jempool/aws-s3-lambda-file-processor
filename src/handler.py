"""Lambda entry point: S3 ObjectCreated event -> summary JSON in output/."""

import json
import logging
from datetime import datetime, timezone
from pathlib import PurePosixPath
from urllib.parse import unquote_plus

import boto3

from processor import process_file

INPUT_PREFIX = "input/"
OUTPUT_PREFIX = "output/"

logger = logging.getLogger()
logger.setLevel(logging.INFO)
s3 = boto3.client("s3")


def lambda_handler(event, context):
    return [_process_record(record) for record in event["Records"]]


def _process_record(record: dict) -> dict:
    bucket = record["s3"]["bucket"]["name"]
    key = unquote_plus(record["s3"]["object"]["key"])  # S3 URL-encodes keys in events
    logger.info("File received", extra={"bucket": bucket, "key": key})

    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    summary = {
        **process_file(body),
        "source_file": f"s3://{bucket}/{key}",
        "processed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }

    output_key = _output_key(key)
    s3.put_object(
        Bucket=bucket,
        Key=output_key,
        Body=json.dumps(summary, indent=2).encode("utf-8"),
        ContentType="application/json",
    )

    log = logger.info if summary["status"] == "PROCESSED" else logger.error
    log(
        f"File {summary['status']}",
        extra={"key": key, "output_key": output_key, "summary": summary},
    )
    return {"key": key, "output_key": output_key, "status": summary["status"]}


def _output_key(input_key: str) -> str:
    """input/sales/jan.json -> output/sales/jan.summary.json"""
    relative = PurePosixPath(input_key.removeprefix(INPUT_PREFIX))
    return f"{OUTPUT_PREFIX}{relative.with_suffix('')}.summary.json"
