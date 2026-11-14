#!/usr/bin/env bash
# Source-free adversarial tests. Fixture "JAR" bytes are synthetic data only.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
runner="$root/scripts/atto-runtime-classpath-audit.sh"
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
classes="$temp/classes"
receipt="$temp/receipts"
cpfile="$temp/runtime.classpath"
mkdir -p "$classes" "$receipt" "$temp/sub" "$temp/emptyclasses"
printf 'synthetic-bytecode\n' >"$classes/Main.class"
printf 'synthetic-jar-one\n' >"$temp/a.jar"
printf 'synthetic-jar-two\n' >"$temp/b.jar"
a="$temp/a.jar"
b="$temp/b.jar"
accepted=0
rejected=0

allow() {
  bash "$runner" "$classes" "$cpfile" "$receipt" >/dev/null
  test -s "$receipt/runtime-dependencies.sha256"
  test -s "$receipt/compiler-classes.sha256"
  test -s "$receipt/runtime-classpath.sha256"
  accepted=$((accepted + 1))
}
deny() {
  local class_path="${1:-$classes}" receipt_path="${2:-$receipt}"
  if bash "$runner" "$class_path" "$cpfile" "$receipt_path" >/dev/null 2>&1; then
    echo "ATTO_CLASSPATH_SELF_TEST_FAILURE accepted malformed dependency path" >&2
    exit 1
  fi
  rejected=$((rejected + 1))
}

printf '%s:%s\n' "$a" "$b" >"$cpfile"; allow
printf '%s\n' "$a" >"$cpfile"; allow
printf ':%s\n' "$a" >"$cpfile"; deny
printf '%s:\n' "$a" >"$cpfile"; deny
printf '%s::%s\n' "$a" "$b" >"$cpfile"; deny
printf '%s:%s\n' "$a" "$a" >"$cpfile"; deny
printf 'relative.jar\n' >"$cpfile"; deny
printf '%s/does-not-exist.jar\n' "$temp" >"$cpfile"; deny
printf '%s/sub/../a.jar\n' "$temp" >"$cpfile"; deny
ln -s "$a" "$temp/link.jar"
printf '%s/link.jar\n' "$temp" >"$cpfile"; deny
printf '%s\n%s\n' "$a" "$b" >"$cpfile"; deny
printf '%s' "$a" >"$cpfile"; printf '\r\n' >>"$cpfile"; deny
printf '%s' "$a" >"$cpfile"; printf '\000\n' >>"$cpfile"; deny
printf '%s' "$a" >"$cpfile"; printf '\033[31m\n' >>"$cpfile"; deny
: >"$cpfile"; deny
printf '%s\n' "$a" >"$cpfile"
ln -s "$classes" "$temp/aliasclasses"
deny "$temp/aliasclasses"
deny "$temp/emptyclasses"
ln -s "$receipt" "$temp/aliasreceipt"
deny "$classes" "$temp/aliasreceipt"
printf 'ATTO_CLASSPATH_HOST_SELF_TEST_PASS accepts=%s rejects=%s NOT_EXECUTED\n' "$accepted" "$rejected"
