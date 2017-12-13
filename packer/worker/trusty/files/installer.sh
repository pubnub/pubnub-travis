#!/usr/bin/env bash

## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

##

## Handle Arguments

if [[ ! -n $1 ]]; then
  echo "No arguments provided, installing with"
  echo "default configuration values."
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --travis_worker_version=*)
      TRAVIS_WORKER_VERSION="${1#*=}"
      ;;
    --docker_version=*)
      DOCKER_VERSION="${1#*=}"
      ;;
    --aws=*)
      AWS="${1#*=}"
      ;;
    --travis_enterprise_host=*)
      TRAVIS_ENTERPRISE_HOST="${1#*=}"
      ;;
    --travis_enterprise_security_token=*)
      TRAVIS_ENTERPRISE_SECURITY_TOKEN="${1#*=}"
      ;;
    --travis_enterprise_build_endpoint=*)
      TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${1#*=}"
      ;;
    --travis_queue_name=*)
      TRAVIS_QUEUE_NAME="${1#*=}"
      ;;
    --skip_docker_populate=*)
      SKIP_DOCKER_POPULATE="${1#*=}"
      ;;
    *)
      printf "*************************************************************\n"
      printf "* Error: Invalid argument.                                  *\n"
      printf "* Valid Arguments are:                                      *\n"
      printf "*  --travis_worker_version=x.x.x                            *\n"
      printf "*  --docker_version=x.x.x                                   *\n"
      printf "*  --aws=true                                               *\n"
      printf "*  --travis_enterprise_host="demo.enterprise.travis-ci.com" *\n"
      printf "*  --travis_enterprise_security_token="token123"            *\n"
      printf "*  --travis_enterprise_build_endpoint="build-api"           *\n"
      printf "*  --travis_queue_name="builds.linux"                       *\n"
      printf "*  --skip_docker_populate=true                              *\n"
      printf "*************************************************************\n"
      exit 1
  esac
  shift
done

if [[ ! -n $DOCKER_VERSION ]]; then
  export DOCKER_VERSION="17.06.2~ce-0~ubuntu"
else
  export DOCKER_VERSION
fi

if [[ ! -n $AWS ]]; then
  export AWS=false

  echo "This worker is in beta and only works on AWS."
  exit 1
else
  export AWS=true

  DEVICE="/dev/xvdc"
  METADATA_SIZE="8G"
  LVM_VOLUME_NAME="docker"
  DOCKER_STORAGE_OPT_DM_BASESIZE="12G"
  DOCKER_STORAGE_OPT_DM_FS="xfs"
fi

##

## We only want to run on 14.04
trusty_check() {
  if [[ !  $(cat /etc/issue) =~ 14.04 ]]; then
    echo "This should only be run on Ubuntu 14.04"
    exit 1
  fi
}

trusty_check
##


## We only want to run as root
root_check() {
  if [[ $(whoami) != "root" ]]; then
    echo "This should only be run as root"
    exit 1
  fi
}

root_check
##

device_mapper_setup() {
  apt-get update
  apt-get install -y lvm2 xfsprogs

  cat << EOF > /usr/local/bin/travis-docker-volume-setup
#!/bin/bash

set -ex

if [[ -e /dev/$LVM_VOLUME_NAME/metadata ]] ; then
  echo "$(basename $0): Metadata volume already exists.  Assuming set up"
  exit 0
fi

pvcreate "$DEVICE"
vgcreate "$LVM_VOLUME_NAME" "$DEVICE"
lvcreate -n metadata "$LVM_VOLUME_NAME" --size $METADATA_SIZE
dd if=/dev/zero of=/dev/"$LVM_VOLUME_NAME"/metadata bs=1M count=10

lvcreate -n data "$LVM_VOLUME_NAME" -l '100%FREE'
dd if=/dev/zero of=/dev/"$LVM_VOLUME_NAME"/data bs=1M count=10
EOF
  chmod +x /usr/local/bin/travis-docker-volume-setup

}

device_mapper_setup

## Install and setup Docker
docker_setup() {
  : "${DOCKER_APT_FILE:=/etc/apt/sources.list.d/docker.list}"
  : "${DOCKER_CONFIG_FILE:=/etc/default/docker}"

  apt-get install -y apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

  if [[ ! -f $DOCKER_APT_FILE ]]; then
    curl -sSL 'https://download.docker.com/linux/ubuntu/gpg' | apt-key add -
    echo 'deb [arch=amd64] https://download.docker.com/linux/ubuntu trusty stable' >"$DOCKER_APT_FILE"
  fi

  apt-get update

  if ! docker version &>/dev/null; then
    apt-get install -y \
      "linux-image-extra-$(uname -r)" \
      docker-ce=$DOCKER_VERSION
  fi

  cat << 'EOF' > /etc/init/docker.conf
# vim:filetype=upstart
description "Docker daemon"

start on (local-filesystems and net-device-up IFACE!=lo)
stop on runlevel [!2345]
limit nofile 524288 1048576
limit nproc 524288 1048576

respawn

pre-start script
	# see also https://github.com/tianon/cgroupfs-mount/blob/master/cgroupfs-mount
	if grep -v '^#' /etc/fstab | grep -q cgroup \
		|| [ ! -e /proc/cgroups ] \
		|| [ ! -d /sys/fs/cgroup ]; then
		exit 0
	fi
	if ! mountpoint -q /sys/fs/cgroup; then
		mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup
	fi
	(
		cd /sys/fs/cgroup
		for sys in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
			mkdir -p $sys
			if ! mountpoint -q $sys; then
				if ! mount -n -t cgroup -o $sys cgroup $sys; then
					rmdir $sys || true
				fi
			fi
		done
	)
  travis-docker-volume-setup
end script

script
	# modify these in /etc/default/$UPSTART_JOB (/etc/default/docker)
	DOCKER=/usr/bin/dockerd
	DOCKER_OPTS=
	if [ -f /etc/default/$UPSTART_JOB ]; then
		. /etc/default/$UPSTART_JOB
	fi
	exec "$DOCKER" $DOCKER_OPTS
end script

# Don't emit "started" event until docker.sock is ready.
# See https://github.com/docker/docker/issues/6647
post-start script
	DOCKER_OPTS=
	if [ -f /etc/default/$UPSTART_JOB ]; then
		. /etc/default/$UPSTART_JOB
	fi
	if ! printf "%s" "$DOCKER_OPTS" | grep -qE -e '-H|--host'; then
		while ! [ -e /var/run/docker.sock ]; do
			initctl status $UPSTART_JOB | grep -qE "(stop|respawn)/" && exit 1
			echo "Waiting for /var/run/docker.sock"
			sleep 0.1
		done
		echo "/var/run/docker.sock is up"
	fi
end script
EOF

  if [[ $AWS == true ]]; then
    DOCKER_MOUNT_POINT="--graph=/mnt/docker"
  fi

  # disable inter-container communication
  if [[ ! $(grep icc $DOCKER_CONFIG_FILE) ]]; then
    echo 'DOCKER_OPTS="-H tcp://0.0.0.0:4243 -H unix:///var/run/docker.sock --storage-driver=devicemapper --icc=false --storage-opt dm.basesize='$DOCKER_STORAGE_OPT_DM_BASESIZE' --storage-opt dm.datadev=/dev/'$LVM_VOLUME_NAME'/data --storage-opt dm.metadatadev=/dev/'$LVM_VOLUME_NAME'/metadata --storage-opt dm.fs='$DOCKER_STORAGE_OPT_DM_FS' '$DOCKER_MOUNT_POINT'"' >> $DOCKER_CONFIG_FILE
    service docker restart
    sleep 2 # a short pause to ensure the docker daemon starts
  fi
}

docker_setup
##

## Pull down all the Travis Docker images
docker_populate_images() {
  DOCKER_CMD="docker -H tcp://0.0.0.0:4243"

  apt-get update
  apt-get install -y curl jq

  image_mappings_json=$(curl https://raw.githubusercontent.com/travis-infrastructure/terraform-config/master/aws-production-2/generated-language-mapping.json)

  docker_images=$(echo "$image_mappings_json" | jq -r "[.[]] | unique | .[]")

  for docker_image in $docker_images; do
    docker pull "$docker_image"

    langs=$(echo "$image_mappings_json" | jq -r "to_entries | map(select(.value | contains(\"$docker_image\"))) | .[] .key")

    for lang in $langs; do
      $DOCKER_CMD tag $docker_image travis:$lang
    done
  done

  declare -a lang_mappings=('clojure:jvm' 'scala:jvm' 'groovy:jvm' 'java:jvm' 'elixir:erlang' 'node-js:node_js')

  for lang_map in "${lang_mappings[@]}"; do
    map=$(echo $lang_map|cut -d':' -f 1)
    lang=$(echo $lang_map|cut -d':' -f 2)

    $DOCKER_CMD tag travis:$lang travis:$map
  done
}
if [[ ! -n $SKIP_DOCKER_POPULATE ]]; then
  docker_populate_images
fi
##

## Install travis-worker from packagecloud
install_travis_worker() {
  if [[ ! -f /etc/apt/sources.list.d/travisci_worker.list ]]; then
    # add packagecloud apt repo for travis-worker
    curl -s https://packagecloud.io/install/repositories/travisci/worker/script.deb.sh | bash

    # make sure we have the latest version of things
    apt-get update
    if [[ -n $TRAVIS_WORKER_VERSION ]]; then
      apt-get install -y travis-worker=$TRAVIS_WORKER_VERSION
    else
      apt-get install -y travis-worker
    fi
  fi
}

install_travis_worker
##

## Configure travis-worker
configure_travis_worker() {
  TRAVIS_ENTERPRISE_CONFIG="/etc/default/travis-enterprise"
  TRAVIS_WORKER_CONFIG="/etc/default/travis-worker"

  # Trusty images don't seem to like SSH
  echo "export TRAVIS_WORKER_DOCKER_NATIVE=\"true\"" >> $TRAVIS_WORKER_CONFIG

  if [[ -n $TRAVIS_ENTERPRISE_HOST ]]; then
    sed -i \
      "s/\# export TRAVIS_ENTERPRISE_HOST=\"enterprise.yourhostname.corp\"/export TRAVIS_ENTERPRISE_HOST=\"$TRAVIS_ENTERPRISE_HOST\"/" \
      $TRAVIS_ENTERPRISE_CONFIG
  fi

  if [[ -n $TRAVIS_ENTERPRISE_SECURITY_TOKEN ]]; then
    sed -i \
      "s/\# export TRAVIS_ENTERPRISE_SECURITY_TOKEN=\"abcd1234\"/export TRAVIS_ENTERPRISE_SECURITY_TOKEN=\"$TRAVIS_ENTERPRISE_SECURITY_TOKEN\"/" \
      $TRAVIS_ENTERPRISE_CONFIG
  fi

  if [[ -n $TRAVIS_ENTERPRISE_BUILD_ENDPOINT ]]; then
    sed -i \
      "s/# export TRAVIS_ENTERPRISE_BUILD_ENDPOINT=\"__build__\"/export TRAVIS_ENTERPRISE_BUILD_ENDPOINT=\"$TRAVIS_ENTERPRISE_BUILD_ENDPOINT\"/" \
      $TRAVIS_ENTERPRISE_CONFIG
  else
    sed -i \
      "s/# export TRAVIS_ENTERPRISE_BUILD_ENDPOINT=\"__build__\"/export TRAVIS_ENTERPRISE_BUILD_ENDPOINT=\"__build__\"/" \
      $TRAVIS_ENTERPRISE_CONFIG
  fi

  if [[ -n $TRAVIS_QUEUE_NAME ]]; then
    sed -i \
      "s/export QUEUE_NAME='builds.linux'/export QUEUE_NAME=\'$TRAVIS_QUEUE_NAME\'/" \
      $TRAVIS_WORKER_CONFIG
  else
    sed -i \
      "s/export QUEUE_NAME='builds.linux'/export QUEUE_NAME=\'builds.trusty\'/" \
      $TRAVIS_WORKER_CONFIG
  fi
}

configure_travis_worker
##

## Host Setup
host_setup() {
  # enable memory and swap accounting, disable apparmor (optional, but recommended)
  GRUB_CMDLINE_LINUX='cgroup_enable=memory swapaccount=1 apparmor=0'

  if [[ -d /etc/default/grub.d ]] ; then
    cat > "/etc/default/grub.d/99-travis-worker-settings.cfg" <<EOF
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX"
EOF
    update-grub
    return
  fi

  GRUB_CFG="/etc/default/grub"
  touch $GRUB_CFG

  if [[ ! $(grep cgroup_enabled $GRUB_CFG) ]]; then
    sed -i \
      "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_LINUX\"/" \
      $GRUB_CFG
  fi

  update-grub
}

host_setup
##

## Give travis-worker a kick to ensure the
## latest config is picked up
if [[ $(pgrep travis-worker) ]]; then
  stop travis-worker
fi
start travis-worker
##

echo 'Installation complete.'
echo 'It is recommended that this host is restarted before running jobs through it'
