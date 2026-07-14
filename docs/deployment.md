# Deployment Guide — NYC TLC Medallion Pipeline

## Prerequisites

- AWS CLI installed and configured
- Python 3.8+ installed
- Git installed
- AWS account with admin access

---

## 1. Clone the Repository

```bash
git clone https://github.com/rahulopt/nyc-tlc-medallion-pipeline.git
cd nyc-tlc-medallion-pipeline
```

---

## 2. Install Python Dependencies

```bash
pip install -r requirements.txt
```

---

## 3. Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: us-east-1
# Default output format: json
```

Verify credentials:
```bash
aws sts get-caller-identity
```

---

## 4. Update Config

Edit `config/variables.sh` — all values are auto-generated from your Account ID, no changes needed unless you want a different project name or region.

```bash
# config/variables.sh
PROJECT_NAME="nyc-tlc"
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
```

---

## 5. Create All AWS Resources

```bash
bash scripts/create_resources.sh
```

This creates in order:
1. S3 Buckets (6)
2. IAM Roles + Policies
3. Glue Database
4. Glue Crawlers
5. Glue Jobs (Bronze, Silver, Gold)
6. DynamoDB Audit Table
7. EventBridge Bus + Rules
8. Step Functions State Machine

---

## 6. Download & Upload Raw Data

```bash
# Set environment variables
export RAW_BUCKET="nyc-tlc-dev-raw-<your-account-id>"

# Download Jan 2024 data (default)
python ingestion/download_data.py

# For a specific month:
export YEAR=2024
export MONTH=03
python ingestion/download_data.py
```

---

## 7. Upload Glue Scripts to S3

```bash
source config/variables.sh

# Bronze
aws s3 cp glue/bronze/bronze_job.py s3://$ASSETS_BUCKET/glue/bronze/bronze_job.py

# Silver
aws s3 cp glue/silver/silver_job.py s3://$ASSETS_BUCKET/glue/silver/silver_job.py

# Gold
aws s3 cp glue/gold/gold_job.py s3://$ASSETS_BUCKET/glue/gold/gold_job.py
```

---

## 8. Setup SES Email (Optional)

Verify your email in AWS SES:
```bash
aws ses verify-email-identity \
    --email-address rahulopt14@gmail.com \
    --region us-east-1
```
Check your inbox and click the verification link.

---

## 9. Deploy Lambda Functions

```bash
bash lambda/deploy_lambda.sh
```

This deploys:
- `nyc-tlc-audit-logger` — logs pipeline runs to DynamoDB
- `nyc-tlc-notifier` — sends email via SES + CloudWatch logs

---

## 10. Run the Full Pipeline

### Option A — Step Functions (Recommended)

```bash
source config/variables.sh
source scripts/lib/utils.sh
source scripts/lib/aws_stepfunctions.sh

start_pipeline "$STATE_MACHINE_NAME"
```

Or from AWS Console:
```
AWS Console → Step Functions → nyc-tlc-dev-pipeline → Start Execution
```

### Option B — Run Jobs Individually

```bash
# Bronze
aws glue start-job-run --job-name nyc-tlc-bronze-job-dev --region us-east-1

# Silver (after bronze completes)
aws glue start-job-run --job-name nyc-tlc-silver-job-dev --region us-east-1

# Gold (after silver completes)
aws glue start-job-run --job-name nyc-tlc-gold-job-dev --region us-east-1

# Run Crawlers
bash crawler/run_crawlers.sh
```

---

## 11. Query with Athena

Open `athena/gold_queries.sql` and run queries in:
```
AWS Console → Athena → Query Editor
Database: nyc-tlc_dev_db
```

Or use setup script:
```bash
bash athena/setup_athena.sh
```

---

## 12. Setup CloudWatch Alarms (Optional)

```bash
bash monitoring/cloudwatch_alarms.sh
```

---

## Cleanup — Delete All Resources

```bash
bash scripts/delete_resources.sh
```

> ⚠️ This will permanently delete ALL project resources including S3 data.

---

## Project Structure

```
nyc-tlc-medallion-pipeline/
├── config/
│   └── variables.sh          # All config variables
├── ingestion/
│   └── download_data.py      # Download NYC TLC data
├── glue/
│   ├── bronze/bronze_job.py  # Bronze ETL
│   ├── silver/silver_job.py  # Silver ETL + DQ
│   └── gold/gold_job.py      # Gold aggregations
├── lambda/
│   ├── audit_logger/         # DynamoDB audit logger
│   ├── notifier/             # SES email notifier
│   ├── metadata_validator/   # S3 file validator
│   └── deploy_lambda.sh      # Lambda deploy script
├── stepfunctions/
│   └── pipeline.json         # State machine definition
├── crawler/
│   └── run_crawlers.sh       # Run Glue crawlers
├── athena/
│   ├── gold_queries.sql      # SQL analytics queries
│   └── setup_athena.sh       # Athena workgroup setup
├── monitoring/
│   └── cloudwatch_alarms.sh  # CloudWatch alarms
├── scripts/
│   ├── create_resources.sh   # Create all AWS resources
│   ├── delete_resources.sh   # Delete all AWS resources
│   └── lib/                  # Helper libraries
├── iam/
│   ├── policies/             # IAM policies
│   └── trust/                # Trust policies
├── docs/
│   ├── architecture.md       # Architecture overview
│   └── deployment.md         # This file
└── requirements.txt
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Glue job fails with `TIMESTAMP_NTZ` error | Use `unix_timestamp()` instead of `.cast("long")` |
| S3 bucket already exists | Script is idempotent — safely skips existing resources |
| Lambda email not sending | Verify sender email in SES Console |
| Athena query fails | Run crawlers first to register tables in Glue Catalog |
| Step Functions execution fails | Check CloudWatch Logs → `/aws/states/` for error details |
