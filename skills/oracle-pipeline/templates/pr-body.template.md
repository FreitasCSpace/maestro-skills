## Summary

Implements Oracle project `__SLUG__`.

Closes #__ANCHOR__

## Stories implemented
__STORIES_LIST__

## Test plan
- [__LINT_MARK__] Lint clean across all touched files (auto-run by oracle-pipeline)
- [__TESTS_MARK__] All test suites pass (auto-run after each story)
- [__COVERAGE_MARK__] Coverage ≥ __COV_THRESHOLD__% on changed files
- [__ACCEPTANCE_MARK__] All story acceptance criteria implemented and self-verified
- [__REVIEW_MARK__] bmad-code-review approved every story
- [ ] Manual smoke test of golden-path user flow — _cannot be automated; run the app and exercise the user journey before approving_
- [ ] Manual SSE / streaming behavior verification (if applicable) — _cannot be automated; observe a live stream against the deployed branch_

## Implementation notes
__IMPLEMENTATION_NOTES__

## Tracking

- Anchor issue: __ANCHOR_URL__
- Failed stories: __FAILED_COUNT__
- Pipeline run: __PIPELINE_LINK__

---
**Do not merge until BOTH PRs in this group (develop + master) are approved.**
