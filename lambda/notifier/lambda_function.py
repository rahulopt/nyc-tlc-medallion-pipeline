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

AWS_REGION       = os.environ.get("AWS_REGION", "us-east-1")
LOG_GROUP_NAME   = os.environ.get("LOG_GROUP_NAME", "/nyc-tlc/pipeline/notifications")

cloudwatch = boto3.client("logs", region_name=AWS_REGION)


# ==============================================================
# Parse EventBridge event
# ==============================================================

def parse_event(event):
    """
    Extract fields from EventBridge Glue job state change event.
    """

    detail       = event.get("detail", {})
    job_name     = detail.get("jobName", "unknown")
    state        = detail.get("state", "unknown")
    job_run_id   = detail.get("jobRunId", "unknown")
    message      = detail.get("message", "")
    completed_on = detail.get("completedOn", "")
    event_time   = event.get("time", datetime.now(timezone.utc).isoformat())

    return {
        "job_name":     job_name,
        "state":        state,
        "job_run_id":   job_run_id,
        "message":      message,
        "completed_on": completed_on,
        "event_time":   event_time
    }


# ==============================================================
# Build notification message
# ==============================================================

def build_message(parsed):
    """
    Build a human-readable notification message based on job state.
    """

    emoji = "✅" if parsed["state"] == "SUCCEEDED" else "❌"

    message = {
        "pipeline":     "NYC TLC Medallion Pipeline",
        "status":       f"{emoji} {parsed['state']}",
        "job_name":     parsed["job_name"],
        "job_run_id":   parsed["job_run_id"],
        "completed_on": parsed["completed_on"],
        "event_time":   parsed["event_time"],
        "message":      parsed["message"] or "No additional details"
    }

    return message


# ==============================================================
# Log notification to CloudWatch
# ==============================================================

def ensure_log_group():
    """Create CloudWatch log group if it doesn't exist."""
    try:
        cloudwatch.create_log_group(logGroupName=LOG_GROUP_NAME)
        logger.info("Created log group: %s", LOG_GROUP_NAME)
    except cloudwatch.exceptions.ResourceAlreadyExistsException:
        pass


def ensure_log_stream(stream_name):
    """Create CloudWatch log stream if it doesn't exist."""
    try:
        cloudwatch.create_log_stream(
            logGroupName=LOG_GROUP_NAME,
            logStreamName=stream_name
        )
    except cloudwatch.exceptions.ResourceAlreadyExistsException:
        pass


def send_notification(notification):
    """
    Send notification to CloudWatch Logs.
    Can be extended to add email (SES), Slack webhook, etc.
    """

    stream_name = datetime.now(timezone.utc).strftime("%Y/%m/%d")

    ensure_log_group()
    ensure_log_stream(stream_name)

    log_event = {
        "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        "message":   json.dumps(notification, indent=2)
    }

    cloudwatch.put_log_events(
        logGroupName=LOG_GROUP_NAME,
        logStreamName=stream_name,
        logEvents=[log_event]
    )

    logger.info(
        "Notification sent to CloudWatch: %s | %s",
        notification["job_name"],
        notification["status"]
    )


# ==============================================================
# Lambda Handler
# ==============================================================

def lambda_handler(event, context):
    """
    Triggered by EventBridge rule on Glue job state change.

    - Builds a notification message
    - Logs to CloudWatch (extensible to SES/Slack)
    - Returns notification details
    """

    logger.info("Received event: %s", json.dumps(event))

    try:

        parsed       = parse_event(event)
        notification = build_message(parsed)

        send_notification(notification)

        logger.info(
            "Notification dispatched — Job: %s | State: %s",
            parsed["job_name"],
            parsed["state"]
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message":    "Notification sent successfully",
                "job_name":   parsed["job_name"],
                "state":      parsed["state"],
                "log_group":  LOG_GROUP_NAME
            })
        }

    except Exception as e:
        logger.error("Failed to send notification: %s", str(e))
        raise
