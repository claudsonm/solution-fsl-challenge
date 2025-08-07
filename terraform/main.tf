# In this file put all the logic to crete the proper infraestructure
terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "6.7.0"
        }

        random = {
            source = "hashicorp/random"
            version = "3.7.2"
        }
    }

    backend "s3" {
        bucket = "solution-fsl-challenge-654"
        key    = "solution-fsl-challenge/terraform.tfstate"
        region = "us-east-1"
    }
}

provider "aws" {
    region = "us-east-1"
    default_tags {
        tags = {
            Environment = var.environment
            Project = "solution-fsl-challenge"
        }
    }
}

resource "random_string" "fsl_challenge_app_suffix" {
    length           = 4
    special          = false
    upper = false
}

resource "random_string" "fsl_challenge_cdn_logs_suffix" {
    length           = 4
    special          = false
    upper = false
}

resource "aws_s3_bucket" "fsl_challenge_app" {
    bucket = "fsl-challenge-app-${random_string.fsl_challenge_app_suffix.id}"
}

resource "aws_s3_bucket_policy" "allow_access_from_cdn" {
    bucket = aws_s3_bucket.fsl_challenge_app.id
    policy = data.aws_iam_policy_document.allow_access_from_cdn.json
}

data "aws_iam_policy_document" "allow_access_from_cdn" {
    statement {
        principals {
            type        = "Service"
            identifiers = ["cloudfront.amazonaws.com"]
        }

        actions = [
            "s3:GetObject"
        ]

        resources = [
            "${aws_s3_bucket.fsl_challenge_app.arn}/*",
        ]

        condition {
            test     = "StringEquals"
            values = [aws_cloudfront_distribution.fsl_app_cdn.arn]
            variable = "AWS:SourceArn"
        }
    }
}

resource "aws_s3_bucket_ownership_controls" "fsl_challenge_cdn_logs" {
    bucket = aws_s3_bucket.fsl_challenge_cdn_logs.id
    rule {
        object_ownership = "BucketOwnerPreferred"
    }
}

resource "aws_s3_bucket_acl" "fsl_challenge_cdn_logs" {
    depends_on = [aws_s3_bucket_ownership_controls.fsl_challenge_cdn_logs]
    bucket = aws_s3_bucket.fsl_challenge_cdn_logs.id
    acl = "log-delivery-write"
}

resource "aws_s3_bucket" "fsl_challenge_cdn_logs" {
    bucket = "fsl-challenge-app-logs-${random_string.fsl_challenge_cdn_logs_suffix.id}"
}

locals {
    s3_origin_id = "fsl_challenge_s3_origin"
}

resource "aws_cloudfront_origin_access_control" "default" {
    name                              = "cf-origin-access-control-${var.environment}"
    description                       = "cf-origin-access-control-${var.environment}"
    origin_access_control_origin_type = "s3"
    signing_behavior                  = "always"
    signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "fsl_app_cdn" {
    depends_on = [aws_s3_bucket_acl.fsl_challenge_cdn_logs]

    origin {
        domain_name              = aws_s3_bucket.fsl_challenge_app.bucket_regional_domain_name
        origin_access_control_id = aws_cloudfront_origin_access_control.default.id
        origin_id                = local.s3_origin_id
    }

    enabled             = true
    is_ipv6_enabled     = true
    default_root_object = "index.html"

    logging_config {
        include_cookies = false
        bucket          = aws_s3_bucket.fsl_challenge_cdn_logs.bucket_regional_domain_name
    }

    # aliases = ["mysite.example.com", "yoursite.example.com"]

    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id

        forwarded_values {
            query_string = false

            cookies {
                forward = "none"
            }
        }

        viewer_protocol_policy = "allow-all"
        min_ttl                = 0
        default_ttl            = 3600
        max_ttl                = 86400
    }

    price_class = "PriceClass_All"

    restrictions {
        geo_restriction {
            restriction_type = "none"
            locations        = []
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }
}
