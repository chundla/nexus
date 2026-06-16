#!/usr/bin/env bash
# Lint staged Swift files only (swift-format + SwiftLint force_try). Repo root as cwd.

set -euo pipefail

if [[ "${SKIP_LINT:-}" == "1" ]]; then
    echo "SKIP_LINT=1 — skipping Swift lint"
    exit 0
fi

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

STAGED_SWIFT=()
while IFS= read -r f; do
    [ -n "$f" ] && STAGED_SWIFT+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACM | grep -E '\.swift$' || true)

if [ ${#STAGED_SWIFT[@]} -eq 0 ]; then
    exit 0
fi

if ! command -v swift-format >/dev/null 2>&1; then
    echo "error: swift-format not found (brew install swift-format)" >&2
    exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: swiftlint not found (brew install swiftlint)" >&2
    exit 1
fi

echo "pre-commit: swift-format lint (${#STAGED_SWIFT[@]} staged file(s))"
swift format lint --strict "${STAGED_SWIFT[@]}"

echo "pre-commit: swiftlint (${#STAGED_SWIFT[@]} staged file(s))"
swiftlint lint --strict --config .swiftlint.yml --quiet -- "${STAGED_SWIFT[@]}"