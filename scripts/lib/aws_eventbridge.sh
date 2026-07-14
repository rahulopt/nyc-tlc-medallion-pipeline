#!/bin/bash

#############################################################
# AWS EventBridge Library
# EventBridge event bus and rule creation functions
#############################################################


#############################################################
# Check if Event Bus Exists
#############################################################

event_bus_exists() {

    local bus_name="$1"

    aws events describe-event-bus \
        --name "$bus_name" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1

}


#############################################################
# Create Custom Event Bus
#############################################################

create_event_bus() {

    local bus_name="$1"

    if event_bus_exists "$bus_name"
    then
        log_warning "Event bus already exists: $bus_name"
        return
    fi

    log_info "Creating EventBridge event bus: $bus_name"

    aws events create-event-bus \
        --name "$bus_name" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating event bus: $bus_name"
    fi

    log_success "Event bus created: $bus_name"

}


#############################################################
# Check if Rule Exists
#############################################################

rule_exists() {

    local rule_name="$1"
    local bus_name="$2"

    aws events describe-rule \
        --name "$rule_name" \
        --event-bus-name "$bus_name" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1

}


#############################################################
# Create EventBridge Rule — Glue Job SUCCEEDED
#############################################################

create_success_rule() {

    local rule_name="$1"
    local bus_name="$2"

    if rule_exists "$rule_name" "$bus_name"
    then
        log_warning "Rule already exists: $rule_name"
        return
    fi

    log_info "Creating success rule: $rule_name"

    aws events put-rule \
        --name "$rule_name" \
        --event-bus-name "$bus_name" \
        --event-pattern '{
            "source": ["aws.glue"],
            "detail-type": ["Glue Job State Change"],
            "detail": {
                "state": ["SUCCEEDED"]
            }
        }' \
        --state "ENABLED" \
        --description "Triggers on Glue job SUCCEEDED events" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating success rule: $rule_name"
    fi

    log_success "Success rule created: $rule_name"

}


#############################################################
# Create EventBridge Rule — Glue Job FAILED
#############################################################

create_failure_rule() {

    local rule_name="$1"
    local bus_name="$2"

    if rule_exists "$rule_name" "$bus_name"
    then
        log_warning "Rule already exists: $rule_name"
        return
    fi

    log_info "Creating failure rule: $rule_name"

    aws events put-rule \
        --name "$rule_name" \
        --event-bus-name "$bus_name" \
        --event-pattern '{
            "source": ["aws.glue"],
            "detail-type": ["Glue Job State Change"],
            "detail": {
                "state": ["FAILED", "ERROR", "STOPPED"]
            }
        }' \
        --state "ENABLED" \
        --description "Triggers on Glue job FAILED/ERROR/STOPPED events" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating failure rule: $rule_name"
    fi

    log_success "Failure rule created: $rule_name"

}


#############################################################
# Create EventBridge Rule — Pipeline Complete
#############################################################

create_complete_rule() {

    local rule_name="$1"
    local bus_name="$2"

    if rule_exists "$rule_name" "$bus_name"
    then
        log_warning "Rule already exists: $rule_name"
        return
    fi

    log_info "Creating pipeline complete rule: $rule_name"

    aws events put-rule \
        --name "$rule_name" \
        --event-bus-name "$bus_name" \
        --event-pattern '{
            "source": ["aws.glue"],
            "detail-type": ["Glue Job State Change"],
            "detail": {
                "jobName": ["nyc-tlc-gold-job-dev"],
                "state": ["SUCCEEDED"]
            }
        }' \
        --state "ENABLED" \
        --description "Triggers when final gold job completes — pipeline done" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating complete rule: $rule_name"
    fi

    log_success "Pipeline complete rule created: $rule_name"

}


#############################################################
# Add Lambda Target to Rule
#############################################################

add_lambda_target() {

    local rule_name="$1"
    local bus_name="$2"
    local lambda_arn="$3"
    local target_id="$4"

    log_info "Adding Lambda target to rule: $rule_name"

    aws events put-targets \
        --rule "$rule_name" \
        --event-bus-name "$bus_name" \
        --targets "Id=${target_id},Arn=${lambda_arn}" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed adding target to rule: $rule_name"
    fi

    log_success "Lambda target added: $target_id -> $rule_name"

}


#############################################################
# Grant EventBridge permission to invoke Lambda
#############################################################

grant_eventbridge_invoke() {

    local lambda_name="$1"
    local rule_arn="$2"
    local statement_id="$3"

    # Remove existing permission if present (ignore error)
    aws lambda remove-permission \
        --function-name "$lambda_name" \
        --statement-id  "$statement_id" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1 || true

    log_info "Granting EventBridge invoke permission on: $lambda_name"

    aws lambda add-permission \
        --function-name "$lambda_name" \
        --statement-id  "$statement_id" \
        --action        "lambda:InvokeFunction" \
        --principal     "events.amazonaws.com" \
        --source-arn    "$rule_arn" \
        --region        "$AWS_REGION"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed granting invoke permission: $lambda_name"
    fi

    log_success "Invoke permission granted: $lambda_name"

}
