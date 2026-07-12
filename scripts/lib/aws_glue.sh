#!/bin/bash

#############################################################
# AWS Glue Library
#############################################################


#############################################################
# Check Glue Database Exists
#############################################################

glue_database_exists() {

    local database_name="$1"

    aws glue get-database \
        --name "$database_name" \
        >/dev/null 2>&1

}



#############################################################
# Create Glue Database
#############################################################

create_glue_database() {

    local database_name="$1"


    if glue_database_exists "$database_name"
    then
        log_warning "Glue Database already exists : $database_name"
        return
    fi


    log_info "Creating Glue Database : $database_name"


    aws glue create-database \
        --database-input Name="$database_name"


    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating Glue Database"
    fi


    log_success "Glue Database created : $database_name"

}

#############################################################
# Create Glue Crawler
#############################################################

crawler_exists() {

    local crawler_name="$1"

    aws glue get-crawler \
    --name "$crawler_name" \
    >/dev/null 2>&1

}



create_glue_crawler() {

    local crawler_name="$1"
    local database_name="$2"
    local role_name="$3"
    local s3_path="$4"


    if crawler_exists "$crawler_name"
    then
        log_warning "Crawler already exists : $crawler_name"
        return
    fi


    log_info "Creating Glue Crawler : $crawler_name"


    aws glue create-crawler \
    --name "$crawler_name" \
    --role "$role_name" \
    --database-name "$database_name" \
    --targets "S3Targets=[{Path=$s3_path}]"


    log_success "Crawler created : $crawler_name"

}