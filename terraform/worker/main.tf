# ----------------------------------------
# Module for Travis Worker
# ----------------------------------------

terraform { required_version = "= 0.9.6" }


# ----- Variables

variable "ami_id"            { }
variable "count"             { }
variable "dist"              { }
variable "env"               { }
variable "instance_type"     { }
variable "platform_fqdn"     { }
variable "rabbitmq_password" { }
variable "region"            { }
variable "role"              { default = "travis-worker" }
variable "route53_zone_id"   { }
variable "sg_ids"            { type = "list" }
variable "ssh_key_name"      { }
variable "ssh_key_path"      { }
variable "sub_domain"        { }
variable "subnet_id"         { }


# ----- Data Sources

data "template_file" "travis-enterprise" {
    template = "${file("${path.module}/templates/travis-enterprise.tpl")}"

    vars {
        platform_fqdn     = "${var.platform_fqdn}"
        rabbitmq_password = "${var.rabbitmq_password}"
    }
}


# ----- Resources

resource "aws_instance" "worker" {
    ami                         = "${var.ami_id}"
    associate_public_ip_address = true
    count                       = "${var.count}"
    ebs_optimized               = true
    instance_type               = "${var.instance_type}"
    key_name                    = "${var.ssh_key_name}"
    subnet_id                   = "${var.subnet_id}"
    vpc_security_group_ids      = [ "${var.sg_ids}" ]

    connection {
        user        = "ubuntu"
        private_key = "${file(var.ssh_key_path)}"
    }

    tags {
        Name        = "${format("%s%d.%s.%s", var.role, count.index + 1, var.dist, var.env)}"
        Role        = "${var.role}"
        Dist        = "${var.dist}"
        CostCenter  = "COGS"
        Department  = "Engineering"
        Environment = "${title(var.env)}"
        Service     = "CICD"
        Component   = "Build"
        Region      = "${var.region}"
    }

    volume_tags {
        Name        = "${format("%s%d.%s.%s", var.role, count.index + 1, var.dist, var.env)}"
        Role        = "${var.role}"
        Dist        = "${var.dist}"
        CostCenter  = "COGS"
        Department  = "Engineering"
        Environment = "${title(var.env)}"
        Service     = "CICD"
        Component   = "Build"
        Region      = "${var.region}"
    }

    ephemeral_block_device {
        device_name = "/dev/sdb"
        no_device = "true"
        virtual_name = "ephemeral0"
    }

    ephemeral_block_device {
        device_name = "/dev/sdc"
        no_device = "true"
        virtual_name = "ephemeral1"
    }

    # Provision Hostname File
    provisioner "file" {
        content = "${format("%s%d.%s.%s.%s.%s", var.role, count.index + 1, var.dist, var.env, var.region, var.sub_domain)}"
        destination = "/tmp/hostname"
    }

    # Provision Template Files
    provisioner "file" {
        content     = "${data.template_file.travis-enterprise.rendered}"
        destination = "/tmp/travis-enterprise"
    }

    # Move Provisioned Files
    provisioner "remote-exec" {
        inline = [
            "sudo mv /tmp/hostname /etc/hostname",
            "sudo mv /tmp/travis-enterprise /etc/default/travis-enterprise"
        ]
    }

    # Bootstrap
    provisioner "remote-exec" {
        inline = [
            "sudo sed -i.bak \"s/127.0.0.1 localhost/127.0.0.1 localhost ${format("%s%d.%s.%s.%s.%s", var.role, count.index + 1, var.dist, var.env, var.region, var.sub_domain)}/g\" /etc/hosts",
            "sudo apt-get update",
            "sudo apt-get upgrade -y",
            "sudo shutdown -r now"
        ]
    }
}

resource "aws_route53_record" "worker" {
    count = "${var.count}"
    zone_id = "${var.route53_zone_id}"
    name = "${format("%s%d.%s", var.role, count.index + 1, var.dist)}"
    type = "A"
    ttl = "300"
    records = [ "${aws_instance.worker.*.public_ip[count.index]}" ]
}


# ----- Outputs

output "private_ips" { value = [ "${aws_instance.worker.*.private_ip}" ] }
output "public_ips"  { value = [ "${aws_instance.worker.*.public_ip}" ] }
output "fqdns"       { value = [ "${aws_route53_record.worker.*.fqdn}" ] }
