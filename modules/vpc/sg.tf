resource "aws_security_group" "permit_all" {
    name = "${var.name_prefix}"
    vpc_id = "${aws_vpc.main.id}"
    description = "Security group that permits all ingress and egress traffic."

    ingress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags {
        Name = "${var.name_prefix}"
    }
}
