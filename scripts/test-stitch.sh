#!/usr/bin/env sh
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/oreslang-stitch-test.XXXXXX")"
trap 'rm -rf "$tmp"' 0 HUP INT TERM

printf 'define module first as\nend' > "$tmp/first.ores"
printf 'pub routine main() => void { return; }\n' > "$tmp/second.ores"

"$root/scripts/stitch-ores.sh" "$tmp/combined.ores" "$tmp/first.ores" "$tmp/second.ores"
grep -q '^end$' "$tmp/combined.ores"
grep -q '^pub routine main()' "$tmp/combined.ores"

ln -s "$tmp/first.ores" "$tmp/link.ores"
if "$root/scripts/stitch-ores.sh" "$tmp/rejected.ores" "$tmp/link.ores" >/dev/null 2>&1; then
  echo "symlinked source was accepted" >&2
  exit 1
fi

dd if=/dev/zero of="$tmp/too-large.ores" bs=1048577 count=1 2>/dev/null
if "$root/scripts/stitch-ores.sh" "$tmp/rejected-large.ores" "$tmp/too-large.ores" >/dev/null 2>&1; then
  echo "oversized source was accepted" >&2
  exit 1
fi

echo "stitcher self-test passed"
