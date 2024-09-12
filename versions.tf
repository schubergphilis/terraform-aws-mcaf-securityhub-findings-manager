terraform {
  required_version = ">= 1.3.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 2.0"
    }
  }
}
