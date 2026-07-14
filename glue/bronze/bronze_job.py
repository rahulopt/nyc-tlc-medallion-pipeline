import sys
import logging

from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql.functions import (
    current_timestamp,
    input_file_name
)


# ==============================================================
# Logging Configuration
# ==============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

logger = logging.getLogger(__name__)


def main():

    """
    Bronze ETL Pipeline

    Flow:
        Raw S3
          |
          | Read parquet
          |
          ↓
        Bronze Processing
          |
          | Add metadata columns
          |
          ↓
        Bronze S3 Layer

    Responsibilities:
    - Read raw parquet data
    - Add ingestion metadata
    - Write bronze parquet data
    """


    # ==============================================================
    # Read Glue Job Arguments
    # ==============================================================

    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "RAW_PATH",
            "CURATED_PATH"
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
    # Read Raw Data From S3
    # ==============================================================

    logger.info(
        "Reading raw parquet data from %s",
        args["RAW_PATH"]
    )


    df = (
        spark.read
        .format("parquet")
        .load(args["RAW_PATH"])
    )


    logger.info(
        "Raw parquet data loaded successfully"
    )


    # Print schema for validation
    logger.info("Input schema:")

    df.printSchema()



    # ==============================================================
    # Bronze Layer Transformations
    # ==============================================================

    logger.info(
        "Adding bronze metadata columns"
    )


    bronze_df = (
        df

        # Add ingestion timestamp
        .withColumn(
            "ingestion_time",
            current_timestamp()
        )

        # Capture source file location
        .withColumn(
            "source_file",
            input_file_name()
        )
    )



    # ==============================================================
    # Write Data To Bronze Layer
    # ==============================================================

    bronze_path = (
        args["CURATED_PATH"]
        + "/bronze/"
    )


    logger.info(
        "Writing bronze data to %s",
        bronze_path
    )


    (
        bronze_df
        .write
        .mode("overwrite")
        .format("parquet")
        .save(bronze_path)
    )


    logger.info(
        "Bronze data written successfully"
    )


    # ==============================================================
    # Commit Glue Job
    # ==============================================================

    job.commit()


if __name__ == "__main__":
    main()