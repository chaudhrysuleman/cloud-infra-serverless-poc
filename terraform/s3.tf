# --- Fetch AWS Account ID ---
data "aws_caller_identity" "current" {}

# --- S3 Bucket for Invoices ---
resource "aws_s3_bucket" "invoices" {
  bucket        = "suleman-parcels-invoices-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Allows destroying bucket with objects when calling terraform destroy

  tags = {
    Name = "poc-parcels-invoices-bucket"
  }
}

# --- S3 Ownership Controls (Recommended for secure operations) ---
resource "aws_s3_bucket_ownership_controls" "invoices" {
  bucket = aws_s3_bucket.invoices.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# --- Disable Public Access (Ensure all invoices are kept private) ---
resource "aws_s3_bucket_public_access_block" "invoices" {
  bucket = aws_s3_bucket.invoices.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
