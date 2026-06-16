#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

chmod +x .githooks/pre-commit .githooks/lint-staged-swift.sh 2>/dev/null || true

git config core.hooksPath .githooks

echo "Installed git hooks: core.hooksPath=.githooks"
echo "  pre-commit: Bob notes cleanup (if .bob/) + staged Swift lint"
echo "  Bypass lint once: SKIP_LINT=1 git commit"
echo "  Full tree lint:   ./scripts/lint-swift.sh"