#!/usr/bin/env bash
# validate-issue-spec.sh — gate the pipeline on issue-as-spec quality.
#
# An issue must be sufficient for independent re-implementation. The Oracle
# pipeline refuses to start unless the anchor issue body satisfies all of:
#
#   1. Body length >= MIN_BODY_LEN (default 200) chars (not just a title)
#   2. Acceptance-criteria markers present:
#        - Given/When/Then  (BDD)
#        - "should ", "must ", "shall "  (requirements language)
#        - "- [ ]" / "- [x]"  (AC checklist)
#   3. At least one section heading (## ...) — i.e. structured doc, not prose
#
# Usage: validate-issue-spec.sh <ISSUE_NUM> [<REPO>]
# Env:   TARGET_ORG (default carespace-ai), MIN_BODY_LEN (default 200)
#
# Exit 0 = OK; exit 1 = insufficient (caller should comment + label + abort).
set -euo pipefail

ISSUE="${1:?usage: validate-issue-spec.sh <ISSUE_NUM> [<REPO>]}"
REPO="${2:-${TARGET_ORG:-carespace-ai}/the-oracle-backlog}"
MIN_BODY_LEN="${MIN_BODY_LEN:-200}"

BODY=$(gh issue view "$ISSUE" --repo "$REPO" --json body | jq -r '.body // ""')
LEN=${#BODY}

FAIL=()

if [ "$LEN" -lt "$MIN_BODY_LEN" ]; then
  FAIL+=("body too short ($LEN chars; need ≥ $MIN_BODY_LEN — issue must describe business rules, not just a title)")
fi

if ! echo "$BODY" | grep -qiE '(\bgiven\b|\bwhen\b|\bthen\b|\bshould\b|\bmust\b|\bshall\b|^- \[)'; then
  FAIL+=("no acceptance-criteria markers (need Given/When/Then, should/must/shall, or - [ ] checklist)")
fi

if ! echo "$BODY" | grep -qE '^## '; then
  FAIL+=("no section headings (## ...) — issue lacks structure")
fi

if [ ${#FAIL[@]} -gt 0 ]; then
  echo "ISSUE_SPEC_INVALID for #$ISSUE in $REPO:"
  for f in "${FAIL[@]}"; do echo "  - $f"; done
  echo ""
  echo "The issue must be the spec. Edit it to include:"
  echo "  - Business rules in functional language (not implementation details)"
  echo "  - Verifiable acceptance criteria (Given X, when Y, then Z)"
  echo "  - Enough detail that an engineer could re-implement from the issue alone"
  exit 1
fi

echo "OK: issue #$ISSUE has sufficient business spec ($LEN chars, ACs present, structured)"
exit 0
