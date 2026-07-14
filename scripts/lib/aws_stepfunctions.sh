#!/bin/bash

#############################################################
# AWS Step Functions Library
# State Machine creation and execution functions
#############################################################


#############################################################
# Step Functions Variables
#############################################################

STATE_MACHINE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-pipeline"


#############################################################
# Check if State Machine Exists
#############################################################

state_machine_exists() {

    local name="$1"

    aws stepfunctions list-state-machines \
        --region "$AWS_REGION" \
        --query "stateMachines[?name=='$name'].stateMachineArn" \
        --output text | grep -q "arn"

}


#############################################################
# Get State Machine ARN
#############################################################

get_state_machine_arn() {

    local name="$1"

    aws stepfunctions list-state-machines \
        --region "$AWS_REGION" \
        --query "stateMachines[?name=='$name'].stateMachineArn" \
        --output text

}


#############################################################
# Create State Machine
#############################################################

create_state_machine() {

    local name="$1"
    local role_name="$2"
    local definition_file="$3"

    if state_machine_exists "$name"
    then
        log_warning "State machine already exists: $name"
        return
    fi

    local role_arn
    role_arn=$(aws iam get-role \
        --role-name "$role_name" \
        --query 'Role.Arn' \
        --output text)

    if [ -z "$role_arn" ]
    then
        exit_on_error "IAM role not found: $role_name"
    fi

    log_info "Creating Step Functions state machine: $name"

    aws stepfunctions create-state-machine \
        --name "$name" \
        --role-arn "$role_arn" \
        --definition "file://$definition_file" \
        --type "STANDARD" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating state machine: $name"
    fi

    log_success "State machine created: $name"
    log_info "View diagram: AWS Console → Step Functions → $name"

}


#############################################################
# Update existing State Machine definition
#############################################################

update_state_machine() {

    local name="$1"
    local definition_file="$2"

    local arn
    arn=$(get_state_machine_arn "$name")

    if [ -z "$arn" ]
    then
        exit_on_error "State machine not found: $name"
    fi

    log_info "Updating state machine: $name"

    aws stepfunctions update-state-machine \
        --state-machine-arn "$arn" \
        --definition "file://$definition_file" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed updating state machine: $name"
    fi

    log_success "State machine updated: $name"

}


#############################################################
# Start Execution
#############################################################

start_pipeline() {

    local name="$1"

    local arn
    arn=$(get_state_machine_arn "$name")

    if [ -z "$arn" ]
    then
        exit_on_error "State machine not found: $name"
    fi

    local execution_name
    execution_name="run-$(date +%Y%m%d-%H%M%S)"

    log_info "Starting pipeline execution: $execution_name"

    EXECUTION_ARN=$(aws stepfunctions start-execution \
        --state-machine-arn "$arn" \
        --name "$execution_name" \
        --region "$AWS_REGION" \
        --query 'executionArn' \
        --output text)

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed starting pipeline execution"
    fi

    log_success "Pipeline started!"
    log_info "Execution ARN : $EXECUTION_ARN"
    log_info "Track here    : AWS Console → Step Functions → Executions"

}
