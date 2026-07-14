#!/bin/bash

#############################################################
# AWS IAM Library
# IAM Role Creation Functions
#############################################################


#############################################################
# Check IAM Role Exists
#############################################################

role_exists() {

    local role_name="$1"

    aws iam get-role \
        --role-name "$role_name" \
        >/dev/null 2>&1

}


#############################################################
# Create IAM Role
#############################################################

create_role() {

    local role_name="$1"
    local trust_policy="$2"


    if role_exists "$role_name"
    then
        log_warning "Role already exists : $role_name"
        return
    fi


    log_info "Creating IAM Role : $role_name"


    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy"


    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating role : $role_name"
    fi


    log_success "Role created : $role_name"

}


#############################################################
# Attach Policy
#############################################################

attach_policy() {

    local role_name="$1"
    local policy_arn="$2"


    log_info "Attaching policy to $role_name"


    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "$policy_arn"


    if [ $? -ne 0 ]
    then
        exit_on_error "Policy attachment failed"
    fi


    log_success "Policy attached"

}

#############################################################
# Attach Managed Policy
#############################################################

attach_managed_policy() {

    local role_name="$1"
    local policy_arn="$2"


    log_info "Attaching policy: $policy_arn"


    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "$policy_arn"


    if [ $? -ne 0 ]
    then
        exit_on_error "Failed attaching policy to $role_name"
    fi


    log_success "Policy attached to $role_name"
}
 
policy_exists() {

    local policy_arn="$1"

    aws iam get-policy \
        --policy-arn "$policy_arn" \
        >/dev/null 2>&1
}

create_policy() {

    local policy_name="$1"
    local policy_document="$2"

    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)

    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"

    if policy_exists "$policy_arn"
    then
        log_warning "Policy already exists : $policy_name"
        return
    fi

    log_info "Creating IAM Policy : $policy_name"

    aws iam create-policy \
        --policy-name "$policy_name" \
        --policy-document "file://$policy_document"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating IAM Policy"
    fi

    log_success "IAM Policy created : $policy_name"
}

attach_custom_policy() {

    local role_name="$1"
    local policy_name="$2"

    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)

    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"

    log_info "Attaching custom policy : $policy_name"

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "$policy_arn"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed attaching custom policy"
    fi

    log_success "Custom policy attached to $role_name"
}

