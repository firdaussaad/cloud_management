terraform {
  backend "s3" {
    bucket         = "kaperski-shop-bucket"
    key            = "terraform.tfstate"
    region         = "us-east-1" # Adjust the region as needed
    
  }
}
