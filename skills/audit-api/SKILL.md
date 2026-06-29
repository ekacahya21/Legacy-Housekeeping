---
name: audit-api
description: Use when you need to audit an API service to find dead code, inventory endpoints, or cross-reference usage with consumer applications. Applies to any language/framework.
---

# API Auditing & Inventory

A reusable, language-agnostic checklist to audit and inventory a backend API or microservice. Drive the audit via `driver.sh` (available on `$PATH`) and follow the patterns below.

All paths in this skill are relative to the **service repo root** (the project being audited).

## Prerequisites

```bash
# Language-specific syntax checkers — use whatever applies:

# JavaScript / Node
sudo apt-get install -y nodejs

# Python
sudo apt-get install -y python3 python3-pip

# Go
sudo apt-get install -y golang-go

# Java
sudo apt-get install -y default-jdk
```

## Setup

```bash
# Run the audit driver to inventory all endpoints, controllers, and models:
driver.sh inventory ./src

# Scan the codebase for security compliance (SQL injection patterns, missing guards):
driver.sh check-security ./src

# Scan the codebase for performance patterns (N+1 queries, blocking event loop calls):
driver.sh check-performance ./src

# Replace ./src with the path to your source code
```

## Process

Run each section below **in order**. Every claim ("this endpoint is dead", "this condition is duplicated") must be verified — never infer.

---

### 1. Endpoint Audit (Dead Code Removal)

#### 1.1 Inventory All Routes

Use the driver to find all HTTP method definitions:

```bash
driver.sh endpoints ./src
```

This produces a list of every endpoint and the file it lives in.

#### 1.2 Cross-reference with Consumers

For each endpoint, check two things:

**A. API Gateway (if present):** Find what prefix maps to this service:

```bash
# e.g., KrakenD, Kong, Nginx, Envoy
grep -R "<service-name>" /path/to/gateway/config*
```

Identify the gateway prefix (e.g., `prefix1/`, `prefix2/`).

**B. Frontend / Clients:** Search all consumer repos for each endpoint name or path:

```bash
# Search all frontend and client repos
for endpoint in $(cut -d' ' -f1 endpoints.txt); do
  echo "--- $endpoint ---"
  grep -r "$endpoint" /path/to/frontend1 /path/to/frontend2 2>/dev/null || echo "NOT FOUND"
done
```

**Decision matrix:**

| FE calls with prefix | Gateway prefix maps to this service | Verdict |
|---|---|---|
| Correct prefix | Correct prefix | **Keep** — actively used |
| Wrong prefix | Correct prefix | **Remove** — calls another service, this is dead |
| No match found | any | **Audit** — check for service-to-service calls |
| Not found anywhere | Not found | **Remove** — truly dead |

#### 1.3 Flag Dead Code for Removal

For each confirmed dead endpoint, document what should be removed across three layers:

```
1. Route/endpoint declaration   (route file / router config)
2. Handler/controller function   (controller file)
3. Data-access / model function  (model / DAL file)
```

> **🔄** Pass the flagged endpoints to the `refactor-api` skill to perform the actual removal.

**⚠️ Critical: Never change response shapes without verifying the consumer first.** Before removing or refactoring any model/controller:
- Trace the full response shape
- Check for extra keys alongside `data` (e.g., metadata, flags, computed fields)
- If the consumer depends on extra keys, preserve them

---

### 2. YAGNI Decision Framework

Before touching any endpoint, ask these questions **in order**:

1. **Is the frontend/client actually calling this?** If **No** → **Remove**
2. **Is it called with a different prefix?** If **Yes** → **Remove** (belongs to another service)
3. **Does the refactor change the JSON response shape?** If **Yes** → **Stop** (verify consumer expectations first)
4. **Are there extra keys alongside `data`?** (metadata, flags, computed fields) If **Yes** → **Preserve** or test thoroughly

---

### 3. Housekeeping Checklist

> This checklist is about **detecting** issues, not fixing them. Mark items as done once you've verified the codebase is clean in each area. Escalate identified issues to the `refactor-api` skill for resolution.

#### Cleanup
- [ ] No unused imports detected
- [ ] No unused variables detected
- [ ] No dead code detected
- [ ] No commented-out code detected
- [ ] No debug logs detected
- [ ] No unsafe duplicated code detected

#### Formatting
- [ ] Formatter has been applied
- [ ] Linter passes cleanly
- [ ] Type check passes
- [ ] Naming is consistent

#### Dependencies & Config
- [ ] No unused dependencies found
- [ ] No deprecated dependencies found
- [ ] No unused configuration found
- [ ] Sample env/docs are current

#### Documentation
- [ ] No outdated comments found
- [ ] README/docs are current
- [ ] TODO/FIXME comments have been reviewed

#### Security
- [ ] No raw query concatenations / SQL injections detected (Verify using `driver.sh check-security <src>`)
- [ ] Every active route is protected by a suitable authentication guard/middleware (unless explicitly designed to be public)
- [ ] No secrets, credentials, or API keys are hardcoded in the codebase

#### Performance
- [ ] No async database/network calls executed inside loops (N+1 query check; Verify using `driver.sh check-performance <src>`)
- [ ] Database query filters/sorts match indexed fields in the schema
- [ ] Event loop is non-blocking (no synchronous file system or heavy cryptographic calls in async request paths)

#### Request Validation
- [ ] All request payloads (body, query parameters, path params) are validated via schema validation (Zod, Joi, Pydantic, etc.)

#### Observability
- [ ] Standard logging utilities are used instead of raw stdout (`console.log`, `print`)
- [ ] All logs are structured (e.g. JSON log outputs) and contain contextual metadata (timestamps, log levels)
- [ ] Correlation IDs (Request Tracing) are propagated in logs for all request lifecycles

#### Safety
- [ ] No business logic change introduced
- [ ] No API contract change introduced (request/response shapes remain strictly unchanged for all successful payloads)
- [ ] No database schema change introduced that breaks compatibility
- [ ] No authentication/authorization behavior change introduced
- [ ] Build and tests pass
- [ ] Test coverage compliance is met (new/modified files meet target coverage, no coverage regressions)

> **🔄 Circular reference:** Cleanup items can be escalated to the `refactor-api` skill for implementation. Safety and test coverage items must be verified before any merge.

---

### 4. Track Progress

Create `api_review.md` in the repo root to track endpoint-by-endpoint status:

```markdown
# API Endpoints Review
**Branch:** `current-branch`
**Date:** YYYY-MM-DD

## Refactor Status
- ✅ Endpoint completed
- ❌ Endpoint pending
- ℹ️ Endpoint audited and kept

## Rating Table
| Rank | Original Score | Endpoint | Controller | Status | New Score | Details |
```

| Rating | Score | Criteria |
|---|---|---|
| 🚨 WORST | 1-3 | God functions, over-engineering, DRY violations |
| ⚠️ POOR | 4-5 | HTTP leaking, magic numbers, poor REST design |
| 🟡 FAIR | 6-7 | Acceptable but structural improvements remain |
| 🟢 BEST | 8-10 | Clean, simple, well-separated |

## Gotchas

- **Response shape changes are invisible to you but break the frontend.** A model that returns `{ status, data, metadata, flags }` has extra keys the frontend depends on. Changing to just `{ status, data }` breaks them. Always verify.
- **"Remove dead endpoints" means removing 3 layers** — route, controller, model. Miss one and the code lingers.
- **API gateway prefix matters.** An endpoint at `/users/export` that the frontend calls as `legacy-api/users/export` but the gateway routes `prefix/users/export` to this service — the frontend endpoint IS dead even though the code path exists.

## Troubleshooting

- **"I can't find the API gateway config":** Look for `krakend.json`, `kong.yml`, `nginx.conf`, `envoy.yaml`, or any reverse proxy config in CI deployment scripts or infra repos.
- **"The route file is enormous":** Focus on endpoints with obvious migration comments first.
- **"I don't know which frontend repos exist":** Check monorepo `clients/` directory, GitHub org repos, or README for published SDKs / frontend packages.