# claudex for macOS and Linux

> [!IMPORTANT]
> This is an unofficial community project. It is not affiliated with, endorsed
> by, or supported by Anthropic or OpenAI. Claude, Claude Code, ChatGPT, Codex,
> and OpenAI are trademarks of their respective owners.

`claudex` runs the official Claude Code CLI as the agent harness while routing
only that command through a loopback-only CLIProxyAPI instance backed by Codex
OAuth. It does not install the OpenAI plugin for Claude Code, use an OpenAI API
key, authenticate a Claude subscription through the proxy, or alter ordinary
`claude` routing.

The included status line retains the existing Claude-style model, directory,
Git branch, context, colors, and separators. In `claudex` only, its subscription
section comes from the same ChatGPT usage service used by Codex. Windows are
identified by their server-reported duration: 18,000 seconds is rendered as
`5h`, and 604,800 seconds as `7d`. A window is omitted when it is absent.
Quota data older than 15 minutes is suppressed rather than presented as current.

Claude Code normally treats an unrecognized gateway model as a 200K model.
`claudex` instead sets both its assumed context size and auto-compaction capacity
to 272,000 tokens, only for the claudex process. Claude Code 2.1.193 added the
[custom-model context override](https://code.claude.com/docs/en/env-vars), and
OpenAI documents 272K as the boundary before
[GPT-5.6 Sol long-context pricing](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
applies. The upstream API supports a larger maximum window, but claudex stays at
272K to avoid crossing that boundary. OpenAI does not publicly document how the
API pricing multiplier maps to ChatGPT subscription quota accounting. Ordinary
`claude` remains unchanged.

Claude Code's bundled `/claude-api` reference can consume most of a 272K window
when loaded. The isolated claudex settings make that skill user-invocable only,
preventing automatic activation while preserving explicit `/claude-api` use.
This override does not apply to ordinary `claude` sessions.

## Install with the guided wizard

The wizard supports macOS and Linux on Intel/AMD 64-bit and ARM64 systems. It
detects the operating system, architecture, login shell, installed tools, and
available package manager before making changes.

```bash
git clone https://github.com/DocksDocks/claudex.git
cd claudex
./install.sh
```

On macOS it uses Homebrew, installing Homebrew through its official installer
when needed. On Linux it supports `apt-get`, `dnf`, `yum`, `apk`, `pacman`, and
`zypper`. The wizard groups missing foundational tools into one confirmed
package-manager operation, installs them, and revalidates every command before
continuing. This includes `curl`, `jq`, `openssl`, `tar`, standard shell tools,
and `lsof` on macOS or `ss` from `iproute2` on Linux.

The same run then:

1. Reuses Claude Code when present or installs it with Anthropic's current
   official native installer. Versions older than 2.1.193 are upgraded because
   they cannot apply the custom-model context override used by claudex.
2. Reuses a current CLIProxyAPI or installs the current official release for
   the detected platform. Downloaded archives must match the official release
   checksum before extraction.
3. Creates the isolated owner-only claudex configuration and generates or
   reuses the local proxy client token.
4. Runs CLIProxyAPI's Codex OAuth browser flow. It never asks for an OpenAI API
   key or a Claude subscription login.
5. Starts the loopback-only proxy and requires the exact `gpt-5.6-sol` model to
   appear in `/v1/models`.
6. Adds `~/.local/bin` to `~/.bashrc` or `~/.zshrc` only when needed, using one
   marked idempotent block and a timestamped owner-only backup.

Preview the complete detection and installation route without changing
anything:

```bash
./install.sh --dry-run
```

For unattended prerequisite installation, accept the wizard's package and
binary installation prompts with `--yes`. On a headless host, also select
CLIProxyAPI's device authorization flow:

```bash
./install.sh --yes --device-login
```

Rerunning `./install.sh` repairs or updates the same isolated installation
instead of duplicating configuration. Existing targets are backed up before
changed content is installed. The dedicated auth directory must contain exactly
one Codex OAuth credential; the wizard fails closed if multiple account
credentials are present. If it adds the PATH block, open a new shell before
running `claudex` by name.

```text
~/.config/claudex/
  claude-settings.json
  cliproxyapi.yaml
  client-token
  runtime.env
~/.local/share/claudex/auth/
~/.local/state/claudex/
~/.local/bin/
  claudex
  claudex-proxy
  claudex-statusline
  claudex-fetch-usage
```

`claudex` passes all remaining arguments directly to Claude Code. Both of these
therefore work:

```bash
claudex --resume
claudex --resume <session-id>
```

The resumed conversation still runs through `gpt-5.6-sol`; sessions created by
plain `claude` are not rerouted globally.

Claude Code deliberately does not persist workspace trust when launched directly
from your home directory. If `~/projects` exists and `claudex` is started from
exactly `$HOME`, the wrapper enters `~/projects` before launching Claude Code.
This avoids the unavoidable home-directory prompt without bypassing permissions;
the normal one-time trust prompt still applies to new project directories. Start
`claudex` from any other directory to use that directory unchanged.

## Operations

```bash
claudex
claudex-proxy status
claudex-proxy logs
claudex-proxy stop
```

## Development verification

```bash
bash -n install.sh bin/* tests/*.sh
shellcheck install.sh bin/* tests/*.sh
tests/install-wizard.sh
tests/claudex-wrapper.sh
tests/fetch-usage.sh
tests/proxy-lifecycle.sh
tests/statusline.sh
```

GitHub Actions runs the same checks on current macOS and Linux runners. The
fixture verifies both the present weekly-only response and the future case in
which ChatGPT returns a 5-hour window again.

## Security model

- CLIProxyAPI binds only to `127.0.0.1`.
- The generated local client key and OAuth files are owner-readable only.
- OAuth access and refresh tokens are never copied into this repository,
  wrapper scripts, shell startup files, or command-line arguments.
- The ChatGPT usage request reads the dedicated CLIProxyAPI OAuth credential,
  passes its authorization header through a temporary owner-only file, and
  stores only window percentages and reset times in the cache.
- The ChatGPT usage endpoint is internal rather than a stable public API. The
  fetcher validates the schema and keeps the last valid cache when it changes or
  is unavailable, while the renderer hides cached data after 15 minutes.
- Automated access to an internal endpoint may be affected by service changes
  or applicable provider terms. Review those terms for your use case and stop
  using the quota integration if it is no longer permitted or supported.
- Dynamic model, path, and Git text has terminal control bytes removed before
  the status line adds its own fixed ANSI styling.

See [SECURITY.md](SECURITY.md) for reporting and credential-response guidance.

## License

The claudex wrapper and installer code in this repository are available under
the [MIT License](LICENSE). Claude Code and CLIProxyAPI remain governed by their
respective upstream licenses and terms.
