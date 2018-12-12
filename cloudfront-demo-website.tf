
resource "aws_s3_bucket" "website_bucket" {
  bucket_prefix   = "demo-website"


  logging {
    target_bucket = "${aws_s3_bucket.access_log_bucket.id}"
    target_prefix = "website-bucket/"
  }
}


resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Demo Website"
}


data "aws_iam_policy_document" "origin_access_policy_website" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.website_bucket.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = "${aws_s3_bucket.website_bucket.id}"
  policy = "${data.aws_iam_policy_document.origin_access_policy_website.json}"
}

resource "aws_cloudfront_distribution" "website_cdn" {
  enabled      = true
  http_version = "http2"

  "origin" {
    origin_id   = "website"
    domain_name = "${aws_s3_bucket.website_bucket.bucket_regional_domain_name}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }

  }

  default_root_object = "index.html"

  custom_error_response {
     error_code            = "404"
     error_caching_min_ttl = "360"
     response_code         = "404"
     response_page_path    = "/404.html"
  }

  "default_cache_behavior" {
    allowed_methods = ["GET", "HEAD", "DELETE", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    "forwarded_values" {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl          = "0"
    default_ttl      = "300"                                              //3600
    max_ttl          = "1200"                                             //86400
    target_origin_id = "website"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  "restrictions" {
    "geo_restriction" {
      restriction_type = "none"
    }
  }

  "logging_config" {
    include_cookies = false
    bucket          = "${aws_s3_bucket.access_log_bucket.id}.s3.amazonaws.com"
    prefix          = "cloudfront-distribution/"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "aws_s3_bucket" "access_log_bucket" {
  bucket_prefix = "demo-website-logs"  
  acl    = "log-delivery-write"
  lifecycle_rule {
      id      = "log"
      enabled = true
      expiration {
        days = 7
      }
    }  
}



data "archive_file" "main_site_zip" {
  type        = "zip"
  source_dir = "main-site"
  output_path = "/tmp/main-site.zip"
}

resource "null_resource" "publish_main_site_to_s3" {

  triggers {
    trigger_on_filechange = "${data.archive_file.main_site_zip.output_md5}"
  }  
  provisioner "local-exec" {
    command = "aws s3 sync main-site s3://${aws_s3_bucket.website_bucket.id}"
  }
}

output "website_cdn_hostname" {
  value = "${aws_cloudfront_distribution.website_cdn.domain_name}"
}