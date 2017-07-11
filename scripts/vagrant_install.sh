#!/usr/bin/env bash

set -e

BASE=$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)

usage() {
    [ -z $1 ] || >&2 echo -e "Invalid argument '$1'\n"

cat <<HERE
Usage: vagrant_install.sh [option ...] [target ...]

Options:
    -s|--skip-missing   Skip install for missing .box files.
    -h|--help           Show this help message.

Targets:
    platform
    worker
HERE
}

USAGE="Usage: vagrant_install.sh [ platform | worker ]"

RUN_PLATFORM=false
RUN_WORKER=false
SKIP_MISSING=false

while [ "$#" -gt 0 ]; do
    case $1 in
        platform) RUN_PLATFORM=true; shift;;
        worker) RUN_WORKER=true; shift;;
        -s|--skip-missing) SKIP_MISSING=true; shift;;
        -h|--help) usage; exit 0;;
        *) usage $1; exit 1;;
    esac
done

if [ "$RUN_PLATFORM" = "false" ] && [ "$RUN_WORKER" = "false" ]; then
    RUN_PLATFORM=true
    RUN_WORKER=true
fi

run_install() {
    local name=$1
    local box_file=$(find "$BASE" -type f -name "${name}_virtualbox_*box" -print -quit)

    if [ -z "$box_file" ]; then
        if [ "$SKIP_MISSING" = "true" ]; then
            echo "No .box file found for '${name}', skipping install ..."
            return
        else
            echo "Error: No .box file found for '$name'"
            exit 1
        fi
    fi

    vagrant box remove $name || true
    vagrant box add $box_file --name $name
}

[ "$RUN_PLATFORM" = "true" ] && run_install travis-platform
[ "$RUN_WORKER" = "true" ] && run_install travis-worker
