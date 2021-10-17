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

data "archive_file" "lambda_zip_dir" {
  type        = "zip"
  output_path = "tmp/lambda_zip_dir.zip"
	source_dir  = "dist"
}

resource "aws_lambda_function" "lambda_scrape" {
  filename         = "${data.archive_file.lambda_zip_dir.output_path}"
  source_code_hash = "${data.archive_file.lambda_zip_dir.output_base64sha256}"
  function_name    = "lambda_scrape"
  handler          = "lambda.lambdaHandler"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      S3_REGION = aws_s3_bucket.bucket.region
      S3_BUCKET = aws_s3_bucket.bucket.bucket
    }
  }
}