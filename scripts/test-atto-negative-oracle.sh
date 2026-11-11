#!/usr/bin/env bash
# Hermetic oracle mutation tests. These use synthetic stderr ONLY, never a compiler.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
out="$tmp/stdout"
err="$tmp/stderr"
: > "$out"
oracle="$root/scripts/atto-negative-oracle.sh"
passed=0
failed_expected=0

accept() {
  local label="$1" diagnostic="$2"
  printf '%s\n' "$diagnostic" > "$err"
  if ! bash "$oracle" "$label" 1 "$out" "$err" > /dev/null; then
    echo "ORACLE_SELF_TEST_FAILURE valid language diagnostic rejected: $label" >&2
    exit 1
  fi
  passed=$((passed + 1))
}
reject() {
  local label="$1" code="$2" diagnostic="$3"
  printf '%s\n' "$diagnostic" > "$err"
  if bash "$oracle" "$label" "$code" "$out" "$err" > /dev/null 2>&1; then
    echo "ORACLE_SELF_TEST_FAILURE inadmissible stderr accepted: $label" >&2
    exit 1
  fi
  failed_expected=$((failed_expected + 1))
}

accept missing-import '/tmp/fixtures/missing-helper.atto:1:1: error: import "./does-not-exist" does not resolve to a file'
accept ambiguous-import '/tmp/fixtures/ambiguous-import.atto:1:1: error: import fnc collide is ambiguous in contracts.atto'
accept ownership-conflict '/tmp/fixtures/ownership-conflict.atto:1:1: error: overlapping mutable borrow arguments'
accept aliased-module-leak '/tmp/fixtures/alias-leak.atto:1:1: error: unknown class transport_contract.Request'

reject missing-import 1 '[ERROR] Failed to execute goal org.codehaus.mojo:exec-maven-plugin: The file could not be opened'
reject ambiguous-import 1 '[ERROR] Could not find or load main class; import failed'
reject ownership-conflict 1 '[ERROR] java.lang.NoClassDefFoundError: overlapping mutable borrow arguments'
reject aliased-module-leak 1 '[ERROR] unknown class transport_contract.Request in Maven plugin stacktrace'
reject missing-import 124 '/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file'
reject missing-import 0 '/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file'
reject missing-import 2 '/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file'
reject missing-import 1 '/tmp/fixtures/other.atto:1:1: error: import does not resolve to a file'
reject ambiguous-import 1 '/tmp/fixtures/ambiguous-import.atto:1:1: error: unrelated issue'
reject ownership-conflict 1 '/tmp/fixtures/ownership-conflict.atto:1:1: error: syntax error'
reject aliased-module-leak 1 '/tmp/fixtures/alias-leak.atto:1:1: error: unknown class innocent.Request'
reject aliased-module-leak 137 '/tmp/fixtures/alias-leak.atto:1:1: error: unknown class transport_contract.Request'
# Matching compiler diagnostics mixed with Maven/Java failures must fail.
reject missing-import 1 $'/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file\n[ERROR] Maven failure'
reject ambiguous-import 1 '/tmp/fixtures/ambiguous-import.atto:1:1: error: import fnc collide is ambiguous in contracts.atto [ERROR] Maven'
reject ownership-conflict 1 $'/tmp/fixtures/ownership-conflict.atto:1:1: error: overlapping mutable borrow arguments\njava.lang.NoClassDefFoundError'
# Binary and terminal-control bytes must not bypass the diagnostic oracle.
reject missing-import 1 
reject missing-import 1 '/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file'
: > "$out"
printf 'ATTO_NEGATIVE_ORACLE_HOST_SELF_TEST_PASS accepts=%s rejects=%s NOT_EXECUTED\n' "$passed" "$failed_expected"
/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file\r'
reject ambiguous-import 1 
reject missing-import 1 '/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file'
: > "$out"
printf 'ATTO_NEGATIVE_ORACLE_HOST_SELF_TEST_PASS accepts=%s rejects=%s NOT_EXECUTED\n' "$passed" "$failed_expected"
/tmp/fixtures/ambiguous-import.atto:1:1: error: import fnc collide is ambiguous in contracts.atto\033[0m'
printf '/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file\\n' > "$err"
printf '\\000' >> "$err"
if bash "$oracle" missing-import 1 "$out" "$err" > /dev/null 2>&1; then
  echo "ORACLE_SELF_TEST_FAILURE NUL byte accepted" >&2
  exit 1
fi
failed_expected=$((failed_expected + 1))
printf '42' > "$out"
reject missing-import 1 '/tmp/fixtures/missing-helper.atto:1:1: error: import does not resolve to a file'
: > "$out"
printf 'ATTO_NEGATIVE_ORACLE_HOST_SELF_TEST_PASS accepts=%s rejects=%s NOT_EXECUTED\n' "$passed" "$failed_expected"
