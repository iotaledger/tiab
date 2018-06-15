resource "aws_ecs_service" "task_service" {
    name                               = "${var.name_prefix}_task_service"
    cluster                            = "${var.cluster_id}"
    task_definition                    = "${aws_ecs_task_definition.task.arn}"
    desired_count                      = "${var.tasks_desired_count}"
    deployment_minimum_healthy_percent = "0"
    deployment_maximum_percent         = "100"

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_ecs_task_definition" "task" {
    family = "${var.name_prefix}_task"
    network_mode = "${var.network_mode}"
    container_definitions = "${var.container_definition_rendered}"

    lifecycle {
        create_before_destroy = true
    }
}
