#!/bin/bash

set -euo pipefail


source config/variables.sh


source scripts/lib/utils.sh
source scripts/lib/aws_s3.sh
source scripts/lib/aws_iam.sh
source scripts/lib/aws_glue.sh


# BUG FIX #2: Removed duplicate "source config/variables.sh"
# (was sourced twice — once at top, once after lib imports)


main() {

    log_info "Starting AWS Infrastructure Deployment"

    check_aws_cli
    check_aws_credentials


    BUCKETS=(
        "$RAW_BUCKET"
        "$CURATED_BUCKET"
        "$GOLD_BUCKET"
        "$REJECT_BUCKET"
        "$ATHENA_RESULTS_BUCKET"
        "$ASSETS_BUCKET"
    )


    COUNT=1
    TOTAL=${#BUCKETS[@]}


    for bucket in "${BUCKETS[@]}"
    do

        log_info "Creating bucket [$COUNT/$TOTAL]: $bucket"

        create_bucket "$bucket"

        enable_versioning "$bucket"

        block_public_access "$bucket"

        create_folder_structure "$bucket"

        log_success "Completed [$COUNT/$TOTAL]: $bucket"

        COUNT=$((COUNT+1))

    done


    log_success "All S3 resources created successfully"



    #############################################################
    # IAM Roles
    #############################################################

    log_info "Creating IAM Roles"


    GLUE_TRUST_POLICY=$(cat iam/trust/glue-trust-policy.json)

    LAMBDA_TRUST_POLICY=$(cat iam/trust/lambda-trust-policy.json)

    STEPFUNCTION_TRUST_POLICY=$(cat iam/trust/stepfunctions-trust-policy.json)



    create_role "$GLUE_ROLE" "$GLUE_TRUST_POLICY"

    create_role "$LAMBDA_ROLE" "$LAMBDA_TRUST_POLICY"

    create_role "$STEP_FUNCTION_ROLE" "$STEPFUNCTION_TRUST_POLICY"


    log_success "IAM Roles Created"

    # BUG FIX #1: Removed duplicate "IAM Roles Created" log
    # BUG FIX #1: Removed premature "Infrastructure Deployment Completed" message
    # (it was appearing BEFORE policies, Glue DB, Crawler, and Job were created)


    #############################################################
    # Attach IAM Policies
    #############################################################

    log_info "Attaching IAM Policies"


    # Glue
    attach_managed_policy \
    "$GLUE_ROLE" \
    "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"


    # Lambda
    attach_managed_policy \
    "$LAMBDA_ROLE" \
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"


    # Step Function
    attach_managed_policy \
    "$STEP_FUNCTION_ROLE" \
    "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"


    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    sed "s/__ACCOUNT_ID__/$ACCOUNT_ID/g" \
    iam/policies/glue-s3-policy.json \
    > /tmp/glue-s3-policy.json

    create_policy \
    "$GLUE_S3_POLICY_NAME" \
    "/tmp/glue-s3-policy.json"

    attach_custom_policy \
    "$GLUE_ROLE" \
    "$GLUE_S3_POLICY_NAME"

    # BUG FIX #3: Changed log_info -> log_success for policy attachment completion
    # BUG FIX #3: Removed duplicate "IAM Policies Attached" log_success before attach_custom_policy
    log_success "IAM Policies Attached"


    #############################################################
    # Glue Database
    #############################################################

    log_info "Creating Glue Database"

    create_glue_database \
    "$GLUE_DATABASE"

    log_success "Glue Database Setup Completed"

    #############################################################
    # Glue Crawler
    #############################################################

    log_info "Creating Glue Crawler"


    create_glue_crawler \
    "$CRAWLER_NAME" \
    "$GLUE_DATABASE" \
    "$GLUE_ROLE" \
    "s3://$RAW_BUCKET"


    log_success "Glue Crawler Setup Completed"

    #############################################################
    # Glue Job - Bronze
    #############################################################

    log_info "Creating Bronze Glue Job"

    create_glue_job \
    "$GLUE_JOB_NAME" \
    "$GLUE_ROLE"

    log_success "Bronze Glue Job Setup Completed"


    #############################################################
    # Glue Job - Silver
    #############################################################

    log_info "Creating Silver Glue Job"

    create_silver_glue_job \
    "$SILVER_JOB_NAME" \
    "$GLUE_ROLE"

    log_success "Silver Glue Job Setup Completed"


    #############################################################
    # Glue Job - Gold
    #############################################################

    log_info "Creating Gold Glue Job"

    create_gold_glue_job \
    "$GOLD_JOB_NAME" \
    "$GLUE_ROLE"

    log_success "Gold Glue Job Setup Completed"


    # BUG FIX #1: Moved completion message to the actual END of main()
    log_success "Infrastructure Deployment Completed"

}
main
