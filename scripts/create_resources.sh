#!/bin/bash

set -euo pipefail


source config/variables.sh


source scripts/lib/utils.sh
source scripts/lib/aws_s3.sh
source scripts/lib/aws_iam.sh
source scripts/lib/aws_glue.sh



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


    log_success "Infrastructure Deployment Completed"

       log_success "IAM Roles Created"


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



    log_success "IAM Policies Attached"


    log_success "Infrastructure Deployment Completed"

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


}
main
