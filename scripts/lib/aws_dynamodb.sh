#!/bin/bash

#############################################################
# AWS DynamoDB Library
# DynamoDB table creation and management functions
#############################################################


#############################################################
# Check if Table Exists
#############################################################

table_exists() {

    local table_name="$1"

    aws dynamodb describe-table \
        --table-name "$table_name" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1

}


#############################################################
# Create Audit Table
#
# Schema:
#   PK : job_run_id  (String) — unique per Glue job run
#   SK : event_time  (String) — ISO timestamp, sort by time
#
# Attributes stored by Lambda audit_logger:
#   - job_name
#   - state (SUCCEEDED / FAILED)
#   - message
#   - started_on
#   - completed_on
#   - logged_at
#############################################################

create_audit_table() {

    local table_name="$1"

    if table_exists "$table_name"
    then
        log_warning "DynamoDB table already exists: $table_name"
        return
    fi

    log_info "Creating DynamoDB audit table: $table_name"

    aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions \
            AttributeName=job_run_id,AttributeType=S \
            AttributeName=event_time,AttributeType=S \
        --key-schema \
            AttributeName=job_run_id,KeyType=HASH \
            AttributeName=event_time,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating DynamoDB table: $table_name"
    fi

    # Wait until table is ACTIVE
    log_info "Waiting for table to become ACTIVE..."

    aws dynamodb wait table-exists \
        --table-name "$table_name" \
        --region "$AWS_REGION"

    log_success "DynamoDB audit table ready: $table_name"

}


#############################################################
# Enable TTL on Audit Table
# Auto-delete records older than 90 days
#############################################################

enable_ttl() {

    local table_name="$1"

    log_info "Enabling TTL on table: $table_name"

    aws dynamodb update-time-to-live \
        --table-name "$table_name" \
        --time-to-live-specification \
            "Enabled=true,AttributeName=ttl" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed enabling TTL on: $table_name"
    fi

    log_success "TTL enabled on: $table_name"

}
