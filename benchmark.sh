#!/usr/bin/env bash
# =============================================================================
# Gemma4 E4B Benchmark — Ollama + OpenCode + Symfony 8
# =============================================================================
# Usage:
#   ./benchmark.sh              # Full benchmark (5 scenarios × 3 runs)
#   ./benchmark.sh S1           # Single scenario
#   ./benchmark.sh S1 1         # Single scenario, single run
# =============================================================================

set -uo pipefail

PROJECT_DIR="/tmp/test-gemma4-symfony"
RESULTS_DIR="/tmp/gemma4-benchmark-results"
BASELINE=$(cat "$RESULTS_DIR/baseline_commit.txt")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="$RESULTS_DIR/$TIMESTAMP"
MODEL="ollama/gemma4-opencode"
RUNS_PER_SCENARIO=3
TIMEOUT_SECONDS=600

# Allow filtering by scenario and run
FILTER_SCENARIO="${1:-}"
FILTER_RUN="${2:-}"

mkdir -p "$RUN_DIR"

# =============================================================================
# SCENARIO DEFINITIONS
# =============================================================================

PROMPT_S1='Create a Doctrine entity App\Entity\Article in src/Entity/Article.php with the following properties: id (integer, auto-generated primary key), title (string, max 255, not nullable), content (text, not nullable), createdAt (datetime_immutable, not nullable), isPublished (boolean, default false). Use PHP 8 attributes for ORM mapping. Also create the corresponding repository App\Repository\ArticleRepository in src/Repository/ArticleRepository.php extending ServiceEntityRepository.'

PROMPT_S2='Create a controller App\Controller\ArticleController in src/Controller/ArticleController.php with two actions: (1) index() mapped to GET /articles that returns a Twig template article/index.html.twig with a hardcoded array of 3 articles (each with title and content), and (2) show(int $id) mapped to GET /articles/{id} that returns a Twig template article/show.html.twig showing a single article. Create both Twig templates extending base.html.twig. Use PHP 8 #[Route] attributes. The controller must extend AbstractController.'

PROMPT_S3='Create a service App\Service\SlugGenerator in src/Service/SlugGenerator.php with a method generateSlug(string $text): string that converts text to a URL-friendly slug (lowercase, replaces spaces and special characters with hyphens, removes consecutive hyphens, trims hyphens from start and end). Use Symfony String component (Symfony\Component\String\Slugger\SluggerInterface) injected via constructor. Then create a PHPUnit test App\Tests\Service\SlugGeneratorTest in tests/Service/SlugGeneratorTest.php that tests at least 4 cases: basic text, text with accents, text with special characters, and text with multiple spaces.'

PROMPT_S4='Create a Symfony Form type App\Form\ContactType in src/Form/ContactType.php with fields: name (TextType, required, min 2 max 100 chars), email (EmailType, required, valid email), subject (ChoiceType with choices General, Support, Partnership), message (TextareaType, required, min 10 chars). Add validation constraints using PHP 8 attributes on a new DTO App\DTO\ContactDTO in src/DTO/ContactDTO.php. Then create App\Controller\ContactController in src/Controller/ContactController.php with: (1) GET and POST /contact showing the form and handling submission, (2) a Twig template contact/index.html.twig rendering the form. On successful submission, add a flash message and redirect to the same page.'

PROMPT_S5='Create a complete CRUD for a Product entity with: (1) Entity App\Entity\Product with properties: id (int, auto PK), name (string 255, not blank), description (text, nullable), price (float, positive), category (string 100, not blank), createdAt (datetime_immutable). (2) Repository App\Repository\ProductRepository with a custom method findByCategory(string $category): array. (3) Form App\Form\ProductType mapping all editable fields. (4) Controller App\Controller\ProductController with routes: GET /products (list), GET /products/new (new form), POST /products/new (create), GET /products/{id} (show), GET /products/{id}/edit (edit form), POST /products/{id}/edit (update), POST /products/{id}/delete (delete). (5) Twig templates for all views in templates/product/. (6) A functional test App\Tests\Controller\ProductControllerTest that tests the index page returns 200. Use PHP 8 attributes everywhere.'

# Expected files per scenario (space-separated)
EXPECTED_S1="src/Entity/Article.php src/Repository/ArticleRepository.php"
EXPECTED_S2="src/Controller/ArticleController.php templates/article/index.html.twig templates/article/show.html.twig"
EXPECTED_S3="src/Service/SlugGenerator.php tests/Service/SlugGeneratorTest.php"
EXPECTED_S4="src/DTO/ContactDTO.php src/Form/ContactType.php src/Controller/ContactController.php templates/contact/index.html.twig"
EXPECTED_S5="src/Entity/Product.php src/Repository/ProductRepository.php src/Form/ProductType.php src/Controller/ProductController.php templates/product/index.html.twig templates/product/new.html.twig templates/product/show.html.twig templates/product/edit.html.twig tests/Controller/ProductControllerTest.php"

# Expected routes per scenario (space-separated, empty if none)
ROUTES_S1=""
ROUTES_S2="/articles /articles/{id}"
ROUTES_S3=""
ROUTES_S4="/contact"
ROUTES_S5="/products /products/new /products/{id} /products/{id}/edit /products/{id}/delete"

# Test files per scenario (empty if none)
TEST_S1=""
TEST_S2=""
TEST_S3="tests/Service/SlugGeneratorTest.php"
TEST_S4=""
TEST_S5="tests/Controller/ProductControllerTest.php"

# Has doctrine entities
DOCTRINE_S1="yes"
DOCTRINE_S2=""
DOCTRINE_S3=""
DOCTRINE_S4=""
DOCTRINE_S5="yes"

SCENARIOS="S1 S2 S3 S4 S5"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    echo "[$(date +%H:%M:%S)] $*"
}

reset_project() {
    cd "$PROJECT_DIR"
    git checkout -- . 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    rm -rf var/cache/* 2>/dev/null || true
    # Verify clean state
    local dirty
    dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$dirty" != "0" ]]; then
        log "WARNING: Project not clean after reset ($dirty dirty files)"
    fi
}

run_opencode() {
    local prompt="$1"
    local output_file="$2"
    local time_file="$3"

    cd "$PROJECT_DIR"
    /usr/bin/time -l \
        opencode run "$prompt" \
            -m "$MODEL" \
            --dir "$PROJECT_DIR" \
            --format json \
        > "$output_file" 2> "$time_file" || true
}

extract_tokens() {
    local json_file="$1"
    python3 -c "
import json, sys

tokens_in = 0
tokens_out = 0
tokens_total = 0
tokens_reasoning = 0
steps = 0
tool_calls = 0

with open('$json_file') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            evt = json.loads(line)
        except:
            continue
        etype = evt.get('type', '')
        if etype == 'step.finish' or etype == 'step_finish':
            part = evt.get('part', evt.get('data', {}))
            toks = part.get('tokens', {})
            tokens_in += toks.get('input', 0)
            tokens_out += toks.get('output', 0)
            tokens_total += toks.get('total', 0)
            tokens_reasoning += toks.get('reasoning', 0)
            steps += 1
        elif etype == 'tool.call' or etype == 'tool_call':
            tool_calls += 1

print(json.dumps({
    'input': tokens_in,
    'output': tokens_out,
    'total': tokens_total,
    'reasoning': tokens_reasoning,
    'steps': steps,
    'tool_calls': tool_calls
}))
" 2>/dev/null || echo '{"input":0,"output":0,"total":0,"reasoning":0,"steps":0,"tool_calls":0}'
}

extract_time() {
    local time_file="$1"
    python3 -c "
import re, json
with open('$time_file') as f:
    content = f.read()

# macOS /usr/bin/time -l format (handles both comma and dot decimal separators)
real_match = re.search(r'([\d,.]+)\s+real', content)
mem_match = re.search(r'(\d+)\s+maximum resident', content)

wall = float(real_match.group(1).replace(',', '.')) if real_match else 0.0
mem = int(mem_match.group(1)) if mem_match else 0

print(json.dumps({'wall_time_seconds': wall, 'peak_memory_bytes': mem}))
" 2>/dev/null || echo '{"wall_time_seconds":0,"peak_memory_bytes":0}'
}

check_timed_out() {
    local time_file="$1"
    local wall
    wall=$(python3 -c "
import re
with open('$time_file') as f:
    content = f.read()
m = re.search(r'([\d,.]+)\s+real', content)
print(float(m.group(1).replace(',', '.')) if m else 0)
" 2>/dev/null || echo "0")
    # If wall time >= timeout - 5, consider it timed out
    python3 -c "print('true' if float('$wall') >= ($TIMEOUT_SECONDS - 5) else 'false')"
}

# =============================================================================
# VALIDATION PIPELINE
# =============================================================================

validate() {
    local scenario="$1"
    local result_file="$2"

    cd "$PROJECT_DIR"

    local expected_var="EXPECTED_${scenario}"
    local routes_var="ROUTES_${scenario}"
    local test_var="TEST_${scenario}"
    local doctrine_var="DOCTRINE_${scenario}"

    local expected_files="${!expected_var}"
    local expected_routes="${!routes_var}"
    local test_file="${!test_var}"
    local has_doctrine="${!doctrine_var}"

    # --- File existence & PHP syntax ---
    local files_json="{"
    local all_exist=true
    local all_syntax=true
    local first=true

    for f in $expected_files; do
        [[ "$first" == "true" ]] && first=false || files_json="$files_json,"

        local exists=false
        local syntax=false

        if [[ -f "$PROJECT_DIR/$f" ]]; then
            exists=true
            if [[ "$f" == *.php ]]; then
                php -l "$PROJECT_DIR/$f" > /dev/null 2>&1 && syntax=true || syntax=false
            else
                syntax=true
            fi
        fi

        files_json="$files_json\"$f\":{\"exists\":$exists,\"syntax_valid\":$syntax}"
        [[ "$exists" == "false" ]] && all_exist=false
        [[ "$syntax" == "false" ]] && all_syntax=false
    done
    files_json="$files_json}"

    # --- Symfony lints ---
    local container_ok=false
    php bin/console lint:container --env=dev > /dev/null 2>&1 && container_ok=true

    local yaml_ok=false
    php bin/console lint:yaml config/ > /dev/null 2>&1 && yaml_ok=true

    local twig_ok=false
    php bin/console lint:twig templates/ > /dev/null 2>&1 && twig_ok=true

    # --- Doctrine mapping ---
    local doctrine_ok=null
    if [[ -n "$has_doctrine" ]]; then
        doctrine_ok=false
        php bin/console doctrine:mapping:info 2>&1 | grep -q "\[OK\]" && doctrine_ok=true
    fi

    # --- Routes ---
    local routes_json="[]"
    if [[ -n "$expected_routes" ]]; then
        local router_output
        router_output=$(php bin/console debug:router 2>/dev/null || echo "")
        routes_json="["
        local rfirst=true
        for r in $expected_routes; do
            [[ "$rfirst" == "true" ]] && rfirst=false || routes_json="$routes_json,"
            local found=false
            echo "$router_output" | grep -q "$r" && found=true
            routes_json="$routes_json{\"path\":\"$r\",\"registered\":$found}"
        done
        routes_json="$routes_json]"
    fi

    # --- PHPUnit ---
    local phpunit_json="null"
    if [[ -n "$test_file" && -f "$PROJECT_DIR/$test_file" ]]; then
        # For S5 functional tests, try creating the schema first
        if [[ "$scenario" == "S5" ]]; then
            APP_ENV=test php bin/console doctrine:schema:create --no-interaction > /dev/null 2>&1 || true
        fi

        local test_output
        local test_exit=0
        test_output=$(APP_ENV=test php bin/phpunit "$test_file" --no-coverage 2>&1) || test_exit=$?

        local tests_run=0
        local assertions=0
        tests_run=$(echo "$test_output" | grep -oE 'OK \([0-9]+' | grep -oE '[0-9]+' || echo "0")
        [[ -z "$tests_run" ]] && tests_run=0
        assertions=$(echo "$test_output" | grep -oE '[0-9]+ assertion' | grep -oE '[0-9]+' || echo "0")
        [[ -z "$assertions" ]] && assertions=0

        local pass=false
        [[ $test_exit -eq 0 ]] && pass=true

        phpunit_json="{\"pass\":$pass,\"tests\":$tests_run,\"assertions\":$assertions,\"exit_code\":$test_exit}"
    fi

    # --- PHP8 attributes count ---
    local attrs_json="{"
    local afirst=true
    for f in $expected_files; do
        if [[ "$f" == *.php && -f "$PROJECT_DIR/$f" ]]; then
            [[ "$afirst" == "true" ]] && afirst=false || attrs_json="$attrs_json,"
            local count
            count=$(grep -c '#\[' "$PROJECT_DIR/$f" 2>/dev/null)
            [[ -z "$count" ]] && count=0
            attrs_json="$attrs_json\"$f\":$count"
        fi
    done
    attrs_json="$attrs_json}"

    # --- Files actually created ---
    local files_created
    files_created=$(cd "$PROJECT_DIR" && { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u)
    local files_created_json
    files_created_json=$(echo "$files_created" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")

    # --- Write result ---
    cat > "$result_file" << VEOF
{
    "files": $files_json,
    "all_files_exist": $all_exist,
    "all_syntax_valid": $all_syntax,
    "lint_container": $container_ok,
    "lint_yaml": $yaml_ok,
    "lint_twig": $twig_ok,
    "doctrine_mapping_valid": $doctrine_ok,
    "routes": $routes_json,
    "phpunit": $phpunit_json,
    "php8_attributes": $attrs_json,
    "files_created": $files_created_json
}
VEOF
}

compute_score() {
    local validation_file="$1"
    python3 -c "
import json

with open('$validation_file') as f:
    v = json.load(f)

score = 0.0

# Files exist: 20 points
if v['all_files_exist']:
    score += 20

# Syntax valid: 20 points
if v['all_syntax_valid']:
    score += 20

# Container lint: 20 points
if v['lint_container']:
    score += 20

# Twig lint: 10 points
if v.get('lint_twig') is True or v.get('lint_twig') is None:
    score += 10

# Doctrine mapping: 10 points (or full if N/A)
dm = v.get('doctrine_mapping_valid')
if dm is None or dm == 'null':
    score += 10
elif dm is True:
    score += 10

# Routes: 10 points (proportional)
routes = v.get('routes', [])
if not routes or routes == 'null':
    score += 10
else:
    found = sum(1 for r in routes if r.get('registered'))
    score += 10 * (found / len(routes))

# PHPUnit: 10 points
pu = v.get('phpunit')
if pu is None or pu == 'null':
    score += 10
elif isinstance(pu, dict) and pu.get('pass'):
    score += 10

print(round(score, 1))
" 2>/dev/null || echo "0"
}

# =============================================================================
# MAIN LOOP
# =============================================================================

echo "========================================="
echo " Gemma4 E4B Benchmark - $TIMESTAMP"
echo " Model: $MODEL"
echo " Project: $PROJECT_DIR"
echo " Baseline: $BASELINE"
echo "========================================="
echo ""

for scenario in $SCENARIOS; do
    # Filter by scenario if specified
    [[ -n "$FILTER_SCENARIO" && "$scenario" != "$FILTER_SCENARIO" ]] && continue

    prompt_var="PROMPT_${scenario}"
    prompt="${!prompt_var}"

    log "=== Scenario $scenario ==="

    for run in $(seq 1 $RUNS_PER_SCENARIO); do
        # Filter by run if specified
        [[ -n "$FILTER_RUN" && "$run" != "$FILTER_RUN" ]] && continue

        RUN_RESULT_DIR="$RUN_DIR/${scenario}/run_${run}"
        mkdir -p "$RUN_RESULT_DIR"

        log "  Run $run/$RUNS_PER_SCENARIO - Reset project..."
        reset_project

        log "  Run $run/$RUNS_PER_SCENARIO - OpenCode running..."
        run_opencode "$prompt" \
            "$RUN_RESULT_DIR/opencode_output.jsonl" \
            "$RUN_RESULT_DIR/time_output.txt"

        # Check timeout
        local_timeout=$(check_timed_out "$RUN_RESULT_DIR/time_output.txt")

        log "  Run $run/$RUNS_PER_SCENARIO - Extracting metrics..."
        tokens=$(extract_tokens "$RUN_RESULT_DIR/opencode_output.jsonl")
        timing=$(extract_time "$RUN_RESULT_DIR/time_output.txt")

        # Save the text response for qualitative analysis
        python3 -c "
import json
texts = []
with open('$RUN_RESULT_DIR/opencode_output.jsonl') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            evt = json.loads(line)
            if evt.get('type') == 'text':
                texts.append(evt.get('part', {}).get('text', ''))
        except: pass
with open('$RUN_RESULT_DIR/response_text.md', 'w') as f:
    f.write('\n'.join(texts))
" 2>/dev/null || true

        log "  Run $run/$RUNS_PER_SCENARIO - Validating..."
        validate "$scenario" "$RUN_RESULT_DIR/validation.json"

        score=$(compute_score "$RUN_RESULT_DIR/validation.json")

        # Assemble final result
        cat > "$RUN_RESULT_DIR/result.json" << REOF
{
    "scenario": "$scenario",
    "run": $run,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "model": "$MODEL",
    "timed_out": $local_timeout,
    "timing": $timing,
    "tokens": $tokens,
    "validation": $(cat "$RUN_RESULT_DIR/validation.json"),
    "score": $score
}
REOF

        local_tokens_total=$(echo "$tokens" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
        local_wall=$(echo "$timing" | python3 -c "import json,sys; print(json.load(sys.stdin)['wall_time_seconds'])")

        log "  Run $run/$RUNS_PER_SCENARIO - Score: $score/100 | Tokens: $local_tokens_total | Time: ${local_wall}s | Timeout: $local_timeout"
        echo ""
    done
done

# =============================================================================
# AGGREGATE RESULTS
# =============================================================================

log "Aggregating results..."

# Collect all results from files
python3 -c "
import json, sys, math, glob

results = []
for fpath in sorted(glob.glob('$RUN_DIR/*/run_*/result.json')):
    with open(fpath) as f:
        results.append(json.load(f))

# Save all results
with open('$RUN_DIR/all_results.json', 'w') as f:
    json.dump(results, f, indent=2)

# Group by scenario
from collections import defaultdict
groups = defaultdict(list)
for r in results:
    groups[r['scenario']].append(r)

summary = []
for scenario in sorted(groups.keys()):
    runs = groups[scenario]
    scores = [r['score'] for r in runs]
    times = [r['timing']['wall_time_seconds'] for r in runs]
    tokens_out = [r['tokens']['output'] for r in runs]
    tokens_total = [r['tokens']['total'] for r in runs]
    steps = [r['tokens']['steps'] for r in runs]
    tool_calls = [r['tokens']['tool_calls'] for r in runs]

    mean_score = sum(scores) / len(scores) if scores else 0
    stddev = math.sqrt(sum((s - mean_score)**2 for s in scores) / len(scores)) if len(scores) > 1 else 0

    success_count = sum(1 for r in runs
        if r['validation']['all_files_exist']
        and r['validation']['all_syntax_valid']
        and r['validation']['lint_container'])

    summary.append({
        'scenario': scenario,
        'runs': len(runs),
        'success_rate': round(success_count / len(runs) * 100, 1),
        'mean_score': round(mean_score, 1),
        'stddev_score': round(stddev, 1),
        'scores': scores,
        'mean_wall_time': round(sum(times) / len(times), 1),
        'mean_tokens_total': round(sum(tokens_total) / len(tokens_total)),
        'mean_tokens_output': round(sum(tokens_out) / len(tokens_out)),
        'mean_steps': round(sum(steps) / len(steps), 1),
        'mean_tool_calls': round(sum(tool_calls) / len(tool_calls), 1),
        'timed_out_count': sum(1 for r in runs if r.get('timed_out')),
    })

with open('$RUN_DIR/summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

# Print summary table
print()
print('=' * 90)
print('SUMMARY')
print('=' * 90)
print(f'{\"Scenario\":<10} {\"Score\":<15} {\"Success\":<10} {\"Time\":<12} {\"Tokens Out\":<12} {\"Steps\":<8} {\"Tools\":<8}')
print('-' * 90)
for s in summary:
    print(f'{s[\"scenario\"]:<10} {s[\"mean_score\"]:.1f}/100 ±{s[\"stddev_score\"]:.1f}  {s[\"success_rate\"]:>5.0f}%     {s[\"mean_wall_time\"]:>7.1f}s    {s[\"mean_tokens_output\"]:>8}    {s[\"mean_steps\"]:>5.1f}   {s[\"mean_tool_calls\"]:>5.1f}')
print('=' * 90)
"

log "Results saved to: $RUN_DIR/"
log "Done!"
