import sys
import logging

from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job

from pyspark.context import SparkContext


# ---------------------------------------------------------------------
# Configure Logging
# ---------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

logger = logging.getLogger(__name__)


def main():
    """
    Bronze ETL Job

    Responsibilities:
    - Read raw parquet data from S3
    - Initialize Glue job
    - Validate connectivity and schema

    Note:
    Business transformations will be implemented in later iterations.
    """

    # -------------------------------------------------------------
    # Read Glue Job Parameters
    # -------------------------------------------------------------
    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "RAW_PATH",
            "CURATED_PATH"
        ]
    )

    # -------------------------------------------------------------
    # Initialize Spark & Glue Context
    # -------------------------------------------------------------
    sc = SparkContext.getOrCreate()

    glue_context = GlueContext(sc)

    spark = glue_context.spark_session

    job = Job(glue_context)

    job.init(args["JOB_NAME"], args)

    # -------------------------------------------------------------
    # Read Raw Parquet Data
    # -------------------------------------------------------------
    logger.info("Reading raw parquet data from %s", args["RAW_PATH"])

    df = (
        spark.read
        .format("parquet")
        .load(args["RAW_PATH"])
    )

    logger.info("Raw parquet data loaded successfully.")

    logger.info("Input schema:")

    df.printSchema()

    # -------------------------------------------------------------
    # Commit Glue Job
    # -------------------------------------------------------------
    logger.info("Bronze ETL initialization completed successfully.")

    job.commit()


if __name__ == "__main__":
    main()