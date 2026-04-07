---
name: pm-huddle-notes
description: Scan #pm-standup and #carespace-team for huddle note canvases (7-day lookback), extract plaintext content, archive to GitHub vault. Idempotent — skips already-archived files.
---

# PM Huddle Notes

**Fully autonomous. Read-only on Slack. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- Read-only on Slack — NEVER posts, edits, or deletes messages in any channel
- Only reads from channels in $HUDDLE_SOURCE_CHANNELS — never substitutes
- Idempotent — checks vault before writing, skips existing files
- Max $HUDDLE_MAX_PER_RUN files written per run
- Skip files with fewer than $HUDDLE_MIN_CONTENT_CHARS chars of content
- ALL API responses go to /tmp files. NEVER dump raw JSON into context.
- GitHub vault writes use sha-based update (safe re-run — never duplicates)

---

## EXECUTION PROTOCOL

Execute steps **one at a time** in order.

For each step:
1. Read the step file listed below using the Read tool
2. Execute the bash block exactly as written
3. Check output before proceeding

Do not read ahead. Only load the next step file after the current step completes successfully.

---

## STEPS

| # | File | Description |
|---|------|-------------|
| 0 | [steps/step-0-load-context.md](steps/step-0-load-context.md) | Source shared context |
| 1 | [steps/step-1-resolve-channel-ids.md](steps/step-1-resolve-channel-ids.md) | Resolve channel names to IDs via paginated conversations.list |
| 2 | [steps/step-2-collect-canvas-files.md](steps/step-2-collect-canvas-files.md) | Scan channels for canvas/huddle files within lookback window |
| 3 | [steps/step-3-load-vault-index.md](steps/step-3-load-vault-index.md) | Load existing vault filenames for idempotency check |
| 4 | [steps/step-4-download-archive.md](steps/step-4-download-archive.md) | Download canvas content, strip HTML, write to GitHub vault |

---

## /tmp FILE MAP

| File | Written by | Read by |
|------|-----------|---------|
| /tmp/huddle-channels.tsv | Step 1 | Step 2 |
| /tmp/huddle-files.tsv | Step 2 | Step 4 |
| /tmp/vault-existing.txt | Step 3 | Step 4 |
| /tmp/huddle-upload.md | Step 4 | Step 4 (intermediate) |
| /tmp/huddle-log.txt | Step 4 | printed to stdout |

# PM Huddle Notes

**Fully autonomous. Read-only on Slack. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ Read-only on Slack — NEVER posts, edits, or deletes messages in any channel
- ⛔ Only reads from channels in $HUDDLE_SOURCE_CHANNELS — never substitutes
- Idempotent — checks vault before writing, skips existing files
- Max $HUDDLE_MAX_PER_RUN files written per run
- Skip files with fewer than $HUDDLE_MIN_CONTENT_CHARS chars of content
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**
- GitHub vault writes use sha-based update (safe re-run — never duplicates)

---

## EXECUTION PROTOCOL

Execute steps **one at a time** in order.

**For each step:**
1. Read the step file listed below using the Read tool
2. Execute the bash block exactly as written
3. Check output before proceeding

**Do not read ahead.** Only load the next step file after the current step completes successfully.

---

## STEPS

| # | File | Description |
|---|------|-------------|
| 0 | [steps/step-0-load-context.md](steps/step-0-load-context.md) | Source shared context |
| 1 | [steps/step-1-resolve-channel-ids.md](steps/step-1-resolve-channel-ids.md) | Resolve source channel names → IDs via paginated conversations.list |
| 2 | [steps/step-2-collect-canvas-files.md](steps/step-2-collect-canvas-files.md) | Scan channels for canvas/huddle files within lookback window |
| 3 | [steps/step-3-load-vault-index.md](steps/step-3-load-vault-index.md) | Load existing vault filenames for idempotency check |
| 4 | [steps/step-4-download-archive.md](steps/step-4-download-archive.md) | Download canvas content, strip HTML, write to GitHub vault |

---

## /tmp FILE MAP

| File | Written by | Read by |
|------|-----------|---------|
| /tmp/huddle-channels.tsv | Step 1 | Steps 2 |
| /tmp/huddle-files.tsv | Step 2 | Step 4 |
| /tmp/vault-existing.txt | Step 3 | Step 4 |
| /tmp/huddle-upload.md | Step 4 | Step 4 (intermediate) |
| /tmp/huddle-log.txt | Step 4 | — (printed to stdout) |
