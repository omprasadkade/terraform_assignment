terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

module "networking" {
  source = "./modules/networking"
}

module "ssh" {
  source = "./modules/ssh"
}

module "ec2" {
  source         = "./modules/ec2"
  vpc_id         = module.networking.vpc_id
  public_subnet  = module.networking.public_subnet_id
  private_subnet = module.networking.private_subnet_id
  key_name       = module.ssh.key_name
}
