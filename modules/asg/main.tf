resource "aws_launch_configuration" "cluster_on_demand" {
    instance_type               = "${var.ec2_instance_type}"
    image_id                    = "${lookup(var.ecs_image_id, var.aws_region)}"
    iam_instance_profile        = "${var.instance_profile}"
    user_data                   = "${data.template_file.autoscaling_user_data.rendered}"
    key_name                    = "${var.ec2_key_name}"
    security_groups             = ["${var.security_group}"]
    associate_public_ip_address = true

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "cluster" {
    name                      = "${var.name_prefix}"
    max_size                  = "${var.group_size}"
    min_size                  = "${var.group_size}"
    desired_capacity          = "${var.group_size}"

    health_check_grace_period = 300
    health_check_type         = "EC2"
    force_delete              = true
    launch_configuration      = "${aws_launch_configuration.cluster_on_demand.name}"
    vpc_zone_identifier       = ["${split(",", var.subnets_ids)}"]

    tag {
        key                 = "Name"
        value               = "${var.name_prefix}"
        propagate_at_launch = true
    }

    lifecycle {
        create_before_destroy = true
    }
}


data "template_file" "autoscaling_user_data" {
    template = "${file("${path.module}/autoscaling_user_data.tpl")}"
    vars {
        ecs_cluster = "${var.cluster_name}"
    }
}
