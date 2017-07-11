# Travis Enterprise

This repository contains the following for PubNub's Travis Enterprise codebase
- Packer configuration and Vagrantfile for local development
- Packer configuration for AMI creation
- High level terraform module for Travis Enterprise set up
- Individual terraform *submodules* for both **Platform** and **Worker** machines


## Local Development

**Dependencies** (Installable via homebrew)
- https://github.com/pubnub/packer-builder-virtualbox-vagrant
- https://github.com/pubnub/hilrunner

**Configuration**

You can configure your local setup via [local_config.yml](local_config.yml)

The [Vagrantfile](Vagrantfile) is set up to handle local rendering of terraform templates according to the variables defined there.

Add your SSL `<fqdn>.crt` and `<fqdn>.key` of choice to the [certs](certs) directory and vagrant will provision the platform machine to use them.

**Build and install vagrant boxes**

Create the `.box` file:
```
# Individually
make [platform | worker]

# Both
make
```

Install the `.box` file locally:
```
# Individually
make [platform | worker].install

# Both
make install
```

**Run VM(s)**
```
# Platform
vagrant up travis-platform

# Worker(s)
vagrant up travis-worker[#]
```

## Deployment

**AMI Creation**

Ensure environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set for the desired aws account

```
# Individually
make [platform | worker].release

# Both
make release
```

The [Makefile](Makefile) accepts (and has defaults for) the following environment variables:
- AWS_REGION
- AWS_VPC_ID
- AWS_SUBNET_ID
- SSH_KEY_NAME
- SSH_KEY_PATH

By default, new AMIs are created with tags:
- Dev = true
- Staging = false
- Prod = false

The terraform module will (given variable `env` set to `dev | staging | prod`) use the latest AMI with the corresponding tag set to true. Currenly AMIs are promoted up environments by manually editing these tags.

**Instance Creation / Management**

The terraform configuration in [this repo](terraform) is intended to be consumed by [pn-terraform](https://github.com/pubnub/pn-terraform)

Simplified example:
```
module "travis" {
    source = "git@github.com:pubnub/pubnub-travis.git//terraform?ref=<version tag>"

    module variables ...
}
```

A complete example can be found [here](https://github.com/pubnub/pn-terraform/tree/master/aws/dev/us-west-1/travis)

After creating a new **Platform** machine via terraform, complete / validate the set up by visiting the configured domain on port `8800` in your browser (ex. `travis.pubnub.com:8800`).


## TODO
- Librato set up
- S3 Caching
- Service Discovery
- Snapshots
- OAuth callback routed through BRP
- Worker Auto-scaling? (Maybe doesn't belong within the module)
