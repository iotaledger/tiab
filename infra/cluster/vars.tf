variable "name_prefix" {
    description = "Name prefix for this environment."
    default = "iri-network-tests"
}

variable "autoscaling_size" { }
variable "testdb_capacity" { }
variable "emptydb_capacity" { }

variable "vpc_cidr" {
    default = "192.168.1.0/24"
}

variable "ec2_key_name" { }
variable "ec2_instance_type" { }

variable "cpu" { }
variable "memory" { }

variable "docker_image_tag" { }
variable "logs_retention_days" {
    default = "7"
}

variable "aws_region" {
    description = "Determine AWS region endpoint to access."
}

provider "aws" {
    region = "${var.aws_region}"
}
