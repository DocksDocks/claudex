#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

STATE_DIR="$TEST_HOME/.local/state/claudex"
AUTH_DIR="$TEST_HOME/.local/share/claudex/auth"
mkdir -p "$STATE_DIR" "$AUTH_DIR"
chmod 700 "$STATE_DIR" "$AUTH_DIR"
printf '{}\n' > "$AUTH_DIR/codex-primary.json"
chmod 600 "$AUTH_DIR/codex-primary.json"

reset_at=$(( $(date +%s) + 86400 ))
input='{"model":{"display_name":"gpt-5.6-sol"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":25,"context_window_size":1000000}}'

render_input() {
  printf '%s\n' "$1" |
    env \
      HOME="$TEST_HOME" \
      CLAUDEX_STATUSLINE=1 \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=468000 \
      "$REPO_ROOT/bin/claudex-statusline"
}

render() {
  render_input "$input"
}

context_372=$(printf '%s\n' \
  '{"model":{"display_name":"gpt-5.6-sol"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":25,"context_window_size":372000}}' |
  env \
    HOME="$TEST_HOME" \
    CLAUDEX_STATUSLINE=1 \
    CLAUDE_CODE_AUTO_COMPACT_WINDOW=372000 \
    "$REPO_ROOT/bin/claudex-statusline")
case "$context_372" in
  *'ctx 25%'*'(93k/372k)'*) ;;
  *) printf '%s\n' '372k claudex context window was not rendered correctly' >&2; exit 1 ;;
esac

printf '{"fetched_at":%s,"windows":[{"window_seconds":604800,"used_percent":36,"reset_at":%s}]}\n' \
  "$(date +%s)" "$reset_at" > "$STATE_DIR/usage.json"
weekly_only=$(render)
case "$weekly_only" in
  *'7d 36%'*) ;;
  *) printf '%s\n' 'weekly-only fixture did not render 7d usage' >&2; exit 1 ;;
esac
case "$weekly_only" in
  *'5h '*) printf '%s\n' 'weekly-only fixture incorrectly rendered 5h usage' >&2; exit 1 ;;
  *) ;;
esac

printf '{"fetched_at":%s,"windows":[{"window_seconds":18000,"used_percent":12,"reset_at":%s},{"window_seconds":604800,"used_percent":36,"reset_at":%s}]}\n' \
  "$(date +%s)" "$reset_at" "$reset_at" > "$STATE_DIR/usage.json"
both_windows=$(render)
case "$both_windows" in
  *'5h 12%'*'7d 36%'*) ;;
  *) printf '%s\n' 'dual-window fixture did not render both windows in order' >&2; exit 1 ;;
esac

stale_at=$(( $(date +%s) - 901 ))
printf '{"fetched_at":%s,"windows":[{"window_seconds":604800,"used_percent":91,"reset_at":%s}]}\n' \
  "$stale_at" "$reset_at" > "$STATE_DIR/usage.json"
stale_cache=$(render)
case "$stale_cache" in
  *'7d 91%'*) printf '%s\n' 'stale usage cache was rendered' >&2; exit 1 ;;
  *) ;;
esac

printf '{"fetched_at":%s,"windows":[{"window_seconds":604800,"used_percent":42,"reset_at":%s}]}\n' \
  "$(date +%s)" "$reset_at" > "$STATE_DIR/usage.json"
printf '{}\n' > "$AUTH_DIR/codex-secondary.json"
chmod 600 "$AUTH_DIR/codex-secondary.json"
ambiguous_auth=$(render)
case "$ambiguous_auth" in
  *'7d 42%'*) printf '%s\n' 'usage rendered with multiple OAuth credentials' >&2; exit 1 ;;
  *) ;;
esac
rm -f "$AUTH_DIR/codex-secondary.json"

rm -f "$AUTH_DIR/codex-primary.json"
missing_auth=$(render)
case "$missing_auth" in
  *'7d 42%'*) printf '%s\n' 'usage rendered without an OAuth credential' >&2; exit 1 ;;
  *) ;;
esac
printf '{}\n' > "$AUTH_DIR/codex-primary.json"
chmod 600 "$AUTH_DIR/codex-primary.json"

injected_osc=$'\033]8;;https://evil.example\a'
malicious_input=$(jq -cn \
  --arg model "gpt-5.6-sol${injected_osc}" \
  --arg dir $'/tmp/unsafe\033[31m-directory' \
  '{model:{display_name:$model},workspace:{current_dir:$dir}}')
sanitized=$(render_input "$malicious_input")
case "$sanitized" in
  *"$injected_osc"*) printf '%s\n' 'model terminal control sequence was not sanitized' >&2; exit 1 ;;
  *) ;;
esac
injected_csi=$'\033[31m'
case "$sanitized" in
  *"unsafe${injected_csi}-directory"*) printf '%s\n' 'directory terminal control sequence was not sanitized' >&2; exit 1 ;;
  *) ;;
esac

printf '%s\n' 'statusline fixtures passed'
