resource "aws_cloudfront_origin_access_identity" "origin_failover_access_identity" {
  comment = "Failover Website"
}

resource "aws_s3_bucket" "failover_bucket" {
  bucket_prefix   = "failover-website"


  logging {
    target_bucket = "${aws_s3_bucket.access_log_bucket.id}"
    target_prefix = "failover-bucket/"
  }
}

data "aws_iam_policy_document" "origin_access_policy_failover" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.failover_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_failover_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.failover_bucket.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_failover_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "failover_bucket_policy" {
  bucket = "${aws_s3_bucket.failover_bucket.id}"
  policy = "${data.aws_iam_policy_document.origin_access_policy_failover.json}"
}

data "archive_file" "failover_site_zip" {
  type        = "zip"
  source_dir = "failover-site"
  output_path = "/tmp/failover-site.zip"
}

resource "null_resource" "publish_failover_site_to_s3" {

  triggers {
    trigger_on_filechange = "${data.archive_file.failover_site_zip.output_md5}"
  }  
  provisioner "local-exec" {
    command = "aws s3 sync failover-site s3://${aws_s3_bucket.failover_bucket.id}"
  }
}
