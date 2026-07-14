import json
import logging
import os
import boto3

from datetime import datetime, timezone

# ==============================================================
# Logging
# ==============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

logger = logging.getLogger(__name__)


# ==============================================================
# Config from env vars
# ==============================================================

AWS_REGION  = os.environ.get("AWS_REGION", "us-east-1")
RAW_BUCKET  = os.environ.get("RAW_BUCKET")

s3 = boto3.client("s3", region_name=AWS_REGION)


# ==============================================================
# Validation Rules
# ==============================================================

# Minimum file size in bytes (at least 1 KB)
MIN_FILE_SIZE_BYTES = 1024

# Expected file extension
EXPECTED_EXTENSION = ".parquet"

# Expected S3 key prefix
EXPECTED_PREFIX = "raw/yellow_tripdata/"

# Expected columns in parquet file
EXPECTED_COLUMNS = [
    "VendorID",
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "passenger_count",
    "trip_distance",
    "PULocationID",
    "DOLocationID",
    "fare_amount",
    "tip_amount",
    "total_amount",
    "payment_type"
]


# ==============================================================
# Validators
# ==============================================================

def validate_extension(key):
    """Check file has .parquet extension."""

    if not key.endswith(EXPECTED_EXTENSION):
        return False, f"Invalid extension — expected .parquet, got: {key}"

    return True, None


def validate_prefix(key):
    """Check file is in correct S3 prefix."""

    if not key.startswith(EXPECTED_PREFIX):
        return False, f"Invalid S3 prefix — expected {EXPECTED_PREFIX}, got: {key}"

    return True, None


def validate_file_size(bucket, key):
    """Check file size is above minimum threshold."""

    response = s3.head_object(Bucket=bucket, Key=key)
    size     = response["ContentLength"]

    if size < MIN_FILE_SIZE_BYTES:
        return False, f"File too small — {size} bytes (min: {MIN_FILE_SIZE_BYTES})"

    logger.info("File size: %d bytes", size)
    return True, None


def validate_columns(bucket, key):
    """
    Check parquet file has expected columns using S3 Select.
    Reads only metadata — does NOT load full file into memory.
    """

    try:
        response = s3.select_object_content(
            Bucket=bucket,
            Key=key,
            ExpressionType="SQL",
            Expression="SELECT * FROM S3Object LIMIT 1",
            InputSerialization={"Parquet": {}},
            OutputSerialization={"JSON": {"RecordDelimiter": "\n"}}
        )

        # Read first record
        record = None
        for event in response["Payload"]:
            if "Records" in event:
                record = json.loads(
                    event["Records"]["Payload"].decode("utf-8").strip()
                )
                break

        if record is None:
            return False, "File is empty — no records found"

        actual_columns   = set(record.keys())
        expected_columns = set(EXPECTED_COLUMNS)
        missing_columns  = expected_columns - actual_columns

        if missing_columns:
            return False, f"Missing columns: {sorted(missing_columns)}"

        logger.info("All expected columns present")
        return True, None

    except Exception as e:
        return False, f"Column validation failed: {str(e)}"


# ==============================================================
# Main Validator
# ==============================================================

def validate_file(bucket, key):
    """
    Run all validation checks on the uploaded file.
    Returns (is_valid, list_of_errors)
    """

    errors = []

    checks = [
        validate_extension(key),
        validate_prefix(key),
        validate_file_size(bucket, key),
        validate_columns(bucket, key)
    ]

    for is_valid, error in checks:
        if not is_valid:
            errors.append(error)

    return len(errors) == 0, errors


# ==============================================================
# Lambda Handler
# ==============================================================

def lambda_handler(event, context):
    """
    Triggered by S3 Event Notification when a new file
    lands in the raw bucket.

    Validates:
    - File extension (.parquet)
    - S3 prefix (raw/yellow_tripdata/)
    - File size (> 1KB)
    - Expected columns present

    Returns:
    - is_valid: True/False
    - errors: list of validation failures
    """

    logger.info("Received event: %s", json.dumps(event))

    results = []

    # S3 event can have multiple records
    for record in event.get("Records", []):

        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]

        logger.info("Validating file: s3://%s/%s", bucket, key)

        is_valid, errors = validate_file(bucket, key)

        result = {
            "bucket":     bucket,
            "key":        key,
            "is_valid":   is_valid,
            "errors":     errors,
            "validated_at": datetime.now(timezone.utc).isoformat()
        }

        if is_valid:
            logger.info("✅ File VALID: s3://%s/%s", bucket, key)
        else:
            logger.error(
                "❌ File INVALID: s3://%s/%s — Errors: %s",
                bucket, key, errors
            )

        results.append(result)

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Metadata validation complete",
            "results": results
        })
    }
