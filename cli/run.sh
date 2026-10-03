#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
compiler="${ORESLANG_COMPILER:-oreslang-compiler}"
exec "$compiler" --platform=server main.ores
