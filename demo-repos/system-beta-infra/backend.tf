terraform {
  backend "s3" {
    bucket = "terraform-states"
    key    = "system-beta-infra/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "http://minio.127.0.0.1.nip.io"
    }
    access_key                  = "terraform"
    secret_key                  = "terraform-secret-key-change-me"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
