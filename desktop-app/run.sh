#!/usr/bin/env sh
set -eu
umask 077

cd "$(dirname "$0")"
tmp_root="${TMPDIR:-/tmp}"
build_dir="$(mktemp -d "${tmp_root%/}/oreslang-desktop-demo.XXXXXX")"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

../scripts/stitch-ores.sh "$build_dir/DesktopApp.ores" title.ores body.ores window.ores DesktopApp.ores

java DesktopHost.java "$build_dir/DesktopApp.ores"
