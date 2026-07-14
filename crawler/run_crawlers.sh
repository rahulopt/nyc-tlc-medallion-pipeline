#!/bin/bash

set -euo pipefail

#############################################################
# Glue Crawlers — Create & Run
# Registers Silver and Gold data into Glue Data Catalog
# so Athena can query them as SQL tables
#############################################################

source config/variables.sh
source scripts/lib/utils.sh
source scripts/lib/aws_glue.sh


#############################################################
# Helper — Wait for crawler to finish
#############################################################

wait_for_crawler() {

    local crawler_name="$1"

    log_info "Waiting for crawler to finish: $crawler_name"

    for i in $(seq 1 30); do

        sleep 10

        STATE=$(aws glue get-crawler \
            --name "$crawler_name" \
            --region "$AWS_REGION" \
            --query 'Crawler.State' \
            --output text)

        log_info "[$i/30] Crawler state: $STATE"

        if [[ "$STATE" == "READY" ]]; then
            log_success "Crawler finished: $crawler_name"
            return 0
        fi

    done

    exit_on_error "Crawler timed out: $crawler_name"

}


#############################################################
# Helper — Create crawler if not exists
#############################################################

create_and_run_crawler() {

    local crawler_name="$1"
    local s3_path="$2"

    # Create if not exists
    if ! crawler_exists "$crawler_name"; then

        log_info "Creating crawler: $crawler_name"

        aws glue create-crawler \
            --name "$crawler_name" \
            --role "$CRAWLER_ROLE" \
            --database-name "$GLUE_DATABASE" \
            --targets "S3Targets=[{Path=$s3_path}]" \
            --region "$AWS_REGION"

        if [ $? -ne 0 ]; then
            exit_on_error "Failed creating crawler: $crawler_name"
        fi

        log_success "Crawler created: $crawler_name"

    else
        log_warning "Crawler already exists: $crawler_name"
    fi

    # Start crawler
    log_info "Starting crawler: $crawler_name"

    aws glue start-crawler \
        --name "$crawler_name" \
        --region "$AWS_REGION"

    if [ $? -ne 0 ]; then
        exit_on_error "Failed starting crawler: $crawler_name"
    fi

    log_success "Crawler started: $crawler_name"

    # Wait for completion
    wait_for_crawler "$crawler_name"

}


#############################################################
# Main
#############################################################

main() {

    log_info "Starting Glue Crawler Pipeline"

    check_aws_cli
    check_aws_credentials


    #############################################################
    # Silver Crawler — registers curated/silver/ tables
    #############################################################

    log_info "=== Silver Crawler ==="

    create_and_run_crawler \
        "$SILVER_CRAWLER_NAME" \
        "s3://$CURATED_BUCKET/silver"

    log_success "Silver tables registered in Glue Catalog"


    #############################################################
    # Gold Crawler — registers gold/ tables
    #############################################################

    log_info "=== Gold Crawler ==="

    create_and_run_crawler \
        "$GOLD_CRAWLER_NAME" \
        "s3://$GOLD_BUCKET/gold"

    log_success "Gold tables registered in Glue Catalog"


    #############################################################
    # Show registered tables
    #############################################################

    log_info "Tables registered in database: $GLUE_DATABASE"

    aws glue get-tables \
        --database-name "$GLUE_DATABASE" \
        --region "$AWS_REGION" \
        --query 'TableList[].Name' \
        --output table

    log_success "Crawler pipeline complete — Athena ready!"

}

main
