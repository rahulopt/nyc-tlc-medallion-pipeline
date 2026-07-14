import sys
import logging

from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql.functions import (
    col,
    current_timestamp,
    to_date,
    hour,
    month,
    year,
    dayofweek,
    round as spark_round,
    lit,
    when
)
from pyspark.sql.types import (
    DoubleType,
    IntegerType,
    LongType
)


# ==============================================================
# Logging Configuration
# ==============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

logger = logging.getLogger(__name__)


# ==============================================================
# Data Quality Rules
# ==============================================================

# Valid passenger count: 1 to 6
MIN_PASSENGER_COUNT = 1
MAX_PASSENGER_COUNT = 6

# Valid trip distance in miles: > 0 and < 500
MIN_TRIP_DISTANCE = 0.0
MAX_TRIP_DISTANCE = 500.0

# Valid fare amount: > 0 and < 10000
MIN_FARE_AMOUNT = 0.0
MAX_FARE_AMOUNT = 10000.0

# Valid total amount: > 0
MIN_TOTAL_AMOUNT = 0.0

# Valid pickup/dropoff year range
MIN_YEAR = 2009
MAX_YEAR = 2030


def apply_quality_checks(df):
    """
    Tag each row as VALID or REJECTED with a reject reason.

    Rules:
    - passenger_count must be between 1 and 6
    - trip_distance must be > 0 and < 500
    - fare_amount must be > 0 and < 10000
    - total_amount must be > 0
    - tpep_pickup_datetime must not be null
    - tpep_dropoff_datetime must not be null
    - dropoff must be after pickup
    - pickup year must be in valid range
    """

    logger.info("Applying data quality checks")

    df = df.withColumn(
        "dq_reject_reason",

        when(
            col("passenger_count").isNull() |
            (col("passenger_count") < MIN_PASSENGER_COUNT) |
            (col("passenger_count") > MAX_PASSENGER_COUNT),
            lit("invalid_passenger_count")
        )
        .when(
            col("trip_distance").isNull() |
            (col("trip_distance") <= MIN_TRIP_DISTANCE) |
            (col("trip_distance") >= MAX_TRIP_DISTANCE),
            lit("invalid_trip_distance")
        )
        .when(
            col("fare_amount").isNull() |
            (col("fare_amount") <= MIN_FARE_AMOUNT) |
            (col("fare_amount") >= MAX_FARE_AMOUNT),
            lit("invalid_fare_amount")
        )
        .when(
            col("total_amount").isNull() |
            (col("total_amount") <= MIN_TOTAL_AMOUNT),
            lit("invalid_total_amount")
        )
        .when(
            col("tpep_pickup_datetime").isNull(),
            lit("null_pickup_datetime")
        )
        .when(
            col("tpep_dropoff_datetime").isNull(),
            lit("null_dropoff_datetime")
        )
        .when(
            col("tpep_dropoff_datetime") <= col("tpep_pickup_datetime"),
            lit("dropoff_before_pickup")
        )
        .when(
            year(col("tpep_pickup_datetime")) < MIN_YEAR,
            lit("pickup_year_too_old")
        )
        .when(
            year(col("tpep_pickup_datetime")) > MAX_YEAR,
            lit("pickup_year_future")
        )
        .otherwise(lit(None))
    )

    df = df.withColumn(
        "dq_status",
        when(col("dq_reject_reason").isNull(), lit("VALID"))
        .otherwise(lit("REJECTED"))
    )

    return df


def apply_transformations(df):
    """
    Apply silver layer transformations on VALID records.

    Transformations:
    - Cast columns to correct types
    - Extract date parts from pickup datetime
    - Calculate trip duration in minutes
    - Round monetary columns to 2 decimal places
    - Add silver processing timestamp
    """

    logger.info("Applying silver transformations")

    df = (
        df

        # Cast to correct types
        .withColumn("passenger_count",  col("passenger_count").cast(IntegerType()))
        .withColumn("trip_distance",    col("trip_distance").cast(DoubleType()))
        .withColumn("fare_amount",      col("fare_amount").cast(DoubleType()))
        .withColumn("tip_amount",       col("tip_amount").cast(DoubleType()))
        .withColumn("tolls_amount",     col("tolls_amount").cast(DoubleType()))
        .withColumn("total_amount",     col("total_amount").cast(DoubleType()))
        .withColumn("PULocationID",     col("PULocationID").cast(LongType()))
        .withColumn("DOLocationID",     col("DOLocationID").cast(LongType()))

        # Extract date parts for partitioning & analytics
        .withColumn("pickup_date",      to_date(col("tpep_pickup_datetime")))
        .withColumn("pickup_year",      year(col("tpep_pickup_datetime")))
        .withColumn("pickup_month",     month(col("tpep_pickup_datetime")))
        .withColumn("pickup_hour",      hour(col("tpep_pickup_datetime")))
        .withColumn("pickup_dayofweek", dayofweek(col("tpep_pickup_datetime")))

        # Trip duration in minutes
        .withColumn(
            "trip_duration_minutes",
            spark_round(
                (
                    col("tpep_dropoff_datetime").cast("long") -
                    col("tpep_pickup_datetime").cast("long")
                ) / 60.0,
                2
            )
        )

        # Round monetary columns
        .withColumn("fare_amount",  spark_round(col("fare_amount"), 2))
        .withColumn("tip_amount",   spark_round(col("tip_amount"), 2))
        .withColumn("tolls_amount", spark_round(col("tolls_amount"), 2))
        .withColumn("total_amount", spark_round(col("total_amount"), 2))

        # Silver processing timestamp
        .withColumn("silver_processed_at", current_timestamp())
    )

    return df


def main():

    """
    Silver ETL Pipeline

    Flow:
        Bronze S3
            |
            | Read parquet
            |
            ↓
        Data Quality Checks
            |
        ┌───┴────────────┐
        ↓                ↓
      VALID           REJECTED
        |                |
        ↓                ↓
    Transformations   Reject S3
        |
        ↓
      Silver S3 (partitioned by year/month)

    Responsibilities:
    - Read bronze parquet data
    - Apply data quality validation rules
    - Route rejected records to reject bucket
    - Apply transformations on valid records
    - Write silver parquet data partitioned by year/month
    """


    # ==============================================================
    # Read Glue Job Arguments
    # ==============================================================

    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "BRONZE_PATH",
            "SILVER_PATH",
            "REJECT_PATH"
        ]
    )


    # ==============================================================
    # Initialize Spark and Glue Context
    # ==============================================================

    sc = SparkContext.getOrCreate()

    glue_context = GlueContext(sc)

    spark = glue_context.spark_session

    job = Job(glue_context)

    job.init(
        args["JOB_NAME"],
        args
    )


    # ==============================================================
    # Read Bronze Data
    # ==============================================================

    logger.info(
        "Reading bronze parquet data from %s",
        args["BRONZE_PATH"]
    )

    df = (
        spark.read
        .format("parquet")
        .load(args["BRONZE_PATH"])
    )

    total_count = df.count()

    logger.info("Total records read from bronze: %d", total_count)


    # ==============================================================
    # Apply Data Quality Checks
    # ==============================================================

    df = apply_quality_checks(df)

    valid_df    = df.filter(col("dq_status") == "VALID")
    rejected_df = df.filter(col("dq_status") == "REJECTED")

    valid_count    = valid_df.count()
    rejected_count = rejected_df.count()

    logger.info("Valid records   : %d", valid_count)
    logger.info("Rejected records: %d", rejected_count)
    logger.info(
        "Rejection rate  : %.2f%%",
        (rejected_count / total_count * 100) if total_count > 0 else 0
    )


    # ==============================================================
    # Write Rejected Records to Reject Bucket
    # ==============================================================

    if rejected_count > 0:

        logger.info(
            "Writing rejected records to %s",
            args["REJECT_PATH"]
        )

        (
            rejected_df
            .write
            .mode("overwrite")
            .format("parquet")
            .partitionBy("dq_reject_reason")
            .save(args["REJECT_PATH"])
        )

        logger.info("Rejected records written successfully")

    else:
        logger.info("No rejected records — skipping reject write")


    # ==============================================================
    # Apply Transformations on Valid Records
    # ==============================================================

    # Drop DQ columns before writing silver
    silver_df = apply_transformations(valid_df)

    silver_df = silver_df.drop("dq_status", "dq_reject_reason")


    # ==============================================================
    # Write Silver Data — Partitioned by year/month
    # ==============================================================

    logger.info(
        "Writing silver data to %s",
        args["SILVER_PATH"]
    )

    (
        silver_df
        .write
        .mode("overwrite")
        .format("parquet")
        .partitionBy("pickup_year", "pickup_month")
        .save(args["SILVER_PATH"])
    )

    logger.info("Silver data written successfully")

    logger.info(
        "Silver ETL complete — valid: %d | rejected: %d | total: %d",
        valid_count,
        rejected_count,
        total_count
    )


    # ==============================================================
    # Commit Glue Job
    # ==============================================================

    job.commit()


if __name__ == "__main__":
    main()
