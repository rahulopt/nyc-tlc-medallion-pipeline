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
# SNS
##########################################

SNS_TOPIC="${PROJECT_NAME}-${ENVIRONMENT}-notifications"

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
##########################################
# Logging
##########################################

LOG_FILE="logs/deployment.log"