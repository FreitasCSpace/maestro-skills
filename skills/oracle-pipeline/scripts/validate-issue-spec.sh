#!/usr/bin/env bash
# validate-issue-spec.sh — gate the pipeline on spec sufficiency.
#
# Two issue shapes are accepted:
#
#   A. Self-contained issue: body itself describes business rules + ACs.
#      Validates: length ≥ MIN_BODY_LEN, AC markers, at least one ## heading.
#
#   B. BMAD-Oracle anchor issue: body is a backlog TOC pointing at a context
#      branch. The actual spec (epics, stories, ACs) lives in
#      bmad-context/<slug>/stories-output.md on bmad/<slug>-context.
#      Validates that the linked context exists and contains AC markers.
#
# An issue passes iff EITHER shape validates. This matches the spirit of
# rule 2: the spec must be human-readable and re-implementable from outside
# Oracle. A BMAD context branch is human-readable on GitHub.
#
# Usage: validate-issue-spec.sh <ISSUE_NUM> [<REPO>]
# Env:   TARGET_ORG (default carespace-ai), MIN_BODY_LEN (default 200)
#
# Exit 0 = OK; exit 1 = insufficient.
set -euo pipefail

ISSUE="${1:?usage: validate-issue-spec.sh <ISSUE_NUM> [<REPO>]}"
REPO="${2:-${TARGET_ORG:-carespace-ai}/the-oracle-backlog}"
MIN_BODY_LEN="${MIN_BODY_LEN:-200}"

BODY=$(gh issue view "$ISSUE" --repo "$REPO" --json body | jq -r '.body // ""')
LEN=${#BODY}

# ── Shape B: BMAD-Oracle anchor (validate the linked context, not the body) ──
# Detect by the canonical reference pattern in BMAD-generated anchor bodies.
BMAD_SLUG=$(echo "$BODY" | grep -oE 'bmad-context/[a-z0-9][a-z0-9-]+' | head -1 | cut -d/ -f2)

if [ -n "$BMAD_SLUG" ]; then
  # Try main first, fall back to the conventional context branch
  STORIES=""
  for REF in "main" "bmad/${BMAD_SLUG}-context"; do
    STORIES=$(gh api "repos/$REPO/contents/bmad-context/$BMAD_SLUG/stories-output.md?ref=$REF" \
      --jq '.content // empty' 2>/dev/null | base64 -d 2>/dev/null || true)
    [ -n "$STORIES" ] && break
  done

  if [ -z "$STORIES" ]; then
    echo "ISSUE_SPEC_INVALID for #$ISSUE in $REPO:"
    echo "  - body references bmad-context/$BMAD_SLUG/ but stories-output.md not found on main or bmad/${BMAD_SLUG}-context"
    exit 1
  fi

  STORIES_LEN=${#STORIES}
  HAS_AC=false
  if echo "$STORIES" | grep -qiE '(\bgiven\b|\bwhen\b|\bthen\b|\bshould\b|\bmust\b|\bshall\b|acceptance.criteria|^- \[)'; then
    HAS_AC=true
  fi

  if [ "$STORIES_LEN" -lt 500 ] || [ "$HAS_AC" != "true" ]; then
    echo "ISSUE_SPEC_INVALID for #$ISSUE in $REPO:"
    [ "$STORIES_LEN" -lt 500 ] && echo "  - bmad-context/$BMAD_SLUG/stories-output.md too short ($STORIES_LEN chars)"
    [ "$HAS_AC" != "true" ]   && echo "  - bmad-context/$BMAD_SLUG/stories-output.md has no AC markers"
    exit 1
  fi

  echo "OK: BMAD-Oracle anchor #$ISSUE — spec lives in bmad-context/$BMAD_SLUG/ ($STORIES_LEN chars, ACs present)"
  exit 0
fi

# ── Shape A: self-contained issue ───────────────────────────────────────────
FAIL=()
[ "$LEN" -lt "$MIN_BODY_LEN" ] && \
  FAIL+=("body too short ($LEN chars; need ≥ $MIN_BODY_LEN)")
echo "$BODY" | grep -qiE '(\bgiven\b|\bwhen\b|\bthen\b|\bshould\b|\bmust\b|\bshall\b|^- \[)' || \
  FAIL+=("no acceptance-criteria markers (Given/When/Then, should/must/shall, or - [ ] checklist)")
echo "$BODY" | grep -qE '^## ' || \
  FAIL+=("no section headings (## ...) — issue lacks structure")

if [ ${#FAIL[@]} -gt 0 ]; then
  echo "ISSUE_SPEC_INVALID for #$ISSUE in $REPO:"
  for f in "${FAIL[@]}"; do echo "  - $f"; done
  echo ""
  echo "The issue must be the spec. Either:"
  echo "  - Embed business rules + ACs directly in the issue body, OR"
  echo "  - Reference a bmad-context/<slug>/ folder that contains stories-output.md"
  exit 1
fi

echo "OK: self-contained issue #$ISSUE has sufficient spec ($LEN chars, ACs present, structured)"
exit 0
