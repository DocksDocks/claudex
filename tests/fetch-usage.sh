#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

AUTH_DIR="$TEST_HOME/.local/share/claudex/auth"
STATE_DIR="$TEST_HOME/.local/state/claudex"
FAKE_BIN="$TEST_HOME/fake-bin"
mkdir -p "$AUTH_DIR" "$STATE_DIR" "$FAKE_BIN"
chmod 700 "$AUTH_DIR" "$STATE_DIR" "$FAKE_BIN"

REAL_JQ=$(command -v jq)
export REAL_JQ

cat > "$FAKE_BIN/jq" <<'EOF'
#!/bin/sh
case "${2:-}" in
  '.access_token // empty') printf '%s\n' 'test-access-token'; exit 0 ;;
  '.account_id // empty') printf '%s\n' 'test-account-id'; exit 0 ;;
esac
exec "$REAL_JQ" "$@"
EOF

cat > "$FAKE_BIN/curl" <<'EOF'
#!/bin/sh
output=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '-o' ]; then
    shift
    output=$1
  fi
  shift
done
[ -n "$output" ] || exit 1
printf '%s\n' '{"rate_limit":{"primary_window":null,"secondary_window":{"limit_window_seconds":604800,"used_percent":37,"reset_at":2000000000}}}' > "$output"
EOF
chmod 700 "$FAKE_BIN/jq" "$FAKE_BIN/curl"

printf '{}\n' > "$AUTH_DIR/codex-primary.json"
chmod 600 "$AUTH_DIR/codex-primary.json"
env HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" "$REPO_ROOT/bin/claudex-fetch-usage"
jq -e '.windows == [{"window_seconds":604800,"used_percent":37,"reset_at":2000000000}]' \
  "$STATE_DIR/usage.json" >/dev/null

rm -f "$STATE_DIR/usage.json"
printf '{}\n' > "$AUTH_DIR/codex-secondary.json"
chmod 600 "$AUTH_DIR/codex-secondary.json"
env HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" "$REPO_ROOT/bin/claudex-fetch-usage"
[ ! -e "$STATE_DIR/usage.json" ] || {
  printf '%s\n' 'usage fetch proceeded with multiple OAuth credentials' >&2
  exit 1
}

printf '%s\n' 'usage fetch fixtures passed'
