#!/usr/bin/env sh
set -eu
umask 077

cd "$(dirname "$0")"
tmp_root="${TMPDIR:-/tmp}"
build_dir="$(mktemp -d "${tmp_root%/}/oreslang-web-demo.XXXXXX")"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

sh ../scripts/stitch-ores.sh "$build_dir/WebServer.ores" index.ores health.ores WebServer.ores

java HttpHost.java "$build_dir/WebServer.ores"
