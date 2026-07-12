#!/bin/bash


#############################################################
# Check if bucket exists
#############################################################

bucket_exists() {

    local bucket_name="$1"

    aws s3api head-bucket \
        --bucket "$bucket_name" \
        >/dev/null 2>&1
}

#############################################################
# Create Bucket
#############################################################

create_folder_structure() {

    local bucket_name="$1"


    case "$bucket_name" in


    *-raw-*)
        folders=(
            "raw/"
        )
        ;;


    *-curated-*)
        folders=(
            "silver/"
        )
        ;;


    *-gold-*)
        folders=(
            "gold/"
        )
        ;;


    *-reject-*)
        folders=(
            "rejected/"
        )
        ;;


    *-assets-*)
        folders=(
            "scripts/"
            "configs/"
        )
        ;;


    *-athena-*)
        folders=(
            "query-results/"
        )
        ;;


    *)
        log_warning "No folder structure defined for $bucket_name"
        return
        ;;

    esac



    for folder in "${folders[@]}"
    do

        aws s3api put-object \
        --bucket "$bucket_name" \
        --key "$folder"

    done

}
#############################################################
# Create Bucket
#############################################################

create_bucket() {

    local bucket_name="$1"


    if bucket_exists "$bucket_name"
    then
        log_warning "Bucket already exists : $bucket_name"
        return
    fi


    log_info "Creating bucket : $bucket_name"


    aws s3api create-bucket \
        --bucket "$bucket_name" \
        --region us-east-1


    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating bucket : $bucket_name"
    fi


    log_success "Bucket created : $bucket_name"

}
#############################################################
# Enable Versioning
#############################################################

enable_versioning() {

    local bucket_name="$1"

    log_info "Enabling versioning : $bucket_name"

    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed to enable versioning : $bucket_name"
    fi

    log_success "Versioning enabled : $bucket_name"

}

#############################################################
# Block Public Access
#############################################################

block_public_access() {

    local bucket_name="$1"

    log_info "Blocking public access : $bucket_name"

    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed to block public access : $bucket_name"
    fi

    log_success "Public access blocked : $bucket_name"

}


#############################################################
# Delete Bucket
#############################################################

delete_bucket() {

    local bucket_name="$1"

    if ! bucket_exists "$bucket_name"
    then
        log_warning "Bucket does not exist : $bucket_name"
        return
    fi

    log_info "Deleting bucket : $bucket_name"

    aws s3 rm s3://"$bucket_name" \
        --recursive \
        >/dev/null 2>&1

    aws s3api delete-bucket \
        --bucket "$bucket_name"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed to delete bucket : $bucket_name"
    fi

    log_success "Bucket deleted : $bucket_name"

}