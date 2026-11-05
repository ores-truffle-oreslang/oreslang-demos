#!/usr/bin/env sh
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/oreslang-stitch-test.XXXXXX")"
trap 'rm -rf "$tmp"' 0 HUP INT TERM

printf 'define module first as\nend' > "$tmp/first.ores"
printf 'pub routine main() => void { return; }\n' > "$tmp/second.ores"

sh "$root/scripts/stitch-ores.sh" "$tmp/combined.ores" "$tmp/first.ores" "$tmp/second.ores"
grep -q '^end$' "$tmp/combined.ores"
grep -q '^pub routine main()' "$tmp/combined.ores"

ln -s "$tmp/first.ores" "$tmp/link.ores"
if "$root/scripts/stitch-ores.sh" "$tmp/rejected.ores" "$tmp/link.ores" >/dev/null 2>&1; then
  echo "symlinked source was accepted" >&2
  exit 1
fi

target="$tmp/preserve.txt"
printf 'preserve me\n' > "$target"
ln -s "$target" "$tmp/output-link.ores"
if "$root/scripts/stitch-ores.sh" "$tmp/output-link.ores" "$tmp/first.ores" >/dev/null 2>&1; then
  echo "symlinked output was accepted" >&2
  exit 1
fi
grep -qx 'preserve me' "$target"

cp "$tmp/first.ores" "$tmp/self.ores"
if "$root/scripts/stitch-ores.sh" "$tmp/self.ores" "$tmp/self.ores" >/dev/null 2>&1; then
  echo "input/output self-overwrite was accepted" >&2
  exit 1
fi
grep -q '^define module first as$' "$tmp/self.ores"

# Dot components do not create a different source/output identity.
if sh "$root/scripts/stitch-ores.sh" "$tmp/./self.ores" "$tmp/self.ores" >/dev/null 2>&1; then
  echo "dot-path input/output identity alias accepted" >&2
  exit 1
fi
grep -q '^define module first as$' "$tmp/self.ores"

# Symlinked parent directories cannot bypass the canonical source/output fence.
mkdir -p "$tmp/real-parent"
printf 'define module original as\nend\n' > "$tmp/real-parent/src.ores"
ln -s "$tmp/real-parent" "$tmp/parent-alias"
if sh "$root/scripts/stitch-ores.sh" "$tmp/parent-alias/src.ores" "$tmp/real-parent/src.ores" >/dev/null 2>&1; then
  echo "symlinked parent input/output alias accepted" >&2
  exit 1
fi
grep -q '^define module original as$' "$tmp/real-parent/src.ores"

dd if=/dev/zero of="$tmp/too-large.ores" bs=1048577 count=1 2>/dev/null
if "$root/scripts/stitch-ores.sh" "$tmp/rejected-large.ores" "$tmp/too-large.ores" >/dev/null 2>&1; then
  echo "oversized source was accepted" >&2
  exit 1
fi


# Untrusted invocations must fail without changing a previously published file.
printf 'known-good publication\n' > "$tmp/prior.ores"
if sh "$root/scripts/stitch-ores.sh" "$tmp/prior.ores" "$tmp/absent.ores" >/dev/null 2>&1; then
  echo "nonexistent source was accepted" >&2
  exit 1
fi
grep -qx 'known-good publication' "$tmp/prior.ores"

if sh "$root/scripts/stitch-ores.sh" "$tmp/missing-dir/output.ores" "$tmp/first.ores" >/dev/null 2>&1; then
  echo "nonexistent publication directory was accepted" >&2
  exit 1
fi
test ! -e "$tmp/missing-dir/output.ores"

# The option-like destination is passed literally, not as an output pathname.
if (cd "$tmp" && sh "$root/scripts/stitch-ores.sh" "-unsafe.ores" "first.ores") >/dev/null 2>&1; then
  echo "option-like output path was accepted" >&2
  exit 1
fi
test ! -e "$tmp/-unsafe.ores"

if sh "$root/scripts/stitch-ores.sh" "$tmp/prior.ores" "$tmp" >/dev/null 2>&1; then
  echo "directory source was accepted" >&2
  exit 1
fi
grep -qx 'known-good publication' "$tmp/prior.ores"

echo "stitcher self-test passed"
