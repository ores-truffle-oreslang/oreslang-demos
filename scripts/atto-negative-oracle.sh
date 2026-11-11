#!/usr/bin/env bash
# Host-only exact-diagnostic oracle. A Maven failure alone NEVER passes a
# compiler-negative guest test. This script does not run AttoLang itself.
set -euo pipefail

if (( $# != 4 )); then
  echo "usage: atto-negative-oracle.sh CASE EXIT_CODE STDOUT STDERR" >&2
  exit 64
fi
case_name="$1"
exit_code="$2"
stdout_file="$3"
stderr_file="$4"

case "$case_name" in
  missing-import)
    # Linked source closure reports this exact phrase in the Java frontend.
    diagnostic='^/[^[:cntrl:]]*/missing-helper[.]atto:[0-9]+:[0-9]+: error: .*does not resolve to a file$'
    ;;
  ambiguous-import)
    # The export-selector resolver requires an unambiguous public declaration.
    diagnostic='^/[^[:cntrl:]]*/ambiguous-import[.]atto:[0-9]+:[0-9]+: error: .*collide.*is ambiguous in [^[:cntrl:]]+$'
    ;;
  ownership-conflict)
    # TypeChecker rejects duplicate simultaneous mutable borrows of one owner.
    diagnostic='^/[^[:cntrl:]]*/ownership-conflict[.]atto:[0-9]+:[0-9]+: error: .*overlapping mutable borrow arguments([^[:cntrl:]]*)$'
    ;;
  aliased-module-leak)
    # Aliasing must be rejected by source analysis, not merely at runtime.
    diagnostic='^/[^[:cntrl:]]*/alias-leak[.]atto:[0-9]+:[0-9]+: error: .*unknown class transport_contract[.]Request([[:space:]]|$)'
    ;;
  *)
    echo "ORACLE_REJECT unknown case=$case_name" >&2
    exit 64
    ;;
esac

if [[ ! "$exit_code" =~ ^[0-9]{1,3}$ ]] || (( 10#$exit_code != 1 )); then
  echo "ORACLE_REJECT $case_name: expected language-rejection exit=1; got=$exit_code" >&2
  exit 1
fi
for path in "$stdout_file" "$stderr_file"; do
  if [[ -L "$path" || ! -f "$path" ]]; then
    echo "ORACLE_REJECT $case_name: missing/nonregular evidence file" >&2
    exit 1
  fi
done
if [[ -s "$stdout_file" ]]; then
  echo "ORACLE_REJECT $case_name: a rejected program emitted stdout" >&2
  exit 1
fi
if (( $(wc -c < "$stderr_file") > 8192 )); then
  echo "ORACLE_REJECT $case_name: diagnostic stream exceeds budget" >&2
  exit 1
fi
# OresMain --check emits one source-anchored compiler diagnostic. An additional
# Maven failure, stack trace, warning or other stderr line cannot count.
if [[ "$(wc -l < "$stderr_file")" -ne 1 ]]; then
  echo "ORACLE_REJECT $case_name: require exactly one diagnostic line" >&2
  exit 1
fi
# Reject control bytes, binary/NUL/ANSI log injection and non-ASCII output.
# The pinned Java CLI sanitizes diagnostics and our reviewed fixture paths are
# ASCII-only. A grep regex match inside an unsanitized byte stream is not proof.
if ! cmp -s "$stderr_file" <(LC_ALL=C tr -cd '\012\040-\176' < "$stderr_file"); then
  echo "ORACLE_REJECT $case_name: nonprintable or non-ASCII diagnostic bytes" >&2
  exit 1
fi
if LC_ALL=C grep -Eiq 'maven|\[ERROR\]|NoClassDefFoundError|Exception in thread|org[.]codehaus|org[.]apache|java[.]lang' "$stderr_file"; then
  echo "ORACLE_REJECT $case_name: infrastructure error present" >&2
  exit 1
fi
# Only a compiler's own stable, case-specific diagnostic satisfies this gate.
# Broad words ("class", "import", "file", "error") and Maven stack traces
# never count as accepted negative language semantics.
if ! LC_ALL=C grep -Eq -- "$diagnostic" "$stderr_file"; then
  echo "ORACLE_REJECT $case_name: missing exact source/phase diagnostic" >&2
  exit 1
fi
printf 'ORACLE_PASS case=%s exit=1 diagnostic=compiler-owned\n' "$case_name"
