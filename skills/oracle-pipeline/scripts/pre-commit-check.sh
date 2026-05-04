#!/usr/bin/env bash
# Pre-commit — final lint + coverage check before staging.
# Usage: pre-commit-check.sh <REPO_ROOT>
set -euo pipefail
REPO="${1:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/lint-check.sh"     "$REPO" || { echo "Pre-commit: lint failed";     exit 1; }
"$SCRIPT_DIR/check-coverage.sh" "$REPO" || { echo "Pre-commit: coverage failed"; exit 1; }
echo "Pre-commit: OK"
