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

AUDIT_TABLE = os.environ["AUDIT_TABLE"]
AWS_REGION  = os.environ.get("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table    = dynamodb.Table(AUDIT_TABLE)


# ==============================================================
# Parse EventBridge event
# ==============================================================

def parse_event(event):
    """
    Extract relevant fields from EventBridge Glue job state event.

    EventBridge event structure for Glue:
    {
        "source": "aws.glue",
        "detail-type": "Glue Job State Change",
        "detail": {
            "jobName": "...",
            "state": "SUCCEEDED | FAILED",
            "jobRunId": "...",
            "message": "...",
            "startedOn": "...",
            "completedOn": "..."
        }
    }
    """

    detail      = event.get("detail", {})
    job_name    = detail.get("jobName", "unknown")
    state       = detail.get("state", "unknown")
    job_run_id  = detail.get("jobRunId", "unknown")
    message     = detail.get("message", "")
    started_on  = detail.get("startedOn", "")
    completed_on = detail.get("completedOn", "")
    event_time  = event.get("time", datetime.now(timezone.utc).isoformat())

    return {
        "job_name":     job_name,
        "state":        state,
        "job_run_id":   job_run_id,
        "message":      message,
        "started_on":   started_on,
        "completed_on": completed_on,
        "event_time":   event_time
    }


# ==============================================================
# Write to DynamoDB
# ==============================================================

def write_audit_log(parsed):
    """
    Write pipeline execution record to DynamoDB audit table.

    DynamoDB schema:
    - PK: job_run_id (String)
    - SK: event_time (String)
    - Attributes: job_name, state, message, started_on, completed_on, logged_at
    """

    item = {
        "job_run_id":   parsed["job_run_id"],
        "event_time":   parsed["event_time"],
        "job_name":     parsed["job_name"],
        "state":        parsed["state"],
        "message":      parsed["message"],
        "started_on":   parsed["started_on"],
        "completed_on": parsed["completed_on"],
        "logged_at":    datetime.now(timezone.utc).isoformat()
    }

    logger.info(
        "Writing audit log for job: %s | state: %s",
        parsed["job_name"],
        parsed["state"]
    )

    table.put_item(Item=item)

    logger.info(
        "Audit log written — job_run_id: %s",
        parsed["job_run_id"]
    )


# ==============================================================
# Lambda Handler
# ==============================================================

def lambda_handler(event, context):
    """
    Triggered by EventBridge rule on Glue job state change.
    Writes execution record to DynamoDB audit table.
    """

    logger.info("Received event: %s", json.dumps(event))

    try:

        parsed = parse_event(event)

        write_audit_log(parsed)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Audit log written successfully",
                "job_run_id": parsed["job_run_id"],
                "state": parsed["state"]
            })
        }

    except Exception as e:
        logger.error("Failed to write audit log: %s", str(e))
        raise
