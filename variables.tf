variable "source_bucket_name" {
  description = "The name of the S3 bucket where the source images are uploaded."
  type        = string
}

variable "thumbnail_bucket_name" {
  description = "The name of the S3 bucket where the thumbnails are stored."
  type        = string
}
