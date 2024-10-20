################################################################################
# S3 Source Image Bucket
################################################################################
data "aws_s3_bucket" "source_image_bucket" {
  bucket = var.source_bucket_name
}

################################################################################
# S3 Thumbnail Image Bucket
################################################################################
data "aws_s3_bucket" "destination_thumbnail_bucket" {
  bucket = var.thumbnail_bucket_name
}

################################################################################
# Local values
################################################################################
/*locals {
  common_tags = {
    Environment = "dev"
    Team        = "engineering"
  }

  naming_prefix = "my-app"
}
*/

################################################################################
# S3 Policy to Get and Put objects
################################################################################
resource "aws_iam_policy" "lambda_s3_policy" {
  name = "LambdaS3Policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Action" : "s3:GetObject",
      "Resource" : "${data.aws_s3_bucket.source_image_bucket.arn}/*"
    }, {
      "Effect" : "Allow",
      "Action" : "s3:PutObject",
      "Resource" : "${data.aws_s3_bucket.destination_thumbnail_bucket.arn}/*"
    }]
  })
}

################################################################################
# Lambda IAM role to assume the role
################################################################################
resource "aws_iam_role" "lambda_s3_role" {
  name = "LambdaS3Role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "lambda.amazonaws.com"
      },
      "Action" : "sts:AssumeRole"
    }]
  })
}

################################################################################
# Assign policy to the role
################################################################################
resource "aws_iam_policy_attachment" "assigning_policy_to_role" {
  name       = "AssigingPolicyToRole"
  roles      = [aws_iam_role.lambda_s3_role.name]
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

resource "aws_iam_policy_attachment" "assigning_lambda_execution_role" {
  name       = "AssigningLambdaExecutionRole"
  roles      = [aws_iam_role.lambda_s3_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


################################################################################
# Creating Lambda Function
################################################################################
resource "aws_lambda_function" "create_thumbnail_lambda_function" {
  function_name = "CreateThumbnailLambdaFunction"
  filename      = "${path.module}/lambda_function.zip"

  runtime     = "python3.12"
  handler     = "thumbnail.lambda_handler"
  memory_size = 256
  timeout     = 300

  environment {
    variables = {
      DEST_BUCKET = data.aws_s3_bucket.destination_thumbnail_bucket.bucket
    }
  }

  source_code_hash = data.archive_file.thumbnail_lambda_source_archive.output_base64sha256
  role             = aws_iam_role.lambda_s3_role.arn

  layers = [
    "arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-Pillow:2"
  ]
}

data "archive_file" "thumbnail_lambda_source_archive" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_code"
  output_path = "${path.module}/lambda_function.zip"
}


################################################################################
# Lambda Function Permission to have S3 as a Trigger for Lambda Function
################################################################################
resource "aws_lambda_permission" "thumbnail_allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_thumbnail_lambda_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.source_image_bucket.arn
}

################################################################################
# Creating S3 Notification for Lambda when Object is uploaded in the Source Bucket
################################################################################
resource "aws_s3_bucket_notification" "thumbnail_notification" {
  bucket = data.aws_s3_bucket.source_image_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.create_thumbnail_lambda_function.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [
    aws_lambda_permission.thumbnail_allow_bucket
  ]
}


