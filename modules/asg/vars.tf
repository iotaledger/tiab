variable "name_prefix" { }
variable "aws_region" { }
variable "ec2_key_name" { }
variable "ec2_instance_type" { }
variable "instance_profile" { }
variable "group_size" { }
variable "subnets_ids" {
  type = "string"
}
variable "security_group" {
  type = "string"
}
variable "cluster_name" { }

/* ECS-optimized AMIs per region */
variable "ecs_image_id" {
  default = {
    eu-west-1      = "ami-d65dfbaf"
    eu-central-1   = "ami-ebfb7e84"
  }
}
