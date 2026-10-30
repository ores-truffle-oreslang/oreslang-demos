#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected="$(tr -d '[:space:]' < "$root/SOURCE_REF")"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]] || { echo "SOURCE_REF must be an exact lowercase 40-character commit SHA" >&2; exit 64; }

: "${ORESLANG_SOURCE_DIR:?Trusted runner must provide ORESLANG_SOURCE_DIR}"
compiler="$(cd "$ORESLANG_SOURCE_DIR" && pwd -P)"
[[ -f "$compiler/pom.xml" ]] || { echo "compiler checkout missing pom.xml" >&2; exit 66; }
test "$(git -C "$compiler" rev-parse HEAD)" = "$expected"
test -z "$(git -C "$compiler" status --porcelain --untracked-files=all)"

command -v mvn >/dev/null
command -v java >/dev/null

echo "demo_head=$(git -C "$root" rev-parse HEAD)"
echo "demo_tree=$(git -C "$root" rev-parse HEAD^{tree})"
echo "compiler_head=$(git -C "$compiler" rev-parse HEAD)"
echo "compiler_tree=$(git -C "$compiler" rev-parse HEAD^{tree})"

mvn -B -ntp -q -e -f "$compiler/pom.xml" -DskipTests package dependency:build-classpath -Dmdep.outputFile=target/exact-demo.classpath

tmp="$(mktemp -d "${TMPDIR:-/tmp}/oreslang-demos-exact.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/oreslang-compiler" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec mvn -B -ntp -q -e -f "$compiler/pom.xml" -DskipTests exec:java "-Dexec.args=\$*"
EOF
chmod 700 "$tmp/oreslang-compiler"
export ORESLANG_COMPILER="$tmp/oreslang-compiler"

# 1. Pure Oreslang CLI application.
cli_out="$tmp/cli.out"
(
  cd "$root/cli"
  sh run.sh
) >"$cli_out"
printf 'Oreslang CLI demo\n19 + 23 =\n42\n' > "$tmp/cli.expected"
diff -u "$tmp/cli.expected" "$cli_out"
echo "PASS cli"

# 2. Desktop application guest manifest without opening a window.
sh "$root/scripts/stitch-ores.sh" "$tmp/DesktopApp.ores" "$root/desktop-app/title.ores" "$root/desktop-app/body.ores" "$root/desktop-app/window.ores" "$root/desktop-app/DesktopApp.ores"
java "$root/desktop-app/DesktopHost.java" --manifest-only "$tmp/DesktopApp.ores" >"$tmp/desktop.out"
printf 'Oreslang Desktop Demo\n640\n360\nThis native window is configured and populated by an Oreslang program.\n' > "$tmp/desktop.expected"
diff -u "$tmp/desktop.expected" "$tmp/desktop.out"
echo "PASS desktop-manifest"

# 3. Web application guest route manifest without opening a listener.
sh "$root/scripts/stitch-ores.sh" "$tmp/WebServer.ores" "$root/web-server/index.ores" "$root/web-server/health.ores" "$root/web-server/WebServer.ores"
"$ORESLANG_COMPILER" --platform=server "$tmp/WebServer.ores" >"$tmp/web.out"
cat > "$tmp/web.expected" <<'EOF'
/
text/html; charset=utf-8
<!doctype html><html><head><meta charset=utf-8><title>Oreslang Web Demo</title></head><body><h1>Oreslang Web Demo</h1><p>This route and response body are defined by Oreslang.</p></body></html>
/health
application/json; charset=utf-8
{"status":"ok","language":"oreslang"}
EOF
diff -u "$tmp/web.expected" "$tmp/web.out"
echo "PASS web-route-manifest"

# 4. Oreslang-generated Java source executes exactly.
(
  cd "$root/interop"
  sh run-oreslang-embeds-java.sh
) >"$tmp/ores-to-java.out"
printf '42\n' > "$tmp/ores-to-java.expected"
diff -u "$tmp/ores-to-java.expected" "$tmp/ores-to-java.out"
echo "PASS oreslang-to-java-codegen"

# 5. Java embeds the exact compiler/runtime and evaluates Oreslang in-process.
(
  cd "$root/interop"
  ORESLANG_SOURCE_DIR="$compiler" sh run-java-embeds-oreslang.sh
) >"$tmp/java-to-ores.out"
printf 'java host <- oreslang guest: 42\n' > "$tmp/java-to-ores.expected"
diff -u "$tmp/java-to-ores.expected" "$tmp/java-to-ores.out"
echo "PASS java-to-oreslang"

echo "5/5 exact-compiler demo contracts passed"
