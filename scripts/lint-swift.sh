#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PATHS=(
  Modules/Sources
  Modules/Tests
  nexus
  nexusTests
  nexusUITests
)

if ! command -v swift-format >/dev/null 2>&1; then
  echo "error: swift-format not found (brew install swift-format)" >&2
  exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint not found (brew install swiftlint)" >&2
  exit 1
fi

echo "== swift-format lint =="
swift format lint --recursive "${PATHS[@]}"

echo "== swiftlint (force_try error only) =="
swiftlint lint --config .swiftlint.yml --quiet

echo "OK"