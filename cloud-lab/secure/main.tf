# Acme photo-share — SECURE stack (the reference fix).
# Same app, same bucket name root, every finding remediated.
# Deploy: terraform init && terraform apply (from this directory).
# NOTE: bucket is named acme-photoshare-secure so both stacks' intent is
# obvious; names, not security, differ.
# (Provider versions live in versions.tf.)

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
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

variable "office_cidr" {
  description = "office egress IP allowed to reach the app"
  type        = string
  default     = "203.0.113.10/32" # TEST-NET-3, i.e. documentation range
}

# --- storage: private, encrypted, logged, versioned --------------------
resource "aws_s3_bucket" "photoshare" {
  bucket = "acme-photoshare-secure"
}

# Explicit deny-everyone default. No bucket policy at all: nothing is public.
resource "aws_s3_bucket_public_access_block" "photoshare" {
  bucket                  = aws_s3_bucket.photoshare.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "photoshare" {
  description             = "photo-share bucket key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "photoshare" {
  bucket = aws_s3_bucket.photoshare.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.photoshare.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "photoshare" {
  bucket = aws_s3_bucket.photoshare.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "acme-photoshare-logs"
}

resource "aws_s3_bucket_logging" "photoshare" {
  bucket        = aws_s3_bucket.photoshare.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/"
}

resource "aws_s3_object" "customers" {
  bucket = aws_s3_bucket.photoshare.id
  key    = "exports/customers.csv"
  source = "${path.module}/files/customers.csv"
}

# --- identity: least privilege -----------------------------------------
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

# Exactly what the app does: read/write objects in its own bucket. Nothing
# else, nowhere else.
resource "aws_iam_role_policy" "app_scoped" {
  name = "photoshare-app-scoped"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.photoshare.arn,
        "${aws_s3_bucket.photoshare.arn}/*"
      ]
    }]
  })
}

# --- network: office-only HTTP, no open SSH, DB not exposed -------------
resource "aws_security_group" "web" {
  name        = "photoshare-web"
  description = "photo-share demo"

  ingress {
    description = "http from office only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.office_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- secrets: generated, vaulted, never in code -------------------------
resource "random_password" "db" {
  length  = 24
  special = true
}

resource "aws_secretsmanager_secret" "db" {
  name = "photoshare/db-password"
  # Zero recovery window: deleting the stack purges the secret immediately
  # instead of scheduling deletion (which would block redeploys — and in
  # production would deserve a deliberate retention choice, not an accident).
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = random_password.db.result
}

# Bootstrap reads the password from Secrets Manager at boot. The secret
# value appears nowhere in this repo — only the secret's ARN.
resource "aws_instance" "app" {
  ami                    = "ami-12345678"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  user_data              = <<-EOT
    #!/bin/bash
    echo "starting photo-share..."
    aws --endpoint-url http://localhost:4566 secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.db.arn} --region us-east-1
  EOT
}

resource "aws_iam_instance_profile" "app" {
  name = "photoshare-app"
  role = aws_iam_role.app.name
}

# --- audit trail ---------------------------------------------------------
# Object-level access logging ships to the logs bucket (see
# aws_s3_bucket_logging above — verified live in Task 5). API-level audit
# (CloudTrail) is the real-AWS companion control: LocalStack Community
# doesn't emulate the CloudTrail API, so it lives as a reviewed code
# pattern in README Appendix B rather than an applied resource.
