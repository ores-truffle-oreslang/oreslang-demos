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
output_dir="$(dirname "$output")"
if [ ! -d "$output_dir" ]; then
  echo "stitch output directory does not exist: $output_dir" >&2
  exit 65
fi

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
