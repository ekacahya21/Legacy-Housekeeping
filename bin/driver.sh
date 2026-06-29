#!/usr/bin/env bash
# Legacy API Housekeeping Driver
# Usage: driver.sh <command> [args...]
# Commands:
#   inventory <src-dir>   — List all route/handler mappings
#   endpoints <src-dir>   — List all endpoint declarations (HTTP-verb, path, handler)
#   handlers  <src-dir>   — List all handler/controller functions and their file locations
#   models    <src-dir>   — List all model/data-access functions
#   crossref  <src-dir> <client-dirs...> — Cross-reference endpoints with client code
#   check-models <src-dir> — Find models that accept (request, response) instead of just request
#   list-files <src-dir>  — List all source files grouped by layer
#   check-security <src-dir> — Scan for raw SQL injection and missing guards
#   check-performance <src-dir> — Scan for N+1 loop queries & sync event loop blocks

set -euo pipefail

inventory() {
  local src="$1"
  echo "=== ENDPOINTS ==="
  echo ""

  # Try to find route/endpoint files by common patterns
  echo "--- Route files found ---"
  local route_files=()
  while IFS= read -r -d '' f; do
    route_files+=("$f")
    echo "  $f"
  done < <(find "$src" -type f \( \
    -name '*route*' -o \
    -name '*router*' -o \
    -name '*endpoint*' -o \
    -name '*handler*' \
  \) ! -path '*/node_modules/*' ! -path '*/__pycache__/*' ! -path '*/.git/*' ! -path '*/vendor/*' ! -path '*/dist/*' ! -path '*/build/*' -print0 2>/dev/null || true)
  echo ""

  echo "--- Controller/Handler files found ---"
  local handler_files=()
  while IFS= read -r -d '' f; do
    handler_files+=("$f")
    echo "  $f"
  done < <(find "$src" -type f \( \
    -name '*controller*' -o \
    -name '*handler*' -o \
    -name '*service*' \
  \) ! -path '*/node_modules/*' ! -path '*/__pycache__/*' ! -path '*/.git/*' ! -path '*/vendor/*' ! -path '*/dist/*' ! -path '*/build/*' -print0 2>/dev/null || true)
  echo ""

  echo "--- Model / Data-access files found ---"
  local model_files=()
  while IFS= read -r -d '' f; do
    model_files+=("$f")
    echo "  $f"
  done < <(find "$src" -type f \( \
    -name '*model*' -o \
    -name '*dal*' -o \
    -name '*repository*' -o \
    -name '*db*' -o \
    -name '*dao*' \
  \) ! -path '*/node_modules/*' ! -path '*/__pycache__/*' ! -path '*/.git/*' ! -path '*/vendor/*' ! -path '*/dist/*' ! -path '*/build/*' -print0 2>/dev/null || true)
}

endpoints() {
  local src="$1"
  echo "# Endpoint Inventory"

  # Search for HTTP method patterns across multiple languages
  echo ""
  echo "## JavaScript / TypeScript (Express, Koa, Fastify)"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=dist --exclude-dir=build "(get|post|put|patch|delete|head|options)\s*\(" "$src" \
    --include='*.js' --include='*.ts' 2>/dev/null \
    | grep -E "router\.|app\.|route\." \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Python (Django, Flask, FastAPI)"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=__pycache__ "@(app|router|blueprint|api)\.(get|post|put|patch|delete|route)\(" "$src" \
    --include='*.py' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Go (net/http, Gin, Echo, Chi)"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "\.(GET|POST|PUT|PATCH|DELETE|HandleFunc|Handle)\(" "$src" \
    --include='*.go' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Java (Spring annotations)"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "@(GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\(" "$src" \
    --include='*.java' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Ruby (Rails routes)"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "^(get|post|put|patch|delete|resources|resource)\s+" "$src" \
    --include='*.rb' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
}

handlers() {
  local src="$1"
  echo "# Handler / Controller Index"

  echo ""
  echo "## JavaScript exports"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "exports\.\w+\s*=" "$src" \
    --include='*.js' 2>/dev/null \
    | grep -iE "controller|handler" \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Python async/sync handlers"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=__pycache__ "^(async\s+)?def\s+\w+" "$src" \
    --include='*.py' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Go exported functions"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "^func [A-Z]\w+" "$src" \
    --include='*.go' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Java methods"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "public\s+\w+\s+\w+\s*\(" "$src" \
    --include='*.java' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
}

models() {
  local src="$1"
  echo "# Model / Data-Access Index"

  echo ""
  echo "## JavaScript exports"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "exports\.\w+\s*=" "$src" \
    --include='*.js' 2>/dev/null \
    | grep -iE "model|dal|repo|db" \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Python classes / functions"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=__pycache__ "^(class|def)\s+\w+" "$src" \
    --include='*.py' 2>/dev/null \
    | grep -iE "model|dal|repo|repository|query" \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "## Go types / structs"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "^type \w+ (struct|interface)" "$src" \
    --include='*.go' 2>/dev/null \
    | grep -iE "model|repo|store|db" \
    | sed 's/^/\t/' || echo "  (none found)"
}

crossref() {
  local src="$1"
  shift
  local client_dirs=("$@")

  # Generate endpoint name list
  local tmp_endpoints
  tmp_endpoints=$(mktemp)

  grep -rohE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "\"[a-zA-Z0-9_/-]+\"" "$src" 2>/dev/null \
    | tr -d '"' \
    | sort -u \
    > "$tmp_endpoints"

  echo "# Cross-Reference: Endpoints vs Client Usage"
  echo ""

  if [ ${#client_dirs[@]} -eq 0 ]; then
    echo "No client directories provided. Hit counts from source only:"
    echo ""
    while IFS= read -r ep; do
      local count
      count=$(grep -rF --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "$ep" "$src" 2>/dev/null | wc -l)
      echo "  $ep → $count references in source"
    done < "$tmp_endpoints"
    echo ""
    echo "Usage: driver.sh crossref <src> <client-dir1> [client-dir2 ...]"
    echo "This will search client/frontend repos for endpoint usage."
  else
    while IFS= read -r ep; do
      local src_count=0
      local client_hits=""

      src_count=$(grep -rF --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "$ep" "$src" 2>/dev/null | wc -l)

      for cd in "${client_dirs[@]}"; do
        local hits
        hits=$(grep -rF --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "$ep" "$cd" 2>/dev/null | head -5 || true)
        if [ -n "$hits" ]; then
          client_hits="${client_hits}  $cd: FOUND${NL}"
        fi
      done

      echo "  $ep"
      echo "    Source refs: $src_count"
      if [ -n "$client_hits" ]; then
        echo "    Client usage:"
        echo "$client_hits" | sed 's/^/      /'
      else
        echo "    Client usage: NOT FOUND in any client dir"
      fi
      echo ""
    done < "$tmp_endpoints"
  fi

  rm -f "$tmp_endpoints"
}

check_models() {
  local src="$1"
  echo "# Check: Models accepting (request, response) instead of just request"
  echo ""

  # JavaScript / TypeScript
  echo "## JS/TS Functions taking 2+ params (potentially req, res)"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "exports\.\w+\s*=\s*\((req|request|res|response|ctx|context),\s*(req|request|res|response|ctx|context)" \
    "$src" --include='*.js' --include='*.ts' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found — good)"

  # Check for functions that call .json() or .send() inside model files
  echo ""
  echo "## Functions calling .json()/.send()/.write() inside model/data files"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "\.json\(|\.send\(|\.write\(" \
    "$src" --include='*.js' --include='*.ts' 2>/dev/null \
    | grep -iE "model|dal|repo|db" \
    | sed 's/^/\t/' || echo "  (none found — good)"

  # Python
  echo ""
  echo "## Python functions with response-writing (make_response, jsonify)"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=__pycache__ "make_response|jsonify|return.*Response" \
    "$src" --include='*.py' 2>/dev/null \
    | grep -iE "model|dal|repo|db" \
    | sed 's/^/\t/' || echo "  (none found — good)"

  # Java
  echo ""
  echo "## Java methods calling response.write / ResponseEntity in model layers"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "HttpServletResponse|ResponseEntity" \
    "$src" --include='*.java' 2>/dev/null \
    | grep -iE "model|dal|repo|dao|repository" \
    | sed 's/^/\t/' || echo "  (none found — good)"
}

list_files() {
  local src="$1"
  echo "# File Inventory by Layer"

  for layer in route controller model; do
    echo ""
    echo "## $layer files"
    find "$src" -type f \
      \( -iname "*${layer}*" \) \
      ! -path '*/node_modules/*' \
      ! -path '*/__pycache__/*' \
      ! -path '*/.git/*' \
      ! -path '*/vendor/*' \
      ! -path '*/dist/*' \
      ! -path '*/build/*' 2>/dev/null \
      | sort \
      | sed 's/^/\t/' || echo "  (none found)"
  done

  # Also show any catch-all utility files
  echo ""
  echo "## Utility files (utils, helpers, shared)"
  find "$src" -type f \
    \( -iname '*util*' -o -iname '*helper*' -o -iname '*shared*' -o -iname '*common*' \) \
    ! -path '*/node_modules/*' \
    ! -path '*/__pycache__/*' \
    ! -path '*/.git/*' \
    ! -path '*/vendor/*' \
    ! -path '*/dist/*' \
    ! -path '*/build/*' 2>/dev/null \
    | sort \
    | sed 's/^/\t/' || echo "  (none found)"
}

check_security() {
  local src="$1"
  echo "# Security Compliance Audit"
  echo ""
  echo "## 1. Raw Query String Concatenation (Potential SQL Injection)"
  echo "Scanning for raw query strings concatenated with variables..."
  echo ""
  
  # JS/TS check
  echo "### JS/TS patterns:"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=dist --exclude-dir=build "(SELECT|INSERT|UPDATE|DELETE).*\+\s*\w+|\`.*(SELECT|INSERT|UPDATE|DELETE).*\$\{.*\}\`" "$src" \
    --include='*.js' --include='*.ts' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
    
  # Python check
  echo ""
  echo "### Python patterns:"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=__pycache__ "f\"(SELECT|INSERT|UPDATE|DELETE).*\{|\"(SELECT|INSERT|UPDATE|DELETE).*\" \*\s*\w+|\"(SELECT|INSERT|UPDATE|DELETE).*\"\s*%\s*\w+|\.execute\(\"(SELECT|INSERT|UPDATE|DELETE).*\.format\(" "$src" \
    --include='*.py' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
    
  # Go check
  echo ""
  echo "### Go patterns:"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "Sprintf\(\"(SELECT|INSERT|UPDATE|DELETE).*%[s|d|v|w]" "$src" \
    --include='*.go' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
    
  echo ""
  echo "## 2. Route Authentication Guard Verification"
  echo "Listing all endpoints and surrounding context (verify if authentication middleware/guard is applied):"
  echo ""
  
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__ "(router\.|app\.|route\.)(get|post|put|patch|delete)\(|@(app|router)\.(get|post|put|patch|delete)\(|@(GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\(" "$src" 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
}

check_performance() {
  local src="$1"
  echo "# Performance Audit"
  echo ""
  echo "## 1. Async Operations Inside Loops (Potential N+1 Queries)"
  echo "Scanning for await or query executions inside map/forEach/for loops..."
  echo ""
  
  echo "### JS/TS Async Callbacks (map/forEach/filter with async):"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "\.(map|forEach|filter|reduce)\(\s*async" "$src" \
    --include='*.js' --include='*.ts' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
    
  echo ""
  echo "### JS/TS await inside loops:"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "await\s+\w+\.(find|query|save|create|update|delete|select|where)" "$src" \
    --include='*.js' --include='*.ts' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"

  echo ""
  echo "### Python database queries in loops:"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=__pycache__ "for\s+\w+\s+in\s+.*:" "$src" --include='*.py' 2>/dev/null \
    | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        if sed -n "$((line_num+1)),$((line_num+5))p" "$file" 2>/dev/null | grep -qE "\.execute\(|\.query\(|session\.query|\.filter\("; then
          echo "  $file:$line_num - Possible query inside loop: $(echo "$line" | cut -d: -f3-)"
        fi
      done || echo "  (none found)"
      
  echo ""
  echo "### Go queries inside loops:"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "for\s+.*\{" "$src" --include='*.go' 2>/dev/null \
    | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        if sed -n "$((line_num+1)),$((line_num+5))p" "$file" 2>/dev/null | grep -qE "Query\(|QueryRow\(|Exec\(|Find\("; then
          echo "  $file:$line_num - Possible query inside loop: $(echo "$line" | cut -d: -f3-)"
        fi
      done || echo "  (none found)"

  echo ""
  echo "## 2. Blocking Synchronous Calls (Event Loop Blockers)"
  echo "Scanning for synchronous/blocking CPU-intensive operations in JS/TS:"
  grep -rnE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor "fs\.readFileSync|fs\.writeFileSync|JSON\.stringify\([^)]+\)\.length|crypto\.pbkdf2Sync|bcrypt\.hashSync|bcrypt\.compareSync" "$src" \
    --include='*.js' --include='*.ts' 2>/dev/null \
    | sed 's/^/\t/' || echo "  (none found)"
}

# Main dispatch
command="${1:-help}"
shift || true

case "$command" in
  inventory)
    [ $# -ge 1 ] || { echo "Usage: $0 inventory <src-dir>"; exit 1; }
    inventory "$1"
    ;;
  endpoints)
    [ $# -ge 1 ] || { echo "Usage: $0 endpoints <src-dir>"; exit 1; }
    endpoints "$1"
    ;;
  handlers)
    [ $# -ge 1 ] || { echo "Usage: $0 handlers <src-dir>"; exit 1; }
    handlers "$1"
    ;;
  models)
    [ $# -ge 1 ] || { echo "Usage: $0 models <src-dir>"; exit 1; }
    models "$1"
    ;;
  crossref)
    [ $# -ge 1 ] || { echo "Usage: $0 crossref <src-dir> [client-dir ...]"; exit 1; }
    src="$1"; shift
    crossref "$src" "$@"
    ;;
  check-models)
    [ $# -ge 1 ] || { echo "Usage: $0 check-models <src-dir>"; exit 1; }
    check_models "$1"
    ;;
  list-files)
    [ $# -ge 1 ] || { echo "Usage: $0 list-files <src-dir>"; exit 1; }
    list_files "$1"
    ;;
  check-security)
    [ $# -ge 1 ] || { echo "Usage: $0 check-security <src-dir>"; exit 1; }
    check_security "$1"
    ;;
  check-performance)
    [ $# -ge 1 ] || { echo "Usage: $0 check-performance <src-dir>"; exit 1; }
    check_performance "$1"
    ;;
  help|*)
    echo "Legacy API Housekeeping Driver"
    echo ""
    echo "Usage:"
    echo "  $0 inventory        <src-dir>       — List all route/handler/model files"
    echo "  $0 endpoints        <src-dir>       — List all endpoint declarations"
    echo "  $0 handlers         <src-dir>       — List all handler/controller functions"
    echo "  $0 models           <src-dir>       — List all model/data-access functions"
    echo "  $0 crossref         <src-dir> [client...] — Cross-ref endpoints with clients"
    echo "  $0 check-models     <src-dir>       — Find models leaking HTTP concerns"
    echo "  $0 list-files       <src-dir>       — List source files by layer"
    echo "  $0 check-security   <src-dir>       — Scan for raw SQL injection and missing guards"
    echo "  $0 check-performance <src-dir>      — Scan for N+1 loop queries & sync event loop blocks"
    echo "  $0 help                             — This message"
    ;;
esac
