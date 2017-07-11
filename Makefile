#/usr/bin/make -f

VERSION ?= $(shell git describe)

# Required for AWS AMI build (make *release)
AWS_REGION ?= us-west-1
AWS_VPC_ID ?= vpc-b9bca5dc
AWS_SUBNET_ID ?= subnet-5c28d904
SSH_KEY_NAME ?= pubnub-2017-q1
SSH_KEY_PATH ?= $(HOME)/.ssh/$(SSH_KEY_NAME).key

# Sources
COMMON_SRC = $(shell find packer -type f ! -path "packer/platform/*" ! -path "packer/worker/*")
PLATFORM_SRC = $(shell find packer/platform -type f)
WORKER_SRC = $(shell find packer/worker -type f)

# Outputs
PLATFORM_BOX = travis-platform_virtualbox_$(VERSION).box
WORKER_BOX = travis-worker_virtualbox_$(VERSION).box


# ----- Run commands for both platform and worker

all: 		platform 			worker
install: 	platform.install 	worker.install
test: 		platform.test 		worker.test
release:	platform.release	worker.release
clean:		platform.clean		worker.clean

.PHONY: all install test release clean


# ----- Run commands on platform or worker individually

platform: $(PLATFORM_BOX)
worker: $(WORKER_BOX)
.PHONY: platform worker

platform.install worker.install: %.install:
	@./scripts/vagrant_install.sh $*
.PHONY: platform.install worker.install

common.test:
	terraform validate terraform
.PHONY: common.test

platform.test worker.test: %.test: common.test
	terraform validate terraform/$*
	packer validate packer/$*/packer.json
.PHONY: platform.test worker.test

platform.release worker.release: %.release: %.test
	packer build -only aws \
		-var aws_region=$(AWS_REGION) \
		-var aws_vpc_id=$(AWS_VPC_ID) \
		-var aws_subnet_id=$(AWS_SUBNET_ID) \
		-var aws_key_name=$(SSH_KEY_NAME) \
		-var aws_key_path=$(SSH_KEY_PATH) \
		-var version=$(VERSION) \
		packer/$*/packer.json
.PHONY: platform.release worker.release

platform.clean worker.clean: %.clean:
	@rm -f travis-$*_virtualbox_*.box
.PHONY: platform.clean worker.clean


# Non-PHONY rules
$(PLATFORM_BOX): $(COMMON_SRC) $(PLATFORM_SRC)
	packer build -only vagrant -var version=$(VERSION) packer/platform/packer.json

$(WORKER_BOX): $(COMMON_SRC) $(WORKER_SRC)
	packer build -only vagrant -var version=$(VERSION) packer/worker/packer.json
