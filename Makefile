#/usr/bin/make -f

VERSION ?= $(shell git describe)

# Required for AWS AMI build (make *release)
ENV ?= dev
SSH_KEY_NAME ?= pubnub-2017-q1
SSH_KEY_PATH ?= $(HOME)/.ssh/$(SSH_KEY_NAME).key

# Sources
COMMON_SRC = $(shell find packer -type f ! -path "packer/platform/*" ! -path "packer/worker/*")
PLATFORM_SRC = $(shell find packer/platform -type f)
WORKER_SRC = $(shell find packer/worker -type f)

# Outputs
PLATFORM_BOX = travis-platform_virtualbox_$(VERSION).box
WORKER_PRECISE_BOX = travis-worker_precise_virtualbox_$(VERSION).box
WORKER_TRUSTY_BOX = travis-worker_trusty_virtualbox_$(VERSION).box

# ----- Run commands for both platform and worker

all: 		platform 			worker/precise			worker/trusty
install: 	platform.install 	worker/precise.install	worker/trusty.install
test: 		platform.test 		worker/precise.test		worker/trusty.test
release:	platform.release	worker/precise.release	worker/trusty.release
clean:		platform.clean		worker/precise.clean	worker/trusty.clean

.PHONY: all install test release clean


# ----- Run commands on platform or worker individually

platform: $(PLATFORM_BOX)
worker/precise: $(WORKER_PRECISE_BOX)
worker/trusty: $(WORKER_TRUSTY_BOX)
.PHONY: platform worker/precise worker/trusty

platform.install worker/precise.install worker/trusty.install: %.install:
	@./scripts/vagrant_install.sh $*
.PHONY: platform.install worker/precise.install worker/trusty.install

common.terraform.test:
	terraform validate terraform
.PHONY: common.terraform.test

platform.terraform.test worker.terraform.test: %.terraform.test: common.terraform.test
	terraform validate terraform/$*
.PHONY: platform.terraform.test worker.terraform.test

platform.packer.test worker/precise.packer.test worker/trusty.packer.test: %.packer.test:
	packer validate packer/$*/packer.json
.PHONY: platform.packer.test worker/precise.packer.test worker/trusty.packer.test

platform.test: platform.terraform.test platform.packer.test
.PHONY: platform.test

worker/precise.test worker/trusty.test: %.test: worker.terraform.test %.packer.test
.PHONY: worker/precise.test worker/trusty.test

platform.release worker/precise.release worker/trusty.release: %.release: %.test
	packer build -only aws \
		-var-file=packer/$(ENV).vars.json \
		-var aws_key_name=$(SSH_KEY_NAME) \
		-var aws_key_path=$(SSH_KEY_PATH) \
		-var version=$(VERSION) \
		packer/$*/packer.json
.PHONY: platform.release worker/precise.release worker/trusty.release

platform.clean worker/precise.clean worker/trusty.clean: %.clean
	@rm -f travis-$*_virtualbox_*.box
.PHONY: platform.clean worker/precise.clean worker/trusty.clean


# Non-PHONY rules
$(PLATFORM_BOX): $(COMMON_SRC) $(PLATFORM_SRC)
	packer build -only vagrant -var version=$(VERSION) packer/platform/packer.json

$(WORKER_PRECISE_BOX): $(COMMON_SRC) $(WORKER_SRC)
	packer build -only vagrant -var version=$(VERSION) packer/worker/precise/packer.json

$(WORKER_TRUSTY_BOX): $(COMMON_SRC) $(WORKER_SRC)
	packer build -only vagrant -var version=$(VERSION) packer/worker/trusty/packer.json
