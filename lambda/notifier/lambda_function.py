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

AWS_REGION      = os.environ.get("AWS_REGION", "us-east-1")
LOG_GROUP_NAME  = os.environ.get("LOG_GROUP_NAME", "/nyc-tlc/pipeline/notifications")

# SES email config — set these in Lambda environment variables
SENDER_EMAIL    = os.environ.get("SENDER_EMAIL")    # verified SES sender
RECIPIENT_EMAIL = os.environ.get("RECIPIENT_EMAIL")  # where to send alerts

cloudwatch = boto3.client("logs", region_name=AWS_REGION)
ses        = boto3.client("ses",  region_name=AWS_REGION)


# ==============================================================
# Parse event
# ==============================================================

def parse_event(event):
    """
    Extract fields from Step Functions Lambda invoke payload.

    Expected payload from pipeline.json:
    {
        "source": "aws.stepfunctions",
        "detail-type": "Pipeline Notification",
        "detail": {
            "jobName": "...",
            "state": "SUCCEEDED | FAILED",
            "jobRunId": "...",
            "message": "..."
        }
    }
    """

    detail       = event.get("detail", {})
    job_name     = detail.get("jobName", "unknown")
    state        = detail.get("state",   "unknown")
    job_run_id   = detail.get("jobRunId", "unknown")
    message      = detail.get("message", "")
    event_time   = event.get("time", datetime.now(timezone.utc).isoformat())

    return {
        "job_name":   job_name,
        "state":      state,
        "job_run_id": job_run_id,
        "message":    message,
        "event_time": event_time
    }


# ==============================================================
# Build email content
# ==============================================================

def build_email(parsed):
    """
    Build HTML + plain text email for SES.
    """

    is_success = parsed["state"] == "SUCCEEDED"
    emoji      = "✅" if is_success else "❌"
    color      = "#2e7d32" if is_success else "#c62828"
    bg_color   = "#e8f5e9" if is_success else "#ffebee"

    subject = f"{emoji} NYC TLC Pipeline — {parsed['state']}"

    html_body = f"""
    <html>
    <body style="font-family: Arial, sans-serif; padding: 20px;">

        <div style="background-color: {bg_color}; border-left: 5px solid {color};
                    padding: 15px; border-radius: 4px; margin-bottom: 20px;">
            <h2 style="color: {color}; margin: 0;">
                {emoji} Pipeline {parsed['state']}
            </h2>
        </div>

        <table style="width: 100%; border-collapse: collapse;">
            <tr style="background-color: #f5f5f5;">
                <td style="padding: 10px; font-weight: bold; width: 30%;">Pipeline</td>
                <td style="padding: 10px;">NYC TLC Medallion Pipeline</td>
            </tr>
            <tr>
                <td style="padding: 10px; font-weight: bold;">Status</td>
                <td style="padding: 10px; color: {color};">
                    <strong>{parsed['state']}</strong>
                </td>
            </tr>
            <tr style="background-color: #f5f5f5;">
                <td style="padding: 10px; font-weight: bold;">Job Name</td>
                <td style="padding: 10px;">{parsed['job_name']}</td>
            </tr>
            <tr>
                <td style="padding: 10px; font-weight: bold;">Execution ID</td>
                <td style="padding: 10px;">{parsed['job_run_id']}</td>
            </tr>
            <tr style="background-color: #f5f5f5;">
                <td style="padding: 10px; font-weight: bold;">Time</td>
                <td style="padding: 10px;">{parsed['event_time']}</td>
            </tr>
            <tr>
                <td style="padding: 10px; font-weight: bold;">Message</td>
                <td style="padding: 10px;">{parsed['message'] or 'No additional details'}</td>
            </tr>
        </table>

        <p style="color: #666; font-size: 12px; margin-top: 20px;">
            NYC TLC Medallion Pipeline — Automated Notification
        </p>

    </body>
    </html>
    """

    text_body = f"""
NYC TLC Pipeline — {parsed['state']}

Pipeline  : NYC TLC Medallion Pipeline
Status    : {parsed['state']}
Job Name  : {parsed['job_name']}
Exec ID   : {parsed['job_run_id']}
Time      : {parsed['event_time']}
Message   : {parsed['message'] or 'No additional details'}
    """

    return subject, html_body, text_body


# ==============================================================
# Send Email via SES
# ==============================================================

def send_email(parsed):
    """
    Send pipeline notification email via AWS SES.
    Skips silently if SENDER_EMAIL or RECIPIENT_EMAIL not configured.
    """

    if not SENDER_EMAIL or not RECIPIENT_EMAIL:
        logger.warning(
            "SES email skipped — SENDER_EMAIL or RECIPIENT_EMAIL not set"
        )
        return

    subject, html_body, text_body = build_email(parsed)

    logger.info(
        "Sending email to %s via SES",
        RECIPIENT_EMAIL
    )

    ses.send_email(
        Source=SENDER_EMAIL,
        Destination={
            "ToAddresses": [RECIPIENT_EMAIL]
        },
        Message={
            "Subject": {
                "Data": subject,
                "Charset": "UTF-8"
            },
            "Body": {
                "Text": {
                    "Data": text_body,
                    "Charset": "UTF-8"
                },
                "Html": {
                    "Data": html_body,
                    "Charset": "UTF-8"
                }
            }
        }
    )

    logger.info("Email sent successfully to %s", RECIPIENT_EMAIL)


# ==============================================================
# Log to CloudWatch
# ==============================================================

def ensure_log_group():
    try:
        cloudwatch.create_log_group(logGroupName=LOG_GROUP_NAME)
    except cloudwatch.exceptions.ResourceAlreadyExistsException:
        pass


def ensure_log_stream(stream_name):
    try:
        cloudwatch.create_log_stream(
            logGroupName=LOG_GROUP_NAME,
            logStreamName=stream_name
        )
    except cloudwatch.exceptions.ResourceAlreadyExistsException:
        pass


def log_to_cloudwatch(parsed):

    stream_name = datetime.now(timezone.utc).strftime("%Y/%m/%d")

    ensure_log_group()
    ensure_log_stream(stream_name)

    cloudwatch.put_log_events(
        logGroupName=LOG_GROUP_NAME,
        logStreamName=stream_name,
        logEvents=[{
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
            "message":   json.dumps(parsed, indent=2)
        }]
    )

    logger.info("Logged to CloudWatch: %s", LOG_GROUP_NAME)


# ==============================================================
# Lambda Handler
# ==============================================================

def lambda_handler(event, context):
    """
    Triggered by Step Functions pipeline (Task state).

    Actions:
    1. Log notification to CloudWatch
    2. Send email via SES (if SENDER_EMAIL + RECIPIENT_EMAIL set)
    """

    logger.info("Received event: %s", json.dumps(event))

    try:

        parsed = parse_event(event)

        # 1. Log to CloudWatch always
        log_to_cloudwatch(parsed)

        # 2. Send email via SES
        send_email(parsed)

        logger.info(
            "Notification complete — Job: %s | State: %s",
            parsed["job_name"],
            parsed["state"]
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message":   "Notification sent",
                "job_name":  parsed["job_name"],
                "state":     parsed["state"],
                "email_sent": bool(SENDER_EMAIL and RECIPIENT_EMAIL)
            })
        }

    except Exception as e:
        logger.error("Notification failed: %s", str(e))
        raise
