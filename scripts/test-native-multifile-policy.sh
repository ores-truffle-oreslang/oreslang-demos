#!/usr/bin/env bash
# Host-only structural policy. It does NOT execute AttoLang or certify linking.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"
test "$(git rev-parse --show-toplevel)" = "$root"
test -f native-multifile/.atto.pkg.toml
test "$(wc -c < native-multifile/JAVA_COMPILER_REF)" -eq 41
grep -Eq '^[a-f0-9]{40}$' native-multifile/JAVA_COMPILER_REF

for path in \
  native-multifile/src/main.atto \
  native-multifile/src/math.atto \
  native-multifile/module/main.atto \
  native-multifile/module/contract.atto \
  native-multifile/module/alias-leak.atto \
  native-multifile/negative/missing-helper.atto \
  native-multifile/negative/ambiguous-import.atto \
  native-multifile/negative/conflicts.atto \
  native-multifile/negative/ownership-conflict.atto \
  native-multifile/negative/ownership-valid.atto; do
  test -f "$path" && test -s "$path" && test ! -L "$path"
done
test -z "$(find native-multifile -type l -print -quit)"
test -z "$(find native-multifile -type f -name '*.ores' -print -quit)"
grep -Fq 'import fnc answer from "./math";' native-multifile/src/main.atto
grep -Fq 'import module transport_contract as tc from "./contract.atto";' native-multifile/module/main.atto
grep -Fq 'pub fnc answer(): int' native-multifile/src/math.atto
grep -Fq 'define module transport_contract as' native-multifile/module/contract.atto
grep -Fq 'import fnc collide from "./conflicts.atto";' native-multifile/negative/ambiguous-import.atto
grep -Fq 'touch(rt mut borrow box, rt mut borrow box);' native-multifile/negative/ownership-conflict.atto
grep -Fq 'touch(rt mut borrow left, rt mut borrow right);' native-multifile/negative/ownership-valid.atto

# The runnable pathway must invoke the original entrypoint and must not
# concatenate/copypaste all source units or use a hidden stitcher fallback.
test ! -L scripts/run-native-multifile-java.sh
bash -n scripts/run-native-multifile-java.sh
# The guest runner must invoke a dedicated Java process, never exec:java via
# Maven, whose plugin errors could be mistaken for compiler diagnostics.
grep -Fq 'dev.oreslang.launcher.OresMain "$@"' scripts/run-native-multifile-java.sh
grep -Fq 'maven-dependency-plugin:3.8.1:build-classpath' scripts/run-native-multifile-java.sh
if grep -Eq '^[[:space:]]+mvn.*exec:java' scripts/run-native-multifile-java.sh; then
  echo 'STRUCTURAL_FAILURE: Maven-in-process guest launcher regressed' >&2; exit 1
fi
bash -n scripts/atto-negative-oracle.sh
bash -n scripts/test-atto-negative-oracle.sh
bash scripts/test-atto-negative-oracle.sh
if grep -Eq '(^|[[:space:]])(cat|paste)[[:space:]].*\\*\\.atto|stitch-ores[.]sh' \
  scripts/run-native-multifile-java.sh; then
  echo 'STRUCTURAL_FAILURE: compiler runner contains a stitch fallback' >&2
  exit 1
fi

# Fail-closed admission probes must terminate BEFORE Maven can run. They test
# the runner's trust boundary, not .atto compiler behavior.
set +e
bad_sha="$(ATTO_EXPECTED_DEMO_SHA=invalid ATTO_JAVA_SOURCE_DIR=/tmp \
  bash scripts/run-native-multifile-java.sh 2>&1)"
bad_rc=$?
missing_checkout="$(ATTO_EXPECTED_DEMO_SHA="$(git rev-parse HEAD)" \
  ATTO_JAVA_SOURCE_DIR=/this-directory-must-not-exist \
  bash scripts/run-native-multifile-java.sh 2>&1)"
missing_rc=$?
set -e
if (( bad_rc == 0 || missing_rc == 0 )) \
  || [[ "$bad_sha" != *NOT_EXECUTED* ]] \
  || [[ "$missing_checkout" != *NOT_EXECUTED* ]]; then
  echo 'STRUCTURAL_FAILURE: exact-identity admission did not fail closed' >&2
  exit 1
fi
echo 'NATIVE_MULTIFILE_HOST_POLICY_PASS (NOT_EXECUTED: compiler guest not invoked)'
