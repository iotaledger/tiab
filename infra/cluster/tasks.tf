module "log" {
  source         = "../../modules/log"
  name_prefix    = "${var.name_prefix}"
  retention_days = "${var.logs_retention_days}"
}

module "tsk-testdb" {
  source                        = "../../modules/tsk"
  name_prefix                   = "${var.name_prefix}-testdb"
  cluster_id                    = "${module.ecs.cluster_name}"
  tasks_desired_count           = "${var.testdb_capacity}"
  //service_role                  = "${module.iam.ecs_service_role}"
  network_mode                  = "host"
  container_definition_rendered = "${data.template_file.task_testdb.rendered}"
}

module "tsk-emptydb" {
  source                        = "../../modules/tsk"
  name_prefix                   = "${var.name_prefix}-emptydb"
  cluster_id                    = "${module.ecs.cluster_name}"
  tasks_desired_count           = "${var.emptydb_capacity}"
  //service_role                  = "${module.iam.ecs_service_role}"
  network_mode                  = "host"
  container_definition_rendered = "${data.template_file.task_emptydb.rendered}"
}
