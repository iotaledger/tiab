output "ecs_instance_profile" {
        value = "${aws_iam_instance_profile.ecs_instance_profile.arn}"
}

output "ecs_service_role" {
        value = "${aws_iam_role.ecs_service_role.name}"
}

output "ecs_autoscaling_role_arn" {
        value = "${aws_iam_role.ecs_autoscaling_role.arn}"
}

output "ecrfull_instance_profile" {
        value = "${aws_iam_instance_profile.ecrfull_instance_profile.name}"
}

output "ecrfull_role_arn" {
        value = "${aws_iam_role.ecrfull_role.arn}"
}
