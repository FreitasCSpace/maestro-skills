---
name: carespace-code-review
description: Autonomous PR security review for CareSpace — HIPAA/OWASP audit + CVE check + code quality, posts findings as PR comment.
---

# CareSpace Code Review Orchestrator

**Four phases — ALL are mandatory, do not stop after Step 5:**
1. **Discover** — Find repos with open PRs, extract their dependencies
2. **Threat Intel** — Query CVE sources, build per-repo vulnerability map
3. **PR Review** — For each PR: read diff, audit security + code quality, include ONLY CVE findings relevant to that PR's changed files/deps, post comment
4. **Notify** — Post summary to `#pm-engineering` Slack channel (STEP 6 — REQUIRED, do not skip)

**RULES:**
- PR comments contain ONLY findings. No "positive observations", no "not affected" lists, no news feed.
- If a PR has zero findings → short PASS comment, no filler.
- CVE findings appear in a PR comment ONLY if the PR touches the vulnerable package OR the repo uses a critically vulnerable version that's actively exploited.
- Use sub-agents (Task tool) for parallel PR reviews when possible.
- Write reviews to `/tmp/review-{repo}-{number}.md`, batch post at the end.
- Summary table counts MUST match actual findings listed above it.
- **STEP 6 IS MANDATORY** — the run is not complete until the Slack message is sent to `#pm-engineering`.

---

## STEP 0: Setup

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status 2>&1 || {
  ARCH=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')
  curl -sL "https://github.com/cli/cli/releases/download/v2.67.0/gh_2.67.0_linux_${ARCH}.tar.gz" | tar xz -C /tmp
  export PATH="/tmp/gh_2.67.0_linux_${ARCH}/bin:$PATH"
}
```

---

## STEP 1: Discover

```bash
# Find repos with open PRs
for repo in $(gh repo list carespace-ai --limit 100 --json name --no-archived --jq '.[].name'); do
  count=$(gh pr list --repo carespace-ai/$repo --state open --json number --jq 'length' 2>/dev/null)
  [ "$count" -gt 0 ] 2>/dev/null && echo "$repo"
done
```

For each repo with PRs, extract dependencies:
```bash
gh api repos/carespace-ai/{repo}/contents/package.json --jq '.content' | base64 -d 2>/dev/null | jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[] | "\(.key)@\(.value)"'
```

---

## STEP 2: Threat Intel (once, per-repo)

Query these sources. Save results per-repo to `/tmp/cve-{repo}.json`:

**OSV.dev** — batch query all deps:
```bash
curl -s -X POST "https://api.osv.dev/v1/querybatch" -H "Content-Type: application/json" -d '{"queries": [{build from actual deps}]}'
```

**GitHub Advisories** — critical + high for npm:
```bash
gh api graphql -f query='{securityVulnerabilities(ecosystem:NPM,first:20,severity:CRITICAL,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{advisory{summary,severity,ghsaId}package{name}vulnerableVersionRange,firstPatchedVersion{identifier}}}}'
```

**Dependabot Alerts** (if enabled):
```bash
gh api repos/carespace-ai/{repo}/dependabot/alerts --jq '.[] | select(.state=="open")' 2>/dev/null
```

**Web Search** — supply chain attacks from last 7 days:
```
"npm supply chain attack" OR "npm package compromised" 2026
```

For each vulnerability found, record: `{id, package, vulnerable_range, fixed_version, severity, summary}`

---

## STEP 3: PR Review (per PR)

For each PR, do a **serious code review** — not a checkbox exercise:

### 3a: Read the full diff
```bash
gh pr diff {number} --repo carespace-ai/{repo}
```

### 3b: Security (OWASP)
Read every changed file. Look for REAL issues only:

- **Auth bypass:** Missing AuthGuard on new endpoints, privilege escalation
- **Injection:** Raw SQL, XSS (dangerouslySetInnerHTML, unsanitized input), command injection
- **Data exposure:** Secrets in code, tokens in localStorage/SharedPreferences, unfiltered PHI in responses
- **Infrastructure:** Secrets in Dockerfile, root containers, debug in prod, unpinned images
- **SSRF/CORS:** Wildcard origins, following untrusted redirects

### 3c: HIPAA / SOC 2 Compliance
Check changed code against healthcare compliance requirements:

- **Access control (HIPAA §164.312(a), SOC 2 CC6.1):** New endpoints handling PHI must have both AuthGuard AND RolesGuard. Patients must only see their own data. Missing role checks = finding.
- **Audit trail (HIPAA §164.312(b), SOC 2 CC7.2):** PHI create/update/delete operations must emit audit events. No audit log on status changes, cancellations, or data modifications = finding.
- **PHI logging (HIPAA §164.502(b)):** console.log/print with userId, patientId, email, token, base64, body scan data = finding. JWT tokens must be redacted as [JWT ***].
- **Minimum necessary (HIPAA §164.502(b)):** API responses returning full patient records when only a subset is needed = finding.
- **Encryption (HIPAA §164.312(e), SOC 2 CC6.7):** PHI at rest must use Azure Key Vault / encrypted storage. PHI in transit must be HTTPS only. http:// URLs = finding.
- **Token storage:** Tokens in SharedPreferences/localStorage/disk = finding. Must be in-memory only.
- **Body scan data:** base64 scan data written to device storage or disk = finding. Must be memory → upload → free.

### 3d: Code Quality
Flag only real problems that affect production:

- Missing error handling that could crash or expose stack traces
- TypeScript `any` on PHI-bearing types (bypasses validation)
- Breaking API changes without endpoint versioning
- Missing tests for new endpoints that handle PHI (SOC 2 CC8.1)
- Unvalidated DTOs on endpoints accepting patient data

**DO NOT list "positive observations".** No filler. If nothing is wrong, the section is omitted.

### 3e: Dependencies (CVE relevance check)
Check if any CVE from Step 2 is **relevant to THIS PR**:
- PR adds/bumps the vulnerable package → flag it
- PR touches code that imports/uses the vulnerable package (e.g., imports axios, uses DOMPurify) → flag it
- Repo has a CRITICAL/actively-exploited vuln (CISA KEV, supply chain) → flag it once per repo, not per PR

If no CVEs are relevant to this PR's changes → **omit the Dependencies section entirely**.

### 3f: Score
Count actual findings across ALL four sections (Security + Compliance + Code Quality + Dependencies):
- Any Critical → **BLOCK**
- Any High → **NEEDS CHANGES**
- Medium/Low only → **NEEDS CHANGES**
- Zero findings → **PASS**

Summary table counts MUST match the actual findings listed above it.

---

## STEP 4: Write Review Files

Write each review to `/tmp/review-{repo}-{number}.md`:

**Comment template (always include ALL sections):**
```markdown
## 🔒 Security Review — {PASS|NEEDS CHANGES|BLOCK}

**PR:** #{number} — {title}
**Files:** {n} changed | +{additions} -{deletions}

---

### Security
{findings with #### blocks, OR:}
✅ No security issues found.

### HIPAA / SOC 2
{findings with #### blocks and regulation refs, OR:}
✅ Compliant — access controls, audit trails, and PHI handling look correct.

### Code Quality
{findings with #### blocks, OR:}
✅ Code quality looks good.

### Dependencies
{CVE findings relevant to THIS PR only, OR:}
✅ No vulnerable dependencies in changed code.

---

### What's Done Right
{1-3 bullet points noting specific good practices in this PR. Examples:}
- AuthGuard + RolesGuard correctly applied on all new endpoints
- Blob storage operations properly isolated behind service layer
- PHI fields excluded from API response DTOs

---

| Severity | Count |
|----------|-------|
| 🔴 Critical | {n} |
| 🟠 High | {n} |
| 🟡 Medium | {n} |
| ⚪ Low | {n} |

---
*CareSpace SecDevOps AI via ClaudeHub — {YYYY-MM-DD UTC}*
```

**Finding format:**
```markdown
#### {emoji} {Severity}: {Issue Title}
**File:** `{path}:{line}`
**Issue:** {one sentence}
**Fix:** {specific fix}
```

For HIPAA/SOC 2 findings, add: `**Regulation:** {HIPAA §xxx / SOC 2 CCx.x}`
For dependency findings, add: `**Fix:** Upgrade `{package}` to `{version}``

---

## STEP 5 + 6: Batch Post → Slack Summary (run as one block)

Run this entire block as a single bash command — post all reviews then immediately send the Slack summary:

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Post all review files to GitHub
for f in /tmp/review-*.md; do
  repo=$(basename "$f" .md | sed 's/review-//;s/-[0-9]*$//')
  num=$(basename "$f" .md | grep -oP '\d+$')
  EXISTING=$(gh api repos/carespace-ai/$repo/issues/$num/comments --jq '.[] | select(.body | contains("CareSpace SecDevOps AI via ClaudeHub")) | .id' 2>/dev/null | head -1)
  if [ -n "$EXISTING" ]; then
    gh api repos/carespace-ai/$repo/issues/comments/$EXISTING -X PATCH -F body=@"$f"
    echo "Updated comment on $repo #$num"
  else
    gh pr comment $num --repo carespace-ai/$repo --body-file "$f"
    echo "Posted comment on $repo #$num"
  fi
done

# Build Slack summary
TOTAL=$(ls /tmp/review-*.md 2>/dev/null | wc -l)
BLOCKS=$(grep -rl "🔒 Security Review — BLOCK" /tmp/review-*.md 2>/dev/null | wc -l)
NEEDS=$(grep -rl "🔒 Security Review — NEEDS CHANGES" /tmp/review-*.md 2>/dev/null | wc -l)
PASSES=$(grep -rl "🔒 Security Review — PASS" /tmp/review-*.md 2>/dev/null | wc -l)
DATE=$(date -u +%Y-%m-%d)

LINES=""
for f in /tmp/review-*.md; do
  repo=$(basename "$f" .md | sed 's/review-//;s/-[0-9]*$//')
  num=$(basename "$f" .md | grep -oP '\d+$')
  verdict=$(grep -oP '🔒 Security Review — \K(BLOCK|NEEDS CHANGES|PASS)' "$f" | head -1)
  title=$(gh pr view $num --repo carespace-ai/$repo --json title --jq '.title' 2>/dev/null)
  LINES="${LINES}• *${repo}* #${num} — ${title}: *${verdict}*\n"
done

SUMMARY_BODY="*${TOTAL} PRs reviewed across carespace-ai* — ${BLOCKS} BLOCK, ${NEEDS} NEEDS CHANGES, ${PASSES} PASS\n\n${LINES}"

# Post to #pm-engineering — this is mandatory and must not be skipped
slack_post "$SLACK_ENGINEERING" "CareSpace Security Review — ${DATE}" "$(printf "$SUMMARY_BODY")" "carespace-code-review"
echo "Slack summary posted to #pm-engineering"
```

---

## CARESPACE CONTEXT

**Stack:** React 18/TypeScript + NestJS/Prisma + Flutter/Dart + Swift + Kotlin. Azure. FusionAuth + JWT + NestJS guards.

**PHI:** Never log userId/patientId/email/token/base64/screenshot. Tokens in-memory only. Body scans: base64 → upload → free. All HTTPS. JWT = [JWT ***] in output.

**OWASP Healthcare:** Prisma only (no raw SQL), no dangerouslySetInnerHTML, AuthGuard + RolesGuard everywhere, Azure Key Vault, class-validator DTOs, audit without PHI.
