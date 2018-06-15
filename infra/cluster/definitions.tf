data "template_file" "task_testdb" {
    template = "${file("task-definitions/ecs_task_iri.tpl")}"

    vars {
        container_name              = "${var.name_prefix}-testdb"
        awslogs_group               = "${module.log.awslogs_group}"
        docker_image                = "${module.ecr.ecr_repository_url}:${var.docker_image_tag}"
        aws_region                  = "${var.aws_region}"
        cpu                         = "${var.cpu}"
        memory                      = "${var.memory}"

        DATABASE_URL                = "https://s3.eu-central-1.amazonaws.com/iotaledger-dbfiles/dev/testnet_files.tgz"
    }
}

data "template_file" "task_emptydb" {
    template = "${file("task-definitions/ecs_task_iri.tpl")}"

    vars {
        container_name              = "${var.name_prefix}-emptydb"
        awslogs_group               = "${module.log.awslogs_group}"
        docker_image                = "${module.ecr.ecr_repository_url}:${var.docker_image_tag}"
        aws_region                  = "${var.aws_region}"
        cpu                         = "${var.cpu}"
        memory                      = "${var.memory}"

        DATABASE_URL                = ""
    }
}
