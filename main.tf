terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Fetch latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  vpc_id = "vpc-0a7f8868dee3ee214"

  # Exact Subnet IDs from production-vpc
  prod_web_subnet_id = "subnet-098fe34d2ec589078"

  private_instances = {
    "prod-app1"    = "subnet-05f96e07dd7a6575d"
    "prod-app2"    = "subnet-04a3343ee3f8a5c00"
    "prod-dbcache" = "subnet-0eedcd56e1da7d49e"
    "prod-db"      = "subnet-04edd3394a64d7bcf"
  }

  # Your existing production-sg ID (selected on screen)
  prod_sg_id = "sg-0996d4413880b4dc5"
}

# 1. Create Security Group for prod-web (Allow SSH & ICMP from 0.0.0.0/0)
resource "aws_security_group" "prod_web_sg" {
  name        = "prod-web-sg"
  description = "Allow SSH and All ICMP IPv4 from 0.0.0.0/0 for prod-web"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All ICMP IPv4 from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prod-web-sg"
  }
}

# 2. Launch prod-web (Public IP enabled)
resource "aws_instance" "prod_web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = local.prod_web_subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.prod_web_sg.id]

  tags = {
    Name = "prod-web"
  }
}

# 3. Launch the 4 private instances (Public IP disabled, attached to sg-0996d4413880b4dc5)
resource "aws_instance" "private_nodes" {
  for_each = local.private_instances

  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = each.value
  associate_public_ip_address = false
  vpc_security_group_ids      = [local.prod_sg_id]

  tags = {
    Name = each.key
  }
}