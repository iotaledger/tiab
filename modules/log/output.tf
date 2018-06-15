output "awslogs_group" {
    value = "${aws_cloudwatch_log_group.awslogs.name}"
}
