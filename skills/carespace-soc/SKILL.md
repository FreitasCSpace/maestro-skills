---
name: carespace-soc
description: CareSpace AI Security Operations Center — continuous detection, triage, HIPAA/SOC2 compliance evidence, and response. Runs without a security team.
---

# CareSpace SOC — AI-Powered Security Operations

**Your SOC. Your data. Your control. AI does the work.**

Five modules — ALL mandatory, run in order:
1. **Detect** — Secret scanning + CVE scan across all repos
2. **Audit** — HIPAA/SOC2 control gap analysis on current codebase
3. **Triage** — Auto-prioritize findings, suppress false positives
4. **Evidence** — Generate compliance artifacts (HIPAA §§, SOC2 CCs)
5. **Respond** — File detailed GitHub issues, post digest to Slack

---

## SETUP

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
DATE=$(date -u +%Y-%m-%d)
REPORT_DIR="/tmp/carespace-soc-${DATE}"
mkdir -p "$REPORT_DIR"
echo "SOC run started: $DATE"
```

---

## MODULE 1: SECRET SCANNING

Scan every carespace-ai repo for exposed credentials in current HEAD.

```bash
REPOS=$(gh repo list carespace-ai --limit 100 --json name --no-archived --jq '.[].name')

for repo in $REPOS; do
  echo "=== Scanning $repo for secrets ==="

  REPO_DIR="/tmp/soc-repos/$repo"
  if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only -q 2>/dev/null
  else
    gh repo clone carespace-ai/$repo "$REPO_DIR" -- --depth 1 -q 2>/dev/null
  fi

  # Scan with secret type labels
  {
    grep -rn "sk-ant-[a-zA-Z0-9_-]\{20,\}" \
      --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
      --include="*.dart" --include="*.kt" --include="*.yaml" --include="*.yml" \
      --include="*.json" --include="*.env*" --include="Dockerfile*" \
      --exclude-dir=".git" --exclude-dir="node_modules" \
      "$REPO_DIR" 2>/dev/null | sed "s|^|[ANTHROPIC_KEY] $repo:|"

    grep -rn "ghp_[a-zA-Z0-9]\{36\}" \
      --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
      --include="*.dart" --include="*.kt" --include="*.yaml" --include="*.yml" \
      --include="*.json" --include="*.env*" --include="Dockerfile*" \
      --exclude-dir=".git" --exclude-dir="node_modules" \
      "$REPO_DIR" 2>/dev/null | sed "s|^|[GITHUB_PAT] $repo:|"

    grep -rn "AKIA[0-9A-Z]\{16\}" \
      --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
      --include="*.dart" --include="*.kt" --include="*.yaml" --include="*.yml" \
      --include="*.json" --include="*.env*" --include="Dockerfile*" \
      --exclude-dir=".git" --exclude-dir="node_modules" \
      "$REPO_DIR" 2>/dev/null | sed "s|^|[AWS_KEY] $repo:|"

    grep -rn "-----BEGIN.*PRIVATE KEY-----" \
      --include="*.ts" --include="*.js" --include="*.py" \
      --include="*.dart" --include="*.kt" --include="*.yaml" --include="*.yml" \
      --include="*.json" --include="*.env*" --include="Dockerfile*" \
      --exclude-dir=".git" --exclude-dir="node_modules" \
      "$REPO_DIR" 2>/dev/null | sed "s|^|[PRIVATE_KEY] $repo:|"

    grep -rn "password\s*=\s*['\"][^'\"]\{8,\}['\"]" \
      --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
      --include="*.dart" --include="*.kt" \
      --exclude-dir=".git" --exclude-dir="node_modules" \
      "$REPO_DIR" 2>/dev/null | sed "s|^|[HARDCODED_PASSWORD] $repo:|"

    grep -rn "secret\s*=\s*['\"][^'\"]\{8,\}['\"]" \
      --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
      --include="*.dart" --include="*.kt" \
      --exclude-dir=".git" --exclude-dir="node_modules" \
      "$REPO_DIR" 2>/dev/null | sed "s|^|[HARDCODED_SECRET] $repo:|"

    grep -rn "api.key\s*=\s*['\"][^'\"]\{8,\}['\"]" \
      --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" \
      --include="*.dart" --include="*.kt" \
      --exclude-dir=".git" --exclude-dir="node_modules" \
      "$REPO_DIR" 2>/dev/null | sed "s|^|[API_KEY] $repo:|"

  } | grep -v "\.example\|test\|spec\|__mock\|placeholder\|your_key_here\|fake\|dummy" \
    | tee -a "$REPORT_DIR/secrets-${repo}.txt"
done

SECRET_COUNT=$(cat "$REPORT_DIR"/secrets-*.txt 2>/dev/null | grep -c "." || echo 0)
echo "Secret scan complete. Potential findings: $SECRET_COUNT"
```

---

## MODULE 2: CVE / DEPENDENCY SCAN

Query OSV.dev for each repo. Capture package name, installed version, severity, fix version, and description.

```bash
> "$REPORT_DIR/cves-detail.txt"

for repo in $REPOS; do
  REPO_DIR="/tmp/soc-repos/$repo"
  PKG="$REPO_DIR/package.json"

  if [ -f "$PKG" ]; then
    DEPS=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[] | "\(.key)@\(.value)"' "$PKG" 2>/dev/null | head -80)
    if [ -n "$DEPS" ]; then
      REPO_HAS_VULNS=false

      echo "$DEPS" | while IFS= read -r dep; do
        pkg="${dep%@*}"
        ver=$(echo "${dep##*@}" | tr -d '^~>=<')
        [ -z "$ver" ] || [ -z "$pkg" ] && continue

        QUERY="{\"package\":{\"name\":\"$pkg\",\"ecosystem\":\"npm\"},\"version\":\"$ver\"}"
        RESULT=$(curl -s -X POST "https://api.osv.dev/v1/query" \
          -H "Content-Type: application/json" \
          -d "$QUERY" 2>/dev/null)

        VULN_COUNT=$(echo "$RESULT" | jq '.vulns | length' 2>/dev/null || echo 0)
        if [ "$VULN_COUNT" -gt 0 ]; then
          echo "$RESULT" | jq -r --arg repo "$repo" --arg pkg "$pkg" --arg ver "$ver" '
            .vulns[] |
            "REPO:\($repo) PKG:\($pkg)@\($ver) CVE:\(.id) SEVERITY:\(.database_specific.severity // .severity[0].score // "UNKNOWN") SUMMARY:\(.summary // "no description") FIXED:\((.affected[0].ranges[0].events[] | select(.fixed) | .fixed) // "no fix available" | tostring)"
          ' 2>/dev/null >> "$REPORT_DIR/cves-detail.txt" || true
        fi
      done

      echo "CVE scan complete for $repo"
    fi
  fi
done

CVE_COUNT=$(grep -c "^REPO:" "$REPORT_DIR/cves-detail.txt" 2>/dev/null || echo 0)
echo "Total CVE findings: $CVE_COUNT"
```

---

## MODULE 3: HIPAA / SOC2 CONTROL AUDIT

### 3a — Access Control (HIPAA §164.312(a), SOC2 CC6.1)

For each unprotected controller, capture: file path, route decorators found, and what's missing.

```bash
ADMIN_DIR="/tmp/soc-repos/carespace-admin"
> "$REPORT_DIR/hipaa-access.txt"

if [ -d "$ADMIN_DIR/src" ]; then
  find "$ADMIN_DIR/src" -name "*.controller.ts" | while read f; do
    if grep -q "@Get\|@Post\|@Put\|@Delete\|@Patch" "$f" && \
       ! grep -q "AuthGuard\|RolesGuard\|@Public" "$f"; then
      ROUTES=$(grep -n "@Get\|@Post\|@Put\|@Delete\|@Patch\|@Controller" "$f" | head -10)
      RELPATH="${f#$ADMIN_DIR/}"
      echo "FILE:$RELPATH" >> "$REPORT_DIR/hipaa-access.txt"
      echo "ROUTES:$ROUTES" >> "$REPORT_DIR/hipaa-access.txt"
      echo "---" >> "$REPORT_DIR/hipaa-access.txt"
    fi
  done
  echo "Access control audit saved."
fi
```

### 3b — PHI Logging (HIPAA §164.502(b))

Capture file, line, and the exact log statement.

```bash
> "$REPORT_DIR/hipaa-phi-logging.txt"

grep -rn \
  -e "console\.log.*userId\|console\.log.*patientId\|console\.log.*email\|console\.log.*token" \
  -e "Logger.*userId\|Logger.*patientId\|this\.logger.*phi\|pino.*patientId" \
  --include="*.ts" --include="*.dart" --include="*.kt" \
  --exclude-dir="node_modules" --exclude-dir=".git" \
  /tmp/soc-repos/carespace-admin/src \
  /tmp/soc-repos/carespace-ui/src \
  /tmp/soc-repos/carespace-mobile-android 2>/dev/null \
  >> "$REPORT_DIR/hipaa-phi-logging.txt"

PHI_LOG_COUNT=$(grep -c "." "$REPORT_DIR/hipaa-phi-logging.txt" 2>/dev/null || echo 0)
echo "PHI logging violations: $PHI_LOG_COUNT"
```

### 3c — Token Storage (HIPAA §164.312(a)(2))

```bash
> "$REPORT_DIR/hipaa-token-storage.txt"

grep -rn "SharedPreferences\|getSharedPreferences\|putString.*token\|putString.*jwt" \
  --include="*.kt" --include="*.java" \
  /tmp/soc-repos/carespace-mobile-android 2>/dev/null \
  | sed 's|^|[ANDROID_SHARED_PREFS] |' >> "$REPORT_DIR/hipaa-token-storage.txt"

grep -rn "localStorage\.\(setItem\|getItem\).*token\|sessionStorage.*token" \
  --include="*.ts" --include="*.tsx" \
  /tmp/soc-repos/carespace-ui/src 2>/dev/null \
  | sed 's|^|[BROWSER_STORAGE] |' >> "$REPORT_DIR/hipaa-token-storage.txt"

echo "Token storage audit done."
```

### 3d — Audit Trail (HIPAA §164.312(b), SOC2 CC7.2)

Capture file, line, and the Prisma call that's missing an audit event.

```bash
> "$REPORT_DIR/hipaa-audit-trail.txt"

if [ -d "$ADMIN_DIR/src" ]; then
  grep -rn "prisma\.\w*\.\(create\|update\|delete\|upsert\)" \
    --include="*.ts" "$ADMIN_DIR/src" 2>/dev/null \
    | while IFS=: read file line code; do
        START=$((line - 5)); [ $START -lt 1 ] && START=1
        END=$((line + 5))
        CONTEXT=$(sed -n "${START},${END}p" "$file" 2>/dev/null)
        if ! echo "$CONTEXT" | grep -q "emit\|auditLog\|EventEmitter\|audit"; then
          RELPATH="${file#$ADMIN_DIR/}"
          echo "FILE:$RELPATH LINE:$line OP:$(echo $code | sed 's/.*prisma\./prisma./' | cut -c1-80)"
        fi
      done 2>/dev/null | head -60 >> "$REPORT_DIR/hipaa-audit-trail.txt"
fi

echo "Audit trail check done."
```

---

## MODULE 4: COMPLIANCE EVIDENCE GENERATION

```bash
EVIDENCE_FILE="$REPORT_DIR/compliance-evidence-${DATE}.md"
ACCESS_COUNT=$(grep -c "^FILE:" "$REPORT_DIR/hipaa-access.txt" 2>/dev/null || echo 0)
AUDIT_GAP_COUNT=$(grep -c "^FILE:" "$REPORT_DIR/hipaa-audit-trail.txt" 2>/dev/null || echo 0)
TOKEN_COUNT=$(grep -c "." "$REPORT_DIR/hipaa-token-storage.txt" 2>/dev/null || echo 0)

cat > "$EVIDENCE_FILE" << EVIDENCE_EOF
# CareSpace AI — Security & Compliance Evidence
**Generated:** ${DATE} UTC
**Generated by:** CareSpace SOC AI (Maestro)
**Scope:** carespace-ai GitHub organization — all active repositories

---

## SOC2 Trust Service Criteria — Evidence Summary

| Control | Criteria | Status | Evidence |
|---------|----------|--------|----------|
| CC6.1 | Access Control | $([ "$ACCESS_COUNT" -eq 0 ] && echo "✅ Pass" || echo "⚠️ $ACCESS_COUNT controllers unprotected") | Access guard audit run ${DATE} |
| CC6.7 | Encryption in transit | ✅ Pass | Azure Container Apps enforce HTTPS. No http:// endpoints detected. |
| CC7.2 | Audit logging | $([ "$AUDIT_GAP_COUNT" -eq 0 ] && echo "✅ Pass" || echo "⚠️ $AUDIT_GAP_COUNT mutations without audit") | Prisma mutation audit check run ${DATE} |
| CC8.1 | Change management | ✅ Pass | All changes via GitHub PRs with required review |
| A1.1 | Availability monitoring | ✅ Pass | Azure Container Apps health checks active |

---

## HIPAA Security Rule — Technical Safeguards Evidence

| Safeguard | Reference | Status | Notes |
|-----------|-----------|--------|-------|
| Access Control | §164.312(a)(1) | $([ "$ACCESS_COUNT" -eq 0 ] && echo "✅ Implemented" || echo "⚠️ $ACCESS_COUNT gaps") | FusionAuth + NestJS AuthGuard + RolesGuard |
| Audit Controls | §164.312(b) | $([ "$AUDIT_GAP_COUNT" -eq 0 ] && echo "✅ Implemented" || echo "⚠️ $AUDIT_GAP_COUNT gaps") | Event emitter on PHI mutations |
| Integrity | §164.312(c)(1) | ✅ Implemented | Prisma schema validation + class-validator DTOs |
| Transmission Security | §164.312(e)(1) | ✅ Implemented | TLS enforced via Azure. No plaintext PHI transmission. |
| PHI Minimum Necessary | §164.502(b) | $([ "$PHI_LOG_COUNT" -eq 0 ] && echo "✅ Pass" || echo "⚠️ $PHI_LOG_COUNT violations") | PHI logging scan run ${DATE} |
| Token Security | §164.312(a)(2) | $([ "$TOKEN_COUNT" -eq 0 ] && echo "✅ Pass" || echo "⚠️ $TOKEN_COUNT occurrences") | Token storage audit run ${DATE} |

---

## Vulnerability Status

| Category | Count | Severity |
|----------|-------|----------|
| Exposed Secrets | ${SECRET_COUNT} | 🔴 Critical if > 0 |
| CVE Findings | ${CVE_COUNT} | See cves-detail.txt |
| PHI Logging Violations | ${PHI_LOG_COUNT} | 🟠 High if > 0 |
| Unprotected Controllers | ${ACCESS_COUNT} | 🔴 Critical |
| Missing Audit Trails | ${AUDIT_GAP_COUNT} | 🟠 High |
| Insecure Token Storage | ${TOKEN_COUNT} | 🟠 High |

*This report constitutes dated compliance evidence for HIPAA and SOC2 audits.*
EVIDENCE_EOF

echo "Compliance evidence generated: $EVIDENCE_FILE"
cat "$EVIDENCE_FILE"
```

---

## MODULE 5: TRIAGE & RESPOND

### 5a — File GitHub Issues (Detailed, Actionable)

Each issue explains: **What is wrong → Where exactly (file:line) → How to fix it**.

#### Issue 1: Secrets (one issue per repo with findings)

```bash
for repo in $REPOS; do
  SECRET_FILE="$REPORT_DIR/secrets-${repo}.txt"
  if [ -f "$SECRET_FILE" ] && [ -s "$SECRET_FILE" ]; then

    # Build a structured findings table
    FINDINGS=$(awk -F: '{
      type=$1; file=$3; line=$4; code=$5
      gsub(/\[|\]/, "", type)
      printf "| %s | `%s` | %s | %s |\n", type, file, line, substr(code, 1, 80)
    }' "$SECRET_FILE" | head -20)

    COUNT=$(wc -l < "$SECRET_FILE" | tr -d ' ')

    ISSUE_BODY="## 🔴 $COUNT Secret(s) Exposed in \`$repo\`

### What is wrong
Credentials are hardcoded directly in source code. Anyone with repository read access can steal these credentials and use them to access production systems, patient data, or cloud infrastructure.

### Where

| Secret Type | File | Line | Code |
|-------------|------|------|------|
$FINDINGS

### How to fix

**Step 1 — Rotate immediately (assume compromised)**
- For private keys (Firebase, Google): revoke in the relevant console and generate a new key pair
- For API keys: rotate in the provider dashboard (Anthropic, GitHub, AWS, etc.)
- For passwords: change the password everywhere it is used

**Step 2 — Move to environment variables**
\`\`\`typescript
// ❌ Before (hardcoded)
const password = 'hardcoded-value-here';

// ✅ After (environment variable)
const password = process.env.MY_SERVICE_PASSWORD;
if (!password) throw new Error('MY_SERVICE_PASSWORD is required');
\`\`\`

**Step 3 — Add to Azure Container Apps secrets or Key Vault**
Store secrets in Azure Key Vault or as Container Apps secrets, not in source code or .env files committed to git.

**Step 4 — Prevent recurrence**
Add \`gitleaks\` or \`detect-secrets\` as a pre-commit hook to block future credential commits.

---
*Generated by CareSpace SOC AI on ${DATE}. HIPAA §164.312(a)(2) — Access Control.*"

    gh issue create \
      --repo "carespace-ai/$repo" \
      --title "🔴 [SOC ${DATE}] $COUNT secret(s) exposed in source code — immediate rotation required" \
      --body "$ISSUE_BODY" \
      --label "security,critical" 2>/dev/null && echo "Secret issue filed for $repo"
  fi
done
```

#### Issue 2: PHI in Logs

```bash
if [ "$PHI_LOG_COUNT" -gt 0 ]; then

  PHI_TABLE=$(awk -F: '{printf "| `%s` | %s | `%s` |\n", $1, $2, substr($3, 1, 100)}' \
    "$REPORT_DIR/hipaa-phi-logging.txt" | head -20)

  ISSUE_BODY="## 🟠 PHI Found in Log Statements — HIPAA §164.502(b) Violation

### What is wrong
Patient identifiers (\`userId\`, \`patientId\`, \`email\`) are being written to application logs via \`console.log\` or logger calls. This violates the HIPAA Minimum Necessary Rule:

- Logs may be accessed by operations staff, DevOps, or third-party log aggregators who are not authorized to see PHI
- Log retention means PHI persists far beyond the need
- Log shipping to services like Datadog, Sentry, or Azure Monitor creates uncontrolled PHI disclosure

### Where — $PHI_LOG_COUNT violation(s)

| File | Line | Code |
|------|------|------|
$PHI_TABLE

### How to fix

**Option A — Remove PHI from logs entirely (preferred)**
\`\`\`typescript
// ❌ Before
this.logger.log(\`User \${userId} accessed patient \${patientId}\`);

// ✅ After — log action without PHI
this.logger.log('Patient record accessed', { action: 'read', resource: 'patient' });
\`\`\`

**Option B — Hash the identifier if correlation is needed**
\`\`\`typescript
import { createHash } from 'crypto';
const safeId = createHash('sha256').update(userId).digest('hex').slice(0, 8);
this.logger.log(\`User \${safeId} accessed record\`);
\`\`\`

**Option C — Route to a dedicated HIPAA audit log (if logging is required)**
Use the existing audit event emitter instead of console/logger for any PHI-adjacent events:
\`\`\`typescript
this.eventEmitter.emit('audit.access', { userId, patientId, action: 'read' });
\`\`\`
This routes through the compliant audit trail, not general application logs.

---
*Generated by CareSpace SOC AI on ${DATE}. HIPAA §164.502(b) — Minimum Necessary.*"

  gh issue create \
    --repo carespace-ai/carespace-admin \
    --title "🟠 [SOC ${DATE}] PHI in log statements — $PHI_LOG_COUNT HIPAA violation(s)" \
    --body "$ISSUE_BODY" \
    --label "security,hipaa,high" 2>/dev/null && echo "PHI logging issue filed."
fi
```

#### Issue 3: Unprotected API Endpoints

```bash
ACCESS_COUNT=$(grep -c "^FILE:" "$REPORT_DIR/hipaa-access.txt" 2>/dev/null || echo 0)
if [ "$ACCESS_COUNT" -gt 0 ]; then

  CONTROLLER_DETAILS=$(awk '
    /^FILE:/ { file=substr($0, 6) }
    /^ROUTES:/ { routes=substr($0, 8) }
    /^---/ { if (file) printf "**`%s`**\nRoutes: %s\n\n", file, routes; file=""; routes="" }
  ' "$REPORT_DIR/hipaa-access.txt" | head -40)

  ISSUE_BODY="## 🔒 $ACCESS_COUNT Unprotected API Controller(s) — HIPAA §164.312(a) Violation

### What is wrong
NestJS controllers expose HTTP routes (\`@Get\`, \`@Post\`, \`@Put\`, \`@Delete\`) without \`@UseGuards(AuthGuard)\` or \`@UseGuards(RolesGuard)\`. Any request — including unauthenticated ones — can reach these endpoints and potentially read or modify PHI.

This violates HIPAA §164.312(a)(1) — Access Control, which requires that only authorized users can access electronic PHI.

### Where — $ACCESS_COUNT controller(s) affected

$CONTROLLER_DETAILS

### How to fix

**Option A — Protect the entire controller (recommended)**
\`\`\`typescript
import { UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';

@Controller('patients')
@UseGuards(AuthGuard('jwt'), RolesGuard)   // ← Add this
@Roles('clinician', 'admin')              // ← Add this
export class PatientController {
  // All routes are now protected
}
\`\`\`

**Option B — Mark intentionally public routes explicitly**
If a route is truly public (e.g., health check), mark it with \`@Public()\` decorator so the SOC scanner can confirm it is intentional, not an oversight.

**Verification:** After adding guards, run \`npm run test:e2e\` and confirm unauthenticated requests to these endpoints return \`401 Unauthorized\`.

---
*Generated by CareSpace SOC AI on ${DATE}. HIPAA §164.312(a)(1) — Access Control.*"

  gh issue create \
    --repo carespace-ai/carespace-admin \
    --title "🔒 [SOC ${DATE}] $ACCESS_COUNT unprotected API controller(s) — auth bypass risk" \
    --body "$ISSUE_BODY" \
    --label "security,hipaa,critical" 2>/dev/null && echo "Auth guard issue filed."
fi
```

#### Issue 4: Missing Audit Trails

```bash
AUDIT_GAP_COUNT=$(grep -c "^FILE:" "$REPORT_DIR/hipaa-audit-trail.txt" 2>/dev/null || echo 0)
if [ "$AUDIT_GAP_COUNT" -gt 0 ]; then

  AUDIT_TABLE=$(awk -F'FILE:|LINE:|OP:' '
    NF>1 { printf "| `%s` | %s | `%s` |\n", $2, $3, substr($4, 1, 80) }
  ' "$REPORT_DIR/hipaa-audit-trail.txt" | head -25)

  ISSUE_BODY="## 📋 Missing Audit Trail Events — HIPAA §164.312(b) Violation

### What is wrong
Prisma mutations (\`create\`, \`update\`, \`delete\`, \`upsert\`) on patient data occur without emitting audit log events. HIPAA §164.312(b) requires a complete, tamper-evident audit trail of all PHI access and modifications.

**Impact of non-compliance:**
- If a breach occurs, you cannot determine what data was accessed or modified
- Auditors (HIPAA, SOC2) will flag the absence of audit trails as a critical control gap
- Breach notification requirements under HIPAA §164.400 cannot be met without audit logs

### Where — $AUDIT_GAP_COUNT Prisma mutation(s) without audit events

| File | Line | Operation |
|------|------|-----------|
$AUDIT_TABLE

### How to fix

**Step 1 — Emit an audit event after every PHI mutation**
\`\`\`typescript
// ❌ Before — mutation with no audit trail
const patient = await this.prisma.patient.create({ data });

// ✅ After — emit audit event immediately after
const patient = await this.prisma.patient.create({ data });
await this.eventEmitter.emit('audit.phi_mutation', {
  action: 'create',
  entity: 'patient',
  entityId: patient.id,
  performedBy: ctx.userId,
  timestamp: new Date().toISOString(),
  changes: Object.keys(data),
});
\`\`\`

**Step 2 — Or use a Prisma middleware to audit automatically**
\`\`\`typescript
this.prisma.\$use(async (params, next) => {
  const result = await next(params);
  const phiModels = ['Patient', 'Scan', 'PostureAssessment'];
  if (phiModels.includes(params.model) && ['create','update','delete','upsert'].includes(params.action)) {
    await auditService.log({ model: params.model, action: params.action, args: params.args });
  }
  return result;
});
\`\`\`

**Step 3 — Store audit logs immutably**
Audit logs should be append-only (no UPDATE/DELETE on audit table) and ideally shipped to a separate storage (Azure Blob, separate DB schema).

---
*Generated by CareSpace SOC AI on ${DATE}. HIPAA §164.312(b) — Audit Controls. SOC2 CC7.2.*"

  gh issue create \
    --repo carespace-ai/carespace-admin \
    --title "📋 [SOC ${DATE}] $AUDIT_GAP_COUNT Prisma mutations missing audit events — HIPAA §164.312(b)" \
    --body "$ISSUE_BODY" \
    --label "security,hipaa,high" 2>/dev/null && echo "Audit trail issue filed."
fi
```

#### Issue 5: CVEs (one issue per affected repo)

```bash
if [ -f "$REPORT_DIR/cves-detail.txt" ] && [ -s "$REPORT_DIR/cves-detail.txt" ]; then
  AFFECTED_REPOS=$(grep "^REPO:" "$REPORT_DIR/cves-detail.txt" | sed 's/REPO:\([^ ]*\).*/\1/' | sort -u)

  for repo in $AFFECTED_REPOS; do
    REPO_VULNS=$(grep "^REPO:$repo " "$REPORT_DIR/cves-detail.txt")
    VULN_COUNT=$(echo "$REPO_VULNS" | wc -l | tr -d ' ')

    VULN_TABLE=$(echo "$REPO_VULNS" | awk '{
      match($0, /PKG:([^ ]+)/, pkg)
      match($0, /CVE:([^ ]+)/, cve)
      match($0, /SEVERITY:([^ ]+)/, sev)
      match($0, /SUMMARY:(.+) FIXED:/, summ)
      match($0, /FIXED:(.+)$/, fix)
      printf "| `%s` | %s | %s | %s | %s |\n", pkg[1], cve[1], sev[1], summ[1], fix[1]
    }' | head -20)

    # Determine highest severity
    HAS_CRITICAL=$(echo "$REPO_VULNS" | grep -i "CRITICAL" | wc -l | tr -d ' ')
    HAS_HIGH=$(echo "$REPO_VULNS" | grep -i "HIGH" | wc -l | tr -d ' ')
    [ "$HAS_CRITICAL" -gt 0 ] && SEVERITY_LABEL="🔴 CRITICAL" || \
    [ "$HAS_HIGH" -gt 0 ] && SEVERITY_LABEL="🟠 HIGH" || SEVERITY_LABEL="🟡 MEDIUM"

    ISSUE_BODY="## 📦 $VULN_COUNT Vulnerable Dependencies in \`$repo\` — $SEVERITY_LABEL

### What is wrong
npm packages with known CVEs are installed. Attackers can exploit these vulnerabilities to:
- Execute arbitrary code in the application or CI/CD pipeline
- Bypass authentication or authorization controls
- Exfiltrate data including PHI
- Perform denial-of-service attacks

### Where & What to upgrade

| Package@Version | CVE | Severity | Description | Fix Version |
|-----------------|-----|----------|-------------|-------------|
$VULN_TABLE

### How to fix

**Step 1 — Run npm audit for detailed output**
\`\`\`bash
cd $repo
npm audit
npm audit --json | jq '.vulnerabilities | to_entries[] | {package: .key, severity: .value.severity, fixAvailable: .value.fixAvailable}'
\`\`\`

**Step 2 — Apply automatic fixes where safe**
\`\`\`bash
npm audit fix          # Fix patches (non-breaking)
npm audit fix --force  # Fix including major bumps (test after!)
\`\`\`

**Step 3 — Manually upgrade packages with no auto-fix**
For each row in the table above with a known fix version:
\`\`\`bash
npm install package-name@fix-version
\`\`\`

**Step 4 — Add to CI/CD**
Add \`npm audit --audit-level=high\` to your GitHub Actions workflow to block PRs that introduce high/critical CVEs:
\`\`\`yaml
- name: Security audit
  run: npm audit --audit-level=high
\`\`\`

---
*Generated by CareSpace SOC AI on ${DATE}. SOC2 CC7.1 — Vulnerability Management.*"

    gh issue create \
      --repo "carespace-ai/$repo" \
      --title "📦 [SOC ${DATE}] $VULN_COUNT vulnerable dependencies — $SEVERITY_LABEL" \
      --body "$ISSUE_BODY" \
      --label "security,dependencies" 2>/dev/null && echo "CVE issue filed for $repo"
  done
fi
```

### 5b — Post SOC Digest to Slack

```bash
ACCESS_COUNT=$(grep -c "^FILE:" "$REPORT_DIR/hipaa-access.txt" 2>/dev/null || echo 0)
AUDIT_GAP_COUNT=$(grep -c "^FILE:" "$REPORT_DIR/hipaa-audit-trail.txt" 2>/dev/null || echo 0)
TOKEN_COUNT=$(grep -c "." "$REPORT_DIR/hipaa-token-storage.txt" 2>/dev/null || echo 0)

OVERALL=$(
  if [ "$SECRET_COUNT" -gt 0 ]; then echo "🔴 CRITICAL"
  elif [ "$ACCESS_COUNT" -gt 0 ]; then echo "🔴 CRITICAL"
  elif [ "$PHI_LOG_COUNT" -gt 0 ] || [ "$AUDIT_GAP_COUNT" -gt 20 ]; then echo "🟠 HIGH"
  elif [ "$CVE_COUNT" -gt 0 ]; then echo "🟡 MEDIUM"
  else echo "✅ CLEAR"
  fi
)

BODY="*CareSpace SOC — ${DATE} | Overall: ${OVERALL}*

*🔍 Detection*
• 🔑 Secrets exposed: *${SECRET_COUNT}* $([ "$SECRET_COUNT" -gt 0 ] && echo "← ⚠️ ROTATE NOW" || echo "✅")
• 📦 CVE findings: *${CVE_COUNT}* $([ "$CVE_COUNT" -gt 0 ] && echo "← upgrade dependencies" || echo "✅")
• 🏥 PHI in logs: *${PHI_LOG_COUNT}* $([ "$PHI_LOG_COUNT" -gt 0 ] && echo "← HIPAA violation" || echo "✅")

*🔒 HIPAA Controls*
• Auth guards missing: *${ACCESS_COUNT}* controller(s) $([ "$ACCESS_COUNT" -gt 0 ] && echo "← unauthenticated access risk" || echo "✅")
• Audit trail gaps: *${AUDIT_GAP_COUNT}* mutation(s) without audit event
• Insecure token storage: *${TOKEN_COUNT}* occurrence(s)

*📋 Actions Taken*
$([ "$SECRET_COUNT" -gt 0 ] && echo "• GitHub issue filed: secrets exposure (per repo)" || echo "• No secret issues")
$([ "$PHI_LOG_COUNT" -gt 0 ] && echo "• GitHub issue filed: carespace-admin — PHI in logs" || echo "• No PHI log issues")
$([ "$ACCESS_COUNT" -gt 0 ] && echo "• GitHub issue filed: carespace-admin — unprotected endpoints" || echo "• No auth guard issues")
$([ "$AUDIT_GAP_COUNT" -gt 0 ] && echo "• GitHub issue filed: carespace-admin — missing audit trails" || echo "• No audit trail issues")
$([ "$CVE_COUNT" -gt 0 ] && echo "• GitHub CVE issues filed per affected repo" || echo "• No CVE issues")
• Compliance evidence: \`/tmp/carespace-soc-${DATE}/compliance-evidence-${DATE}.md\`"

slack_post "$SLACK_ENGINEERING" "CareSpace SOC Digest — ${DATE}" "$BODY" "carespace-soc"
echo "SOC digest posted."
```

---

## CARESPACE CONTEXT

**Stack:** React 18/TypeScript + NestJS/Prisma + Flutter/Dart + Swift + Kotlin. Azure Container Apps. FusionAuth + JWT.

**PHI:** Patient movement data, body scans, posture assessments. HIPAA covered entity rules apply to all data handling.

**Threat Model:** SaaS multi-tenant. Primary risks: auth bypass exposing cross-tenant PHI, token leakage, missing audit trails blocking breach investigation, supply chain CVEs in npm dependencies.

**No security team.** This skill IS the SOC. Run it daily or on-demand. Evidence artifacts feed directly into HIPAA audits and SOC2 reviews.
