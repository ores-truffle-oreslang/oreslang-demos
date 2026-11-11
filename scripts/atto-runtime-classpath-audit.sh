#!/usr/bin/env bash
# Audit a Maven-generated runtime classpath before launching a compiler guest.
# This verifies identity and path hygiene, not the trustworthiness of JAR code.
set -euo pipefail
umask 077

if (( $# != 3 )); then
  echo 'usage: atto-runtime-classpath-audit.sh CLASSES_DIR CLASSPATH_FILE RECEIPTS_DIR' >&2
  exit 64
fi
classes="$1"
classpath_file="$2"
receipts="$3"

reject() { echo "ATTO_CLASSPATH_REJECT: $*" >&2; exit 70; }
[[ -d "$classes" && ! -L "$classes" ]] || reject 'missing or symlinked compiled class directory'
[[ -f "$classpath_file" && ! -L "$classpath_file" ]] || reject 'missing or symlinked classpath receipt'
[[ -d "$receipts" && ! -L "$receipts" ]] || reject 'missing or symlinked evidence directory'
command -v realpath >/dev/null || reject 'realpath unavailable'
command -v sha256sum >/dev/null || reject 'sha256sum unavailable'

classes="$(realpath -e -- "$classes")"
test -n "$classes"
if [[ -n "$(find "$classes" -type l -print -quit)" ]]; then
  reject 'compiled class tree contains symlinks'
fi
test "$(wc -c < "$classpath_file")" -le 65536 || reject 'classpath output over 64KiB'
# The supported Linux Java runner uses an ASCII, single-line JVM classpath.
# Reject log/option injection (CR, NUL, ANSI, UTF-8, multiline and tabs).
if ! cmp -s "$classpath_file" <(LC_ALL=C tr -cd '\012\040-\176' < "$classpath_file"); then
  reject 'nonprintable classpath bytes'
fi
test "$(wc -l < "$classpath_file")" -le 1 || reject 'multiline classpath'
raw="$(cat "$classpath_file")"
[[ -n "$raw" ]] || reject 'empty runtime classpath'
[[ "$raw" != :* && "$raw" != *: && "$raw" != *::* ]] || reject 'empty classpath segment'

IFS=':' read -r -a deps <<< "$raw"
(( ${#deps[@]} >= 1 )) || reject 'empty dependency set'
printf '' >"$receipts/runtime-dependencies.sha256"
declare -A seen=()
for dep in "${deps[@]}"; do
  [[ "$dep" = /* && "$dep" == *.jar ]] || reject 'classpath entry is not an absolute JAR'
  [[ -f "$dep" && ! -L "$dep" ]] || reject 'missing or symlinked dependency'
  [[ "$(realpath -e -- "$dep")" == "$dep" ]] || reject 'dependency has alias or traversal path'
  [[ -z "${seen[$dep]:-}" ]] || reject 'duplicate classpath entry'
  seen["$dep"]=1
  sha256sum "$dep" >>"$receipts/runtime-dependencies.sha256"
done

find "$classes" -type f -print0 | sort -z \
  | xargs -0 -r sha256sum >"$receipts/compiler-classes.sha256"
test -s "$receipts/compiler-classes.sha256" || reject 'compiled class tree is empty'
printf '%s\n' "$classes:$raw" | sha256sum >"$receipts/runtime-classpath.sha256"
echo "ATTO_RUNTIME_CLASSPATH_ATTEST_PASS dependencies=${#deps[@]} class_files=$(wc -l < "$receipts/compiler-classes.sha256")"
