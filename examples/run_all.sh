#!/usr/bin/env bash
#
# Run all SnakeBridge examples sequentially
#

set -o pipefail

# Keep OTLP exporters disabled unless explicitly enabled by the caller.
export SNAKEPIT_ENABLE_OTLP="${SNAKEPIT_ENABLE_OTLP:-false}"
export SNAKEPIT_OTEL_CONSOLE="${SNAKEPIT_OTEL_CONSOLE:-false}"
export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-none}"
export OTEL_METRICS_EXPORTER="${OTEL_METRICS_EXPORTER:-none}"
export OTEL_LOGS_EXPORTER="${OTEL_LOGS_EXPORTER:-none}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Track timing
START_TIME=$(date +%s)
START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Print the SnakeBridge ASCII art
print_header() {
    echo -e "${GREEN}"
    cat << 'EOF'

   ███████╗███╗   ██╗ █████╗ ██╗  ██╗███████╗██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗
   ██╔════╝████╗  ██║██╔══██╗██║ ██╔╝██╔════╝██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
   ███████╗██╔██╗ ██║███████║█████╔╝ █████╗  ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗
   ╚════██║██║╚██╗██║██╔══██║██╔═██╗ ██╔══╝  ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝
   ███████║██║ ╚████║██║  ██║██║  ██╗███████╗██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
   ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝

                    ┌─────────────────────────────────────┐
                    │  Elixir  ←──── gRPC ────→  Python   │
                    └─────────────────────────────────────┘

EOF
    echo -e "${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                    SnakeBridge Examples Runner${NC} "
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_start_info() {
    echo -e "${BLUE}Started:${NC}  $START_TIMESTAMP"
    echo -e "${BLUE}Host:${NC}     $(hostname)"
    local elixir_info
    elixir_info=$(elixir --version 2>&1) || true
    echo -e "${BLUE}Elixir:${NC}   $(echo "$elixir_info" | head -1)"
    echo -e "${BLUE}Python:${NC}   $(python3 --version 2>&1)"
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

print_example_header() {
    local name=$1
    local num=$2
    local total=$3
    local top="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    local bottom="┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    local inner_width=$(( ${#top} - 2 ))
    local text="Example ${num}/${total}: ${name}"
    local content_len=$(( ${#text} + 1 ))

    if (( content_len > inner_width )); then
        local max_text=$(( inner_width - 1 ))
        if (( max_text > 3 )); then
            text="${text:0:$((max_text-3))}..."
        else
            text="${text:0:$max_text}"
        fi
        content_len=$(( ${#text} + 1 ))
    fi

    local padding=$(( inner_width - content_len ))
    echo ""
    echo -e "${MAGENTA}${top}${NC}"
    printf "%b %b%s%b%*s%b\n" \
        "${MAGENTA}┃${NC}" \
        "${BOLD}" \
        "${text}" \
        "${NC}" \
        "$padding" \
        "" \
        "${MAGENTA}┃${NC}"
    echo -e "${MAGENTA}${bottom}${NC}"
    echo ""
}

print_success() {
    local name=$1
    local duration=$2
    echo ""
    echo -e "${GREEN}✓ ${name} completed in ${duration}s${NC}"
}

print_failure() {
    local name=$1
    echo ""
    echo -e "${RED}✗ ${name} failed${NC}"
}

print_summary() {
    local end_time=$(date +%s)
    local end_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local total_duration=$((end_time - START_TIME))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                           SUMMARY${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Started:${NC}   $START_TIMESTAMP"
    echo -e "${BLUE}Finished:${NC}  $end_timestamp"
    echo -e "${BLUE}Duration:${NC}  ${minutes}m ${seconds}s (${total_duration} seconds)"
    echo ""
    echo -e "${BLUE}Examples Run:${NC}"
    for i in "${!EXAMPLE_NAMES[@]}"; do
        if [ "${EXAMPLE_RESULTS[$i]}" == "0" ]; then
            echo -e "  ${GREEN}✓${NC} ${EXAMPLE_NAMES[$i]} (${EXAMPLE_DURATIONS[$i]}s)"
        else
            echo -e "  ${RED}✗${NC} ${EXAMPLE_NAMES[$i]} (failed)"
        fi
    done
    echo ""

    local passed=0
    local failed=0
    for result in "${EXAMPLE_RESULTS[@]}"; do
        if [ "$result" == "0" ]; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}All ${passed} examples passed!${NC}"
    else
        echo -e "${YELLOW}Passed: ${passed}, Failed: ${failed}${NC}"
    fi
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}"
    cat << 'EOF'
   _____                      _      _       _
  / ____|                    | |    | |     | |
 | |     ___  _ __ ___  _ __ | | ___| |_ ___| |
 | |    / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \ |
 | |___| (_) | | | | | | |_) | |  __/ ||  __/_|
  \_____\___/|_| |_| |_| .__/|_|\___|\__\___(_)
                       | |
                       |_|
EOF
    echo -e "${NC}"
}

run_example() {
    local dir=$1
    local name=$(basename "$dir")
    local example_start=$(date +%s)

    cd "$dir"

    # Compile (deps already updated in upfront phase)
    echo -e "${YELLOW}Compiling...${NC}"
    if ! mix compile --quiet 2>&1; then
        EXAMPLE_RESULTS+=("1")
        EXAMPLE_DURATIONS+=("0")
        print_failure "$name"
        return 1
    fi

    # Run the demo
    echo -e "${YELLOW}Running demo...${NC}"
    echo ""

    if mix run --no-start -e "Demo.run" 2>&1; then
        local example_end=$(date +%s)
        local example_duration=$((example_end - example_start))
        EXAMPLE_RESULTS+=("0")
        EXAMPLE_DURATIONS+=("$example_duration")
        print_success "$name" "$example_duration"
        return 0
    else
        EXAMPLE_RESULTS+=("1")
        EXAMPLE_DURATIONS+=("0")
        print_failure "$name"
        return 1
    fi
}

run_script_example() {
    local script_path=$1
    local name=$(basename "$script_path")
    local example_start=$(date +%s)

    cd "$ROOT_DIR"

    echo -e "${YELLOW}Running script...${NC}"
    echo ""

    if elixir "$script_path" 2>&1; then
        local example_end=$(date +%s)
        local example_duration=$((example_end - example_start))
        EXAMPLE_RESULTS+=("0")
        EXAMPLE_DURATIONS+=("$example_duration")
        print_success "$name" "$example_duration"
        return 0
    else
        EXAMPLE_RESULTS+=("1")
        EXAMPLE_DURATIONS+=("0")
        print_failure "$name"
        return 1
    fi
}

# Arrays to track results
declare -a EXAMPLE_NAMES
declare -a EXAMPLE_RESULTS
declare -a EXAMPLE_DURATIONS

# Define examples to run (in order)
EXAMPLES=(
    "basic"
    "math_demo"
    "types_showcase"
    "error_showcase"
    "docs_showcase"
    "telemetry_showcase"
    "proof_pipeline"
    "twenty_libraries"
    "wrapper_args_example"
    "signature_showcase"
    "class_resolution_example"
    "class_constructor_example"
    "dynamic_dispatch_example"
    "session_lifecycle_example"
    "python_idioms_example"
    "protocol_integration_example"
    "streaming_example"
    "strict_mode_example"
    "universal_ffi_example"
)

print_deps_header() {
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}                    Updating Dependencies${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

update_all_deps() {
    print_deps_header

    local total=${#EXAMPLES[@]}
    local current=0
    local failed=0

    for example in "${EXAMPLES[@]}"; do
        ((current++))
        local example_dir="$SCRIPT_DIR/$example"

        if [ -d "$example_dir" ]; then
            printf "  [%2d/%d] %-30s " "$current" "$total" "$example"
            cd "$example_dir"

            # Update deps (quiet, but capture errors)
            if mix deps.get --quiet 2>&1 | grep -v "^$" > /tmp/deps_output_$$.txt 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                # Check if it's just a warning or actual error
                if mix deps.get 2>&1 | grep -q "error\|Error\|ERROR"; then
                    echo -e "${RED}✗${NC}"
                    ((failed++))
                else
                    echo -e "${GREEN}✓${NC}"
                fi
            fi
            rm -f /tmp/deps_output_$$.txt
        fi
    done

    echo ""
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}All dependencies updated successfully!${NC}"
    else
        echo -e "${YELLOW}Warning: $failed example(s) had dependency issues${NC}"
    fi
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────────${NC}"
}

# Main execution
main() {
    print_header
    print_start_info

    # Update all dependencies first
    update_all_deps

    local total=${#EXAMPLES[@]}
    local current=0

    for example in "${EXAMPLES[@]}"; do
        ((current++))
        local example_dir="$SCRIPT_DIR/$example"

        if [ -d "$example_dir" ]; then
            EXAMPLE_NAMES+=("$example")
            print_example_header "$example" "$current" "$total"
            run_example "$example_dir" || true
        elif [ -f "$example_dir" ]; then
            EXAMPLE_NAMES+=("$example")
            print_example_header "$example" "$current" "$total"
            run_script_example "$example_dir" || true
        else
            echo -e "${YELLOW}Skipping $example (path not found)${NC}"
            EXAMPLE_NAMES+=("$example")
            EXAMPLE_RESULTS+=("1")
            EXAMPLE_DURATIONS+=("0")
        fi
    done

    print_summary
}

# Run main
main "$@"
