# ----------------------------------------
# Module for Travis Platform
# ----------------------------------------

terraform { required_version = "= 0.9.6" }


# ----- Variables

variable "ami_id"          { }
variable "count"           { }
variable "env"             { }
variable "instance_type"   { }
variable "eip"             { }
variable "region"          { }
variable "role"            { default = "travis-platform" }
variable "route53_zone_id" { }
variable "sg_ids"          { type = "list" }
variable "ssh_key_name"    { }
variable "ssh_key_path"    { }
variable "ssl_key_path"    { }
variable "ssl_cert_path"   { }
variable "sub_domain"      { }
variable "subnet_id"       { }

# Template Variables
variable "admin_password"       { }
variable "fqdn"                 { }
variable "github_client_id"     { }
variable "github_client_secret" { }
variable "librato_enabled"      { default = "false" }
variable "librato_email"        { default = "" }
variable "librato_token"        { default = "" }
variable "rabbitmq_password"    { }
variable "replicated_log_level" { default = "debug" }


# ----- Data Sources

data "aws_eip" "platform" {
    public_ip = "${var.eip}"
}

data "template_file" "replicated" {
    template = "${file("${path.module}/templates/replicated.conf.tpl")}"

    vars {
        platform_admin_password = "${var.admin_password}"
        platform_fqdn           = "${var.fqdn}"
        replicated_log_level    = "${var.replicated_log_level}"
        bypass_preflight_checks = "false"
    }
}

data "template_file" "settings" {
    template = "${file("${path.module}/templates/settings.json.tpl")}"

    vars {
        github_client_id     = "${var.github_client_id}"
        github_client_secret = "${var.github_client_secret}"
        librato_enabled      = "${var.librato_enabled}"
        librato_email        = "${var.librato_email}"
        librato_token        = "${var.librato_token}"
        rabbitmq_password    = "${var.rabbitmq_password}"
    }
}


# ----- Resources

resource "aws_eip_association" "platform" {
    count = "${var.count}"
    instance_id = "${aws_instance.platform.id}"
    allocation_id = "${data.aws_eip.platform.id}"
}

resource "aws_instance" "platform" {
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
        Name        = "${format("%s%d.%s", var.role, count.index + 1, var.env)}"
        Role        = "${var.role}"
        CostCenter  = "COGS"
        Department  = "Engineering"
        Environment = "${title(var.env)}"
        Service     = "CICD"
        Component   = "Build"
        Region      = "${var.region}"
    }

    volume_tags {
        Name        = "${format("%s%d.%s", var.role, count.index + 1, var.env)}"
        Role        = "${var.role}"
        CostCenter  = "COGS"
        Department  = "Engineering"
        Environment = "${title(var.env)}"
        Service     = "CICD"
        Component   = "Build"
        Region      = "${var.region}"
    }

    # Provision Hostname File
    provisioner "file" {
        content = "${format("%s%d.%s.%s.%s", var.role, count.index + 1, var.env, var.region, var.sub_domain)}"
        destination = "/tmp/hostname"
    }

    # Provision SSL Key/Cert Files
    provisioner "file" {
        source      = "${var.ssl_key_path}"
        destination = "/tmp/ssl.key"
    }

    provisioner "file" {
        source      = "${var.ssl_cert_path}"
        destination = "/tmp/ssl.crt"
    }

    # Provision Template Files
    provisioner "file" {
        content     = "${data.template_file.replicated.rendered}"
        destination = "/tmp/replicated.conf"
    }

    provisioner "file" {
        content     = "${data.template_file.settings.rendered}"
        destination = "/tmp/settings.json"
    }

    # Move Provisioned Files
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /opt/pubnub/certs /opt/pubnub/travis-platform",
            "sudo mv /tmp/hostname /etc/hostname",
            "sudo mv /tmp/ssl.key /opt/pubnub/certs/${var.fqdn}.key",
            "sudo mv /tmp/ssl.crt /opt/pubnub/certs/${var.fqdn}.crt",
            "sudo mv /tmp/replicated.conf /etc/replicated.conf",
            "sudo mv /tmp/settings.json /opt/pubnub/travis-platform/settings.json"
        ]
    }

    # Set File Permissions
    provisioner "remote-exec" {
        inline = [
            "sudo chmod 640 /opt/pubnub/travis-platform/settings.json",
            "sudo chown root:docker /opt/pubnub/travis-platform/settings.json",
            "sudo chmod 640 /etc/replicated.conf",
            "sudo chown root:docker /etc/replicated.conf"
        ]
    }

    # Bootstrap
    provisioner "remote-exec" {
        inline = [
            "sudo sed -i.bak \"s/127.0.0.1 localhost/127.0.0.1 localhost ${format("%s%d.%s.%s.%s", var.role, count.index + 1, var.env, var.region, var.sub_domain)}/g\" /etc/hosts",
            "sudo apt-get update",
            "sudo apt-get upgrade -y",
            "sudo /opt/pubnub/travis-platform/installer.sh no-proxy no-docker private-address=${self.private_ip} public-address=${self.public_ip}",
            "sudo shutdown -r now"
        ]
    }
}

resource "aws_route53_record" "platform" {
    count = "${var.count}"
    zone_id = "${var.route53_zone_id}"
    name = "${format("${var.role}%d", count.index + 1)}"
    type = "A"
    ttl = "300"
    records = [ "${data.aws_eip.platform.public_ip}" ]
}


# ----- Outputs

output "private_ips" { value = [ "${aws_instance.platform.*.private_ip}" ] }
output "public_ips"  { value = [ "${data.aws_eip.platform.public_ip}" ] }
output "fqdns"       { value = [ "${aws_route53_record.platform.*.fqdn}" ] }
