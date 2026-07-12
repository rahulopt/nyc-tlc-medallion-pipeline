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

