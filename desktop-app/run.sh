#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
build_dir="${TMPDIR:-/tmp}/oreslang-desktop-demo-$$"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$build_dir"
cat title.ores body.ores window.ores DesktopApp.ores > "$build_dir/DesktopApp.ores"

java DesktopHost.java "$build_dir/DesktopApp.ores"
