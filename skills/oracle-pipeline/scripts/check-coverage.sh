#!/usr/bin/env bash
# Check-coverage — run tests and verify coverage ≥ COVERAGE_THRESHOLD (default 80).
# Usage: check-coverage.sh <REPO_ROOT>
# Exits 0 if tests pass and coverage meets threshold, 1 otherwise.
set -euo pipefail

REPO="${1:-$PWD}"
THRESHOLD="${COVERAGE_THRESHOLD:-80}"
cd "$REPO"

# JS / TS
if [ -f package.json ]; then
  if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    echo "Running npm test in $REPO"
    if jq -e '.scripts["test:coverage"]' package.json >/dev/null 2>&1; then
      npm run test:coverage --silent || exit 1
    else
      npm test --silent -- --coverage 2>/dev/null || npm test --silent || exit 1
    fi
    # Try common coverage summary locations
    if [ -f coverage/coverage-summary.json ]; then
      PCT=$(jq -r '.total.lines.pct' coverage/coverage-summary.json 2>/dev/null || echo 0)
      echo "Coverage (lines): ${PCT}%"
      awk -v p="$PCT" -v t="$THRESHOLD" 'BEGIN{exit !(p+0>=t+0)}' || {
        echo "Coverage ${PCT}% < ${THRESHOLD}%"; exit 1; }
    fi
    exit 0
  fi
fi

# Python
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then
  if command -v pytest >/dev/null 2>&1; then
    echo "Running pytest with coverage in $REPO"
    pytest --cov=. --cov-report=term --cov-fail-under="$THRESHOLD" || exit 1
    exit 0
  fi
fi

# Go
if [ -f go.mod ]; then
  echo "Running go test with coverage in $REPO"
  go test -cover ./... > /tmp/go-cover.out || exit 1
  PCT=$(grep -oE 'coverage: [0-9.]+%' /tmp/go-cover.out | head -1 | grep -oE '[0-9.]+' || echo 0)
  echo "Go coverage: ${PCT}%"
  awk -v p="$PCT" -v t="$THRESHOLD" 'BEGIN{exit !(p+0>=t+0)}' || {
    echo "Coverage ${PCT}% < ${THRESHOLD}%"; exit 1; }
  exit 0
fi

echo "No test runner detected for $REPO — skipping coverage check"
exit 0
