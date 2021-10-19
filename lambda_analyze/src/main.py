import os
import boto3
import sys

sys.path.append("/opt")
os.environ["JUPYTER_CONFIG_DIR"] = "/tmp"
os.environ["JUPYTER_CONFIG_PATH"] = "/tmp"
os.environ["JUPYTER_DATA_DIR"] = "/opt/share/jupyter"
# os.environ["JUPYTER_PATH"] = "/tmp"
# os.environ["JUPYTER_RUNTIME_DIR"] = "/tmp"
os.environ["PYTHONPATH"]=f"${os.environ['PYTHONPATH']}:/opt"
os.environ["IPYTHONDIR"]="/tmp/ipythondir"

S3_BUCKET = os.getenv("S3_BUCKET", "s3-data-quest.rearc.io")

s3 = boto3.resource('s3')

def lambda_handler(event, context):
    s3.meta.client.download_file(S3_BUCKET, 'pr.data.0.Current', '/tmp/pr.data.0.Current')
    s3.meta.client.download_file(S3_BUCKET, 'datausa.api.json', '/tmp/datausa.api.json')
    os.system("jupyter nbconvert --execute --to notebook --output-dir='/tmp' analysis.ipynb")
    s3.meta.client.upload_file("/tmp/analysis.ipynb", S3_BUCKET, "analysis.ipynb")
    os.system("jupyter nbconvert --execute --to html --output-dir='/tmp' analysis.ipynb")
    s3.meta.client.upload_file("/tmp/analysis.html", S3_BUCKET, "analysis.html")
    return "Success"