variable "name_prefix" {
    description = "Name prefix for this environment."
    default = "iri-network-tests"
}

variable "autoscaling_size" { }

variable "vpc_cidr" {
    default = "192.168.1.0/24"
}

variable "aws_region" {
    description = "Determine AWS region endpoint to access."
}

variable "ec2_key_name" { }
variable "ec2_instance_type" { }

provider "aws" {
    region = "${var.aws_region}"
}
