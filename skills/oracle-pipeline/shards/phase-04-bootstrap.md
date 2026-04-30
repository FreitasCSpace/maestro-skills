# Phase 04 — Bootstrap Tests (per repo, once at project start)

Check each cloned repo for an existing test suite. If none, bootstrap one.
This runs ONCE before the story loop — not per story.

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"

  TEST_FILES=$(find . -type f \
    \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" -o -name "test_*" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -1)

  if [ -z "$TEST_FILES" ]; then
    # Bootstrap per stack:
    # Node/TS: add jest.config.js + src/__tests__/smoke.test.ts
    # Python:  add pytest.ini + tests/test_smoke.py
    # Go:      add pkg/smoke_test.go
    # Dart:    add test/smoke_test.dart
    # (Use same template as pipeline/SKILL.md Phase 3.5)
    git add -A
    git commit -m "[Bootstrap] add test scaffold for project run"
    echo "Bootstrapped test suite in $REPO"
  else
    echo "Tests already exist in $REPO — skipping bootstrap"
  fi

  cd /tmp/oracle-work
done
```

Append `## Test Bootstrap` section to PIPELINE.md listing which repos were
bootstrapped. Bootstrap commits are part of the cumulative diff but exempt
from per-story scope guardrail.

---

**Next:** Read `shards/phase-05-story-loop.md`
