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

# Quoted source and destination paths containing spaces and shell glob tokens
# are literal files, not wildcard expansions or split positional arguments.
mkdir -p "$tmp/path [literal] with spaces"
printf 'literal-path-source\n' > "$tmp/path [literal] with spaces/input [a].ores"
sh "$root/scripts/stitch-ores.sh" \
  "$tmp/path [literal] with spaces/output [b].ores" \
  "$tmp/path [literal] with spaces/input [a].ores"
printf 'literal-path-source\n\n' > "$tmp/expected-literal.ores"
if ! cmp -s "$tmp/expected-literal.ores" \
    "$tmp/path [literal] with spaces/output [b].ores"; then
  echo "quoted literal paths were split or expanded" >&2
  exit 1
fi

# Atomic publication must not inherit unsafe permissions from an old target.
# This also verifies a positive update replaces the previous file contents.
printf 'old-publication\n' > "$tmp/permissions.ores"
chmod 666 "$tmp/permissions.ores"
printf 'new-private-publication\n' > "$tmp/permissions-source.ores"
sh "$root/scripts/stitch-ores.sh" "$tmp/permissions.ores" "$tmp/permissions-source.ores"
printf 'new-private-publication\n\n' > "$tmp/permissions-expected.ores"
if ! cmp -s "$tmp/permissions-expected.ores" "$tmp/permissions.ores"; then
  echo "published source content was not atomically replaced" >&2
  exit 1
fi
if [ "$(find "$tmp/permissions.ores" -perm 0600 -print)" != "$tmp/permissions.ores" ]; then
  echo "published source had unsafe permissions" >&2
  exit 1
fi


# A later symlink input must reject the entire transaction, even after the
# first regular input was read. Existing publication and temp cleanup survive.
printf 'previously-verified-output\n' > "$tmp/late-symlink-output.ores"
ln -s "$tmp/second.ores" "$tmp/late-symlink-input.ores"
if sh "$root/scripts/stitch-ores.sh" "$tmp/late-symlink-output.ores" \
    "$tmp/first.ores" "$tmp/late-symlink-input.ores" >/dev/null 2>&1; then
  echo "later symlinked input was accepted" >&2
  exit 1
fi
grep -qx 'previously-verified-output' "$tmp/late-symlink-output.ores"
if [ -n "$(find "$tmp" -maxdepth 1 -name '.ores-stitch.*' -print)" ]; then
  echo "failed symlink transaction left a temporary output" >&2
  exit 1
fi

# The inclusive one-MiB per-file admission boundary remains valid and
# contributes one extra newline to the published byte stream.
sh "$root/scripts/stitch-ores.sh" "$tmp/exact-one-file.ores" "$tmp/one-mib.ores"
cp "$tmp/one-mib.ores" "$tmp/exact-one-file-expected.ores"
printf '\n' >> "$tmp/exact-one-file-expected.ores"
if ! cmp -s "$tmp/exact-one-file-expected.ores" "$tmp/exact-one-file.ores"; then
  echo "exact 1 MiB per-file source boundary was changed or rejected" >&2
  exit 1
fi

# Atomic replacement of a multiply-linked output must not modify the
# separately linked original publication or inherit its inode permissions.
printf 'previously-linked-content\n' > "$tmp/hardlink-output.ores"
ln "$tmp/hardlink-output.ores" "$tmp/hardlink-retained.ores"
printf 'fresh-published-content\n' > "$tmp/hardlink-input.ores"
sh "$root/scripts/stitch-ores.sh" "$tmp/hardlink-output.ores" "$tmp/hardlink-input.ores"
printf 'fresh-published-content\n\n' > "$tmp/hardlink-expected.ores"
if ! cmp -s "$tmp/hardlink-expected.ores" "$tmp/hardlink-output.ores"; then
  echo "hardlinked destination publication bytes were corrupted" >&2
  exit 1
fi
if [ "$(cat "$tmp/hardlink-retained.ores")" != 'previously-linked-content' ]; then
  echo "hardlinked previous publication was modified" >&2
  exit 1
fi
if [ "$(find "$tmp/hardlink-output.ores" -perm 0600 -print)" != "$tmp/hardlink-output.ores" ]; then
  echo "published replacement did not retain private permissions" >&2
  exit 1
fi

# When the intended output is a hardlink to a source, atomic rename must
# detach the output inode rather than mutate original source bytes in-place.
printf 'original-hardlink-source' > "$tmp/wave501-hardlink-source.ores"
ln "$tmp/wave501-hardlink-source.ores" "$tmp/wave501-hardlink-output.ores"
sh "$root/scripts/stitch-ores.sh" "$tmp/wave501-hardlink-output.ores" "$tmp/wave501-hardlink-source.ores"
printf 'original-hardlink-source\n' > "$tmp/wave501-hardlink-expected.ores"
if ! cmp -s "$tmp/wave501-hardlink-output.ores" "$tmp/wave501-hardlink-expected.ores"; then
  echo "hardlink output did not contain exactly the stitched source" >&2
  exit 1
fi
if [ "$(cat "$tmp/wave501-hardlink-source.ores")" != 'original-hardlink-source' ]; then
  echo "hardlinked source was modified by publication" >&2
  exit 1
fi

# Named pipes must be refused as nonregular sources before any attempt to
# read their contents (which would block without a writer). The failed write
# must preserve an already published file and clean temporary artifacts.
mkfifo "$tmp/wave610-named-pipe.ores"
printf 'preexisting-pipe-publication\n' > "$tmp/wave610-pipe-output.ores"
pipe_status=0
timeout 5 sh "$root/scripts/stitch-ores.sh" \
  "$tmp/wave610-pipe-output.ores" "$tmp/wave610-named-pipe.ores" \
  >/dev/null 2>&1 || pipe_status=$?
if [ "$pipe_status" -ne 65 ]; then
  echo "nonregular named-pipe source did not reject promptly (status=$pipe_status)" >&2
  exit 1
fi
grep -qx 'preexisting-pipe-publication' "$tmp/wave610-pipe-output.ores"
if [ -n "$(find "$tmp" -maxdepth 1 -name '.ores-stitch.*' -print)" ]; then
  echo "named-pipe refusal left behind a temporary publication" >&2
  exit 1
fi


# Multibyte UTF-8, CRLF and literal HTML metacharacters must be copied exactly
# without newline normalization, interpolation or shell expansion.
printf 'αβ\r\n"<&\n' > "$tmp/wave2032a-first.ores"
printf '🔥\r\n' > "$tmp/wave2032a-second.ores"
sh "$root/scripts/stitch-ores.sh" "$tmp/wave2032a-unicode-output.ores" \
  "$tmp/wave2032a-first.ores" "$tmp/wave2032a-second.ores"
printf 'αβ\r\n"<&\n\n🔥\r\n\n' > "$tmp/wave2032a-expected.ores"
if ! cmp -s "$tmp/wave2032a-expected.ores" "$tmp/wave2032a-unicode-output.ores"; then
  echo "UTF-8 or CRLF source bytes were changed during stitching" >&2
  exit 1
fi

# Two concurrent publishers may race to the same output name, but readers
# must get exactly one fully assembled publication. Atomic rename also leaves
# both immutable source files and private output permissions intact.
printf 'alpha-race-source' > "$tmp/wave2032a-alpha.ores"
printf 'beta-race-source' > "$tmp/wave2032a-beta.ores"
printf 'alpha-race-source\n' > "$tmp/wave2032a-alpha-expected.ores"
printf 'beta-race-source\n' > "$tmp/wave2032a-beta-expected.ores"
for race in 1 2 3 4 5 6 7 8; do
  sh "$root/scripts/stitch-ores.sh" "$tmp/wave2032a-race-output.ores" \
    "$tmp/wave2032a-alpha.ores" &
  alpha_pid=$!
  sh "$root/scripts/stitch-ores.sh" "$tmp/wave2032a-race-output.ores" \
    "$tmp/wave2032a-beta.ores" &
  beta_pid=$!
  wait "$alpha_pid"
  wait "$beta_pid"
  if ! cmp -s "$tmp/wave2032a-race-output.ores" "$tmp/wave2032a-alpha-expected.ores" &&
     ! cmp -s "$tmp/wave2032a-race-output.ores" "$tmp/wave2032a-beta-expected.ores"; then
    echo "concurrent publication exposed torn or interleaved source bytes" >&2
    exit 1
  fi
  if [ "$(find "$tmp/wave2032a-race-output.ores" -perm 0600 -print)" != "$tmp/wave2032a-race-output.ores" ]; then
    echo "concurrent stitch publication lost private permissions" >&2
    exit 1
  fi
done
grep -qx 'alpha-race-source' "$tmp/wave2032a-alpha.ores"
grep -qx 'beta-race-source' "$tmp/wave2032a-beta.ores"
if [ -n "$(find "$tmp" -maxdepth 1 -name '.ores-stitch.*' -print)" ]; then
  echo "concurrent publishers leaked temporary output files" >&2
  exit 1
fi

echo "stitcher self-test passed"
