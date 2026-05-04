#!/usr/bin/env bash
# Lint-check — auto-detect repo stack, run linter, fail on errors.
# Usage: lint-check.sh <REPO_ROOT>
# Exits 0 if clean (or no linter configured), 1 if violations found.
set -euo pipefail

REPO="${1:-$PWD}"
cd "$REPO"

# JS / TS — npm lint or eslint
if [ -f package.json ]; then
  if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
    echo "Running npm run lint in $REPO"
    npm run lint --silent || exit 1
    exit 0
  fi
  if [ -f node_modules/.bin/eslint ] || command -v eslint >/dev/null 2>&1; then
    echo "Running eslint in $REPO"
    npx --no-install eslint . --max-warnings=0 || exit 1
    exit 0
  fi
fi

# Python — ruff > flake8
if command -v ruff >/dev/null 2>&1 && { [ -f pyproject.toml ] || [ -f ruff.toml ] || [ -f .ruff.toml ]; }; then
  echo "Running ruff check in $REPO"
  ruff check . || exit 1
  exit 0
fi
if command -v flake8 >/dev/null 2>&1 && [ -f setup.cfg -o -f .flake8 ]; then
  echo "Running flake8 in $REPO"
  flake8 . || exit 1
  exit 0
fi

# Go
if [ -f go.mod ]; then
  echo "Running go vet in $REPO"
  go vet ./... || exit 1
  exit 0
fi

echo "No linter configured for $REPO — skipping"
exit 0
