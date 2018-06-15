output "ecr_repository_url" {
    value = "${aws_ecr_repository.cluster.repository_url}"
}
