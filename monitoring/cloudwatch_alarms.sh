#!/bin/bash

set -euo pipefail

#############################################################
# CloudWatch Alarms — NYC TLC Medallion Pipeline
# Creates alarms for Glue job failures and Lambda errors
#############################################################

source config/variables.sh
source scripts/lib/utils.sh


#############################################################
# Helper — Create or update alarm
#############################################################

create_alarm() {

    local alarm_name="$1"
    local description="$2"
    local namespace="$3"
    local metric="$4"
    local dimensions="$5"
    local threshold="$6"
    local comparison="$7"
    local period="$8"
    local eval_periods="$9"

    log_info "Creating alarm: $alarm_name"

    aws cloudwatch put-metric-alarm \
        --alarm-name        "$alarm_name" \
        --alarm-description "$description" \
        --namespace         "$namespace" \
        --metric-name       "$metric" \
        --dimensions        $dimensions \
        --threshold         "$threshold" \
        --comparison-operator "$comparison" \
        --period            "$period" \
        --evaluation-periods "$eval_periods" \
        --statistic         "Sum" \
        --treat-missing-data "notBreaching" \
        --region            "$AWS_REGION"

    if [ $? -ne 0 ]; then
        exit_on_error "Failed creating alarm: $alarm_name"
    fi

    log_success "Alarm created: $alarm_name"

}


#############################################################
# Main
#############################################################

main() {

    log_info "Creating CloudWatch Alarms"

    check_aws_cli
    check_aws_credentials


    #############################################################
    # Glue Job Failure Alarms
    #############################################################

    log_info "=== Glue Job Alarms ==="

    for JOB in "$GLUE_JOB_NAME" "$SILVER_JOB_NAME" "$GOLD_JOB_NAME"; do

        create_alarm \
            "${JOB}-failure-alarm" \
            "Triggers when Glue job $JOB fails" \
            "Glue" \
            "glue.driver.aggregate.numFailedTasks" \
            "Name=JobName,Value=${JOB}" \
            "1" \
            "GreaterThanOrEqualToThreshold" \
            "300" \
            "1"

    done


    #############################################################
    # Lambda Error Alarms
    #############################################################

    log_info "=== Lambda Error Alarms ==="

    for FUNC in "nyc-tlc-audit-logger" "nyc-tlc-notifier" "nyc-tlc-metadata-validator"; do

        create_alarm \
            "${FUNC}-error-alarm" \
            "Triggers when Lambda $FUNC has errors" \
            "AWS/Lambda" \
            "Errors" \
            "Name=FunctionName,Value=${FUNC}" \
            "1" \
            "GreaterThanOrEqualToThreshold" \
            "60" \
            "1"

    done


    #############################################################
    # DynamoDB Alarms
    #############################################################

    log_info "=== DynamoDB Alarms ==="

    create_alarm \
        "${AUDIT_TABLE}-system-errors" \
        "Triggers on DynamoDB system errors in audit table" \
        "AWS/DynamoDB" \
        "SystemErrors" \
        "Name=TableName,Value=${AUDIT_TABLE}" \
        "1" \
        "GreaterThanOrEqualToThreshold" \
        "60" \
        "1"


    #############################################################
    # Step Functions Alarm
    #############################################################

    log_info "=== Step Functions Alarms ==="

    create_alarm \
        "${STATE_MACHINE_NAME}-failed-alarm" \
        "Triggers when pipeline state machine execution fails" \
        "AWS/States" \
        "ExecutionsFailed" \
        "Name=StateMachineArn,Value=arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
        "1" \
        "GreaterThanOrEqualToThreshold" \
        "60" \
        "1"


    log_success "All CloudWatch Alarms created!"
    log_info "View in AWS Console → CloudWatch → Alarms"

}

main
