resource "aws_ecs_cluster" "cluster" {
    name = "${var.name_prefix}_cluster"
}
