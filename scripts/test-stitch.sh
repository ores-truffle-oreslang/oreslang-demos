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

# The total 4 MiB bound must fail atomically even when each individual
# input is within the independent 1 MiB per-source admission limit.
dd if=/dev/zero of="$tmp/one-mib.ores" bs=1048576 count=1 2>/dev/null
for n in 1 2 3 4 5; do
  cp "$tmp/one-mib.ores" "$tmp/chunk-$n.ores"
done
printf 'retain previously published source\n' > "$tmp/atomic-total.ores"
if sh "$root/scripts/stitch-ores.sh" "$tmp/atomic-total.ores" \
  "$tmp/chunk-1.ores" "$tmp/chunk-2.ores" "$tmp/chunk-3.ores" \
  "$tmp/chunk-4.ores" "$tmp/chunk-5.ores" >/dev/null 2>&1; then
  echo "aggregate source byte limit was accepted" >&2
  exit 1
fi
grep -qx 'retain previously published source' "$tmp/atomic-total.ores"

# The exact inclusive 4 MiB aggregate input boundary remains admissible.
# Four inserted newlines expand the published output without charging source bytes.
sh "$root/scripts/stitch-ores.sh" "$tmp/exact-total.ores" \
  "$tmp/chunk-1.ores" "$tmp/chunk-2.ores" \
  "$tmp/chunk-3.ores" "$tmp/chunk-4.ores"
actual_size="$(wc -c < "$tmp/exact-total.ores" | tr -d '[:space:]')"
if [ "$actual_size" -ne 4194308 ]; then
  echo "exact 4 MiB source input boundary was corrupted: $actual_size" >&2
  exit 1
fi


# A later invalid source must not partially publish the bytes of an earlier
# source or leave a temporary artifact beside a previously valid output.
printf 'previously published bytes\n' > "$tmp/later-source-atomic.ores"
if sh "$root/scripts/stitch-ores.sh" "$tmp/later-source-atomic.ores" \
    "$tmp/first.ores" "$tmp/absent-after-first.ores" >/dev/null 2>&1; then
  echo "invalid later source was accepted" >&2
  exit 1
fi
grep -qx 'previously published bytes' "$tmp/later-source-atomic.ores"
if [ -n "$(find "$tmp" -maxdepth 1 -name '.ores-stitch.*' -print)" ]; then
  echo "stitcher left a temporary output after later-source rejection" >&2
  exit 1
fi

# Quoted source and destination paths must remain one argument each; preserve
# input order and insert exactly one newline after every original input.
mkdir -p "$tmp/quoted source paths"
printf 'alpha-raw' > "$tmp/quoted source paths/first input.ores"
printf 'beta-raw\n' > "$tmp/quoted source paths/second input.ores"
sh "$root/scripts/stitch-ores.sh" "$tmp/quoted output name.ores" \
  "$tmp/quoted source paths/first input.ores" \
  "$tmp/quoted source paths/second input.ores"
printf 'alpha-raw\nbeta-raw\n\n' > "$tmp/quoted expected.ores"
if ! cmp -s "$tmp/quoted expected.ores" "$tmp/quoted output name.ores"; then
  echo "quoted source paths or input order were not preserved" >&2
  exit 1
fi

# A repeated input is a separate source contribution; zero bytes insert one
# newline separator without changing the order of requested source paths.
printf 'A' > "$tmp/repeat-source.ores"
: > "$tmp/empty-source.ores"
sh "$root/scripts/stitch-ores.sh" "$tmp/repeat-output.ores" \
  "$tmp/repeat-source.ores" "$tmp/empty-source.ores" "$tmp/repeat-source.ores"
printf 'A\n\nA\n' > "$tmp/repeat-expected.ores"
if ! cmp -s "$tmp/repeat-expected.ores" "$tmp/repeat-output.ores"; then
  echo "repeated or empty source input changed ordered stitch bytes" >&2
  exit 1
fi

echo "stitcher self-test passed"
