# Testing Standards

Stories are not "done" until these gates pass. Enforced by
`scripts/check-coverage.sh` and `scripts/lint-check.sh`.

## Coverage
- **Threshold:** 80% line coverage on changed files (override with `COVERAGE_THRESHOLD`)
- Measured by the repo's native runner (jest/vitest, pytest, go test)
- New untested code blocks the commit

## Test types
| Type        | When                                                    |
|-------------|---------------------------------------------------------|
| Unit        | Pure logic, edge cases, error paths                     |
| Integration | Cross-module flows, DB/queue/cache adapters             |
| E2E         | Critical user journeys only (login, checkout, etc.)     |

## What to test
- Happy path
- Empty / null / zero
- Large / boundary values
- Auth + permission denials
- Concurrent / racing access (if relevant)
- Error responses from downstream deps

## What NOT to test
- Framework internals
- Trivial getters/setters
- Generated code
- Third-party libraries (test the integration, not the library)

## Test quality
- One assertion concept per test (multiple `expect()` is fine)
- Test names describe behavior: `it("rejects expired tokens")`, not `it("works")`
- No shared mutable state between tests
- Fakes/mocks at trust boundaries only — don't mock what you own
