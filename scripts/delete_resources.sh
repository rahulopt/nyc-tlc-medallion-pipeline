#!/bin/bash

set -euo pipefail

#############################################################
# Delete All AWS Resources
# Cleans up everything created by create_resources.sh
#############################################################

source config/variables.sh
source scripts/lib/utils.sh
source scripts/lib/aws_s3.sh


#############################################################
# Main Cleanup
#############################################################

main() {

    log_warning "Starting AWS Infrastructure Cleanup"
    log_warning "This will DELETE all project resources!"
    echo ""
    read -p "Are you sure? Type 'yes' to continue: " CONFIRM

    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi


    #############################################################
    # Stop Running Step Functions Executions
    #############################################################

    log_info "Stopping running Step Functions executions"

    SF_ARN=$(aws stepfunctions list-state-machines \
        --region "$AWS_REGION" \
        --query "stateMachines[?name=='$STATE_MACHINE_NAME'].stateMachineArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$SF_ARN" ]; then

        RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
            --state-machine-arn "$SF_ARN" \
            --status-filter "RUNNING" \
            --region "$AWS_REGION" \
            --query 'executions[*].executionArn' \
            --output text 2>/dev/null || echo "")

        for EXEC_ARN in $RUNNING_EXECUTIONS; do
            log_info "Aborting execution: $EXEC_ARN"
            aws stepfunctions stop-execution \
                --execution-arn "$EXEC_ARN" \
                --region "$AWS_REGION" \
                >/dev/null 2>&1 || true
            log_success "Execution aborted"
        done

    fi


    #############################################################
    # Stop Running Glue Jobs
    #############################################################

    log_info "Stopping running Glue jobs"

    for JOB in "$GLUE_JOB_NAME" "$SILVER_JOB_NAME" "$GOLD_JOB_NAME"; do

        RUNNING_RUN_ID=$(aws glue get-job-runs \
            --job-name "$JOB" \
            --region "$AWS_REGION" \
            --query "JobRuns[?JobRunState=='RUNNING'].Id | [0]" \
            --output text 2>/dev/null || echo "")

        if [ -n "$RUNNING_RUN_ID" ] && [ "$RUNNING_RUN_ID" != "None" ]; then
            log_info "Stopping job run: $JOB ($RUNNING_RUN_ID)"
            aws glue batch-stop-job-run \
                --job-name "$JOB" \
                --job-run-ids "$RUNNING_RUN_ID" \
                --region "$AWS_REGION" \
                >/dev/null 2>&1 || true
            log_success "Job stopped: $JOB"
        fi

    done


    #############################################################
    # Step Functions — Delete State Machine
    #############################################################

    log_info "Deleting Step Functions State Machine"

    if [ -n "$SF_ARN" ]; then
        aws stepfunctions delete-state-machine \
            --state-machine-arn "$SF_ARN" \
            --region "$AWS_REGION"
        log_success "State machine deleted: $STATE_MACHINE_NAME"
    else
        log_warning "State machine not found: $STATE_MACHINE_NAME"
    fi


    #############################################################
    # EventBridge — Rules and Event Bus
    #############################################################

    log_info "Deleting EventBridge Rules"

    for RULE in "$EVENT_RULE_SUCCESS" "$EVENT_RULE_FAILURE" "$EVENT_RULE_COMPLETE"; do

        # Remove targets first
        TARGET_IDS=$(aws events list-targets-by-rule \
            --rule "$RULE" \
            --event-bus-name "$EVENT_BUS_NAME" \
            --region "$AWS_REGION" \
            --query 'Targets[*].Id' \
            --output text 2>/dev/null || echo "")

        if [ -n "$TARGET_IDS" ]; then
            aws events remove-targets \
                --rule "$RULE" \
                --event-bus-name "$EVENT_BUS_NAME" \
                --ids $TARGET_IDS \
                --region "$AWS_REGION" >/dev/null 2>&1 || true
        fi

        # Delete rule
        aws events delete-rule \
            --name "$RULE" \
            --event-bus-name "$EVENT_BUS_NAME" \
            --region "$AWS_REGION" \
            >/dev/null 2>&1 \
            && log_success "Rule deleted: $RULE" \
            || log_warning "Rule not found: $RULE"

    done

    log_info "Deleting EventBridge Event Bus"

    aws events delete-event-bus \
        --name "$EVENT_BUS_NAME" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1 \
        && log_success "Event bus deleted: $EVENT_BUS_NAME" \
        || log_warning "Event bus not found: $EVENT_BUS_NAME"


    #############################################################
    # Lambda Functions
    #############################################################

    log_info "Deleting Lambda Functions"

    for FUNC in "nyc-tlc-audit-logger" "nyc-tlc-notifier" "nyc-tlc-metadata-validator"; do

        aws lambda delete-function \
            --function-name "$FUNC" \
            --region "$AWS_REGION" \
            >/dev/null 2>&1 \
            && log_success "Lambda deleted: $FUNC" \
            || log_warning "Lambda not found: $FUNC"

    done


    #############################################################
    # Glue — Jobs, Crawlers, Database
    #############################################################

    log_info "Deleting Glue Jobs"

    for JOB in "$GLUE_JOB_NAME" "$SILVER_JOB_NAME" "$GOLD_JOB_NAME"; do

        aws glue delete-job \
            --job-name "$JOB" \
            --region "$AWS_REGION" \
            >/dev/null 2>&1 \
            && log_success "Glue job deleted: $JOB" \
            || log_warning "Glue job not found: $JOB"

    done

    log_info "Deleting Glue Crawlers"

    for CRAWLER in "$CRAWLER_NAME" "$SILVER_CRAWLER_NAME" "$GOLD_CRAWLER_NAME"; do

        aws glue delete-crawler \
            --name "$CRAWLER" \
            --region "$AWS_REGION" \
            >/dev/null 2>&1 \
            && log_success "Crawler deleted: $CRAWLER" \
            || log_warning "Crawler not found: $CRAWLER"

    done

    log_info "Deleting Glue Database"

    aws glue delete-database \
        --name "$GLUE_DATABASE" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1 \
        && log_success "Glue database deleted: $GLUE_DATABASE" \
        || log_warning "Glue database not found: $GLUE_DATABASE"


    #############################################################
    # DynamoDB
    #############################################################

    log_info "Deleting DynamoDB Table"

    aws dynamodb delete-table \
        --table-name "$AUDIT_TABLE" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1 \
        && log_success "DynamoDB table deleted: $AUDIT_TABLE" \
        || log_warning "DynamoDB table not found: $AUDIT_TABLE"


    #############################################################
    # IAM — Detach policies, delete roles
    #############################################################

    log_info "Cleaning up IAM Roles"

    for ROLE in "$GLUE_ROLE" "$LAMBDA_ROLE" "$STEP_FUNCTION_ROLE"; do

        # Delete inline policies first
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$ROLE" \
            --query 'PolicyNames[*]' \
            --output text 2>/dev/null || echo "")

        for INLINE_POLICY in $INLINE_POLICIES; do
            aws iam delete-role-policy \
                --role-name "$ROLE" \
                --policy-name "$INLINE_POLICY" \
                >/dev/null 2>&1 || true
            log_success "Inline policy deleted: $INLINE_POLICY from $ROLE"
        done

        # Detach all managed policies
        POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE" \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null || echo "")

        for POLICY_ARN in $POLICIES; do
            aws iam detach-role-policy \
                --role-name "$ROLE" \
                --policy-arn "$POLICY_ARN" \
                >/dev/null 2>&1 || true
        done

        # Delete role
        aws iam delete-role \
            --role-name "$ROLE" \
            >/dev/null 2>&1 \
            && log_success "IAM role deleted: $ROLE" \
            || log_warning "IAM role not found: $ROLE"

    done

    # Delete custom managed policy
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${GLUE_S3_POLICY_NAME}"

    aws iam delete-policy \
        --policy-arn "$POLICY_ARN" \
        >/dev/null 2>&1 \
        && log_success "IAM policy deleted: $GLUE_S3_POLICY_NAME" \
        || log_warning "IAM policy not found: $GLUE_S3_POLICY_NAME"


    #############################################################
    # S3 Buckets
    #############################################################

    log_info "Deleting S3 Buckets"

    BUCKETS=(
        "$RAW_BUCKET"
        "$CURATED_BUCKET"
        "$GOLD_BUCKET"
        "$REJECT_BUCKET"
        "$ATHENA_RESULTS_BUCKET"
        "$ASSETS_BUCKET"
    )

    for BUCKET in "${BUCKETS[@]}"; do
        delete_bucket "$BUCKET"
    done


    log_success "All resources deleted successfully"

}

main
