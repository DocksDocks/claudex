#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

assert_contains() {
  local haystack=$1 needle=$2
  case "$haystack" in
    *"$needle"*) ;;
    *)
      printf 'expected output to contain: %s\n' "$needle" >&2
      printf '%s\n' 'captured output follows:' >&2
      printf '%s\n' "$haystack" >&2
      exit 1
      ;;
  esac
}

make_platform() {
  local bin_dir=$1 os=$2 arch=$3
  mkdir -p "$bin_dir"
  cat > "$bin_dir/uname" <<EOF
#!/bin/sh
case "\${1:-}" in
  -s) printf '%s\\n' '$os' ;;
  -m) printf '%s\\n' '$arch' ;;
  *) printf '%s\\n' '$os' ;;
esac
EOF
  chmod 700 "$bin_dir/uname"
}

link_fixture_command() {
  local bin_dir=$1 command_name=$2 source
  source=$(command -v "$command_name")
  ln -s "$source" "$bin_dir/$command_name"
}

make_dependency_fixture() {
  local bin_dir=$1 os=$2 arch=$3 manager=$4 command_name
  make_platform "$bin_dir" "$os" "$arch"
  for command_name in \
    bash curl openssl awk sed grep install mktemp tar find \
    basename cat chmod cmp cp date dirname env head mkdir mv nohup ps rm sleep stat \
    tail touch tr; do
    link_fixture_command "$bin_dir" "$command_name"
  done
  cat > "$bin_dir/$manager" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod 700 "$bin_dir/$manager"
}

help_output=$("$REPO_ROOT/install.sh" --help 2>&1) || {
  printf '%s\n' 'installer --help failed' >&2
  exit 1
}
assert_contains "$help_output" '--dry-run'
assert_contains "$help_output" '--yes'
assert_contains "$help_output" '--device-login'

linux_bin="$TEST_ROOT/linux-bin"
make_platform "$linux_bin" Linux x86_64
cat > "$linux_bin/apt-get" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 700 "$linux_bin/apt-get"
linux_output=$(env \
  HOME="$TEST_ROOT/linux-home" \
  SHELL=/bin/bash \
  PATH="$linux_bin:/usr/bin:/bin" \
  "$REPO_ROOT/install.sh" --dry-run 2>&1) || {
    printf '%s\n' 'Linux dry-run failed' >&2
    exit 1
  }
assert_contains "$linux_output" 'Platform: Linux x86_64'
assert_contains "$linux_output" 'Claude Code: missing; would install Anthropic official native release'
assert_contains "$linux_output" 'CLIProxyAPI: missing; would install verified official linux_amd64 release'
assert_contains "$linux_output" 'Dry run complete; no files were changed.'
[ ! -e "$TEST_ROOT/linux-home/.config/claudex" ] || {
  printf '%s\n' 'Linux dry-run changed configuration' >&2
  exit 1
}

mac_bin="$TEST_ROOT/mac-bin"
make_platform "$mac_bin" Darwin arm64
cat > "$mac_bin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' '2.1.207 (Claude Code)'
EOF
cat > "$mac_bin/cliproxyapi" <<'EOF'
#!/bin/sh
printf '%s\n' 'CLIProxyAPI Version: 7.2.72, Commit: test, BuiltAt: test'
printf '%s\n' '  -config string'
printf '%s\n' '  -codex-login'
printf '%s\n' '  -codex-device-login'
EOF
chmod 700 "$mac_bin/claude" "$mac_bin/cliproxyapi"
mac_output=$(env \
  HOME="$TEST_ROOT/mac-home" \
  SHELL=/bin/zsh \
  PATH="$mac_bin:/usr/bin:/bin" \
  "$REPO_ROOT/install.sh" --dry-run 2>&1) || {
    printf '%s\n' 'macOS dry-run failed' >&2
    exit 1
  }
assert_contains "$mac_output" 'Platform: macOS arm64'
assert_contains "$mac_output" "Claude Code: found $mac_bin/claude (2.1.207)"
assert_contains "$mac_output" "CLIProxyAPI: found $mac_bin/cliproxyapi (7.2.72)"
assert_contains "$mac_output" 'Dry run complete; no files were changed.'
[ ! -e "$TEST_ROOT/mac-home/.config/claudex" ] || {
  printf '%s\n' 'macOS dry-run changed configuration' >&2
  exit 1
}

old_claude_bin="$TEST_ROOT/old-claude-bin"
make_platform "$old_claude_bin" Linux x86_64
cat > "$old_claude_bin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' '2.1.192 (Claude Code)'
EOF
cat > "$old_claude_bin/apt-get" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 700 "$old_claude_bin/claude" "$old_claude_bin/apt-get"
old_claude_output=$(env \
  HOME="$TEST_ROOT/old-claude-home" \
  SHELL=/bin/bash \
  PATH="$old_claude_bin:/usr/bin:/bin" \
  "$REPO_ROOT/install.sh" --dry-run 2>&1) || {
    printf '%s\n' 'old Claude Code dry-run failed' >&2
    exit 1
  }
assert_contains "$old_claude_output" \
  "Claude Code: found $old_claude_bin/claude (2.1.192); would install current native release (requires 2.1.193+)"

linux_deps_bin="$TEST_ROOT/linux-deps-bin"
make_dependency_fixture "$linux_deps_bin" Linux x86_64 apt-get
linux_deps_output=''
linux_deps_output=$(env \
  HOME="$TEST_ROOT/linux-deps-home" \
  SHELL=/bin/bash \
  PATH="$linux_deps_bin" \
  "$REPO_ROOT/install.sh" --dry-run 2>&1) || {
    printf '%s\n' 'Linux dependency dry-run failed' >&2
    printf '%s\n' "$linux_deps_output" >&2
    exit 1
  }
assert_contains "$linux_deps_output" 'System dependencies: missing jq ss'
assert_contains "$linux_deps_output" 'Dependency installer: apt-get install jq iproute2'

for manager_and_iproute in 'dnf iproute' 'yum iproute' 'apk iproute2' 'pacman iproute2' 'zypper iproute2'; do
  manager=${manager_and_iproute%% *}
  iproute_package=${manager_and_iproute#* }
  manager_bin="$TEST_ROOT/${manager}-deps-bin"
  make_dependency_fixture "$manager_bin" Linux x86_64 "$manager"
  manager_output=''
  manager_output=$(env \
    HOME="$TEST_ROOT/${manager}-deps-home" \
    SHELL=/bin/bash \
    PATH="$manager_bin" \
    "$REPO_ROOT/install.sh" --dry-run 2>&1) || {
      printf '%s\n' "$manager dependency dry-run failed" >&2
      exit 1
    }
  assert_contains "$manager_output" "Dependency installer: $manager install jq $iproute_package"
done

mac_deps_bin="$TEST_ROOT/mac-deps-bin"
make_dependency_fixture "$mac_deps_bin" Darwin arm64 brew
link_fixture_command "$mac_deps_bin" lsof
mac_deps_output=''
mac_deps_output=$(env \
  HOME="$TEST_ROOT/mac-deps-home" \
  SHELL=/bin/zsh \
  PATH="$mac_deps_bin" \
  "$REPO_ROOT/install.sh" --dry-run 2>&1) || {
    printf '%s\n' 'macOS dependency dry-run failed' >&2
    printf '%s\n' "$mac_deps_output" >&2
    exit 1
  }
assert_contains "$mac_deps_output" 'System dependencies: missing jq'
assert_contains "$mac_deps_output" 'Dependency installer: brew install jq'

printf '%s\n' 'installer wizard fixtures passed'
