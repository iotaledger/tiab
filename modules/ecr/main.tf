resource "aws_ecr_repository" "cluster" {
  name = "${var.name_prefix}"
}
