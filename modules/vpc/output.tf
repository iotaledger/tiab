output "vpc_id" {
    value = "${aws_vpc.main.id}"
}

output "cluster_subnet" {
    value = "${aws_subnet.cluster_subnet.id}"
}

output "sg_permit_all_id" {
    value = "${aws_security_group.permit_all.id}"
}

output "route_table_main" {
    value = "${aws_route_table.main.id}"
}
