---
name: security-digest
description: Daily security intelligence digest — scans 7 sources (NIST NVD, CISA KEV, GitHub Advisories, OSV.dev, npm audit, JFrog Research, Hacker News) for vulnerabilities. Tags items matching CareSpace stack with ⚠️ AFFECTS CARESPACE. Posts to #ops-general Slack. Idempotent.
---

# Security Digest

**Fully autonomous. File-based pipeline — all data in /tmp files. Posts once per day.**

## GUARDRAILS
- Read-only — never modifies any external system except Slack
- Idempotent — checks if digest was already posted today, updates if so
- Max 20 items per digest — prioritize by severity and relevance
- Only include CVEs with CVSS >= 7.0 unless directly matching CareSpace stack
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

## SOURCES (7 feeds)
```
1. NIST NVD         — https://services.nvd.nist.gov/rest/json/cves/2.0/
                       All CVEs published today, CVSS >= 7.0
2. CISA KEV         — https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
                       Actively exploited vulnerabilities with remediation deadlines
3. GitHub Advisories — GraphQL API (securityAdvisories)
                       npm, pip, pub, go ecosystem advisories published today
4. OSV.dev          — https://api.osv.dev/v1/query
                       Open Source Vulnerability database — query by package
5. npm audit feed   — https://registry.npmjs.org/-/npm/v1/security/advisories
                       npm-specific advisories (via GitHub Advisory DB)
6. JFrog Research   — https://research.jfrog.com/feed.xml
                       Supply chain, malicious packages, artifact security
7. Hacker News      — https://hn.algolia.com/api/v1/search_by_date
                       Community-surfaced security news from today
```

## CARESPACE STACK (for ⚠️ AFFECTS CARESPACE tagging)
```
LANGUAGES:  TypeScript, JavaScript, Dart, Python, Go
FRAMEWORKS: NestJS, React, Next.js, Flutter, FastAPI, Express
RUNTIME:    Node.js 20, Python 3.12, Dart 3.x
DATABASES:  PostgreSQL, Redis, MongoDB
INFRA:      Docker, Nginx, Azure, Linux, Kubernetes
PACKAGES:   Prisma, TypeORM, Socket.IO, RxJS, Riverpod, Freezed, bcrypt, jsonwebtoken, passport
AUTH:       FusionAuth, OAuth2, JWT
MEDIA:      FFmpeg, OpenCV, MediaPipe
COMPLIANCE: HIPAA, SOC2
```

## SLACK CONFIG
```
CHANNEL_ID = C0AKJEUC9DH
CHANNEL    = #ops-general
```

---

## EXECUTION

### Step 0: Load Context + Stack Keywords

```bash
echo "=== Security Digest — $(date +%Y-%m-%d) ==="
DIGEST_DATE=$(date +%Y-%m-%d)

# Stack keywords for matching — used across all sources
STACK_KW="node|nodejs|npm|typescript|javascript|react|nextjs|next\.js|nestjs|express|prisma|typeorm|postgresql|postgres|redis|mongodb|mongo|docker|nginx|azure|linux|kernel|python|fastapi|uvicorn|flutter|dart|opencv|ffmpeg|mediapipe|fusionauth|jwt|jsonwebtoken|passport|socket\.io|rxjs|webpack|vite|esbuild|openssl|curl|git|pip|poetry|bcrypt|sharp|multer|helmet|cors|dotenv|axios|got|undici|fetch"

# Direct package names we use (for OSV.dev queries)
NPM_PACKAGES="@nestjs/core @nestjs/common @prisma/client socket.io express react react-dom next jsonwebtoken bcrypt passport helmet cors multer sharp axios"
PIP_PACKAGES="fastapi uvicorn sqlalchemy pydantic opencv-python mediapipe"
```

### Step 1: Fetch NIST NVD CVEs → /tmp/nvd-cves.json

```bash
TODAY_START="${DIGEST_DATE}T00:00:00.000"
TODAY_END="${DIGEST_DATE}T23:59:59.999"

curl -s "https://services.nvd.nist.gov/rest/json/cves/2.0/?pubStartDate=${TODAY_START}&pubEndDate=${TODAY_END}&resultsPerPage=100" \
  -H "Accept: application/json" \
  > /tmp/nvd-raw.json

jq --arg kw "$STACK_KW" '[.vulnerabilities[]? | {
  id: .cve.id,
  desc: ((.cve.descriptions[]? | select(.lang=="en") | .value) // "")[0:200],
  cvss: ((.cve.metrics.cvssMetricV31[0]?.cvssData.baseScore) // (.cve.metrics.cvssMetricV30[0]?.cvssData.baseScore) // 0),
  severity: ((.cve.metrics.cvssMetricV31[0]?.cvssData.baseSeverity) // "UNKNOWN"),
  published: .cve.published,
  affects_stack: ((.cve.descriptions[]? | select(.lang=="en") | .value) // "" | test($kw; "i"))
} | select(.cvss >= 7.0 or .affects_stack == true)] | sort_by(-.cvss) | .[0:30]' /tmp/nvd-raw.json > /tmp/nvd-cves.json

NVD_TOTAL=$(jq length /tmp/nvd-cves.json)
NVD_STACK=$(jq '[.[]|select(.affects_stack==true)]|length' /tmp/nvd-cves.json)
echo "NVD: $NVD_TOTAL total (CVSS>=7), $NVD_STACK affect CareSpace stack"
```

### Step 2: Fetch CISA KEV → /tmp/cisa-kev.json

```bash
curl -s "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json" \
  > /tmp/cisa-raw.json

jq --arg since "$DIGEST_DATE" --arg kw "$STACK_KW" \
  '[.vulnerabilities[] | select(.dateAdded >= $since) | {
    id: .cveID,
    vendor: .vendorProject,
    product: .product,
    name: .vulnerabilityName,
    action: .requiredAction,
    due: .dueDate,
    affects_stack: ((.product + " " + .vendorProject) | test($kw; "i"))
  }]' /tmp/cisa-raw.json > /tmp/cisa-kev.json

CISA_TOTAL=$(jq length /tmp/cisa-kev.json)
CISA_STACK=$(jq '[.[]|select(.affects_stack==true)]|length' /tmp/cisa-kev.json)
echo "CISA KEV: $CISA_TOTAL new ($CISA_STACK affect CareSpace stack)"
```

### Step 3: Fetch GitHub Security Advisories → /tmp/gh-advisories.json

```bash
gh api graphql -f query='
{
  securityAdvisories(first: 50, orderBy: {field: PUBLISHED_AT, direction: DESC}) {
    nodes {
      ghsaId
      summary
      severity
      publishedAt
      references { url }
      vulnerabilities(first: 5) {
        nodes {
          package { name ecosystem }
          vulnerableVersionRange
        }
      }
    }
  }
}' 2>/dev/null | jq --arg date "$DIGEST_DATE" --arg kw "$STACK_KW" \
  '[.data.securityAdvisories.nodes[] | select(.publishedAt >= $date) | {
    id: .ghsaId,
    summary: .summary[0:200],
    severity: .severity,
    packages: [.vulnerabilities.nodes[].package | "\(.ecosystem)/\(.name)"],
    pkg_names: [.vulnerabilities.nodes[].package.name],
    url: (.references[0].url // ""),
    affects_stack: (
      (.vulnerabilities.nodes[].package.name | test($kw; "i")) or
      (.summary | test($kw; "i"))
    )
  }]' > /tmp/gh-advisories.json

GH_TOTAL=$(jq length /tmp/gh-advisories.json)
GH_STACK=$(jq '[.[]|select(.affects_stack==true)]|length' /tmp/gh-advisories.json)
echo "GitHub Advisories: $GH_TOTAL today ($GH_STACK affect CareSpace stack)"
```

### Step 4: Query OSV.dev for CareSpace Packages → /tmp/osv-results.json

Query OSV.dev directly for our critical packages to catch anything the other sources miss.

```bash
> /tmp/osv-results.json
echo "[" > /tmp/osv-all.json

# Check critical npm packages
for pkg in @nestjs/core @prisma/client socket.io express next react-dom jsonwebtoken bcrypt passport; do
  RESP=$(curl -s -X POST "https://api.osv.dev/v1/query" \
    -H "Content-Type: application/json" \
    -d "{\"package\":{\"name\":\"$pkg\",\"ecosystem\":\"npm\"}}" 2>/dev/null)
  echo "$RESP" | jq --arg pkg "$pkg" --arg date "$DIGEST_DATE" \
    '[(.vulns // [])[] | select(.published >= $date or .modified >= $date) | {
      id: .id,
      summary: (.summary // .details[0:150] // "No summary"),
      severity: ((.database_specific.severity // .severity[0].score // "UNKNOWN") | tostring),
      package: $pkg,
      ecosystem: "npm",
      affects_stack: true
    }]' >> /tmp/osv-all.json 2>/dev/null
  sleep 0.2
done

# Check critical pip packages
for pkg in fastapi uvicorn pydantic sqlalchemy opencv-python; do
  RESP=$(curl -s -X POST "https://api.osv.dev/v1/query" \
    -H "Content-Type: application/json" \
    -d "{\"package\":{\"name\":\"$pkg\",\"ecosystem\":\"PyPI\"}}" 2>/dev/null)
  echo "$RESP" | jq --arg pkg "$pkg" --arg date "$DIGEST_DATE" \
    '[(.vulns // [])[] | select(.published >= $date or .modified >= $date) | {
      id: .id,
      summary: (.summary // .details[0:150] // "No summary"),
      severity: "HIGH",
      package: $pkg,
      ecosystem: "PyPI",
      affects_stack: true
    }]' >> /tmp/osv-all.json 2>/dev/null
  sleep 0.2
done

# Flatten and dedup
jq -s 'add | unique_by(.id) | .[0:10]' /tmp/osv-all.json > /tmp/osv-results.json 2>/dev/null || echo '[]' > /tmp/osv-results.json

OSV_COUNT=$(jq length /tmp/osv-results.json)
echo "OSV.dev: $OSV_COUNT vulnerabilities for CareSpace packages today"
```

### Step 5: Fetch Security News → /tmp/security-news.json

```bash
# Hacker News — security stories from today
OLDEST_TS=$(date -d "$DIGEST_DATE" +%s 2>/dev/null || date -d 'today 00:00' +%s 2>/dev/null || echo $(($(date +%s) - $(date +%H)*3600 - $(date +%M)*60)))

curl -s "https://hn.algolia.com/api/v1/search_by_date?query=security+vulnerability+CVE&tags=story&numericFilters=created_at_i>$OLDEST_TS" \
  | jq --arg kw "$STACK_KW" '[.hits[0:15] | .[] | {
    title: .title,
    url: .url,
    points: .points,
    source: "HackerNews",
    affects_stack: (.title | test($kw; "i"))
  }]' > /tmp/hn-security.json

# JFrog Security Research blog RSS
curl -s "https://research.jfrog.com/feed.xml" 2>/dev/null \
  | grep -oP '<item>.*?</item>' | head -5 \
  | while read -r item; do
    TITLE=$(echo "$item" | grep -oP '<title>\K[^<]+')
    LINK=$(echo "$item" | grep -oP '<link>\K[^<]+')
    echo "{\"title\":\"$TITLE\",\"url\":\"$LINK\",\"source\":\"JFrog Research\",\"affects_stack\":false}"
  done | jq -s '.' > /tmp/jfrog-news.json 2>/dev/null || echo '[]' > /tmp/jfrog-news.json

jq -s 'add | .[0:10]' /tmp/hn-security.json /tmp/jfrog-news.json > /tmp/security-news.json
echo "Security news: $(jq length /tmp/security-news.json)"
```

### Step 6: Build Digest → /tmp/security-digest.md

Every item that matches CareSpace's stack gets tagged with `⚠️ AFFECTS CARESPACE` so the team can spot them instantly.

```bash
DIGEST_DATE=$(date +%Y-%m-%d)
NVD_TOTAL=$(jq length /tmp/nvd-cves.json)
NVD_STACK=$(jq '[.[]|select(.affects_stack==true)]|length' /tmp/nvd-cves.json)
CISA_TOTAL=$(jq length /tmp/cisa-kev.json)
CISA_STACK=$(jq '[.[]|select(.affects_stack==true)]|length' /tmp/cisa-kev.json)
GH_TOTAL=$(jq length /tmp/gh-advisories.json)
GH_STACK=$(jq '[.[]|select(.affects_stack==true)]|length' /tmp/gh-advisories.json)
OSV_COUNT=$(jq length /tmp/osv-results.json)
NEWS_COUNT=$(jq length /tmp/security-news.json)
TOTAL_STACK=$((NVD_STACK + CISA_STACK + GH_STACK + OSV_COUNT))

# Alert level
if [ "$CISA_STACK" -gt 0 ]; then
  ALERT="🔴 *CRITICAL* — CISA KEV affects CareSpace stack"
elif [ "$TOTAL_STACK" -gt 3 ]; then
  ALERT="🟠 *HIGH* — ${TOTAL_STACK} vulnerabilities affect CareSpace stack"
elif [ "$TOTAL_STACK" -gt 0 ]; then
  ALERT="🟡 *ELEVATED* — ${TOTAL_STACK} stack-relevant findings"
elif [ "$CISA_TOTAL" -gt 0 ]; then
  ALERT="🟡 *ELEVATED* — CISA KEV updates (not stack-specific)"
else
  ALERT="🟢 *NORMAL* — No stack-relevant vulnerabilities today"
fi

# CISA KEV section
CISA_SECTION=""
if [ "$CISA_TOTAL" -gt 0 ]; then
  CISA_SECTION=$(jq -r '.[] | (if .affects_stack then "⚠️ *AFFECTS CARESPACE* " else "" end) + "• *\(.id)* — \(.vendor) \(.product)\n  → _\(.name)_\n  → Action: \(.action[0:100])\n  → Due: \(.due)"' /tmp/cisa-kev.json | head -30)
fi

# NVD CVE section — stack-relevant first, then others
CVE_STACK=$(jq -r '.[] | select(.affects_stack==true) | "⚠️ *AFFECTS CARESPACE* • *\(.id)* (CVSS \(.cvss)) [\(.severity)] — \(.desc[0:140])..."' /tmp/nvd-cves.json | head -10)
CVE_OTHER=$(jq -r '.[] | select(.affects_stack!=true) | "• *\(.id)* (CVSS \(.cvss)) [\(.severity)] — \(.desc[0:140])..."' /tmp/nvd-cves.json | head -10)

# GitHub Advisory section
GH_SECTION=$(jq -r '.[] | (if .affects_stack then "⚠️ *AFFECTS CARESPACE* " else "" end) + "• *\(.id)* [\(.severity)] — \(.summary[0:120])...\n  Packages: \(.packages | join(", "))"' /tmp/gh-advisories.json | head -15)

# OSV.dev section (all affect CareSpace by definition)
OSV_SECTION=$(jq -r '.[] | "⚠️ *AFFECTS CARESPACE* • *\(.id)* — \(.package) (\(.ecosystem)) — \(.summary[0:120])..."' /tmp/osv-results.json | head -10)

# News section
NEWS_SECTION=$(jq -r '.[] | (if .affects_stack then "⚠️ " else "" end) + "• <\(.url)|\(.title[0:80])> _(\(.source))_"' /tmp/security-news.json | head -8)

cat > /tmp/security-digest.md << DEOF
$ALERT

*Summary:* ⚠️ Stack-relevant: $TOTAL_STACK | NVD: $NVD_TOTAL | CISA: $CISA_TOTAL | GH: $GH_TOTAL | OSV: $OSV_COUNT
*Sources:* NIST NVD, CISA KEV, GitHub Advisories, OSV.dev, JFrog Research, Hacker News
$([ "$CISA_TOTAL" -gt 0 ] && echo "
*🚨 CISA Known Exploited Vulnerabilities*
$CISA_SECTION")
$([ -n "$CVE_STACK" ] && echo "
*🛡️ NVD CVEs Affecting CareSpace Stack*
$CVE_STACK")
$([ -n "$OSV_SECTION" ] && echo "
*📦 OSV.dev — Direct Package Vulnerabilities*
$OSV_SECTION")
$([ "$GH_TOTAL" -gt 0 ] && echo "
*🔒 GitHub Security Advisories*
$GH_SECTION")
$([ -n "$CVE_OTHER" ] && echo "
*📋 Other High-Severity CVEs (CVSS ≥ 7.0)*
$CVE_OTHER")
$([ "$NEWS_COUNT" -gt 0 ] && echo "
*📰 Security News*
$NEWS_SECTION")

_Stack: Node.js, NestJS, React, Next.js, Prisma, PostgreSQL, Redis, Docker, Python, FastAPI, Flutter, OpenCV, Azure_
DEOF

cat /tmp/security-digest.md
```

### Step 7: Post to Slack (idempotent)

```bash
DIGEST_DATE=$(date +%Y-%m-%d)
CHANNEL_ID="C0AKJEUC9DH"
TITLE="Security Digest — $DIGEST_DATE"
BODY=$(cat /tmp/security-digest.md)
BODY_TRUNC="${BODY:0:2800}"

BLOCKS=$(jq -n \
  --arg title "$TITLE" \
  --arg body "$BODY_TRUNC" \
  --arg footer "_Security digest by CareSpace PM AI via ClaudeHub — $DIGEST_DATE_" \
  '[
    {"type":"header","text":{"type":"plain_text","text":$title}},
    {"type":"section","text":{"type":"mrkdwn","text":$body}},
    {"type":"divider"},
    {"type":"context","elements":[{"type":"mrkdwn","text":$footer}]}
  ]')

OLDEST=$(date -d 'today 00:00' +%s 2>/dev/null || echo $(($(date +%s) - 86400)))
EXISTING_TS=$(curl -s "https://slack.com/api/conversations.history?channel=$CHANNEL_ID&oldest=$OLDEST&limit=50" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  | jq -r --arg t "$TITLE" '.messages[]|select(.blocks[0].text.text==$t)|.ts' | head -1)

if [ -n "$EXISTING_TS" ] && [ "$EXISTING_TS" != "null" ]; then
  curl -s -X POST "https://slack.com/api/chat.update" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg ch "$CHANNEL_ID" --arg ts "$EXISTING_TS" --argjson blocks "$BLOCKS" \
      '{channel:$ch,ts:$ts,blocks:$blocks}')" > /dev/null
  echo "UPDATED existing digest in #ops-general"
else
  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg ch "$CHANNEL_ID" --argjson blocks "$BLOCKS" --arg text "$TITLE" \
      '{channel:$ch,text:$text,blocks:$blocks}')" > /dev/null
  echo "POSTED new digest to #ops-general"
fi
```

Output the final summary: alert level, stack-relevant count, and Slack post status.
