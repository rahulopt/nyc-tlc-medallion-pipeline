#!/bin/bash

set -euo pipefail

#############################################################
# Lambda Deploy Script
# Packages and deploys Lambda functions to AWS
# Email credentials passed as env vars — NOT stored in git
#############################################################

source config/variables.sh
source scripts/lib/utils.sh


#############################################################
# Config
#############################################################

# Real emails set here — NOT in variables.sh or git
SENDER_EMAIL_REAL="rahulopt14@gmail.com"
RECIPIENT_EMAIL_REAL="rahulopt14@gmail.com"

AUDIT_LOGGER_NAME="nyc-tlc-audit-logger"
NOTIFIER_NAME="nyc-tlc-notifier"

LAMBDA_RUNTIME="python3.12"
LAMBDA_HANDLER="lambda_function.lambda_handler"
LAMBDA_TIMEOUT=30
LAMBDA_MEMORY=128


#############################################################
# Helper — Package Lambda zip
#############################################################

package_lambda() {

    local src_dir="$1"
    local zip_file="$2"

    log_info "Packaging Lambda: $src_dir"

    zip -j "$zip_file" "$src_dir/lambda_function.py"

    log_success "Packaged: $zip_file"

}


#############################################################
# Helper — Check if Lambda exists
#############################################################

lambda_exists() {

    local name="$1"

    aws lambda get-function \
        --function-name "$name" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1

}


#############################################################
# Helper — Create Lambda function
#############################################################

create_lambda() {

    local name="$1"
    local zip_file="$2"
    local env_vars="$3"

    local role_arn
    role_arn=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE" \
        --query 'Role.Arn' \
        --output text)

    log_info "Creating Lambda: $name"

    aws lambda create-function \
        --function-name "$name" \
        --runtime "$LAMBDA_RUNTIME" \
        --role "$role_arn" \
        --handler "$LAMBDA_HANDLER" \
        --zip-file "fileb://$zip_file" \
        --timeout "$LAMBDA_TIMEOUT" \
        --memory-size "$LAMBDA_MEMORY" \
        --environment "Variables={$env_vars}" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]; then
        exit_on_error "Failed creating Lambda: $name"
    fi

    log_success "Lambda created: $name"

}


#############################################################
# Helper — Update Lambda code + env vars
#############################################################

update_lambda() {

    local name="$1"
    local zip_file="$2"
    local env_vars="$3"

    log_info "Updating Lambda code: $name"

    aws lambda update-function-code \
        --function-name "$name" \
        --zip-file "fileb://$zip_file" \
        --region "$AWS_REGION"

    # Wait for update to complete
    aws lambda wait function-updated \
        --function-name "$name" \
        --region "$AWS_REGION"

    log_info "Updating Lambda env vars: $name"

    aws lambda update-function-configuration \
        --function-name "$name" \
        --environment "Variables={$env_vars}" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]; then
        exit_on_error "Failed updating Lambda: $name"
    fi

    log_success "Lambda updated: $name"

}


#############################################################
# Deploy a Lambda (create or update)
#############################################################

deploy_lambda() {

    local name="$1"
    local src_dir="$2"
    local env_vars="$3"

    local zip_file="/tmp/${name}.zip"

    package_lambda "$src_dir" "$zip_file"

    if lambda_exists "$name"; then
        update_lambda "$name" "$zip_file" "$env_vars"
    else
        create_lambda "$name" "$zip_file" "$env_vars"
    fi

    rm -f "$zip_file"

}


#############################################################
# Main
#############################################################

main() {

    log_info "Starting Lambda Deployment"

    check_aws_cli
    check_aws_credentials


    #############################################################
    # Deploy audit_logger
    # Env vars: AUDIT_TABLE, AWS_REGION
    #############################################################

    log_info "=== Deploying audit_logger ==="

    deploy_lambda \
        "$AUDIT_LOGGER_NAME" \
        "lambda/audit_logger" \
        "AUDIT_TABLE=${AUDIT_TABLE},AWS_REGION=${AWS_REGION}"

    log_success "audit_logger deployed"


    #############################################################
    # Deploy notifier
    # Env vars: AWS_REGION, LOG_GROUP_NAME, SENDER_EMAIL, RECIPIENT_EMAIL
    # Email set here — NOT in git
    #############################################################

    log_info "=== Deploying notifier ==="

    deploy_lambda \
        "$NOTIFIER_NAME" \
        "lambda/notifier" \
        "AWS_REGION=${AWS_REGION},LOG_GROUP_NAME=/nyc-tlc/pipeline/notifications,SENDER_EMAIL=${SENDER_EMAIL_REAL},RECIPIENT_EMAIL=${RECIPIENT_EMAIL_REAL}"

    log_success "notifier deployed"


    log_success "All Lambda functions deployed!"
    log_info "Reminder: Verify $SENDER_EMAIL_REAL in AWS SES Console"

}

main
