#!/bin/bash

set -euo pipefail

#############################################################
# Load Configuration
#############################################################

source config/variables.sh


#############################################################
# Load Libraries
#############################################################

source scripts/lib/utils.sh
source scripts/lib/aws_s3.sh


#############################################################
# Main Cleanup
#############################################################

main() {

    log_warning "Starting AWS Infrastructure Cleanup"


    BUCKETS=(
        "$RAW_BUCKET"
        "$CURATED_BUCKET"
        "$GOLD_BUCKET"
        "$REJECT_BUCKET"
        "$ATHENA_RESULTS_BUCKET"
        "$ASSETS_BUCKET"
    )


    for bucket in "${BUCKETS[@]}"
    do

        log_info "Deleting bucket: $bucket"

        delete_bucket "$bucket"

    done


    log_success "Cleanup completed successfully"

}


main