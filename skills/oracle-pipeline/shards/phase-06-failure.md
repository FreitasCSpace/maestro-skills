# Phase 06 — Hard Story Failure Handling

Read this shard immediately when any story fails hard (review, security, or
build exceeded max retries).

## Label rollback

```bash
gh issue comment "$ANCHOR_ISSUE" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Pipeline failed at story $FAILED_STORY: $ERROR_SUMMARY"

jq -r '.[].number' /tmp/oracle-work/stories.json | while read n; do
  gh issue edit "$n" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --remove-label oracle:implementing \
    --add-label oracle:blocked-pipeline-failed
done
```

## State left behind

Leave project branches at the last successful story's commit. Do NOT push,
do NOT open PRs, do NOT trigger deploy.

Update PIPELINE.md `## Status` to `FAILED_AT_STORY_<N.M>`. Exit non-zero.

## Resume contract

A re-application of `maestro-ready` to any story in the group will re-trigger
this skill. The orchestrator detects the last commit on the branch, reads the
next story from BMAD, and resumes from `$FAILED_STORY`.

## PIPELINE_RUNAWAY

If the project as a whole accumulates >5 hard story failures across the
session, abort:

```bash
gh issue comment "$ANCHOR_ISSUE" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "PIPELINE_RUNAWAY: $HARD_FAILURE_COUNT hard failures — human review required"
exit 2
```
