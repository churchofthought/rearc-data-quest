terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "s3-data-quest.rearc.io"
}

resource "aws_s3_bucket_policy" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = ["s3:ListBucket", "s3:GetObject"]
        Effect    = "Allow"
        Principal = "*"
        Sid       = ""
        Resource  = [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:*"
        Effect   = "Allow"
        Sid      = ""
        Resource = [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "null_resource" "lambda_scrape_dependencies" {
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("src", "*"): filesha1(f)]))
  }
  provisioner "local-exec" {
    command = "cd lambda_scrape/src && npm run build"
  }
}

data "archive_file" "lambda_scrape_zip_dir" {
  type        = "zip"
  output_path = "tmp/lambda_scrape_zip_dir.zip"
	source_dir  = "lambda_scrape/dist"

  depends_on = [
    null_resource.lambda_scrape_dependencies
  ]
}

resource "aws_lambda_function" "lambda_scrape" {
  filename         = "${data.archive_file.lambda_scrape_zip_dir.output_path}"
  source_code_hash = "${data.archive_file.lambda_scrape_zip_dir.output_base64sha256}"
  function_name    = "lambda_scrape"
  handler          = "lambda.lambdaHandler"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda_role.arn
  timeout          = 900

  environment {
    variables = {
      S3_REGION = aws_s3_bucket.bucket.region
      S3_BUCKET = aws_s3_bucket.bucket.bucket
      NODE_OPTIONS = "--enable-source-maps --experimental-specifier-resolution=node"
    }
  }
}

