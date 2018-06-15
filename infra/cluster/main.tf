module "iam" {
  source      = "../../modules/iam"
  name_prefix = "${var.name_prefix}"
}

module "vpc" {
  source         = "../../modules/vpc"
  cidr_block     = "${var.vpc_cidr}"
  name_prefix    = "${var.name_prefix}"
}

module "ecr" {
  source      = "../../modules/ecr"
  name_prefix = "${var.name_prefix}"
}

module "ecs" {
  source      = "../../modules/ecs"
  name_prefix = "${var.name_prefix}"
}

module "asg" {
  source            = "../../modules/asg"
  name_prefix       = "${var.name_prefix}"
  aws_region        = "${var.aws_region}"
  ec2_key_name      = "${var.ec2_key_name}"
  ec2_instance_type = "${var.ec2_instance_type}"
  instance_profile  = "${module.iam.ecs_instance_profile}"
  subnets_ids       = "${module.vpc.cluster_subnet}"
  security_group    = "${module.vpc.sg_permit_all_id}"
  cluster_name      = "${module.ecs.cluster_name}"
  group_size        = "${var.autoscaling_size}"
}
