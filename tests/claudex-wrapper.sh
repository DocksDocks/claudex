#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

CONFIG_DIR="$TEST_HOME/.config/claudex"
BIN_DIR="$TEST_HOME/.local/bin"
PROJECTS_DIR="$TEST_HOME/projects"
OTHER_DIR="$TEST_HOME/other"
mkdir -p "$CONFIG_DIR" "$BIN_DIR" "$PROJECTS_DIR" "$OTHER_DIR"

printf '%s\n' 'host: "127.0.0.1"' 'port: 8317' > "$CONFIG_DIR/cliproxyapi.yaml"
printf '%064d\n' 0 > "$CONFIG_DIR/client-token"
printf '{}\n' > "$CONFIG_DIR/claude-settings.json"
chmod 600 "$CONFIG_DIR"/*

cat > "$BIN_DIR/claudex-proxy" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$BIN_DIR/claude" <<'EOF'
#!/bin/sh
printf 'cwd=%s\n' "$PWD"
printf 'args='
printf '<%s>' "$@"
printf '\n'
EOF
chmod 700 "$BIN_DIR/claudex-proxy" "$BIN_DIR/claude"

from_home=$(
  cd "$TEST_HOME"
  env \
    HOME="$TEST_HOME" \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    XDG_BIN_HOME="$BIN_DIR" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    "$REPO_ROOT/bin/claudex" --help
)
case "$from_home" in
  *"cwd=$PROJECTS_DIR"*) ;;
  *) printf 'claudex did not leave HOME for the persistent project workspace\n' >&2; exit 1 ;;
esac
case "$from_home" in
  *'args='*'<--help>'*) ;;
  *) printf '%s\n' 'claudex did not preserve arguments after changing workspace' >&2; exit 1 ;;
esac

from_other=$(
  cd "$OTHER_DIR"
  env \
    HOME="$TEST_HOME" \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    XDG_BIN_HOME="$BIN_DIR" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    "$REPO_ROOT/bin/claudex" --help
)
case "$from_other" in
  *"cwd=$OTHER_DIR"*) ;;
  *) printf '%s\n' 'claudex changed a non-HOME working directory' >&2; exit 1 ;;
esac

printf '%s\n' 'claudex wrapper fixtures passed'
