---
name: secrets-scanner
description: Scan repository for leaked secrets, API keys, tokens, and credentials.
tags: [security, secrets, scanning, autonomous]
---

# Secrets Scanner

Scan the entire repository for leaked secrets, hardcoded credentials, and exposed API keys.

## AUTONOMOUS WORKFLOW

### Step 1: Full Repository Scan
```bash
# API Keys and tokens
grep -rn "sk-\|pk_\|api_key\|apiKey\|api-key\|access_token\|accessToken\|secret_key\|secretKey\|AKIA[0-9A-Z]\{16\}" --include="*.ts" --include="*.js" --include="*.py" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env*" --include="*.toml" --include="*.cfg" .

# Passwords
grep -rn "password\s*[:=]\s*[\"'][^\"']*[\"']\|passwd\|DB_PASS\|POSTGRES_PASSWORD" --include="*.ts" --include="*.py" --include="*.yml" --include="*.env*" --include="*.json" .

# Private keys
grep -rn "BEGIN.*PRIVATE KEY\|BEGIN RSA\|BEGIN EC\|BEGIN DSA" -r .

# Connection strings
grep -rn "mongodb://\|postgres://\|mysql://\|redis://\|amqp://" --include="*.ts" --include="*.py" --include="*.yml" --include="*.env*" --include="*.json" .
```

### Step 2: Check Git History
```bash
git log --all --oneline | head -20
git log --all --diff-filter=D --name-only -- "*.env" "*.pem" "*.key" 2>/dev/null | head -20
```

### Step 3: Check .gitignore
Verify these are excluded: .env, *.pem, *.key, *.p12, credentials.json, serviceAccountKey.json

### Step 4: False Positive Filtering
Exclude: .env.example (with placeholder values), test fixtures, documentation examples

### Step 5: Generate Report
Write `secrets-scan-report.md` with all findings and whether secrets need rotation.
