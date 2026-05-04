# Clean Code Checklist

Applied by `bmad-dev-story` and verified during `bmad-code-review`.

## Naming
- Descriptive identifiers; no single-letter variables except loop counters
- Booleans named as predicates (`is_ready`, `has_errors`)
- Functions named for what they return / do, not how

## Functions
- Single responsibility; ≤ 50 lines
- ≤ 4 parameters; group related params into a struct/object
- Pure where possible; side-effects pushed to edges

## Errors
- Never swallow exceptions silently
- Validate at trust boundaries (HTTP handlers, queue consumers, CLI args)
- Return typed errors / Result types where the language supports them

## Comments
- Explain WHY, not WHAT
- Delete commented-out code
- Public API gets a docstring; internals usually don't

## Duplication
- DRY across the same layer
- Don't deduplicate across layers (controller ≠ service ≠ repo)

## Dependencies
- No new runtime dep without justification
- Lock files committed; versions pinned in production code paths
