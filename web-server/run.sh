#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
build_dir="${TMPDIR:-/tmp}/oreslang-web-demo-$$"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$build_dir"
cat index.ores health.ores WebServer.ores > "$build_dir/WebServer.ores"

java HttpHost.java "$build_dir/WebServer.ores"
