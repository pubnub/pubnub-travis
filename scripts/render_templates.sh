#!/usr/bin/env bash

set -e

BASE=$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)

OUT_DIR="$BASE/rendered"
VARS_FILE="$BASE/local_config.yml"

command -v hilrunner > /dev/null || {
    echo "Required command 'hilrunner' not found"
    echo "--> https://github.com/pubnub/hilrunner"
    exit 1
}

mkdir -p "$OUT_DIR/platform" "$OUT_DIR/worker"

render_platform() {
    local template_dir="$BASE/terraform/platform/templates"
    for name in "replicated.conf" "settings.json"; do
        hilrunner -vars $VARS_FILE -out "$OUT_DIR/platform/$name" "$template_dir/$name.tpl"
    done
}

render_worker() {
    local template_dir="$BASE/terraform/worker/templates"
    hilrunner -vars $VARS_FILE -out "$OUT_DIR/worker/travis-enterprise" "$template_dir/travis-enterprise.tpl"
}

render_platform
render_worker
