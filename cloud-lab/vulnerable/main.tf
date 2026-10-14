# Acme photo-share — VULNERABLE stack (the audit target).
# Deploy:  terraform init && terraform apply   (from this directory)
# Against: LocalStack at localhost:4566 (see ../../docker-compose.yml).
# Read every block before deploying. Spoiler: nothing here is safe.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test" # LocalStack accepts anything
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3             = "http://localhost:4566"
    iam            = "http://localhost:4566"
    sts            = "http://localhost:4566"
    ec2            = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
    kms            = "http://localhost:4566"
  }
}

# --- storage -----------------------------------------------------------
resource "aws_s3_bucket" "photoshare" {
  bucket = "acme-photoshare"
  # No encryption block, no logging block, no versioning block.
  # Every missing block below is a finding.
}

# Anyone on the internet can read every object. The app only needed to
# serve resized thumbnails — but the policy below covers the whole bucket.
resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.photoshare.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*" # <-- the whole internet
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.photoshare.arn}/*"
    }]
  })
}

# The "private" customer export. Deploy this, then curl it with NO
# credentials and watch it download.
resource "aws_s3_object" "customers" {
  bucket = aws_s3_bucket.photoshare.id
  key    = "exports/customers.csv"
  source = "${path.module}/files/customers.csv"
}

# --- identity ----------------------------------------------------------
# The app role can do nearly everything, everywhere. The app uploads
# thumbnails to one bucket.
resource "aws_iam_role" "app" {
  name = "photoshare-app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_wildcard" {
  name = "photoshare-app-broad"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*", "ec2:*"] # <-- every S3/EC2 action...
      Resource = "*"               # <-- ...on every resource
    }]
  })
}

# --- network -----------------------------------------------------------
# Web, SSH, and Postgres open to the planet. SSH was "temporary for
# debugging" two years ago.
resource "aws_security_group" "web" {
  name        = "photoshare-web"
  description = "photo-share demo"

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # <-- the world
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # <-- database to the world
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- compute -----------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = "ami-12345678" # LocalStack accepts any ID
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  user_data              = templatefile("${path.module}/user_data.sh", { db_password = var.db_password })
}

resource "aws_iam_instance_profile" "app" {
  name = "photoshare-app"
  role = aws_iam_role.app.name
}

# There is deliberately NO aws_cloudtrail resource and NO
# aws_s3_bucket_logging resource in this stack. Nothing records API calls
# or object access — the A3 lesson (no telemetry, no investigation) as
# infrastructure.
