resource "aws_cloudwatch_log_group" "awslogs" {
  name = "${var.name_prefix}"
  retention_in_days = "${var.retention_days}"
}
