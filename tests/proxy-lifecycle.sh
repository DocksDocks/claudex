#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
proxy_pid=''
cleanup() {
  [ -z "$proxy_pid" ] || kill "$proxy_pid" 2>/dev/null || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

CONFIG_DIR="$TEST_ROOT/config/claudex"
STATE_DIR="$TEST_ROOT/state/claudex"
BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$BIN_DIR"
chmod 700 "$CONFIG_DIR" "$STATE_DIR" "$BIN_DIR"

printf '%s\n' 'host: "127.0.0.1"' 'port: 8317' > "$CONFIG_DIR/cliproxyapi.yaml"
cp /bin/sh "$BIN_DIR/cli-proxy-api"
chmod 700 "$BIN_DIR/cli-proxy-api"

cat > "$BIN_DIR/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 700 "$BIN_DIR/curl"

"$BIN_DIR/cli-proxy-api" -c 'trap "exit 0" TERM INT; while :; do sleep 1; done' \
  -config "$CONFIG_DIR/cliproxyapi.yaml" &
proxy_pid=$!

output=$(env \
  HOME="$TEST_ROOT/home" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  XDG_BIN_HOME="$BIN_DIR" \
  XDG_CONFIG_HOME="$TEST_ROOT/config" \
  XDG_STATE_HOME="$TEST_ROOT/state" \
  "$REPO_ROOT/bin/claudex-proxy" start 2>&1) || {
    printf '%s\n' "$output" >&2
    printf '%s\n' 'proxy helper did not adopt the matching orphan process' >&2
    exit 1
  }

recorded_pid=$(sed -n '1p' "$STATE_DIR/cliproxyapi.pid")
[ "$recorded_pid" = "$proxy_pid" ] || {
  printf 'expected adopted PID %s, got %s\n' "$proxy_pid" "$recorded_pid" >&2
  exit 1
}
kill -0 "$proxy_pid"

case "$output" in
  *"healthy on http://127.0.0.1:8317 (pid $proxy_pid)"*) ;;
  *) printf '%s\n' 'proxy adoption did not report the expected healthy process' >&2; exit 1 ;;
esac

printf '%s\n' 'proxy lifecycle fixtures passed'
