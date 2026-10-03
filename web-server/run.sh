#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
tmp_root="${TMPDIR:-/tmp}"
build_dir="$(mktemp -d "${tmp_root%/}/oreslang-web-demo.XXXXXX")"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup 0 HUP INT TERM

cat index.ores health.ores WebServer.ores > "$build_dir/WebServer.ores"

java HttpHost.java "$build_dir/WebServer.ores"
