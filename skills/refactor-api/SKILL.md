---
name: refactor-api
description: Use when you need to improve code quality in an API service — standardizing error handling, eliminating duplication, and extracting shared utilities. Applies to any language/framework.
---

# API Refactoring & Code Quality Improvement

A reusable, language-agnostic checklist to clean and refactor a backend API or microservice. Use this after an `audit-api` pass (or during any development phase) to ensure the codebase follows clean architecture patterns.

All paths in this skill are relative to the **service repo root** (the project being refactored).

## Prerequisites

```bash
# Language-specific syntax checkers — use whatever applies:
node -c ./src/index.js        # Node/JS
python -m py_compile main.py  # Python
go vet ./...                  # Go
```

---

### 1. Remove Dead Code

After an audit has confirmed which endpoints are dead, remove them in three layers:

```
1. Remove route/endpoint declaration   (route file / router config)
2. Remove handler/controller function   (controller file)
3. Remove data-access / model function  (model / DAL file)
```

**⚠️ Critical: Never change response shapes without verifying the consumer first.** Before removing any model/controller:
- Trace the full response shape
- Check for extra keys alongside `data` (e.g., metadata, flags, computed fields)
- If the consumer depends on extra keys, preserve them

---

### 2. Standardize Controller Error Handling & Request Lifecycle

#### 2.1 Create a Controller Wrapper with Validation and Observability

**Language-agnostic pattern:** Extract a reusable wrapper that:
1. Generates or forwards a request-level Correlation ID.
2. Integrates input schema validation handlers.
3. Catches and logs errors structurally with correlation context.
4. Returns consistent response formats (ensuring existing contract shapes are preserved).

```pseudocode
FUNCTION wrap(handler, schema = NULL):
    RETURN FUNCTION(request, response, next):
        // 1. Establish request-scoped Correlation ID
        correlationId = request.headers["x-correlation-id"] OR generateUUID()
        context.set("correlationId", correlationId)
        
        TRY:
            // 2. Perform Input validation (if schema provided)
            IF schema IS NOT NULL THEN
                validatedData = schema.validate(request.body, request.query, request.params)
                request.validated = validatedData
                
            AWAIT handler(request, response, next)
            
        CATCH error:
            // 3. Handle schema/input validation errors (maps to 400 Bad Request)
            IF error IS ValidationError THEN
                logger.warn("Validation failed", {
                    correlationId: correlationId,
                    errors: error.details,
                    path: request.path
                })
                
                // Map validation error back to standard error shape of target codebase
                response.status(400).json({
                    status: 400,
                    message: "Validation failed",
                    errors: error.details 
                })
            ELSE
                // 4. Handle internal errors securely (maps to 500)
                logger.error("Controller execution failed", {
                    correlationId: correlationId,
                    message: error.message,
                    stack: error.stack,
                    method: request.method,
                    path: request.path
                })
                
                response.status(500).json({
                    status: 500,
                    message: "Internal server error",
                    // Avoid leaking raw stacks to users, but keep shape consistent
                    error: "An unexpected error occurred"
                })

FUNCTION sendSuccess(response, data):
    IF data has a "status" field THEN
        // Legacy model response — pass through verbatim to keep shape
        response.status(data.status).json(data)
    ELSE
        response.status(200).json({
            status: 200,
            message: "Success",
            data: data
        })
```

#### 2.2 Apply to All Controllers

**Before — every handler has custom validations, logging, and try/catch:**

```pseudocode
// In every single handler, duplicated N times
HANDLER getData(request, response):
    TRY:
        IF NOT isUUID(request.params.id) THEN
            RETURN response.status(400).json({ error: "Invalid ID" })
            
        result = model.getData(request.params.id)
        response.status(result.status).json(result)
    CATCH error:
        console.error(error)
        response.status(500).json({ status: 500, error: error.message })
```

**After — validation schema + one wrapper handles error, correlation IDs, and validations:**

```pseudocode
// 1. Declare validation schema
USER_ID_SCHEMA = Schema({
    params: { id: UUID() }
})

// 2. Focused handler logic
HANDLER getData(request, response):
    // Access validated parameters from context
    result = model.getData(request.validated.params.id)
    sendSuccess(response, result)

// 3. Register route with wrapper
router.get("/data/:id", wrap(getData, USER_ID_SCHEMA))
```

#### 2.3 Fix Models That Accept (request, response)

If a model function previously received both `request` and `response` and wrote directly to `response`, change it to **accept only request parameters and return the result**. Controllers should own the response.

**Before:**

```pseudocode
FUNCTION legacyImport(request, response):
    data = parse(request.body)
    response.status(200).json({ status: 200, data: data })
```

**After:**

```pseudocode
FUNCTION legacyImport(request):
    data = parse(request.body)
    RETURN { status: 200, data: data }
// Controller calls sendSuccess(response, model.legacyImport(request))
```

---

### 3. Eliminate Duplicated Code

#### 3.1 Combinatorial Conditionals

Look for functions that write every permutation of N booleans as separate branches:

**Before (N booleans = 2^N branches):**

```pseudocode
IF a AND b AND c THEN
    conditions = [condA, condB, condC]
ELSE IF a AND b AND NOT c THEN
    conditions = [condA, condB]
ELSE IF a AND NOT b AND c THEN
    conditions = [condA, condC]
ELSE IF a AND NOT b AND NOT c THEN
    conditions = [condA]
...  // 2^3 = 8 branches
```

**After (2 branches, N conditions):**

```pseudocode
conditions = []
IF a THEN conditions.PUSH(condA)
IF b THEN conditions.PUSH(condB)
IF c THEN conditions.PUSH(condC)
where = conditions.NOT_EMPTY ? buildConditions(conditions) : default
```

#### 3.2 Runtime Verification

After de-duplication, run the test suite and verify output:

```bash
# Language-specific syntax check
node -c path/to/file.js    # Node/JS
python -m py_compile file.py  # Python
go vet ./...               # Go
javac File.java            # Java

# Run tests
npm test                   # Node
pytest                     # Python
go test ./...              # Go
mvn test                   # Java
```

---

### 4. Extract Shared Utilities

If the same output generation (Excel, CSV, PDF, JSON) or pagination logic appears in multiple controllers, extract it to a single shared module.

**Before:**

```pseudocode
// In controller A
FUNCTION exportAsExcel(request, response):
    data = model.getDataA()
    workbook = NEW_EXCEL_WORKBOOK()
    worksheet = workbook.ADD_SHEET("A")
    // ... 20 lines of setup
    workbook.WRITE(response)

// In controller B — same 20 lines duplicated
FUNCTION exportAsExcel(request, response):
    data = model.getDataB()
    workbook = NEW_EXCEL_WORKBOOK()
    worksheet = workbook.ADD_SHEET("B")
    // ... same 20 lines
    workbook.WRITE(response)
```

**After:**

```pseudocode
// utils/exporter.js
FUNCTION exportToExcel(response, sheetName, columns, rows, filename):
    workbook = NEW_EXCEL_WORKBOOK()
    worksheet = workbook.ADD_SHEET(sheetName)
    worksheet.HEADERS = columns
    rows.FOREACH(row => worksheet.ADD_ROW(row))
    workbook.WRITE(response)

// In any controller:
exporter.exportToExcel(response, "A", headers, data, "report.xlsx")
```

---

### 5. Address Performance & Security Issues

#### 5.1 Parameterize Queries (SQL Injection Prevention)

Never use string concatenation or interpolation when building database query strings with user input. Use parameter binding supported by your database client/ORM.

**Before (Vulnerable SQL injection):**
```pseudocode
// JS/TS concatenation vulnerability
query = "SELECT * FROM users WHERE email = '" + request.body.email + "' AND status = 'active'"
results = await db.query(query)
```

**After (Secure Parameterized query):**
```pseudocode
// Use placeholder bindings (?, $1, :name, etc. depending on SQL engine)
query = "SELECT * FROM users WHERE email = ? AND status = ?"
results = await db.query(query, [request.body.email, "active"])
```

#### 5.2 Resolve N+1 Queries (Eager Loading & Batching)

Avoid running database queries inside loops (such as `for` loops, `.map`, or `.forEach`). Instead, fetch relation records in a single batch query or use database joins.

**Before (N+1 database queries):**
```pseudocode
// 1 query to fetch posts
posts = await db.query("SELECT * FROM posts WHERE category = ?", [category])

// N queries to fetch authors
FOR post IN posts:
    post.author = await db.query("SELECT * FROM users WHERE id = ?", [post.authorId])
```

**After (Batch fetch / Eager preloading - keeps exact same JSON output shape):**
```pseudocode
posts = await db.query("SELECT * FROM posts WHERE category = ?", [category])

// Collect unique IDs and batch fetch relations in one query
authorIds = posts.MAP(p => p.authorId).FILTER_UNIQUE()

IF authorIds IS NOT EMPTY THEN
    authors = await db.query("SELECT * FROM users WHERE id IN (?)", [authorIds])
    authorMap = MAP_BY_KEY(authors, "id")
    
    // Map relations back synchronously in memory
    FOR post IN posts:
        post.author = authorMap.GET(post.authorId)
```

---

### 6. Refactoring Checklist

Use this checklist before, during, and after every refactoring session to ensure nothing breaks.

#### Scope
- [ ] Refactor scope is clearly defined
- [ ] Affected endpoints/modules are listed
- [ ] No unrelated feature changes included

#### Contract Safety
- [ ] Request structure is unchanged (strict query/param/body compliance)
- [ ] Response structure is unchanged (strict JSON body shape compliance)
- [ ] Status codes are unchanged
- [ ] Error format is unchanged (validation errors mapped to the existing error shape)

#### Business Logic Safety
- [ ] Business logic is preserved
- [ ] Validation rules are preserved (or strengthened securely)
- [ ] Permission checks are preserved
- [ ] Database behavior is preserved
- [ ] External service behavior is preserved

#### Code Structure
- [ ] Controller responsibilities are clear
- [ ] Service/use case responsibilities are clear
- [ ] Repository/model responsibilities are clear
- [ ] Large functions are split where appropriate
- [ ] Module boundaries are clear

#### Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] API tests pass
- [ ] Regression scenarios are tested

#### Review
- [ ] Risk areas are documented
- [ ] Rollback plan is available
- [ ] CI/CD passes

---

## Integration with audit-api

Use this skill after an `audit-api` pass to clean up the code that remains. The typical flow is:

1. **audit-api** → Inventory, cross-reference, flag dead endpoints, check security/performance leaks.
2. **refactor-api** → Standardize error handling/validation wrappers, de-dup, parameterize queries, batch N+1 loops.

During a normal development cycle, this skill can be used as a PR review checkpoint to verify that new code follows best practices before merging.

## Gotchas

- **Response shape changes are invisible to you but break the frontend.** A model that returns `{ status, data, metadata, flags }` has extra keys the frontend depends on. Changing to just `{ status, data }` breaks them. Always verify.
- **Don't run one-shot search-replace on model files.** The model layer accumulates the most tacit knowledge about response shapes. Trace each one manually.

## Troubleshooting

- **"The handler file is enormous":** Delegate error standardization in chunks — do one routing file at a time, regression-testing between each.
- **"There's no test suite":** Manual verification after each change: fire a curl request to confirm the response shape is unchanged.