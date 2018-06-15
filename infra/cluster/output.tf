output "vpc_id" {
  value = "${module.vpc.vpc_id}"
}

output "vpc_cidr" {
  value = "${var.vpc_cidr}"
}

output "cluster_subnet_id" {
  value = "${module.vpc.cluster_subnet}"
}

output "cluster_instances_sg_id" {
  value = "${module.vpc.sg_permit_all_id}"
}

output "ecs_cluster_name" {
  value = "${module.ecs.cluster_name}"
}

output "ecs_instance_profile" {
  value = "${module.iam.ecs_instance_profile}"
}

output "ecs_service_role" {
  value = "${module.iam.ecs_service_role}"
}

output "ecs_autoscaling_role_arn" {
  value = "${module.iam.ecs_autoscaling_role_arn}"
}

output "ecr_repository_url" {
  value = "${module.ecr.ecr_repository_url}"
}

output "route_table_main" {
  value = "${module.vpc.route_table_main}"
}

output "ecrfull_instance_profile" {
  value = "${module.iam.ecrfull_instance_profile}"
}

output "ecrfull_role_arn" {
  value = "${module.iam.ecrfull_role_arn}"
}
