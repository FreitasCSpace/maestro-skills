---
name: oracle-pipeline-lifecycle
description: |
  Lifecycle operations for an Oracle backlog project's PR group — group
  status check (FR15 readiness gate), group merge on approval (FR17), and
  group close on rejection (FR18). Wraps multi-gitter for batch operations
  across every repo in the project's PR group, identified by the shared
  `feat/oracle-project-<slug>` branch name. Companion skill to
  `oracle-pipeline` (which opens the group); this skill closes the loop.
---

# Oracle Pipeline Lifecycle

You are the lifecycle handler for an Oracle backlog project. The
`oracle-pipeline` skill opens a group of PRs (one per affected repo, all
sharing the branch `feat/oracle-project-<slug>` and the label
`group:project-<slug>`). This skill handles what happens *after*:

- **status** — read group readiness for the meta-issue summary (FR15)
- **merge** — merge every PR in the group on approval (FR17)
- **close** — close every PR in the group on rejection (FR18)
- **prune** — after a 30-day grace period, delete the project branches in
  every affected repo (FR18 grace expiry)

All four operations use **multi-gitter** because they apply the same action
to N repos identified by a shared branch name. See `docs/multi-repo-tools.md`
in this repo for why.

---

## Inputs

Provided via `$CLAUDEHUB_INPUT_KWARGS` JSON:

```json
{
  "operation": "status|merge|close|prune",
  "project_slug": "asset-management-system-ams",
  "meta_issue_number": 500,
  "target_org": "carespace-ai",
  "involved_repos": ["carespace-admin", "carespace-ui", "carespace-api"]
}
```

`involved_repos` is the resolved list from the meta-issue's BMAD
`feature-intent.json.involved_repos[].full_name`. The Maestro orchestrator
resolves it before invoking this skill so we don't re-clone the backlog repo.

`$GITHUB_TOKEN` must be the Maestro AI GitHub App installation token with
PR write permission on every repo in `involved_repos`.

## Output

Structured JSON to stdout:

```json
{
  "operation": "merge",
  "project_slug": "...",
  "results": [
    {"repo": "carespace-admin", "outcome": "merged",  "sha": "abc123"},
    {"repo": "carespace-ui",    "outcome": "merged",  "sha": "def456"},
    {"repo": "carespace-api",   "outcome": "skipped", "reason": "checks failing"}
  ],
  "all_succeeded": false
}
```

---

## Step 0 — Setup

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status

# multi-gitter reads GITHUB_TOKEN from env automatically
which multi-gitter || {
  echo "Installing multi-gitter..."
  go install github.com/lindell/multi-gitter@latest
}

BRANCH="feat/oracle-project-$PROJECT_SLUG"
REPO_FLAGS=""
for r in "${INVOLVED_REPOS[@]}"; do
  REPO_FLAGS="$REPO_FLAGS --repo $TARGET_ORG/$r"
done
```

`--repo` flags are repeated rather than `--org` because we want exactly the
repos in this project's PR group, not every repo in the org.

---

## Operation: status (FR15)

Used by the orchestrator before posting the "Ready for review" comment on
the meta-issue, and after the deploy succeeds.

```bash
multi-gitter status \
  $REPO_FLAGS \
  --branch "$BRANCH" \
  --output json > /tmp/status.json

# Roll up the per-repo states for the meta-issue comment
jq '[.[] | {repo: .repository, state: .state, url: .url, merged: .merged}]' \
  /tmp/status.json
```

Aggregate states for the structured output:

| multi-gitter state | mapped outcome |
|---|---|
| `merged` | `merged` |
| `closed` (not merged) | `closed` |
| `open` + checks `success` | `ready` |
| `open` + checks `pending` | `checks_pending` |
| `open` + checks `failure` | `checks_failing` |
| no PR found | `missing` |

`all_succeeded` for the `status` operation is `true` iff every repo is
`ready` or `merged`.

---

## Operation: merge (FR17)

Triggered when the meta-issue closes with the `approved` label (or via a
`/approve` comment, per FR17).

```bash
multi-gitter merge \
  $REPO_FLAGS \
  --branch "$BRANCH" \
  --output json > /tmp/merge.json
```

multi-gitter `merge` defaults respect each repo's branch protection rules.
On `main` with required reviews, the merge will fail unless the PR has the
required approvals — that's the desired behavior; we don't want to bypass
human review at merge time.

After the multi-gitter run, comment on each PR (FR17 wording):

```bash
jq -r '.[] | select(.merged == true) | .url' /tmp/merge.json | while read url; do
  gh pr comment "$url" --body "Approved at project-meta issue #$META_ISSUE_NUMBER. Merged as part of group:project-$PROJECT_SLUG."
done
```

If any repo failed to merge (e.g., checks not green, missing approvals):

```bash
jq -r '.[] | select(.merged == false) | "\(.repository): \(.error // "unknown")"' /tmp/merge.json
```

Comment back on the meta-issue listing the unmerged repos so the human can
reconcile manually. Do NOT retry — group merge is human-supervised.

---

## Operation: close (FR18)

Triggered when the meta-issue closes without approval (or with `rejected`).

```bash
multi-gitter close \
  $REPO_FLAGS \
  --branch "$BRANCH" \
  --message "Rejected at project-meta issue #$META_ISSUE_NUMBER" \
  --output json > /tmp/close.json
```

multi-gitter `close` posts the `--message` as a PR comment before closing,
which satisfies FR18's `Rejected at project-meta issue #<N>` requirement
naturally.

**Do NOT delete branches yet.** FR18 mandates a 30-day grace period for
forensic review. Branch deletion is the `prune` operation, scheduled via a
separate cron 30 days out.

---

## Operation: prune (FR18 grace expiry)

Triggered by a scheduled cron 30 days after the meta-issue closed without
approval. Deletes the `feat/oracle-project-<slug>` branch in every
involved repo.

```bash
for r in "${INVOLVED_REPOS[@]}"; do
  gh api -X DELETE "repos/$TARGET_ORG/$r/git/refs/heads/$BRANCH" \
    && echo "{\"repo\":\"$r\",\"outcome\":\"deleted\"}" \
    || echo "{\"repo\":\"$r\",\"outcome\":\"skipped\",\"reason\":\"branch missing or protected\"}"
done | jq -s '{operation: "prune", project_slug: env.PROJECT_SLUG, results: .}'
```

Branch deletion via raw `gh api` rather than multi-gitter because there is
no multi-gitter subcommand for arbitrary branch deletion (it operates on
PRs, not raw refs). Trivial enough to do directly.

---

## Audit Logging

Same FR24 contract as `oracle-pipeline`. Emit one structured stdout line
per repo per operation:

```json
{"project_slug":"...","meta_issue_number":500,"action":"group_merge",
 "actor":"maestro-orchestrator","timestamp":"...","outcome":"success",
 "repo":"carespace-admin","sha":"abc123"}
```

Required actions: `group_status_check`, `group_merge_attempted`,
`group_merge_succeeded`, `group_merge_failed`, `group_closed`,
`group_pruned`.

---

## Failure modes

- **multi-gitter missing** — install via `go install` (see Step 0). If `go`
  is also missing, fall back to a hand-rolled `gh pr` loop per repo and
  log a `MISSING_MULTIGITTER` warning. The hand-rolled loop is correct but
  slower and lacks structured output.
- **Token lacks merge permission on a repo** — multi-gitter reports per-repo
  failure; pass through to the structured output and let the orchestrator
  surface it on the meta-issue.
- **Branch protection blocks merge** — by design. Do not bypass. Surface
  the failure to the human reviewer.
- **Repo no longer exists / archived** — log and skip.

---

## Why a separate skill

This is a separate skill from `oracle-pipeline` because:

1. **Different trigger.** `oracle-pipeline` triggers on `maestro-ready`
   labeling; this triggers on meta-issue close (or on a status-poll cron).
2. **Different runtime.** Implementation runs for hours; lifecycle ops
   complete in seconds.
3. **Different blast radius.** Implementation can only touch
   `feat/oracle-project-*` branches. Merge actually mutates `main` — a
   distinct permission scope.
4. **Different tool.** Hand-rolled loop for implementation, multi-gitter
   for lifecycle.

Keeping them separate also means a bug in the lifecycle handler cannot
break the implementation pipeline, and vice versa.
