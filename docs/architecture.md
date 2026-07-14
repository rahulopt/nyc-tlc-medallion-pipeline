# Architecture — NYC TLC Medallion Pipeline

## Overview

This project implements a **Medallion Architecture** (Bronze → Silver → Gold) on AWS for the NYC Taxi & Limousine Commission (TLC) trip dataset.

---

## High-Level Architecture

```
NYC TLC Dataset (Public)
        │
        ▼
ingestion/download_data.py
        │
        ▼
Amazon S3 — Raw Bucket
        │
        ▼
AWS Step Functions (Orchestration)
        │
        ├──► Glue Bronze Job ──► S3 Curated/bronze/
        │
        ├──► Glue Silver Job ──► S3 Curated/silver/   ──► S3 Reject/silver/
        │
        ├──► Glue Gold Job ───► S3 Gold/
        │
        ├──► Glue Crawler (Silver) ──► Glue Data Catalog
        │
        ├──► Glue Crawler (Gold) ───► Glue Data Catalog
        │
        ├──► Lambda audit_logger ───► DynamoDB Audit Table
        │
        └──► Lambda notifier ───────► CloudWatch Logs + SES Email
```

---

## Medallion Layers

### 🥉 Bronze Layer
- **Source:** Raw S3 parquet files
- **Script:** `glue/bronze/bronze_job.py`
- **Output:** `s3://<curated-bucket>/bronze/`
- **Transformations:**
  - Add `ingestion_time` metadata column
  - Add `source_file` metadata column
  - Write as parquet (overwrite mode)

### 🥈 Silver Layer
- **Source:** Bronze layer parquet
- **Script:** `glue/silver/silver_job.py`
- **Output:** `s3://<curated-bucket>/silver/` (partitioned by `pickup_year/pickup_month`)
- **Reject:** `s3://<reject-bucket>/silver/` (partitioned by `dq_reject_reason`)
- **Data Quality Rules (8):**
  - `passenger_count` between 1–6
  - `trip_distance` > 0 and < 500 miles
  - `fare_amount` > 0 and < $10,000
  - `total_amount` > 0
  - `tpep_pickup_datetime` not null
  - `tpep_dropoff_datetime` not null
  - Dropoff must be after pickup
  - Pickup year between 2009–2030
- **Transformations:**
  - Correct data type casting
  - Extract `pickup_date`, `pickup_year`, `pickup_month`, `pickup_hour`, `pickup_dayofweek`
  - Calculate `trip_duration_minutes`
  - Round monetary columns to 2 decimal places

### 🥇 Gold Layer
- **Source:** Silver layer parquet
- **Script:** `glue/gold/gold_job.py`
- **Output:** `s3://<gold-bucket>/gold/`
- **Tables (4):**

| Table | Description | Partition |
|-------|-------------|-----------|
| `daily_trip_summary` | Daily aggregations — trips, revenue, avg fare | year/month |
| `hourly_trip_summary` | Hourly aggregations — peak hour analysis | year/month |
| `location_trip_summary` | Per-location aggregations — hotspot analysis | none |
| `payment_type_summary` | Per-payment-type — credit vs cash | none |

---

## AWS Services Used

| Service | Purpose |
|---------|---------|
| **Amazon S3** | Raw, Curated, Gold, Reject, Assets, Athena results buckets |
| **AWS Glue** | ETL jobs (Bronze/Silver/Gold), Crawlers, Data Catalog |
| **AWS Step Functions** | Pipeline orchestration |
| **AWS Lambda** | audit_logger, notifier, metadata_validator |
| **Amazon DynamoDB** | Pipeline execution audit log |
| **Amazon EventBridge** | Glue job state change events (success/failure) |
| **Amazon Athena** | SQL analytics on Gold layer |
| **Amazon SES** | Email notifications on pipeline completion |
| **Amazon CloudWatch** | Logs, Metrics, Alarms |
| **AWS IAM** | Roles and policies for all services |

---

## S3 Bucket Structure

```
nyc-tlc-dev-raw-<account>/
└── raw/yellow_tripdata/year=2024/month=01/

nyc-tlc-dev-curated-<account>/
├── bronze/
└── silver/pickup_year=2024/pickup_month=1/

nyc-tlc-dev-gold-<account>/
└── gold/
    ├── daily_trip_summary/pickup_year=2024/pickup_month=1/
    ├── hourly_trip_summary/pickup_year=2024/pickup_month=1/
    ├── location_trip_summary/
    └── payment_type_summary/

nyc-tlc-dev-reject-<account>/
└── silver/dq_reject_reason=invalid_fare_amount/

nyc-tlc-dev-assets-<account>/
└── glue/
    ├── bronze/bronze_job.py
    ├── silver/silver_job.py
    └── gold/gold_job.py
```

---

## Step Functions Flow

```
Start Bronze Job
      │
 SUCCEEDED?──❌──► Notify Failure ──► Log Audit Failure ──► Pipeline Failed
      │✅
Start Silver Job
      │
 SUCCEEDED?──❌──► Notify Failure ──► Log Audit Failure ──► Pipeline Failed
      │✅
Start Gold Job
      │
 SUCCEEDED?──❌──► Notify Failure ──► Log Audit Failure ──► Pipeline Failed
      │✅
Run Silver Crawler
      │
Run Gold Crawler
      │
Log Audit Success (Lambda)
      │
Notify Success (Lambda → SES Email)
      │
Pipeline Succeeded ✅
```

---

## IAM Roles

| Role | Service | Policies |
|------|---------|---------|
| `nyc-tlc-GlueExecutionRole` | AWS Glue | AWSGlueServiceRole + custom S3 policy |
| `nyc-tlc-LambdaExecutionRole` | AWS Lambda | AWSLambdaBasicExecutionRole |
| `nyc-tlc-StepFunctionExecutionRole` | Step Functions | AWSStepFunctionsFullAccess |

---

## Data Flow Diagram

```
Raw Parquet (48 MB)
        │
        ▼ Bronze ETL (add metadata)
Bronze Parquet (~58 MB)
        │
        ▼ Silver ETL (DQ + transforms)
        ├──► Valid Records → Silver Parquet (partitioned)
        └──► Rejected Records → Reject Bucket
                │
                ▼ Gold ETL (aggregations)
        4 Gold Tables:
        ├── daily_trip_summary
        ├── hourly_trip_summary
        ├── location_trip_summary
        └── payment_type_summary
                │
                ▼ Crawlers
        Glue Data Catalog (SQL tables)
                │
                ▼
        Amazon Athena (SQL queries)
```
