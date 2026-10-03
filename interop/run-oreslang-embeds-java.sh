#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
compiler="${ORESLANG_COMPILER:-oreslang-compiler}"
build_dir="${TMPDIR:-/tmp}/oreslang-java-interop-$$"

cleanup() {
  rm -rf "$build_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$build_dir"

"$compiler" --platform=server OreslangEmbedsJava.ores > "$build_dir/HelloFromGeneratedJava.java"

grep -q 'public final class HelloFromGeneratedJava' "$build_dir/HelloFromGeneratedJava.java"
exec java "$build_dir/HelloFromGeneratedJava.java"
