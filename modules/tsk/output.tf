output "ecs_task_definiton" {
  value = "${aws_ecs_service.task_service.task_definition}"
}

output "ecs_service_name" {
  value = "${aws_ecs_service.task_service.name}"
}
