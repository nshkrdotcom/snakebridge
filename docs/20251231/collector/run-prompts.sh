#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROMPTS_DIR="$SCRIPT_DIR"
STATE_DIR="$PROJECT_ROOT/logs/snakebridge-v0.8.7-mvp"
LOG_DIR="$STATE_DIR/logs-$(date +%Y%m%d-%H%M%S)"
COMPLETED_FILE="$STATE_DIR/completed.txt"

# SnakeBridge v0.8.7 MVP Critical Fixes
# Prompts 1, 2, 3 can run independently
# Prompt 4 depends on prompts 2 and 3
PROMPTS=(
  "prompt-01-registry-cleanup.md"
  "prompt-02-session-consistency.md"
  "prompt-03-error-handling.md"
  "prompt-04-docs-api-alignment.md"
)

if ! command -v claude >/dev/null 2>&1; then
  echo "[ERROR] claude is not on PATH"
  exit 1
fi

# Handle --reset flag
if [[ "${1:-}" == "--reset" ]]; then
  echo "Resetting completion state..."
  rm -f "$COMPLETED_FILE"
  echo "Done. Run without --reset to start fresh."
  exit 0
fi

# Handle --status flag
if [[ "${1:-}" == "--status" ]]; then
  echo "Completion status:"
  echo "=================="
  if [[ -f "$COMPLETED_FILE" ]]; then
    echo "Completed prompts:"
    cat "$COMPLETED_FILE" | while read -r line; do echo "  ✓ $line"; done
    echo ""
    echo "Remaining prompts:"
    for p in "${PROMPTS[@]}"; do
      name="$(basename "$p" .md)"
      if ! grep -qx "$name" "$COMPLETED_FILE" 2>/dev/null; then
        echo "  - $name"
      fi
    done
  else
    echo "No prompts completed yet."
  fi
  exit 0
fi

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"
touch "$COMPLETED_FILE"
cd "$PROJECT_ROOT"

is_completed() {
  local name="$1"
  grep -qx "$name" "$COMPLETED_FILE" 2>/dev/null
}

mark_completed() {
  local name="$1"
  echo "$name" >> "$COMPLETED_FILE"
}

COMPLETED_COUNT=$(wc -l < "$COMPLETED_FILE" | tr -d ' ')
REMAINING_COUNT=$((${#PROMPTS[@]} - COMPLETED_COUNT))

echo "SnakeBridge v0.8.7 MVP Critical Fixes Runner"
echo "============================================"
echo "Project root:  $PROJECT_ROOT"
echo "Prompts dir:   $PROMPTS_DIR"
echo "Log dir:       $LOG_DIR"
echo "State file:    $COMPLETED_FILE"
echo "Total prompts: ${#PROMPTS[@]}"
echo "Completed:     $COMPLETED_COUNT"
echo "Remaining:     $REMAINING_COUNT"
echo "Mode: AUTONOMOUS (--dangerously-skip-permissions)"
echo "Output: JSON (--output-format json)"
echo ""
echo "Usage: $0 [--reset|--status]"
echo "  --reset   Clear completion state and start fresh"
echo "  --status  Show which prompts are completed/remaining"
echo ""

SUCCESSFUL=()
FAILED=()

run_prompt() {
  local prompt_file="$1"
  local prompt_name
  local log_file
  local prompt_content

  prompt_name="$(basename "$prompt_file" .md)"
  log_file="$LOG_DIR/${prompt_name}.log"
  prompt_content="$(cat "$prompt_file")"

  echo ""
  echo "------------------------------------------------------------"
  echo "[$(date '+%H:%M:%S')] Starting: $prompt_name"
  echo "------------------------------------------------------------"
  echo ""
  echo "[Starting claude for $prompt_name...]"
  echo ""

  if command -v stdbuf >/dev/null 2>&1; then
    if stdbuf -oL -eL claude -p "$prompt_content" --dangerously-skip-permissions --output-format json 2>&1 | tee "$log_file"; then
      SUCCESSFUL+=("$prompt_name")
      return 0
    else
      FAILED+=("$prompt_name")
      return 1
    fi
  else
    if claude -p "$prompt_content" --dangerously-skip-permissions --output-format json 2>&1 | tee "$log_file"; then
      SUCCESSFUL+=("$prompt_name")
      return 0
    else
      FAILED+=("$prompt_name")
      return 1
    fi
  fi
}

SKIPPED=()

for prompt_name in "${PROMPTS[@]}"; do
  prompt_file="$PROMPTS_DIR/$prompt_name"
  base_name="$(basename "$prompt_name" .md)"

  if [ ! -f "$prompt_file" ]; then
    echo "[WARN] Prompt $prompt_name not found, skipping"
    continue
  fi

  if is_completed "$base_name"; then
    echo "[SKIP] $base_name (already completed)"
    SKIPPED+=("$base_name")
    continue
  fi

  if run_prompt "$prompt_file"; then
    echo ""
    echo "[$(date '+%H:%M:%S')] Completed: $base_name"
    mark_completed "$base_name"
  else
    echo ""
    echo "[ERROR] $base_name failed (see log in $LOG_DIR)"
    echo ""
    echo "To retry, just run the script again - it will resume from this prompt."
    echo "To start fresh, run: $0 --reset"
  fi
done

echo ""
echo "============================================================"
echo "Summary - $(date)"
echo "============================================================"

if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo "Skipped (${#SKIPPED[@]} - already completed):"
  for name in "${SKIPPED[@]}"; do
    echo "  - $name"
  done
fi

if [ ${#SUCCESSFUL[@]} -gt 0 ]; then
  echo ""
  echo "Successful this run (${#SUCCESSFUL[@]}):"
  for name in "${SUCCESSFUL[@]}"; do
    echo "  ✓ $name"
  done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "Failed (${#FAILED[@]}):"
  for name in "${FAILED[@]}"; do
    echo "  ✗ $name"
  done
fi

echo ""
echo "Logs:  $LOG_DIR"
echo "State: $COMPLETED_FILE"
echo ""
echo "Commands:"
echo "  $0           # Resume from where you left off"
echo "  $0 --status  # Check progress"
echo "  $0 --reset   # Start fresh"

if [ ${#FAILED[@]} -gt 0 ]; then
  exit 1
fi

exit 0
