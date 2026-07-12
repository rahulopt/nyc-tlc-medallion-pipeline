# nyc-tlc-medallion-pipeline
# 🚕 NYC TLC Medallion Data Pipeline

A production-grade AWS Data Engineering project implementing the **Medallion Architecture (Raw → Curated → Gold)** using AWS services and PySpark.

---

## 📌 Project Overview

This project builds an end-to-end cloud-native data pipeline for the **NYC Taxi & Limousine Commission (TLC)** trip dataset.

The pipeline automatically:

- Downloads monthly NYC TLC trip data
- Stores raw data in Amazon S3
- Performs ETL using AWS Glue (PySpark)
- Executes Data Quality validation
- Separates rejected records
- Builds analytics-ready datasets
- Updates the Glue Data Catalog
- Enables SQL analytics using Amazon Athena
- Tracks pipeline executions in DynamoDB
- Sends success/failure notifications through SNS
- Orchestrates the complete workflow using AWS Step Functions

---

## 🏗️ Architecture

```
NYC TLC Dataset
        │
        ▼
Python Downloader
        │
        ▼
Amazon S3 (Raw)
        │
        ▼
AWS Step Functions
        │
        ▼
Glue Bronze ETL
        │
        ▼
Data Quality Validation
        │
 ┌──────┴─────────┐
 ▼                ▼
Reject Bucket   Curated Layer
                    │
                    ▼
              Gold Layer
                    │
                    ▼
             Glue Crawler
                    │
                    ▼
          Glue Data Catalog
                    │
                    ▼
              Amazon Athena
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
 DynamoDB Audit           SNS Notification
```

---

## 🛠️ Tech Stack

- Python
- PySpark
- AWS Glue
- Amazon S3
- AWS Lambda
- AWS Step Functions
- Amazon Athena
- AWS Glue Data Catalog
- AWS Glue Crawlers
- Amazon DynamoDB
- Amazon SNS
- Amazon CloudWatch
- IAM
- Bash
- Git & GitHub

---

## 📂 Project Structure

```
config/
scripts/
iam/
ingestion/
glue/
lambda/
crawler/
athena/
stepfunctions/
monitoring/
tests/
docs/
```

---

## 🚀 Current Status

Project is under active development.

Phase 1: Repository Setup ✅

---

## 📄 License

MIT License