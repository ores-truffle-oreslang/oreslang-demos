#!/usr/bin/env sh
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: stitch-ores.sh OUTPUT INPUT..." >&2
  exit 64
fi

output="$1"
shift
max_file_bytes=1048576
max_total_bytes=4194304
total=0

case "$output" in
  -*) echo "refusing option-like output path: $output" >&2; exit 65 ;;
esac
if [ -L "$output" ]; then
  echo "refusing symlinked stitch output: $output" >&2
  exit 65
fi
# Atomic rename must target a regular file name, not descend into an existing
# directory or replace a FIFO/device. Verify before staging any source bytes.
if [ -e "$output" ] && [ ! -f "$output" ]; then
  echo "refusing non-regular stitch output: $output" >&2
  exit 65
fi
output_dir="$(dirname "$output")"
if [ ! -d "$output_dir" ]; then
  echo "stitch output directory does not exist: $output_dir" >&2
  exit 65
fi
# Keep the output inode identity stable across syntactic ./ aliases and
# symlinked parent directories before any temporary output is published.
output_canonical_dir="$(cd "$output_dir" && pwd -P)" || exit 65
output_canonical="$output_canonical_dir/$(basename "$output")"

umask 077
tmp_output="$(mktemp "$output_dir/.ores-stitch.XXXXXX")" || exit 70
trap 'rm -f "$tmp_output"' 0 HUP INT TERM

for source in "$@"; do
  if [ "$source" = "$output" ]; then
    echo "refusing to overwrite an input source: $source" >&2
    exit 65
  fi
  if [ -L "$source" ] || [ ! -f "$source" ]; then
    echo "refusing non-regular or symlinked Oreslang source: $source" >&2
    exit 65
  fi
  source_canonical_dir="$(cd "$(dirname "$source")" && pwd -P)" || exit 65
  if [ "$source_canonical_dir/$(basename "$source")" = "$output_canonical" ]; then
    echo "refusing input/output alias by canonical path: $source" >&2
    exit 65
  fi
  size="$(wc -c < "$source" | tr -d '[:space:]')"
  case "$size" in
    ''|*[!0-9]*) echo "cannot determine source size: $source" >&2; exit 65 ;;
  esac
  if [ "$size" -gt "$max_file_bytes" ]; then
    echo "Oreslang source exceeds per-file demo limit: $source" >&2
    exit 65
  fi
  total=$((total + size))
  if [ "$total" -gt "$max_total_bytes" ]; then
    echo "stitched Oreslang source exceeds demo limit" >&2
    exit 65
  fi
  cat -- "$source" >> "$tmp_output"
  printf '\n' >> "$tmp_output"
done

mv "$tmp_output" "$output"
trap - 0 HUP INT TERM
