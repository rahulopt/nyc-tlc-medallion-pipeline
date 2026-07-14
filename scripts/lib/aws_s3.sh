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
# Delete Bucket (including all versions)
#############################################################

delete_bucket() {

    local bucket_name="$1"

    if ! bucket_exists "$bucket_name"
    then
        log_warning "Bucket does not exist : $bucket_name"
        return
    fi

    log_info "Deleting bucket : $bucket_name"

    # Delete all object versions (handles versioning-enabled buckets)
    VERSIONS=$(aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null || echo '{"Objects":[]}')

    if [ "$(echo "$VERSIONS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('Objects') or []))")" -gt "0" ]; then
        echo "$VERSIONS" | python3 -c "
import sys, json, subprocess
data = json.load(sys.stdin)
objects = data.get('Objects') or []
# batch delete in groups of 1000
for i in range(0, len(objects), 1000):
    batch = objects[i:i+1000]
    delete_payload = json.dumps({'Objects': batch, 'Quiet': True})
    subprocess.run([
        'aws', 's3api', 'delete-objects',
        '--bucket', '$bucket_name',
        '--delete', delete_payload
    ], capture_output=True)
print(f'Deleted {len(objects)} versions')
"
    fi

    # Delete all delete markers
    MARKERS=$(aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null || echo '{"Objects":[]}')

    if [ "$(echo "$MARKERS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('Objects') or []))")" -gt "0" ]; then
        echo "$MARKERS" | python3 -c "
import sys, json, subprocess
data = json.load(sys.stdin)
objects = data.get('Objects') or []
for i in range(0, len(objects), 1000):
    batch = objects[i:i+1000]
    delete_payload = json.dumps({'Objects': batch, 'Quiet': True})
    subprocess.run([
        'aws', 's3api', 'delete-objects',
        '--bucket', '$bucket_name',
        '--delete', delete_payload
    ], capture_output=True)
print(f'Deleted {len(objects)} delete markers')
"
    fi

    # Delete remaining non-versioned objects
    aws s3 rm "s3://$bucket_name" \
        --recursive \
        >/dev/null 2>&1 || true

    # Now delete the bucket
    aws s3api delete-bucket \
        --bucket "$bucket_name"

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed to delete bucket : $bucket_name"
    fi

    log_success "Bucket deleted : $bucket_name"

}