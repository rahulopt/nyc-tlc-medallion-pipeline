#!/bin/bash

set -euo pipefail

#############################################################
# Athena Setup & Query Runner
# - Creates Athena workgroup with S3 output location
# - Runs all gold queries and shows results
#############################################################

source config/variables.sh
source scripts/lib/utils.sh


WORKGROUP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-workgroup"
OUTPUT_LOCATION="s3://${ATHENA_RESULTS_BUCKET}/query-results/"


#############################################################
# Create Athena Workgroup
#############################################################

create_workgroup() {

    local wg_name="$1"

    # Check if workgroup exists
    if aws athena get-work-group \
        --work-group "$wg_name" \
        --region "$AWS_REGION" \
        >/dev/null 2>&1
    then
        log_warning "Workgroup already exists: $wg_name"
        return
    fi

    log_info "Creating Athena workgroup: $wg_name"

    aws athena create-work-group \
        --name "$wg_name" \
        --region "$AWS_REGION" \
        --configuration "ResultConfiguration={OutputLocation=${OUTPUT_LOCATION}},EnforceWorkGroupConfiguration=true,PublishCloudWatchMetricsEnabled=true"

    if [ $? -ne 0 ]; then
        exit_on_error "Failed creating workgroup: $wg_name"
    fi

    log_success "Workgroup created: $wg_name"
}


#############################################################
# Run a single Athena query and wait for result
#############################################################

run_query() {

    local query_name="$1"
    local query_string="$2"

    log_info "Running query: $query_name"

    EXECUTION_ID=$(aws athena start-query-execution \
        --query-string "$query_string" \
        --work-group "$WORKGROUP_NAME" \
        --region "$AWS_REGION" \
        --query-execution-context Database="$GLUE_DATABASE" \
        --query 'QueryExecutionId' \
        --output text)

    if [ -z "$EXECUTION_ID" ]; then
        exit_on_error "Failed to start query: $query_name"
    fi

    log_info "QueryExecutionId: $EXECUTION_ID"

    # Wait for query to complete
    for i in $(seq 1 30); do

        sleep 3

        STATE=$(aws athena get-query-execution \
            --query-execution-id "$EXECUTION_ID" \
            --region "$AWS_REGION" \
            --query 'QueryExecution.Status.State' \
            --output text)

        if [[ "$STATE" == "SUCCEEDED" ]]; then
            log_success "Query succeeded: $query_name"

            # Print results
            echo ""
            echo "--- Results: $query_name ---"
            aws athena get-query-results \
                --query-execution-id "$EXECUTION_ID" \
                --region "$AWS_REGION" \
                --query 'ResultSet.Rows[*].Data[*].VarCharValue' \
                --output table
            echo ""
            return 0

        elif [[ "$STATE" == "FAILED" || "$STATE" == "CANCELLED" ]]; then
            REASON=$(aws athena get-query-execution \
                --query-execution-id "$EXECUTION_ID" \
                --region "$AWS_REGION" \
                --query 'QueryExecution.Status.StateChangeReason' \
                --output text)
            exit_on_error "Query $query_name failed: $REASON"
        fi

    done

    exit_on_error "Query timed out: $query_name"
}


#############################################################
# Main
#############################################################

main() {

    log_info "Setting up Athena"

    check_aws_cli
    check_aws_credentials

    # Create workgroup
    create_workgroup "$WORKGROUP_NAME"

    log_success "Athena setup complete"
    log_info "Workgroup : $WORKGROUP_NAME"
    log_info "Output    : $OUTPUT_LOCATION"
    log_info "Database  : $GLUE_DATABASE"

    echo ""
    log_info "Running gold table queries..."
    echo ""


    # Q1 — Daily trips Jan 2024
    run_query "daily_trips_jan_2024" \
    "SELECT pickup_date, total_trips, total_revenue, avg_fare FROM daily_trip_summary WHERE pickup_year=2024 AND pickup_month=1 ORDER BY pickup_date LIMIT 5"


    # Q2 — Top 5 revenue days
    run_query "top_5_revenue_days" \
    "SELECT pickup_date, total_trips, total_revenue FROM daily_trip_summary ORDER BY total_revenue DESC LIMIT 5"


    # Q3 — Busiest hours
    run_query "busiest_hours" \
    "SELECT pickup_hour, SUM(total_trips) AS total_trips, ROUND(AVG(avg_fare),2) AS avg_fare FROM hourly_trip_summary WHERE pickup_year=2024 GROUP BY pickup_hour ORDER BY total_trips DESC LIMIT 5"


    # Q4 — Top 10 pickup locations
    run_query "top_10_pickup_locations" \
    "SELECT pulocationid, total_trips, avg_fare, total_revenue FROM location_trip_summary ORDER BY total_trips DESC LIMIT 10"


    # Q5 — Payment type breakdown
    run_query "payment_type_breakdown" \
    "SELECT CASE payment_type WHEN 1 THEN 'Credit Card' WHEN 2 THEN 'Cash' WHEN 3 THEN 'No Charge' WHEN 4 THEN 'Dispute' ELSE 'Unknown' END AS payment_method, total_trips, avg_fare, avg_tip, total_revenue FROM payment_type_summary ORDER BY total_trips DESC"


    log_success "All Athena queries completed!"
    log_info "Full results saved to: $OUTPUT_LOCATION"

}

main
