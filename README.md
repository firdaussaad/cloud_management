# cloud_management

# Terraform AWS Infrastructure

This Terraform script sets up a 2-tier architecture on AWS, including a VPC with public and private subnets, an Application Load Balancer (ALB), EC2 instances running Docker, and a MySQL RDS instance. The state file is stored in an S3 bucket for remote state management.

## Prerequisites

1. [Terraform](https://www.terraform.io/downloads.html) installed on your local machine.
2. An AWS account with the necessary permissions to create the described resources.
3. AWS CLI configured with your credentials.

## Configuration

### AWS Credentials

Make sure your AWS credentials are configured. You can set them up in the `~/.aws/credentials` file:

[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
region = YOUR_AWS_REGION


### Variables

The following variables can be set in a `terraform.tfvars` file or directly in the command line:

- `region`: The AWS region to deploy the infrastructure (default: `us-east-1`).
- `environment`: The environment name (e.g., `dev`, `prod`) (default: `dev`).
- `db_password`: The password for the MySQL RDS instance.

Example `terraform.tfvars`:

```hcl
region = "us-east-1"
environment = "dev"
db_password = "your_secure_password"
```

Usage
Initialize Terraform
Initialize the Terraform configuration. This will download the necessary providers and set up the backend configuration.

```hcl
terraform init
```

Backend Configuration
The Terraform state is stored in an S3 bucket specified in backend.tf:

```hcl
terraform {
  backend "s3" {
    bucket         = "kaperski-shop-bucket"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table" # Optional, for state locking
  }
}
```


