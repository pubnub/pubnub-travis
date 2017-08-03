# ----------------------------------------
# Module for Travis Enterprise
# ----------------------------------------

terraform { required_version = "= 0.9.6" }


# ----- Variables

variable "env"               { }
variable "rabbitmq_password" { }
variable "route53_zone_id"   { }
variable "ssh_key_name"      { }
variable "ssh_key_path"      { }
variable "ssl_key_path"      { }
variable "ssl_cert_path"     { }
variable "sub_domain"        { }
variable "subnet_id"         { }
variable "vpc_id"            { }

variable "platform_admin_password"       { }
variable "platform_count"                { }
variable "platform_fqdn"                 { }
variable "platform_github_client_id"     { }
variable "platform_github_client_secret" { }
variable "platform_instance_type"        { }
variable "platform_librato_enabled"      { default = "false" }
variable "platform_librato_email"        { default = "" }
variable "platform_librato_token"        { default = "" }
variable "platform_replicated_log_level" { default = "debug" }
variable "platform_sg_ids"               { type = "list" }

variable "worker_count"         { }
variable "worker_instance_type" { }
variable "worker_sg_ids"        { type = "list" }


# ----- Data Sources

data "aws_region" "current" { current = true }

data "aws_ami" "platform" {
    most_recent = true
    owners      = [ "self" ]

    filter {
        name   = "state"
        values = [ "available" ]
    }

    filter {
        name   = "tag:Role"
        values = [ "travis-platform" ]
    }

    # Only allow AMIs tagged for this environment
    filter {
        name = "tag:Env"
        values = "${var.env}"
    }
}

data "aws_ami" "worker" {
    most_recent = true
    owners      = [ "self" ]

    filter {
        name   = "state"
        values = [ "available" ]
    }

    filter {
        name   = "tag:Role"
        values = [ "travis-worker" ]
    }

    # Only allow AMIs tagged for this environment
    filter {
        name = "tag:Env"
        values = "${var.env}"
    }
}


# ----- Resources

resource "aws_security_group" "allow_travis_workers" {
    name        = "allow_travis_workers"
    description = "Allow Travis Workers"
    vpc_id      = "${var.vpc_id}"

    tags { Name = "allow_travis_workers" }
}

resource "aws_security_group_rule" "allow_travis_workers" {
    count = "${var.worker_count > 0 ? 1 : 0}"
    type              = "ingress"
    security_group_id = "${aws_security_group.allow_travis_workers.id}"

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [ "${formatlist("%s/32", module.worker.private_ips)}" ]
}


# ----- Modules

module "platform" {
    source = "./platform"

    ami_id          = "${data.aws_ami.platform.id}"
    count           = "${var.platform_count}"
    env             = "${var.env}"
    instance_type   = "${var.platform_instance_type}"
    region          = "${data.aws_region.current.name}"
    route53_zone_id = "${var.route53_zone_id}"
    ssh_key_name    = "${var.ssh_key_name}"
    ssh_key_path    = "${var.ssh_key_path}"
    ssl_key_path    = "${var.ssl_key_path}"
    ssl_cert_path   = "${var.ssl_cert_path}"
    sg_ids          = [ "${distinct(concat(var.platform_sg_ids, list(aws_security_group.allow_travis_workers.id)))}" ]
    sub_domain      = "${var.sub_domain}"
    subnet_id       = "${var.subnet_id}"

    # Template Variables
    admin_password       = "${var.platform_admin_password}"
    fqdn                 = "${var.platform_fqdn}"
    github_client_id     = "${var.platform_github_client_id}"
    github_client_secret = "${var.platform_github_client_secret}"
    librato_enabled      = "${var.platform_librato_enabled}"
    librato_email        = "${var.platform_librato_email}"
    librato_token        = "${var.platform_librato_token}"
    rabbitmq_password    = "${var.rabbitmq_password}"
    replicated_log_level = "${var.platform_replicated_log_level}"
}

module "worker" {
    source = "./worker"

    ami_id          = "${data.aws_ami.worker.id}"
    count           = "${var.worker_count}"
    env             = "${var.env}"
    instance_type   = "${var.worker_instance_type}"
    ssh_key_name    = "${var.ssh_key_name}"
    ssh_key_path    = "${var.ssh_key_path}"
    region          = "${data.aws_region.current.name}"
    route53_zone_id = "${var.route53_zone_id}"
    sg_ids          = [ "${var.worker_sg_ids}" ]
    sub_domain      = "${var.sub_domain}"
    subnet_id       = "${var.subnet_id}"

    # Template Variables
    platform_fqdn     = "${var.platform_fqdn}"
    rabbitmq_password = "${var.rabbitmq_password}"
}

# Private Hosted Zone for Private IPs
resource "aws_route53_zone" "private" {
    count   = "${var.platform_count > 0 ? 1 : 0}"
    comment = "Travis Private Hosted Zone"
    name    = "${var.platform_fqdn}"
    vpc_id  = "${var.vpc_id}"
}

resource "aws_route53_record" "private_platform" {
    count   = "${var.platform_count > 0 ? 1 : 0}"
    name    = "${var.platform_fqdn}"
    records = [ "${module.platform.private_ips}" ]
    type    = "A"
    ttl     = "300"
    zone_id = "${aws_route53_zone.private.zone_id}"
}


# ----- Outputs

output "allow_travis_workers" { value = "${aws_security_group.allow_travis_workers.id}" }

output "platform_private_ips" { value = [ "${module.platform.private_ips}" ] }
output "platform_public_ips"  { value = [ "${module.platform.public_ips}" ] }
output "platform_fqdns"       { value = [ "${module.platform.fqdns}" ] }

output "worker_private_ips" { value = [ "${module.worker.private_ips}" ] }
output "worker_public_ips"  { value = [ "${module.worker.public_ips}" ] }
output "worker_fqdns"       { value = [ "${module.worker.fqdns}" ] }

output "private_route53_zone_id" { value = "${aws_route53_zone.private.zone_id}" }
