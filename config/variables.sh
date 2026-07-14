#!/bin/bash

##########################################
# Project Information
##########################################
PROJECT_NAME="nyc-tlc"

ENVIRONMENT="dev"

AWS_REGION="us-east-1"

RESOURCE_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

##########################################
# AWS Account
##########################################

ACCOUNT_ID=$(aws sts get-caller-identity \
--query Account \
--output text)

##########################################
# S3 Buckets
##########################################
RAW_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-raw-${ACCOUNT_ID}"

CURATED_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-curated-${ACCOUNT_ID}"

GOLD_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-gold-${ACCOUNT_ID}"

REJECT_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-reject-${ACCOUNT_ID}"

ATHENA_RESULTS_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-athena-${ACCOUNT_ID}"

ASSETS_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-assets-${ACCOUNT_ID}"

##########################################
# Glue
##########################################

GLUE_DATABASE="${PROJECT_NAME}_${ENVIRONMENT}_db"

##########################################
# DynamoDB
##########################################

AUDIT_TABLE="${PROJECT_NAME}_${ENVIRONMENT}_audit"

##########################################
# EventBridge
##########################################

EVENT_BUS_NAME="${PROJECT_NAME}-${ENVIRONMENT}-event-bus"
EVENT_RULE_SUCCESS="${PROJECT_NAME}-${ENVIRONMENT}-glue-success-rule"
EVENT_RULE_FAILURE="${PROJECT_NAME}-${ENVIRONMENT}-glue-failure-rule"
EVENT_RULE_COMPLETE="${PROJECT_NAME}-${ENVIRONMENT}-pipeline-complete-rule"

##########################################
# IAM Roles
##########################################

GLUE_ROLE="${PROJECT_NAME}-GlueExecutionRole"

LAMBDA_ROLE="${PROJECT_NAME}-LambdaExecutionRole"

STEP_FUNCTION_ROLE="${PROJECT_NAME}-StepFunctionExecutionRole"
##########################################
# Glue Crawler
##########################################

CRAWLER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-raw-crawler"
CRAWLER_ROLE="${GLUE_ROLE}"

SILVER_CRAWLER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-silver-crawler"
GOLD_CRAWLER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-gold-crawler"

############################################
# Glue Job - Bronze
############################################
GLUE_JOB_NAME="nyc-tlc-bronze-job-dev"
GLUE_VERSION="5.0"
WORKER_TYPE="G.1X"
NUMBER_OF_WORKERS="2"
SCRIPT_LOCATION="s3://$ASSETS_BUCKET/glue/bronze/bronze_job.py"

############################################
# Glue Job - Silver
############################################
SILVER_JOB_NAME="nyc-tlc-silver-job-dev"
SILVER_SCRIPT_LOCATION="s3://$ASSETS_BUCKET/glue/silver/silver_job.py"
BRONZE_PATH="s3://$CURATED_BUCKET/bronze"
SILVER_PATH="s3://$CURATED_BUCKET/silver"
REJECT_PATH="s3://$REJECT_BUCKET/silver"

############################################
# Glue Job - Gold
############################################
GOLD_JOB_NAME="nyc-tlc-gold-job-dev"
GOLD_SCRIPT_LOCATION="s3://$ASSETS_BUCKET/glue/gold/gold_job.py"
GOLD_PATH="s3://$GOLD_BUCKET/gold"
##########################################
# Logging
##########################################
############################################
##########################################
# IAM Policy
##########################################

GLUE_S3_POLICY_NAME="nyc-tlc-glue-s3-policy"
LOG_FILE="logs/deployment.log"

##########################################
# Step Functions
##########################################

STATE_MACHINE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-pipeline"

##########################################
# SES Email Notifications
# NOTE: Set real values as Lambda env vars
# Do NOT commit real emails to git
##########################################

SENDER_EMAIL="REPLACE_WITH_VERIFIED_SES_EMAIL"
RECIPIENT_EMAIL="REPLACE_WITH_RECIPIENT_EMAIL"
