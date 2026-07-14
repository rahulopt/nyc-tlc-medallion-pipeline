# 🚕 NYC TLC Medallion Data Pipeline

A production-grade AWS Data Engineering project implementing the **Medallion Architecture (Bronze → Silver → Gold)** using AWS Glue, Step Functions, Lambda, EventBridge, DynamoDB, Athena, and SES.

---

## 📌 Project Overview

This project builds an end-to-end cloud-native data pipeline for the **NYC Taxi & Limousine Commission (TLC)** trip dataset.

The pipeline automatically:
- Downloads monthly NYC TLC trip data
- Stores raw data in Amazon S3
- Runs Bronze → Silver → Gold ETL using AWS Glue (PySpark)
- Validates data quality and separates rejected records
- Builds 4 analytics-ready Gold tables
- Updates Glue Data Catalog via Crawlers
- Enables SQL analytics using Amazon Athena
- Orchestrates the complete workflow using AWS Step Functions
- Logs all pipeline runs to DynamoDB
- Sends success/failure email notifications via SES
- Monitors with CloudWatch Alarms

---

## 🏗️ Architecture

```
NYC TLC Dataset
        │
        ▼
Python Downloader (ingestion/download_data.py)
        │
        ▼
Amazon S3 — Raw Bucket
        │
        ▼
AWS Step Functions (Orchestration)
        │
        ├──► Glue Bronze Job ──────────────► S3 Curated/bronze/
        │
        ├──► Glue Silver Job ──────────────► S3 Curated/silver/  (partitioned)
        │         │                          S3 Reject/silver/    (DQ failures)
        │
        ├──► Glue Gold Job ────────────────► S3 Gold/ (4 tables)
        │
        ├──► Silver Crawler ───────────────► Glue Data Catalog
        ├──► Gold Crawler ─────────────────► Glue Data Catalog
        │                                          │
        │                                          ▼
        │                                   Amazon Athena
        │
        ├──► Lambda audit_logger ──────────► DynamoDB Audit Table
        └──► Lambda notifier ───────────────► CloudWatch + SES Email
```

---

## 🛠️ Tech Stack

| Category | Service |
|----------|---------|
| Storage | Amazon S3 |
| ETL | AWS Glue (PySpark) |
| Orchestration | AWS Step Functions |
| Serverless | AWS Lambda (Python) |
| Events | Amazon EventBridge |
| Audit | Amazon DynamoDB |
| Analytics | Amazon Athena + Glue Data Catalog |
| Notifications | Amazon SES + CloudWatch Logs |
| Monitoring | Amazon CloudWatch Alarms |
| Security | AWS IAM |
| IaC | Bash scripts |
| Language | Python, PySpark, Bash, SQL |

---

## 📂 Project Structure

```
nyc-tlc-medallion-pipeline/
│
├── config/
│   └── variables.sh              # All project config variables
│
├── ingestion/
│   └── download_data.py          # Download NYC TLC parquet from public URL
│
├── glue/
│   ├── bronze/bronze_job.py      # Bronze ETL — add metadata columns
│   ├── silver/silver_job.py      # Silver ETL — DQ checks + transformations
│   └── gold/gold_job.py          # Gold ETL — 4 analytics aggregation tables
│
├── lambda/
│   ├── audit_logger/             # Log pipeline runs to DynamoDB
│   ├── notifier/                 # Send SES email + CloudWatch notification
│   ├── metadata_validator/       # Validate raw S3 files before processing
│   └── deploy_lambda.sh          # Package and deploy Lambda functions
│
├── stepfunctions/
│   └── pipeline.json             # State machine — Bronze → Silver → Gold → Notify
│
├── crawler/
│   └── run_crawlers.sh           # Create and run Silver + Gold crawlers
│
├── athena/
│   ├── gold_queries.sql          # 11 analytical SQL queries
│   └── setup_athena.sh           # Create Athena workgroup + run queries
│
├── monitoring/
│   └── cloudwatch_alarms.sh      # CloudWatch alarms for all services
│
├── scripts/
│   ├── create_resources.sh       # Create ALL AWS resources
│   ├── delete_resources.sh       # Delete ALL AWS resources
│   └── lib/
│       ├── utils.sh              # Logging + AWS CLI validation
│       ├── aws_s3.sh             # S3 bucket operations
│       ├── aws_iam.sh            # IAM roles + policies
│       ├── aws_glue.sh           # Glue jobs + crawlers + database
│       ├── aws_dynamodb.sh       # DynamoDB table creation
│       ├── aws_eventbridge.sh    # EventBridge bus + rules
│       └── aws_stepfunctions.sh  # Step Functions state machine
│
├── iam/
│   ├── policies/glue-s3-policy.json
│   └── trust/                    # Trust policies for Glue, Lambda, Step Functions
│
├── docs/
│   ├── architecture.md           # Full architecture documentation
│   └── deployment.md             # Step-by-step deployment guide
│
├── tests/
│   ├── unit/
│   └── integration/
│
├── requirements.txt
└── README.md
```

---

## 🥇 Gold Layer Tables

| Table | Description |
|-------|-------------|
| `daily_trip_summary` | Daily trips, revenue, avg fare, avg distance |
| `hourly_trip_summary` | Hourly trends — peak hour analysis |
| `location_trip_summary` | Per pickup location — hotspot analysis |
| `payment_type_summary` | Credit card vs cash breakdown |

---

## 🚀 Quick Start

```bash
# 1. Clone
git clone https://github.com/rahulopt/nyc-tlc-medallion-pipeline.git
cd nyc-tlc-medallion-pipeline

# 2. Install dependencies
pip install -r requirements.txt

# 3. Create all AWS resources
bash scripts/create_resources.sh

# 4. Download + upload raw data
export RAW_BUCKET="nyc-tlc-dev-raw-<your-account-id>"
python ingestion/download_data.py

# 5. Deploy Lambda functions
bash lambda/deploy_lambda.sh

# 6. Run the full pipeline
source config/variables.sh && source scripts/lib/aws_stepfunctions.sh
start_pipeline "$STATE_MACHINE_NAME"
```

See [docs/deployment.md](docs/deployment.md) for the complete deployment guide.

---

## 📊 Step Functions Pipeline Flow

```
Start Bronze Job
      │✅
Start Silver Job
      │✅
Start Gold Job
      │✅
Run Silver Crawler
      │
Run Gold Crawler
      │
Log Audit (DynamoDB)
      │
Notify Success (SES Email) ✅

On any failure → Notify Failure → Log Audit → Pipeline Failed ❌
```

---

## 🧹 Cleanup

```bash
bash scripts/delete_resources.sh
```

---

## 📄 License

MIT License

---

## 👤 Author

Rahul Singh Rana — [GitHub](https://github.com/rahulopt)
