import os
import boto3

S3_BUCKET = os.getenv("S3_BUCKET", "s3-data-quest.rearc.io")

s3 = boto3.resource('s3')

def lambda_handler(event, context):
    os.system("jupyter nbconvert --execute --to notebook --inplace analysis.ipynb ")
    s3.meta.client.upload_file("analysis.ipynb", S3_BUCKET, "analysis.ipynb")
    os.system("jupyter nbconvert --to html analysis.ipynb")
    s3.meta.client.upload_file("analysis.html", S3_BUCKET, "analysis.html")

lambda_handler(None, None)