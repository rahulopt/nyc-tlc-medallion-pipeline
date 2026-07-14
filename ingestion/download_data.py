import os
import boto3
import requests

# BUG FIX #6: Removed unused 'from datetime import datetime' import


# ==========================
# Configuration
# ==========================

AWS_REGION = "us-east-1"

BUCKET_NAME = os.environ["RAW_BUCKET"]

# BUG FIX #5: YEAR and MONTH ab hardcoded nahi hain
# env vars se read ho rahe hain, with sensible defaults (2024-01)
YEAR = os.environ.get("YEAR", "2024")
MONTH = os.environ.get("MONTH", "01")

DATA_URL = (
    f"https://d37ci6vzurychx.cloudfront.net/trip-data/"
    f"yellow_tripdata_{YEAR}-{MONTH}.parquet"
)


LOCAL_FILE = f"yellow_tripdata_{YEAR}-{MONTH}.parquet"


# ==========================
# Download Data
# ==========================

def download_data():

    print("Downloading NYC TLC data...")

    response = requests.get(DATA_URL)

    response.raise_for_status()

    with open(LOCAL_FILE, "wb") as file:
        file.write(response.content)


    print("Download completed")


# ==========================
# Upload to S3
# ==========================

def upload_to_s3():

    print("Uploading to S3...")


    s3 = boto3.client(
        "s3",
        region_name=AWS_REGION
    )


    s3_key = (
        f"raw/yellow_tripdata/"
        f"year={YEAR}/"
        f"month={MONTH}/"
        f"{LOCAL_FILE}"
    )


    s3.upload_file(
        LOCAL_FILE,
        BUCKET_NAME,
        s3_key
    )


    print(
        f"Uploaded: s3://{BUCKET_NAME}/{s3_key}"
    )



# ==========================
# Main
# ==========================

if __name__ == "__main__":

    download_data()

    upload_to_s3()
