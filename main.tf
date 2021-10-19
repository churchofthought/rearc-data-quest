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
        Resource = [
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
      }
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
        Action = "s3:*"
        Effect = "Allow"
        Sid    = ""
        Resource = [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Sid      = ""
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "lambda:InvokeFunction",
          "lambda:InvokeAsync",
        ]
        Sid      = ""
        Effect   = "Allow"
        Resource = aws_lambda_function.lambda_analyze.arn
      }
    ]
  })
}

resource "null_resource" "lambda_scrape_dependencies" {
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("lambda_scrape/src/", "**") : filesha1("lambda_scrape/src/${f}")]))
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
  filename         = data.archive_file.lambda_scrape_zip_dir.output_path
  source_code_hash = data.archive_file.lambda_scrape_zip_dir.output_base64sha256
  function_name    = "lambda_scrape"
  handler          = "index.lambdaHandler"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda_role.arn
  timeout          = 60

  environment {
    variables = {
      S3_REGION      = aws_s3_bucket.bucket.region
      S3_BUCKET      = aws_s3_bucket.bucket.bucket
      LAMBDA_ANALYZE = aws_lambda_function.lambda_analyze.arn
      NODE_OPTIONS = "--enable-source-maps --experimental-specifier-resolution=node"
    }
  }
}


resource "null_resource" "lambda_analyze_dependencies" {
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("lambda_analyze/src/", "**") : filesha1("lambda_analyze/src/${f}")]))
  }
}


data "archive_file" "lambda_analyze_zip_dir" {
  type        = "zip"
  output_path = "tmp/lambda_analyze_zip_dir.zip"
  source_dir  = "lambda_analyze/src"

  depends_on = [
    null_resource.lambda_analyze_dependencies
  ]
}

resource "aws_lambda_layer_version" "jupyter_layer_1" {
  filename   = "lambda_analyze/python_modules_1.zip"
  layer_name = "lambda_jupyter_1"
  source_code_hash = filebase64sha256("lambda_analyze/python_modules_1.zip")
  compatible_runtimes = ["python3.8"]
}

resource "aws_lambda_layer_version" "jupyter_layer_2" {
  filename   = "lambda_analyze/python_modules_2.zip"
  layer_name = "lambda_jupyter_2"
  source_code_hash = filebase64sha256("lambda_analyze/python_modules_2.zip")
  compatible_runtimes = ["python3.8"]
}
resource "aws_lambda_function" "lambda_analyze" {
  filename         = data.archive_file.lambda_analyze_zip_dir.output_path
  source_code_hash = data.archive_file.lambda_analyze_zip_dir.output_base64sha256
  function_name    = "lambda_analyze"
  handler          = "main.lambda_handler"
  runtime          = "python3.8"
  role             = aws_iam_role.lambda_role.arn
  timeout          = 120
  memory_size      = 2048
  layers = [
    aws_lambda_layer_version.jupyter_layer_1.arn,
    aws_lambda_layer_version.jupyter_layer_2.arn
  ]
  environment {
    variables = {
      S3_REGION    = aws_s3_bucket.bucket.region
      S3_BUCKET    = aws_s3_bucket.bucket.bucket
    }
  }
}


resource "aws_cloudwatch_event_rule" "rescrape" {
    name = "rescrape"
    description = "Recurrent Scrape"
    schedule_expression = "rate(24 hours)"
}

resource "aws_cloudwatch_event_target" "check_scrape" {
    rule = aws_cloudwatch_event_rule.rescrape.name
    target_id = "lambda_scrape"
    arn = aws_lambda_function.lambda_scrape.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_lambda_scrape" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_scrape.function_name
    principal = "events.amazonaws.com"
    source_arn = aws_cloudwatch_event_rule.rescrape.arn
}