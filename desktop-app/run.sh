#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
tmp_root="${TMPDIR:-/tmp}"
build_dir="$(mktemp -d "${tmp_root%/}/oreslang-desktop-demo.XXXXXX")"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup 0 HUP INT TERM

cat title.ores body.ores window.ores DesktopApp.ores > "$build_dir/DesktopApp.ores"

java DesktopHost.java "$build_dir/DesktopApp.ores"
