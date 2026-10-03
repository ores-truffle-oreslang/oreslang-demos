#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
compiler="${ORESLANG_COMPILER:-oreslang-compiler}"
build_dir="${TMPDIR:-/tmp}/oreslang-cli-demo-$$"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$build_dir"
cat math.ores messages.ores main.ores > "$build_dir/main.ores"

"$compiler" --platform=server "$build_dir/main.ores"
