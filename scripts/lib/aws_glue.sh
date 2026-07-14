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

    # BUG FIX #4: Added missing error check after crawler creation
    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating Glue Crawler : $crawler_name"
    fi

    log_success "Crawler created : $crawler_name"

}
#############################################################
# Check Glue Job Exists
#############################################################

glue_job_exists() {

    local job_name="$1"

    aws glue get-job \
        --job-name "$job_name" \
        >/dev/null 2>&1
}


#############################################################
# Create Glue Job - Bronze
#############################################################

create_glue_job() {

    local job_name="$1"
    local role_name="$2"

    if glue_job_exists "$job_name"
    then
        log_warning "Glue Job already exists : $job_name"
        return
    fi

    log_info "Creating Glue Job : $job_name"

    aws glue create-job \
        --name "$job_name" \
        --role "$role_name" \
        --command Name=glueetl,ScriptLocation="$SCRIPT_LOCATION",PythonVersion=3 \
        --glue-version "$GLUE_VERSION" \
        --worker-type "$WORKER_TYPE" \
        --number-of-workers "$NUMBER_OF_WORKERS" \
        --default-arguments '{
            "--job-language":"python",
            "--RAW_PATH":"s3://'"$RAW_BUCKET"'",
            "--CURATED_PATH":"s3://'"$CURATED_BUCKET"'"
        }'

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating Glue Job"
    fi

    log_success "Glue Job created : $job_name"

}


#############################################################
# Create Glue Job - Silver
#############################################################

#############################################################
# Create Glue Job - Silver
#############################################################

create_silver_glue_job() {

    local job_name="$1"
    local role_name="$2"

    if glue_job_exists "$job_name"
    then
        log_warning "Glue Job already exists : $job_name"
        return
    fi

    log_info "Creating Silver Glue Job : $job_name"

    aws glue create-job \
        --name "$job_name" \
        --role "$role_name" \
        --command Name=glueetl,ScriptLocation="$SILVER_SCRIPT_LOCATION",PythonVersion=3 \
        --glue-version "$GLUE_VERSION" \
        --worker-type "$WORKER_TYPE" \
        --number-of-workers "$NUMBER_OF_WORKERS" \
        --default-arguments '{
            "--job-language":"python",
            "--BRONZE_PATH":"'"$BRONZE_PATH"'",
            "--SILVER_PATH":"'"$SILVER_PATH"'",
            "--REJECT_PATH":"'"$REJECT_PATH"'"
        }'

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating Silver Glue Job"
    fi

    log_success "Silver Glue Job created : $job_name"

}



#############################################################
# Create Glue Job - Gold
#############################################################

create_gold_glue_job() {

    local job_name="$1"
    local role_name="$2"

    if glue_job_exists "$job_name"
    then
        log_warning "Glue Job already exists : $job_name"
        return
    fi

    log_info "Creating Gold Glue Job : $job_name"

    aws glue create-job \
        --name "$job_name" \
        --role "$role_name" \
        --command Name=glueetl,ScriptLocation="$GOLD_SCRIPT_LOCATION",PythonVersion=3 \
        --glue-version "$GLUE_VERSION" \
        --worker-type "$WORKER_TYPE" \
        --number-of-workers "$NUMBER_OF_WORKERS" \
        --default-arguments '{
            "--job-language":"python",
            "--SILVER_PATH":"'"$SILVER_PATH"'",
            "--GOLD_PATH":"'"$GOLD_PATH"'"
        }'

    if [ $? -ne 0 ]
    then
        exit_on_error "Failed creating Gold Glue Job"
    fi

    log_success "Gold Glue Job created : $job_name"

}
