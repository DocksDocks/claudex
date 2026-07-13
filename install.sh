#!/bin/bash
set -euo pipefail

umask 077

DEVICE_LOGIN=0
AUTO_YES=0
DRY_RUN=0
PATH_BLOCK_ADDED=0

usage() {
  cat <<EOF
Usage: $0 [options]

Guided macOS/Linux installer for Claude Code, CLIProxyAPI, and claudex.

Options:
  --device-login  Use CLIProxyAPI's headless Codex device-login flow
  --yes           Install or update missing/outdated prerequisites without prompting
  --dry-run       Show detected tools and planned installation routes; change nothing
  -h, --help      Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device-login) DEVICE_LOGIN=1 ;;
    --yes) AUTO_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'claudex installer: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUPS=()

backup_file() {
  local target=$1 backup
  [ -e "$target" ] || return 0
  backup="${target}.backup-${STAMP}"
  cp -p "$target" "$backup"
  chmod go-rwx "$backup"
  BACKUPS+=("$backup")
}

OS=$(uname -s)
case "$OS" in
  Linux) PLATFORM_NAME=Linux ;;
  Darwin) PLATFORM_NAME=macOS ;;
  *)
    printf 'claudex installer: unsupported operating system: %s\n' "$OS" >&2
    exit 1
    ;;
esac
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)
    RELEASE_ARCH=amd64
    DISPLAY_ARCH=x86_64
    ;;
  aarch64|arm64)
    RELEASE_ARCH=aarch64
    DISPLAY_ARCH=arm64
    ;;
  *)
    printf 'claudex installer: unsupported architecture: %s\n' "$ARCH" >&2
    exit 1
    ;;
esac

REQUIRED_COMMANDS=(
  bash curl jq openssl awk sed grep install mktemp tar find
  basename cat chmod cmp cp date dirname env head mkdir mv nohup ps rm sleep stat
  tail touch tr uname
)
if [ "$OS" = Darwin ]; then
  REQUIRED_COMMANDS+=(lsof)
else
  REQUIRED_COMMANDS+=(ss)
fi

MISSING_COMMANDS=()
collect_missing_commands() {
  local command_name
  MISSING_COMMANDS=()
  for command_name in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || MISSING_COMMANDS+=("$command_name")
  done
}

detect_package_manager() {
  if [ "$OS" = Darwin ]; then
    if command -v brew >/dev/null 2>&1; then
      printf '%s\n' brew
    else
      printf '%s\n' brew-bootstrap
    fi
    return 0
  fi

  local manager
  for manager in apt-get dnf yum apk pacman zypper; do
    if command -v "$manager" >/dev/null 2>&1; then
      printf '%s\n' "$manager"
      return 0
    fi
  done
  return 1
}

package_for_command() {
  local manager=$1 command_name=$2
  case "$command_name" in
    bash|curl|jq|sed|grep|tar|lsof) printf '%s\n' "$command_name" ;;
    openssl)
      [ "$manager" = brew ] || [ "$manager" = brew-bootstrap ] \
        && printf '%s\n' openssl@3 \
        || printf '%s\n' openssl
      ;;
    awk) printf '%s\n' gawk ;;
    basename|cat|chmod|cp|date|dirname|env|head|install|mkdir|mktemp|mv|nohup|rm|sleep|stat|tail|touch|tr|uname)
      printf '%s\n' coreutils
      ;;
    cmp) printf '%s\n' diffutils ;;
    find) printf '%s\n' findutils ;;
    ps)
      case "$manager" in
        apt-get|zypper) printf '%s\n' procps ;;
        *) printf '%s\n' procps-ng ;;
      esac
      ;;
    ss)
      case "$manager" in
        dnf|yum) printf '%s\n' iproute ;;
        *) printf '%s\n' iproute2 ;;
      esac
      ;;
  esac
}

append_dependency_package() {
  local package=$1 existing
  if [ "${#DEPENDENCY_PACKAGES[@]}" -gt 0 ]; then
    for existing in "${DEPENDENCY_PACKAGES[@]}"; do
      [ "$existing" != "$package" ] || return 0
    done
  fi
  DEPENDENCY_PACKAGES+=("$package")
}

collect_missing_commands
PACKAGE_MANAGER=''
DEPENDENCY_PACKAGES=()
if [ "${#MISSING_COMMANDS[@]}" -gt 0 ]; then
  PACKAGE_MANAGER=$(detect_package_manager || true)
  if [ -n "$PACKAGE_MANAGER" ]; then
    for missing_command in "${MISSING_COMMANDS[@]}"; do
      dependency_package=$(package_for_command "$PACKAGE_MANAGER" "$missing_command")
      append_dependency_package "$dependency_package"
    done
  fi
fi

find_cliproxy_binary() {
  local candidate
  for candidate in cli-proxy-api cliproxyapi CLIProxyAPI; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

cliproxy_version() {
  "$1" -help 2>&1 |
    sed -n 's/^CLIProxyAPI Version: \([^,[:space:]]*\).*/\1/p' |
    head -n 1
}

printf '%s\n' 'claudex guided installer'
printf 'Platform: %s %s\n' "$PLATFORM_NAME" "$DISPLAY_ARCH"
if [ "${#MISSING_COMMANDS[@]}" -eq 0 ]; then
  printf '%s\n' 'System dependencies: ready'
else
  printf 'System dependencies: missing'
  printf ' %s' "${MISSING_COMMANDS[@]}"
  printf '\n'
  if [ "$PACKAGE_MANAGER" = brew-bootstrap ]; then
    printf 'Dependency installer: install Homebrew, then brew install'
    printf ' %s' "${DEPENDENCY_PACKAGES[@]}"
    printf '\n'
  elif [ -n "$PACKAGE_MANAGER" ]; then
    printf 'Dependency installer: %s install' "$PACKAGE_MANAGER"
    printf ' %s' "${DEPENDENCY_PACKAGES[@]}"
    printf '\n'
  else
    printf '%s\n' 'Dependency installer: unavailable for this Linux distribution'
  fi
fi

DETECTED_CLAUDE=$(command -v claude 2>/dev/null || true)
if [ -n "$DETECTED_CLAUDE" ]; then
  DETECTED_CLAUDE_VERSION=$("$DETECTED_CLAUDE" --version 2>/dev/null | awk 'NR == 1 { print $1 }')
  printf 'Claude Code: found %s (%s)\n' "$DETECTED_CLAUDE" "${DETECTED_CLAUDE_VERSION:-version unknown}"
else
  printf '%s\n' 'Claude Code: missing; would install Anthropic official native release'
fi

DETECTED_CLIPROXY=''
if [ -n "${CLIPROXY_BINARY:-}" ]; then
  DETECTED_CLIPROXY=$CLIPROXY_BINARY
else
  DETECTED_CLIPROXY=$(find_cliproxy_binary || true)
fi
if [ -n "$DETECTED_CLIPROXY" ] && [ -x "$DETECTED_CLIPROXY" ]; then
  DETECTED_CLIPROXY_VERSION=$(cliproxy_version "$DETECTED_CLIPROXY")
  printf 'CLIProxyAPI: found %s (%s)\n' "$DETECTED_CLIPROXY" "${DETECTED_CLIPROXY_VERSION:-version unknown}"
else
  printf 'CLIProxyAPI: missing; would install verified official %s_%s release\n' \
    "$(printf '%s' "$OS" | tr '[:upper:]' '[:lower:]')" "$RELEASE_ARCH"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' 'Dry run complete; no files were changed.'
  [ "${#MISSING_COMMANDS[@]}" -eq 0 ] || [ -n "$PACKAGE_MANAGER" ]
  exit $?
fi

absolute_path() {
  local path=$1 directory filename
  case "$path" in
    /*) ;;
    *) path="$PWD/$path" ;;
  esac
  directory=$(dirname "$path")
  filename=$(basename "$path")
  directory=$(cd "$directory" && pwd -P)
  printf '%s/%s\n' "$directory" "$filename"
}

confirm_action() {
  local prompt=$1 answer
  if [ "$AUTO_YES" -eq 1 ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    printf 'claudex installer: %s; rerun with --yes to authorize installation\n' "$prompt" >&2
    exit 1
  fi
  printf '%s [Y/n] ' "$prompt" >&2
  read -r answer
  case "$answer" in
    ''|y|Y|yes|YES) ;;
    *) printf '%s\n' 'claudex installer: cancelled' >&2; exit 1 ;;
  esac
}

run_as_root() {
  if [ "$EUID" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    printf '%s\n' 'claudex installer: dependency installation requires root or sudo' >&2
    exit 1
  fi
}

bootstrap_homebrew() {
  local installer brew_binary
  installer=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")
  /usr/bin/curl -fsSL \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
    -o "$installer"
  chmod 600 "$installer"
  /bin/bash -n "$installer" || {
    printf '%s\n' 'claudex installer: downloaded Homebrew installer is not valid Bash' >&2
    exit 1
  }
  /bin/bash "$installer"
  rm -f "$installer"

  for brew_binary in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$brew_binary" ]; then
      PATH="$(dirname "$brew_binary"):$PATH"
      export PATH
      return 0
    fi
  done
  printf '%s\n' 'claudex installer: Homebrew installation did not produce a brew executable' >&2
  exit 1
}

install_system_dependencies() {
  [ "${#MISSING_COMMANDS[@]}" -gt 0 ] || return 0
  [ -n "$PACKAGE_MANAGER" ] || {
    printf '%s\n' 'claudex installer: no supported package manager found' >&2
    exit 1
  }

  if [ "$PACKAGE_MANAGER" = brew-bootstrap ]; then
    confirm_action "Missing system dependencies require Homebrew. Install Homebrew and ${DEPENDENCY_PACKAGES[*]}?"
    bootstrap_homebrew
    PACKAGE_MANAGER=brew
  else
    confirm_action "Install missing system dependencies with $PACKAGE_MANAGER: ${DEPENDENCY_PACKAGES[*]}?"
  fi

  case "$PACKAGE_MANAGER" in
    brew) brew install "${DEPENDENCY_PACKAGES[@]}" ;;
    apt-get)
      run_as_root apt-get update
      run_as_root apt-get install -y "${DEPENDENCY_PACKAGES[@]}"
      ;;
    dnf) run_as_root dnf -y install "${DEPENDENCY_PACKAGES[@]}" ;;
    yum) run_as_root yum -y install "${DEPENDENCY_PACKAGES[@]}" ;;
    apk) run_as_root apk add "${DEPENDENCY_PACKAGES[@]}" ;;
    pacman) run_as_root pacman -S --needed --noconfirm "${DEPENDENCY_PACKAGES[@]}" ;;
    zypper) run_as_root zypper --non-interactive install "${DEPENDENCY_PACKAGES[@]}" ;;
  esac
  hash -r
  collect_missing_commands
  if [ "${#MISSING_COMMANDS[@]}" -gt 0 ]; then
    printf 'claudex installer: dependencies remain unavailable after installation:' >&2
    printf ' %s' "${MISSING_COMMANDS[@]}" >&2
    printf '\n' >&2
    exit 1
  fi
}

install_system_dependencies

install_official_claude() {
  local installer native_target
  confirm_action 'Claude Code is missing. Install Anthropic official native Claude Code?'
  native_target="$HOME/.local/bin/claude"
  [ ! -e "$native_target" ] || backup_file "$native_target"
  installer=$(mktemp "${TMPDIR:-/tmp}/claude-code-install.XXXXXX")
  curl -fsSL https://claude.ai/install.sh -o "$installer"
  chmod 600 "$installer"
  bash -n "$installer" || {
    printf '%s\n' 'claudex installer: downloaded Claude Code installer is not valid Bash' >&2
    exit 1
  }
  bash "$installer"
  rm -f "$installer"
  PATH="$HOME/.local/bin:$PATH"
  export PATH
}

fetch_cliproxy_release() {
  CLIPROXY_RELEASE_FILE=$(mktemp "${TMPDIR:-/tmp}/cliproxyapi-release.XXXXXX")
  if ! curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest \
    -o "$CLIPROXY_RELEASE_FILE"; then
    return 1
  fi
  CLIPROXY_LATEST_TAG=$(jq -r '.tag_name // empty' "$CLIPROXY_RELEASE_FILE")
  CLIPROXY_LATEST_VERSION=${CLIPROXY_LATEST_TAG#v}
  [ -n "$CLIPROXY_LATEST_VERSION" ]
}

install_cliproxy_release() {
  local asset checksums_url archive_url expected actual extracted
  asset="CLIProxyAPI_${CLIPROXY_LATEST_VERSION}_$(printf '%s' "$OS" | tr '[:upper:]' '[:lower:]')_${RELEASE_ARCH}.tar.gz"
  checksums_url=$(jq -r '.assets[] | select(.name == "checksums.txt") | .browser_download_url' "$CLIPROXY_RELEASE_FILE")
  archive_url=$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .browser_download_url' "$CLIPROXY_RELEASE_FILE")
  if [ -z "$checksums_url" ] || [ -z "$archive_url" ]; then
    printf 'claudex installer: official release does not contain %s\n' "$asset" >&2
    exit 1
  fi

  CLIPROXY_DOWNLOAD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cliproxyapi-download.XXXXXX")
  curl -fsSL "$checksums_url" -o "$CLIPROXY_DOWNLOAD_DIR/checksums.txt"
  curl -fsSL "$archive_url" -o "$CLIPROXY_DOWNLOAD_DIR/$asset"
  expected=$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print $1; exit }' "$CLIPROXY_DOWNLOAD_DIR/checksums.txt")
  actual=$(openssl dgst -sha256 "$CLIPROXY_DOWNLOAD_DIR/$asset" | awk '{ print $NF }')
  if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
    printf '%s\n' 'claudex installer: CLIProxyAPI release checksum verification failed' >&2
    exit 1
  fi
  tar -xzf "$CLIPROXY_DOWNLOAD_DIR/$asset" -C "$CLIPROXY_DOWNLOAD_DIR"
  extracted=$(find "$CLIPROXY_DOWNLOAD_DIR" -type f \
    \( -name 'cli-proxy-api' -o -name 'cliproxyapi' -o -name 'CLIProxyAPI' \) \
    -print | head -n 1)
  if [ -z "$extracted" ] || [ ! -x "$extracted" ]; then
    printf '%s\n' 'claudex installer: verified CLIProxyAPI archive contains no executable' >&2
    exit 1
  fi
  SOURCE_CLIPROXY_BINARY=$extracted
}

install_latest_cliproxy() {
  local formula_version brew_source
  if [ "$OS" = Darwin ] && command -v brew >/dev/null 2>&1; then
    formula_version=$(brew info --json=v2 cliproxyapi 2>/dev/null |
      jq -r '.formulae[0].versions.stable // empty' 2>/dev/null || true)
    if [ "$formula_version" = "$CLIPROXY_LATEST_VERSION" ]; then
      if brew list --versions cliproxyapi >/dev/null 2>&1; then
        brew upgrade cliproxyapi
      else
        brew install cliproxyapi
      fi
      brew_source="$(brew --prefix cliproxyapi)/bin/cliproxyapi"
      [ -x "$brew_source" ] || {
        printf '%s\n' 'claudex installer: Homebrew installed cliproxyapi but its executable was not found' >&2
        exit 1
      }
      SOURCE_CLIPROXY_BINARY=$brew_source
      return 0
    fi
  fi
  install_cliproxy_release
}

CLAUDE_BINARY=$(command -v claude || true)
if [ -z "$CLAUDE_BINARY" ]; then
  install_official_claude
  CLAUDE_BINARY=$(command -v claude || true)
fi
[ -n "$CLAUDE_BINARY" ] || {
  printf '%s\n' 'claudex installer: official Claude Code installation did not produce a claude executable' >&2
  exit 1
}
CLAUDE_BINARY=$(absolute_path "$CLAUDE_BINARY")

SOURCE_CLIPROXY_BINARY=$DETECTED_CLIPROXY
CLIPROXY_RELEASE_FILE=''
CLIPROXY_DOWNLOAD_DIR=''
if [ -z "${CLIPROXY_BINARY:-}" ]; then
  if fetch_cliproxy_release; then
    installed_cliproxy_version=''
    if [ -n "$SOURCE_CLIPROXY_BINARY" ] && [ -x "$SOURCE_CLIPROXY_BINARY" ]; then
      installed_cliproxy_version=$(cliproxy_version "$SOURCE_CLIPROXY_BINARY")
    fi
    if [ "$installed_cliproxy_version" != "$CLIPROXY_LATEST_VERSION" ]; then
      if [ -n "$installed_cliproxy_version" ]; then
        confirm_action "CLIProxyAPI $installed_cliproxy_version differs from current $CLIPROXY_LATEST_VERSION. Install the verified current release?"
      else
        confirm_action "CLIProxyAPI is missing. Install verified official release $CLIPROXY_LATEST_VERSION?"
      fi
      install_latest_cliproxy
    fi
  elif [ -z "$SOURCE_CLIPROXY_BINARY" ] || [ ! -x "$SOURCE_CLIPROXY_BINARY" ]; then
    printf '%s\n' 'claudex installer: cannot discover the current CLIProxyAPI release' >&2
    exit 1
  else
    printf '%s\n' 'claudex installer: release check unavailable; reusing installed CLIProxyAPI' >&2
  fi
fi
if [ -z "$SOURCE_CLIPROXY_BINARY" ] || [ ! -x "$SOURCE_CLIPROXY_BINARY" ]; then
  printf '%s\n' 'claudex installer: current official CLIProxyAPI binary not found' >&2
  exit 1
fi
SOURCE_CLIPROXY_BINARY=$(absolute_path "$SOURCE_CLIPROXY_BINARY")

cliproxy_help=$("$SOURCE_CLIPROXY_BINARY" -help 2>&1 || true)
printf '%s' "$cliproxy_help" | grep -q -e '-config string' || {
  printf '%s\n' 'claudex installer: CLIProxyAPI help lacks the required -config flag' >&2
  exit 1
}
printf '%s' "$cliproxy_help" | grep -q -e '-codex-login' || {
  printf '%s\n' 'claudex installer: CLIProxyAPI help lacks the required -codex-login flag' >&2
  exit 1
}
if [ "$DEVICE_LOGIN" -eq 1 ]; then
  printf '%s' "$cliproxy_help" | grep -q -e '-codex-device-login' || {
    printf '%s\n' 'claudex installer: CLIProxyAPI help lacks -codex-device-login' >&2
    exit 1
  }
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claudex"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claudex"
AUTH_DIR="$DATA_DIR/auth"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claudex"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"

mkdir -p "$CONFIG_DIR" "$AUTH_DIR" "$STATE_DIR" "$STATE_DIR/logs" "$BIN_DIR"
chmod 700 "$CONFIG_DIR" "$DATA_DIR" "$AUTH_DIR" "$STATE_DIR" "$STATE_DIR/logs"

shopt -s nullglob
oauth_files=("$AUTH_DIR"/codex-*.json)
shopt -u nullglob
if [ "${#oauth_files[@]}" -gt 1 ]; then
  printf '%s\n' 'claudex installer: multiple Codex OAuth credentials found in the dedicated auth directory' >&2
  printf '%s\n' 'Keep exactly one intended account credential there, then rerun the installer.' >&2
  exit 1
fi

install_if_changed() {
  local source=$1 target=$2 mode=$3
  if [ -e "$target" ] && cmp -s "$source" "$target"; then
    chmod "$mode" "$target"
    return 1
  fi
  backup_file "$target"
  install -m "$mode" "$source" "$target"
  return 0
}

TARGET_CLIPROXY_BINARY="$BIN_DIR/cli-proxy-api"
if [ "$SOURCE_CLIPROXY_BINARY" != "$TARGET_CLIPROXY_BINARY" ]; then
  install_if_changed "$SOURCE_CLIPROXY_BINARY" "$TARGET_CLIPROXY_BINARY" 700 || true
else
  chmod 700 "$TARGET_CLIPROXY_BINARY"
fi
[ -z "$CLIPROXY_RELEASE_FILE" ] || rm -f "$CLIPROXY_RELEASE_FILE"
[ -z "$CLIPROXY_DOWNLOAD_DIR" ] || rm -rf "$CLIPROXY_DOWNLOAD_DIR"

for script_name in claudex claudex-proxy claudex-statusline claudex-fetch-usage; do
  install_if_changed "$SCRIPT_DIR/bin/$script_name" "$BIN_DIR/$script_name" 700 || true
done

TOKEN_FILE="$CONFIG_DIR/client-token"
token=''
if [ -r "$TOKEN_FILE" ]; then
  token=$(sed -n '1p' "$TOKEN_FILE")
fi
if ! [[ "$token" =~ ^[0-9a-f]{64}$ ]]; then
  [ ! -e "$TOKEN_FILE" ] || backup_file "$TOKEN_FILE"
  openssl rand -hex 32 > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  token=$(sed -n '1p' "$TOKEN_FILE")
fi

CONFIG_FILE="$CONFIG_DIR/cliproxyapi.yaml"
PORT=''
if [ -r "$CONFIG_FILE" ] \
   && grep -Eq '^host:[[:space:]]*"?127\.0\.0\.1"?[[:space:]]*$' "$CONFIG_FILE"; then
  PORT=$(awk '/^port: [0-9]+$/ { print $2; exit }' "$CONFIG_FILE")
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
  PORT=8317
  port_in_use() {
    if [ "$OS" = "Darwin" ]; then
      lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
    else
      ss -ltnH "sport = :$1" | grep -q .
    fi
  }
  while port_in_use "$PORT"; do
    PORT=$((PORT + 1))
    [ "$PORT" -le 65535 ] || {
      printf '%s\n' 'claudex installer: no free loopback port found' >&2
      exit 1
    }
  done
fi

yaml_string() {
  jq -Rn --arg value "$1" '$value'
}

config_tmp=$(mktemp "$CONFIG_DIR/.cliproxyapi.XXXXXX")
{
  printf 'host: "127.0.0.1"\n'
  printf 'port: %s\n' "$PORT"
  printf 'remote-management:\n'
  printf '  allow-remote: false\n'
  printf '  secret-key: ""\n'
  printf '  disable-control-panel: true\n'
  printf 'auth-dir: %s\n' "$(yaml_string "$AUTH_DIR")"
  printf 'api-keys:\n'
  printf '  - %s\n' "$(yaml_string "$token")"
  printf 'debug: false\n'
  printf 'pprof:\n'
  printf '  enable: false\n'
  printf '  addr: "127.0.0.1:8316"\n'
  printf 'plugins:\n'
  printf '  enabled: false\n'
  printf 'logging-to-file: false\n'
  printf 'usage-statistics-enabled: false\n'
  printf 'passthrough-headers: false\n'
} > "$config_tmp"
CONFIG_CHANGED=0
if install_if_changed "$config_tmp" "$CONFIG_FILE" 600; then
  CONFIG_CHANGED=1
fi
rm -f "$config_tmp"

shell_quote() {
  local escaped
  escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$escaped"
}

RUNTIME_FILE="$CONFIG_DIR/runtime.env"
runtime_tmp=$(mktemp "$CONFIG_DIR/.runtime.XXXXXX")
{
  printf 'CLIPROXY_BINARY=%s\n' "$(shell_quote "$TARGET_CLIPROXY_BINARY")"
  printf 'CLIPROXY_CONFIG=%s\n' "$(shell_quote "$CONFIG_FILE")"
  printf 'CLAUDEX_PORT=%s\n' "$(shell_quote "$PORT")"
  printf 'CLAUDEX_BASE_URL=%s\n' "$(shell_quote "http://127.0.0.1:$PORT")"
  printf 'CLAUDEX_TOKEN_FILE=%s\n' "$(shell_quote "$TOKEN_FILE")"
  printf 'CLAUDEX_PROXY_HELPER=%s\n' "$(shell_quote "$BIN_DIR/claudex-proxy")"
  printf 'CLAUDEX_STATE_DIR=%s\n' "$(shell_quote "$STATE_DIR")"
  printf 'CLAUDEX_WRITABLE_PATH=%s\n' "$(shell_quote "$STATE_DIR")"
  printf 'CLAUDEX_LOG_FILE=%s\n' "$(shell_quote "$STATE_DIR/cliproxyapi.log")"
  printf 'CLAUDEX_PID_FILE=%s\n' "$(shell_quote "$STATE_DIR/cliproxyapi.pid")"
  printf 'CLAUDE_BINARY=%s\n' "$(shell_quote "$CLAUDE_BINARY")"
} > "$runtime_tmp"
install_if_changed "$runtime_tmp" "$RUNTIME_FILE" 600 || true
rm -f "$runtime_tmp"

SETTINGS_FILE="$CONFIG_DIR/claude-settings.json"
settings_tmp=$(mktemp "$CONFIG_DIR/.claude-settings.XXXXXX")
jq -n --arg command "$BIN_DIR/claudex-statusline" '{
  statusLine: {
    type: "command",
    command: $command,
    refreshInterval: 5
  }
}' > "$settings_tmp"
install_if_changed "$settings_tmp" "$SETTINGS_FILE" 600 || true
rm -f "$settings_tmp"

if ! printf '%s' ":$PATH:" | grep -q ":$BIN_DIR:"; then
  case "${SHELL:-}" in
    */zsh) SHELL_RC="$HOME/.zshrc" ;;
    *) SHELL_RC="$HOME/.bashrc" ;;
  esac
  MARKER_BEGIN='# >>> claudex PATH >>>'
  if [ ! -r "$SHELL_RC" ] || ! grep -Fq "$MARKER_BEGIN" "$SHELL_RC"; then
    [ ! -e "$SHELL_RC" ] || backup_file "$SHELL_RC"
    {
      printf '\n%s\n' "$MARKER_BEGIN"
      printf '%s\n' "case \":\$PATH:\" in *\":\$HOME/.local/bin:\"*) ;; *) export PATH=\"\$HOME/.local/bin:\$PATH\" ;; esac"
      printf '%s\n' '# <<< claudex PATH <<<'
    } >> "$SHELL_RC"
    PATH_BLOCK_ADDED=1
  fi
fi

if [ "${#oauth_files[@]}" -eq 0 ]; then
  printf '%s\n' 'Complete Codex OAuth using the ChatGPT account with the intended subscription.'
  if [ "$DEVICE_LOGIN" -eq 1 ]; then
    WRITABLE_PATH="$STATE_DIR" "$TARGET_CLIPROXY_BINARY" -config "$CONFIG_FILE" -codex-device-login
  else
    WRITABLE_PATH="$STATE_DIR" "$TARGET_CLIPROXY_BINARY" -config "$CONFIG_FILE" -codex-login
  fi
  shopt -s nullglob
  oauth_files=("$AUTH_DIR"/codex-*.json)
  shopt -u nullglob
fi
[ "${#oauth_files[@]}" -eq 1 ] || {
  printf '%s\n' 'claudex installer: Codex OAuth must create exactly one credential file' >&2
  exit 1
}
chmod 600 "${oauth_files[@]}"

if [ "$CONFIG_CHANGED" -eq 1 ]; then
  "$BIN_DIR/claudex-proxy" stop
fi
"$BIN_DIR/claudex-proxy" start

headers_file=$(mktemp "$STATE_DIR/.models-headers.XXXXXX")
models_file=$(mktemp "$STATE_DIR/.models-response.XXXXXX")
trap 'rm -f "$headers_file" "$models_file"' EXIT
printf 'Authorization: Bearer %s\n' "$token" > "$headers_file"
unset token
curl -fsS --max-time 10 -H "@$headers_file" \
  -o "$models_file" "http://127.0.0.1:$PORT/v1/models"
rm -f "$headers_file"
jq -e '.data | any(.id == "gpt-5.6-sol")' "$models_file" >/dev/null || {
  printf '%s\n' 'claudex installer: exact model gpt-5.6-sol is absent from /v1/models' >&2
  printf '%s\n' 'Available GPT-5.6 model IDs:' >&2
  jq -r '.data[]?.id | select(startswith("gpt-5.6"))' "$models_file" >&2
  exit 1
}
rm -f "$models_file"
trap - EXIT

printf 'claudex installed: %s %s, Claude %s, CLIProxyAPI on 127.0.0.1:%s\n' \
  "$OS" "$(uname -m)" "$($CLAUDE_BINARY --version)" "$PORT"
printf '%s\n' 'Codex OAuth credential present; exact model gpt-5.6-sol is available.'
if [ "$PATH_BLOCK_ADDED" -eq 1 ]; then
  printf '%s\n' 'Open a new shell to use claudex by name.'
fi
if [ "${#BACKUPS[@]}" -gt 0 ]; then
  printf '%s\n' 'Backups created:'
  printf '  %s\n' "${BACKUPS[@]}"
fi
