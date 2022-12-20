data "aws_caller_identity" "current" {}

locals {
  account_id                          = data.aws_caller_identity.current.account_id
  lambda_file_system_local_mount_path = "/mnt/efs"
}

resource "aws_ecr_repository" "this" {
  name = "${var.org}-ecr-tfmodule-lf-${var.env}"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "null_resource" "ecr_image" {
  triggers = {
    python_file = md5(file("./lambda/lambda.py"))
    docker_file = md5(file("./lambda/Dockerfile"))
  }

  provisioner "local-exec" {
    command = <<EOF
           aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${var.region}.amazonaws.com
           docker build -t ${aws_ecr_repository.this.repository_url}:latest .
           docker push ${aws_ecr_repository.this.repository_url}:latest
       EOF
    # interpreter = ["pwsh", "-Command"] # For Windows 
    interpreter = ["bash", "-c"] # For Linux/MacOS
    working_dir = "./lambda"
  }
}

data "aws_ecr_image" "lambda_image" {
  depends_on = [
    null_resource.ecr_image
  ]
  repository_name = aws_ecr_repository.this.name
  image_tag       = "latest"
}

# AWS Lambda
resource "aws_iam_role" "lambda_role" {
  name               = "${var.org}-lambda_role-${var.env}"
  assume_role_policy = <<-ROLE
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  ROLE
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "${var.org}-lambda_logging-${var.env}"
  path        = "/"
  description = "IAM policy for logging from a Lambda"

  policy = <<-POLICY
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*",
        "Effect": "Allow"
      },
      {
        "Action": [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ],
        "Resource": "*",
        "Effect": "Allow"
      }
    ]
  }
  POLICY
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_security_group" "lambda" {
  name        = "${var.org}-sg-lambda-${var.env}"
  description = "Allow outbound traffic (egress) for lambda"
  vpc_id      = var.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
# data "archive_file" "lambda" {
#   type             = "zip"
#   source_dir       = "${path.module}/lambda"
#   output_file_mode = "0666"
#   output_path      = "${path.module}/tmp/lambda/lambda.zip"
# }

resource "aws_lambda_function" "this" {
  package_type = "Image"
#   filename = "${path.module}/tmp/lambda/lambda.zip"
#   source_code_hash = data.archive_file.lambda.output_base64sha256
  function_name = "${var.org}-lambda-${var.env}"
  role          = aws_iam_role.lambda_role.arn
#   handler       = "lambda.lambda_handler"
  image_uri     = "${aws_ecr_repository.this.repository_url}:latest"
#   runtime       = "python3.8"
  
  ephemeral_storage {
    size = 1024
  }

  memory_size = 2048
  timeout     = 300

  vpc_config {
    security_group_ids = [aws_security_group.lambda.id]
    subnet_ids         = var.private_subnets
  }

  file_system_config {
    arn              = aws_efs_access_point.lambda.arn
    local_mount_path = local.lambda_file_system_local_mount_path
  }

  environment {
    variables = {
      EFS_MOUNT_POINT = local.lambda_file_system_local_mount_path
    }
  }

  depends_on = [
    aws_ecr_repository.this,
    null_resource.ecr_image,
    data.aws_ecr_image.lambda_image,
    aws_iam_role_policy_attachment.lambda_logs
  ]
  lifecycle {
    ignore_changes = [
      source_code_hash
    ]
  }
}

# CloudWatch Log Group for the Lambda function
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "${var.org}-lambda-logs-${var.env}"
  retention_in_days = 7
}

# EFS file system

resource "aws_efs_file_system" "this" {
  creation_token = "${var.org}-efs-tfmodule-${var.env}"

  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS"
  }
}

# EFS file system policy

resource "aws_efs_file_system_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  bypass_policy_lockout_safety_check = true

  policy = <<-POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "LambdaAccess",
            "Effect": "Allow",
            "Principal": { "AWS": "${aws_iam_role.lambda_role.arn}" },
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                },
                "StringEquals": {
                    "elasticfilesystem:AccessPointArn" : "${aws_efs_access_point.lambda.arn}"
                }
            }
        }
    ]
}
POLICY
}

# AWS EFS mount target

# EFS Security Group / EFS SG
resource "aws_security_group" "efs" {
  name        = "${var.org}-sg-efs-${var.env}}"
  description = "Allow EFS inbound traffic from VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_efs_mount_target" "this" {
  count           = length(var.private_subnets)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS access points

resource "aws_efs_access_point" "lambda" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/lambda"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = 755
    }
  }
}
