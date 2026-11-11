#!/usr/bin/env bash
# Compiler-backed, opt-in Java/Graal source-linking checks. No stitching.
# Requires an authorized, clean checkout of the PRIVATE compiler on this runner.
set -euo pipefail
umask 077

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
pin_file="$root/native-multifile/JAVA_COMPILER_REF"
expected_compiler="$(cat "$pin_file")"
[[ "$expected_compiler" =~ ^[a-f0-9]{40}$ ]] || {
  echo "NOT_EXECUTED: invalid native-multifile/JAVA_COMPILER_REF" >&2; exit 64;
}
[[ "$(wc -c < "$pin_file")" -eq 41 ]] || {
  echo "NOT_EXECUTED: compiler pin must include one trailing newline" >&2; exit 64;
}

: "${ATTO_EXPECTED_DEMO_SHA:?NOT_EXECUTED: set exact demo PR head SHA}"
[[ "$ATTO_EXPECTED_DEMO_SHA" =~ ^[a-f0-9]{40}$ ]] || {
  echo "NOT_EXECUTED: invalid demo SHA" >&2; exit 64;
}
test "$(git -C "$root" rev-parse HEAD)" = "$ATTO_EXPECTED_DEMO_SHA" || {
  echo "NOT_EXECUTED: demo HEAD mismatch" >&2; exit 66;
}
test -z "$(git -C "$root" status --porcelain --untracked-files=all)" || {
  echo "NOT_EXECUTED: demo checkout is dirty" >&2; exit 66;
}

source_dir="${ATTO_JAVA_SOURCE_DIR:-${ORESLANG_SOURCE_DIR:-}}"
[[ -n "$source_dir" && -d "$source_dir" ]] || {
  echo "NOT_EXECUTED: trusted runner must set ATTO_JAVA_SOURCE_DIR" >&2; exit 66;
}
compiler="$(cd "$source_dir" && pwd -P)"
test "$(git -C "$compiler" rev-parse --show-toplevel)" = "$compiler" || {
  echo "NOT_EXECUTED: expected compiler checkout root" >&2; exit 66;
}
test -f "$compiler/pom.xml" || {
  echo "NOT_EXECUTED: compiler checkout missing pom.xml" >&2; exit 66;
}
test "$(git -C "$compiler" rev-parse HEAD)" = "$expected_compiler" || {
  echo "NOT_EXECUTED: private compiler HEAD does not match pin" >&2; exit 66;
}
test -z "$(git -C "$compiler" status --porcelain --untracked-files=all)" || {
  echo "NOT_EXECUTED: compiler checkout is dirty" >&2; exit 66;
}
for cmd in java mvn timeout sha256sum diff; do
  command -v "$cmd" >/dev/null || { echo "NOT_EXECUTED: missing $cmd" >&2; exit 69; }
done

# Maven exec.args is parsed as a CLI string: reject whitespace or metacharacters
# in checkout locations rather than pretending argument boundaries are preserved.
[[ "$root" =~ ^[A-Za-z0-9_./-]+$ && "$compiler" =~ ^[A-Za-z0-9_./-]+$ ]] || {
  echo "NOT_EXECUTED: unsafe source path for Maven exec.args" >&2; exit 64;
}

receipt="${ATTO_RECEIPT_DIR:-}"
temporary=0
if [[ -z "$receipt" ]]; then
  receipt="$(mktemp -d "${TMPDIR:-/tmp}/atto-native-receipt.XXXXXX")"
  temporary=1
else
  mkdir -p "$receipt"
fi
if [[ -L "$receipt" || ! -d "$receipt" ]]; then
  echo "NOT_EXECUTED: evidence path must be a real directory" >&2; exit 66
fi
if (( temporary )); then
  trap 'rm -rf -- "$receipt"' EXIT
fi

{
  printf 'status=NOT_EXECUTED\n'
  printf 'demo_head=%s\n' "$ATTO_EXPECTED_DEMO_SHA"
  printf 'demo_tree=%s\n' "$(git -C "$root" rev-parse HEAD^{tree})"
  printf 'compiler_head=%s\n' "$expected_compiler"
  printf 'compiler_tree=%s\n' "$(git -C "$compiler" rev-parse HEAD^{tree})"
  printf 'backend=java-graalvm\n'
  printf 'profile=server-jit\n'
  printf 'mode=linked-native-at-to-source-units\n'
  printf 'no_stitch=true\n'
  printf 'compiler_pom_sha256=%s\n' "$(sha256sum "$compiler/pom.xml" | cut -d ' ' -f1)"
} >"$receipt/identity.txt"
echo "Starting exact Java/GraalVM compiler build"
env -u ORESLANG_PATH timeout --signal=TERM --kill-after=5s 600s \
  mvn -B -ntp -q -e -f "$compiler/pom.xml" -DskipTests clean package \
  >"$receipt/compiler-build.stdout" 2>"$receipt/compiler-build.stderr"

# Provide source and artifact identities, without claiming Native Image/AOT.
find "$compiler/target" -maxdepth 1 -type f -name '*.jar' -print0 \
  | sort -z | xargs -0 -r sha256sum >"$receipt/compiler-artifacts.sha256"
test -s "$receipt/compiler-artifacts.sha256" || {
  echo "NOT_EXECUTED: no compiled compiler artifact identity" >&2; exit 70;
}

# Construct a complete, pinned runtime classpath once. Maven may resolve
# dependencies and build classes, but it must NOT launch the guest: exec:java
# can normalize exit codes, prepend unrelated plugin failures, or mix output.
env -u ORESLANG_PATH timeout --signal=TERM --kill-after=5s 180s \
  mvn -B -ntp -q -f "$compiler/pom.xml" \
  org.apache.maven.plugins:maven-dependency-plugin:3.8.1:build-classpath \
  "-Dmdep.outputFile=$receipt/classpath.txt" \
  >"$receipt/classpath-build.stdout" 2>"$receipt/classpath-build.stderr"
test -s "$receipt/classpath.txt" || {
  echo "NOT_EXECUTED: Maven did not supply runtime dependency classpath" >&2; exit 70;
}
test -d "$compiler/target/classes" || {
  echo "NOT_EXECUTED: compiler classes are missing" >&2; exit 70;
}
# JAR hash and compiled class tree bind the launcher to the pinned source.
# A classpath string digest alone is insufficient: dependency contents can
# change at the same path. Hash each actual runtime dependency independently,
# then verify that the compiler's compiled classes are present.
printf '' >"$receipt/runtime-dependencies.sha256"
# Here-string adds a newline even when Maven emits a classpath without one.
IFS=':' read -r -a runtime_deps <<< "$(cat "$receipt/classpath.txt")"
test "${#runtime_deps[@]}" -gt 0 || {
  echo "NOT_EXECUTED: no runtime dependencies resolved" >&2; exit 70;
}
for dependency in "${runtime_deps[@]}"; do
  if [[ -L "$dependency" || ! -f "$dependency" ]]; then
    echo "NOT_EXECUTED: missing or symlinked runtime dependency" >&2; exit 70;
  fi
  sha256sum "$dependency" >>"$receipt/runtime-dependencies.sha256"
done
find "$compiler/target/classes" -type f -print0 | sort -z \
  | xargs -0 -r sha256sum >"$receipt/compiler-classes.sha256"
test -s "$receipt/compiler-classes.sha256" || {
  echo "NOT_EXECUTED: no compiler bytecode to execute" >&2; exit 70;
}
runtime_classpath="$compiler/target/classes:$(cat "$receipt/classpath.txt")"
printf '%s\n' "$runtime_classpath" | sha256sum > "$receipt/runtime-classpath.sha256"
java -version >"$receipt/java-version.stdout" 2>"$receipt/java-version.stderr"

# Record authored sources separately from compiled artifacts. This is
# provenance, not a substitute for actual compiler execution.
find "$root/native-multifile" -type f -name '*.atto' -print0 \
  | sort -z | xargs -0 -r sha256sum > "$receipt/fixture-sources.sha256"
test -s "$receipt/fixture-sources.sha256"
printf 'case\tphase\texit\tverdict\n' > "$receipt/cases.tsv"
# A runner that has entered guest testing but fails mid-matrix must report
# FAIL, never NOT_EXECUTED or a partially valid PASS.
sed -i 's/^status=NOT_EXECUTED$/status=FAIL/' "$receipt/identity.txt"

invoke() {
  local label="$1"
  shift
  local exit_code=0
  # Each --check or guest run starts a dedicated JVM. The host compiler
  # command owns its real exit status and complete stdout/stderr; Maven cannot
  # masquerade as a source diagnostic or conceal an application failure.
  (
    ulimit -f 4096  # Max regular output file size per process (Linux: 2 MiB).
    env -u ORESLANG_PATH -u JAVA_TOOL_OPTIONS -u _JAVA_OPTIONS \
        -u JDK_JAVA_OPTIONS -u CLASSPATH \
      timeout --signal=TERM --kill-after=5s 120s \
      java -cp "$runtime_classpath" dev.oreslang.launcher.OresMain "$@"
  ) >"$receipt/$label.stdout" 2>"$receipt/$label.stderr" || exit_code=$?
  printf '%s\n' "$exit_code" >"$receipt/$label.exit"
  return "$exit_code"
}

positive() {
  local label="$1" entry="$2"
  echo "CHECK $label entry=$entry"
  if ! invoke "$label-check" --check "$entry"; then
    echo "FAIL $label: linked source admission rejected the positive fixture" >&2; return 1
  fi
  if [[ -s "$receipt/$label-check.stdout" ]] || [[ -s "$receipt/$label-check.stderr" ]]; then
    echo "FAIL $label: linked source check emitted unexpected diagnostics" >&2; return 1
  fi
  printf '%s\t%s\t0\tPASS\n' "$label" check >> "$receipt/cases.tsv"

  echo "EXECUTE $label entry=$entry"
  if ! invoke "$label-run" --mode=jit --platform=server "$entry"; then
    echo "FAIL $label: compiler-backed guest invocation failed" >&2; return 1
  fi
  printf '42' >"$receipt/$label.expected"
  if ! diff -u "$receipt/$label.expected" "$receipt/$label-run.stdout"; then
    echo "FAIL $label: guest output != 42" >&2; return 1
  fi
  if [[ -s "$receipt/$label-run.stderr" ]]; then
    echo "FAIL $label: guest emitted diagnostic stderr" >&2; return 1
  fi
  printf '%s\t%s\t0\tPASS\n' "$label" linked-guest >> "$receipt/cases.tsv"
  echo "PASS $label linked_guest_stdout=42"
}

negative() {
  local label="$1" entry="$2"
  echo "CHECK $label (must reject before execution) entry=$entry"
  if invoke "$label-check" --check "$entry"; then
    echo "FAIL $label: compiler admitted an intentionally invalid source" >&2; return 1
  fi
  local rc
  rc="$(cat "$receipt/$label-check.exit")"
  if ! bash "$root/scripts/atto-negative-oracle.sh" \
    "$label" "$rc" "$receipt/$label-check.stdout" "$receipt/$label-check.stderr"; then
    echo "FAIL $label: rejection is not an exact compiler diagnostic" >&2; return 1
  fi
  printf '%s\t%s\t%s\tPASS\n' "$label" check "$rc" >> "$receipt/cases.tsv"
  echo "PASS $label exact_compile_time_rejection"
}

# One unverified compiler feature cannot be bypassed by stitching, emitting
# expected text from a host shim, or treating a Maven failure as a guest pass.
positive linked-function "$root/native-multifile/src/main.atto"
positive linked-module-class "$root/native-multifile/module/main.atto"
positive ownership-valid "$root/native-multifile/negative/ownership-valid.atto"

negative missing-import "$root/native-multifile/negative/missing-helper.atto"
negative ambiguous-import "$root/native-multifile/negative/ambiguous-import.atto"
negative ownership-conflict "$root/native-multifile/negative/ownership-conflict.atto"
negative aliased-module-leak "$root/native-multifile/module/alias-leak.atto"

sed -i 's/^status=FAIL$/status=PASS/' "$receipt/identity.txt"
printf 'positive_cases=3\nnegative_cases=4\n' >>"$receipt/identity.txt"
echo "NATIVE_MULTIFILE_JAVA_GUEST_PASS demo=$ATTO_EXPECTED_DEMO_SHA compiler=$expected_compiler (JIT guest, not Native Image AOT)"
