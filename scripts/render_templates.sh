#!/usr/bin/env bash

set -e

BASE=$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)

OUT_DIR="$BASE/rendered"
TEMPLATE_DIR="$BASE/platform/terraform/templates"
VARS_FILE="$BASE/template_vars.yml"

command -v hilrunner > /dev/null || {
    echo "Required command 'hilrunner' not found"
    exit 1
}

mkdir -p $OUT_DIR

for name in 'replicated.conf' 'settings.json'; do
    hilrunner -vars $VARS_FILE -out "$OUT_DIR/$name" "$TEMPLATE_DIR/$name.tpl"
done
