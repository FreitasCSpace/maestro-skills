# Multi-repo PR orchestration: tool evaluation

**Decision:** Use **multi-gitter** for the lifecycle phase (group merge / close / status). Keep the hand-rolled loop in the `oracle-pipeline` skill for the implementation phase. Reject **turbolift**.

This doc records the reasoning so future-you doesn't relitigate it.

## The two phases

The Oracle sandbox flow has two distinct multi-repo moments:

1. **Implementation** — `oracle-pipeline` skill produces *different* diffs in N repos (one per affected repo) and opens N PRs as a group. Each repo's diff is the cumulative result of iterating a project's stories. Per-repo state is built up locally before any push.
2. **Lifecycle** — after PRs are opened, the meta-issue-close handler must (a) read group status across N repos, (b) merge all PRs in the group on approval (FR17), (c) close all PRs in the group on rejection (FR18). All three are *the same operation* applied across N repos.

These two phases have inverse fits with the OSS tools.

## Tool fit

| Concern | multi-gitter | turbolift | Hand-rolled |
|---|---|---|---|
| Apply *same* change to N repos via script | ✅ primary use case (`run`) | ✅ primary use case (`foreach`) | ✗ overkill |
| Apply *different* per-repo diffs | ⚠ awkward — script must branch on `$REPOSITORY` | ⚠ awkward — `foreach` runs same command everywhere | ✅ natural |
| Batch PR open with labels/reviewers | ✅ `run` | ✅ `create-prs` | ✅ `gh pr create` loop |
| **Batch group merge (FR17)** | ✅ `merge --branch <ref>` | ⚠ `update-prs` (less first-class) | needs hand-rolled loop |
| **Batch group close (FR18)** | ✅ `close --branch <ref>` | ⚠ `update-prs --close` | needs hand-rolled loop |
| Batch group status (FR15 readiness check) | ✅ `status --branch <ref>` | ✅ `pr-status` | needs hand-rolled loop |
| Auth | per-platform tokens; supports GH/GitLab/Gitea/BitBucket/Gerrit | requires `gh auth login` (GitHub-only) | uses `$GITHUB_TOKEN` directly |
| License | MIT | Apache-2.0 | n/a |
| Distribution | Single Go binary | Single Go binary | n/a |

## Decisions

### 1. Implementation phase — keep the hand-rolled loop

The `oracle-pipeline` skill produces per-repo workspaces with already-committed branches. Wrapping that into a multi-gitter "run a script in each repo" harness would be net-negative: the script would have to read pre-built state from disk and reproduce the push+PR step that's already four lines of `gh` CLI. No win.

### 2. Lifecycle phase — adopt multi-gitter

`multi-gitter merge --branch feat/oracle-project-<slug>` and `multi-gitter close --branch feat/oracle-project-<slug>` collapse FR17 and FR18 to one command each, with built-in per-repo error reporting. This is exactly the kind of operation the tool is built for: same action, N repos, identified by a shared branch name.

The lifecycle wrapper lives in the new `skills/oracle-pipeline-lifecycle/` skill in this repo. The corresponding GitHub Actions workflows in `carespace-ai/infra` (when that repo exists) invoke this skill on the meta-issue close webhook.

### 3. Reject turbolift

- GitHub-only (multi-gitter supports five platforms — useful if we ever mirror to GitLab for compliance reasons)
- `merge` and `close` are not first-class subcommands; they're bolted onto `update-prs`
- Strength is "interactive, use any editor" — irrelevant to an autonomous agent

## Operational notes

- multi-gitter expects the repo list via `--org`, `--repo`, or `--repo-search`. For Oracle group ops, we'll resolve the list at runtime from the project meta-issue's `feature-intent.json.involved_repos[].full_name` and pass each via repeated `--repo` flags.
- multi-gitter authentication uses `GITHUB_TOKEN`. The lifecycle skill receives the same Maestro AI GitHub App installation token used by `oracle-pipeline`.
- `--concurrent` defaults to 1; bump to N (number of involved repos) to parallelize the lifecycle op.
- For FR21 (weekly ruleset bypass canary): multi-gitter is overkill — keep that as a one-shot `gh api` call against a single canary repo.

## Future: open-source promotion

If multi-gitter ever lacks something we need (e.g., richer per-repo result aggregation for the meta-issue summary comment), upstream a PR rather than fork. License is MIT; the project is actively maintained.

## References

- multi-gitter: https://github.com/lindell/multi-gitter
- turbolift: https://github.com/Skyscanner/turbolift
- Sandbox PRD FR9, FR15, FR17, FR18: `carespace-ai/the-oracle-backlog/sandbox-arquiteture/prd.md`
- Sandbox architecture §5.2–5.6: `carespace-ai/the-oracle-backlog/sandbox-arquiteture/architecture.md`
