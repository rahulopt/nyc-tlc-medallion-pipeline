import sys
import logging

from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql.functions import (
    col,
    count,
    avg,
    sum as spark_sum,
    max as spark_max,
    min as spark_min,
    round as spark_round,
    current_timestamp
)


# ==============================================================
# Logging Configuration
# ==============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

logger = logging.getLogger(__name__)


def build_daily_summary(df):
    """
    Gold Table 1: Daily Trip Summary

    Aggregates per pickup_date:
    - total trips
    - total passengers
    - avg / total fare
    - avg / total tip
    - avg / total distance
    - avg trip duration
    """

    logger.info("Building daily_trip_summary")

    daily_df = (
        df
        .groupBy("pickup_date", "pickup_year", "pickup_month")
        .agg(
            count("*")                                      .alias("total_trips"),
            spark_sum("passenger_count")                    .alias("total_passengers"),
            spark_round(avg("fare_amount"), 2)              .alias("avg_fare"),
            spark_round(spark_sum("fare_amount"), 2)        .alias("total_fare"),
            spark_round(avg("tip_amount"), 2)               .alias("avg_tip"),
            spark_round(spark_sum("tip_amount"), 2)         .alias("total_tip"),
            spark_round(avg("trip_distance"), 2)            .alias("avg_distance"),
            spark_round(spark_sum("trip_distance"), 2)      .alias("total_distance"),
            spark_round(avg("trip_duration_minutes"), 2)    .alias("avg_duration_minutes"),
            spark_round(spark_sum("total_amount"), 2)       .alias("total_revenue")
        )
        .withColumn("gold_processed_at", current_timestamp())
        .orderBy("pickup_date")
    )

    return daily_df


def build_hourly_summary(df):
    """
    Gold Table 2: Hourly Trip Summary

    Aggregates per pickup_year + pickup_month + pickup_hour:
    - total trips
    - avg fare
    - avg distance
    - avg duration

    Useful for: peak hour analysis
    """

    logger.info("Building hourly_trip_summary")

    hourly_df = (
        df
        .groupBy("pickup_year", "pickup_month", "pickup_hour")
        .agg(
            count("*")                                      .alias("total_trips"),
            spark_round(avg("fare_amount"), 2)              .alias("avg_fare"),
            spark_round(avg("trip_distance"), 2)            .alias("avg_distance"),
            spark_round(avg("trip_duration_minutes"), 2)    .alias("avg_duration_minutes"),
            spark_round(spark_sum("total_amount"), 2)       .alias("total_revenue")
        )
        .withColumn("gold_processed_at", current_timestamp())
        .orderBy("pickup_year", "pickup_month", "pickup_hour")
    )

    return hourly_df


def build_location_summary(df):
    """
    Gold Table 3: Location Trip Summary

    Aggregates per pickup location (PULocationID):
    - total trips
    - avg fare
    - avg distance
    - total revenue

    Useful for: hotspot analysis
    """

    logger.info("Building location_trip_summary")

    location_df = (
        df
        .groupBy("PULocationID")
        .agg(
            count("*")                                      .alias("total_trips"),
            spark_round(avg("fare_amount"), 2)              .alias("avg_fare"),
            spark_round(avg("trip_distance"), 2)            .alias("avg_distance"),
            spark_round(avg("trip_duration_minutes"), 2)    .alias("avg_duration_minutes"),
            spark_round(spark_sum("total_amount"), 2)       .alias("total_revenue"),
            spark_round(avg("tip_amount"), 2)               .alias("avg_tip")
        )
        .withColumn("gold_processed_at", current_timestamp())
        .orderBy(col("total_trips").desc())
    )

    return location_df


def build_payment_summary(df):
    """
    Gold Table 4: Payment Type Summary

    Aggregates per payment_type:
    - total trips
    - avg fare
    - avg tip
    - total revenue

    Useful for: payment behavior analysis
    payment_type: 1=Credit, 2=Cash, 3=No charge, 4=Dispute
    """

    logger.info("Building payment_type_summary")

    payment_df = (
        df
        .groupBy("payment_type")
        .agg(
            count("*")                                      .alias("total_trips"),
            spark_round(avg("fare_amount"), 2)              .alias("avg_fare"),
            spark_round(avg("tip_amount"), 2)               .alias("avg_tip"),
            spark_round(spark_sum("total_amount"), 2)       .alias("total_revenue"),
            spark_round(spark_max("fare_amount"), 2)        .alias("max_fare"),
            spark_round(spark_min("fare_amount"), 2)        .alias("min_fare")
        )
        .withColumn("gold_processed_at", current_timestamp())
        .orderBy("payment_type")
    )

    return payment_df


def write_gold_table(df, path, partition_cols=None):
    """
    Write a gold table to S3 as parquet.
    Optionally partition by given columns.
    """

    writer = (
        df.write
        .mode("overwrite")
        .format("parquet")
    )

    if partition_cols:
        writer = writer.partitionBy(*partition_cols)

    writer.save(path)

    logger.info("Written gold table to: %s", path)


def main():

    """
    Gold ETL Pipeline

    Flow:
        Silver S3
            |
            | Read parquet
            |
            ↓
        Gold Aggregations
            |
      ┌─────┼──────┬──────────┐
      ↓     ↓      ↓          ↓
    Daily Hourly Location  Payment
      |     |      |          |
      └─────┴──────┴──────────┘
                  |
                  ↓
              Gold S3

    Gold Tables:
    - daily_trip_summary    → trends over time
    - hourly_trip_summary   → peak hour analysis
    - location_trip_summary → hotspot analysis
    - payment_type_summary  → payment behavior
    """


    # ==============================================================
    # Read Glue Job Arguments
    # ==============================================================

    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "SILVER_PATH",
            "GOLD_PATH"
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
    # Read Silver Data
    # ==============================================================

    logger.info(
        "Reading silver data from %s",
        args["SILVER_PATH"]
    )

    df = (
        spark.read
        .format("parquet")
        .load(args["SILVER_PATH"])
    )

    total_count = df.count()
    logger.info("Total silver records loaded: %d", total_count)


    # ==============================================================
    # Build & Write Gold Tables
    # ==============================================================

    gold_base = args["GOLD_PATH"]

    # Table 1 — Daily Summary (partitioned by year/month)
    daily_df = build_daily_summary(df)
    write_gold_table(
        daily_df,
        f"{gold_base}/daily_trip_summary",
        partition_cols=["pickup_year", "pickup_month"]
    )

    # Table 2 — Hourly Summary (partitioned by year/month)
    hourly_df = build_hourly_summary(df)
    write_gold_table(
        hourly_df,
        f"{gold_base}/hourly_trip_summary",
        partition_cols=["pickup_year", "pickup_month"]
    )

    # Table 3 — Location Summary (no partition — small dataset)
    location_df = build_location_summary(df)
    write_gold_table(
        location_df,
        f"{gold_base}/location_trip_summary"
    )

    # Table 4 — Payment Summary (no partition — very small)
    payment_df = build_payment_summary(df)
    write_gold_table(
        payment_df,
        f"{gold_base}/payment_type_summary"
    )

    logger.info("Gold ETL complete — all 4 tables written successfully")


    # ==============================================================
    # Commit Glue Job
    # ==============================================================

    job.commit()


if __name__ == "__main__":
    main()
