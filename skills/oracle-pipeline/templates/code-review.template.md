# Story Code Review — {{STORY_KEY}}

**Story:** {{STORY_TITLE}}
**Affected modules:** {{STORY_AFFECTED_MODULES}}
**Reviewer:** Oracle Pipeline (self-review)

## Acceptance criteria
{{STORY_AC}}

## Checklist

### Correctness
- [ ] All acceptance criteria implemented
- [ ] Edge cases handled (empty input, null, large input, concurrency)
- [ ] Error paths return meaningful errors, not silent failures

### Tests
- [ ] Unit tests cover new logic
- [ ] Integration tests cover cross-module flows
- [ ] Coverage on new/changed lines ≥ 80%
- [ ] All tests pass locally

### Code quality
- [ ] Follows existing repo patterns and naming conventions
- [ ] No dead code, no commented-out blocks
- [ ] Functions ≤ 50 lines, single responsibility
- [ ] No premature abstractions

### Security
- [ ] User input validated at trust boundaries
- [ ] No secrets committed
- [ ] No SQL injection / XSS / path-traversal risks introduced

### Scope
- [ ] Only files in `affected_modules` were touched
- [ ] No unrelated refactors bundled in

## Findings
- HIGH: {{count}}
- MEDIUM: {{count}}
- LOW: {{count}}

## Verdict
- [ ] approved
- [ ] changes_requested
