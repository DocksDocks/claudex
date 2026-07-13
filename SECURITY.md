# Security

## Supported version

Security fixes apply to the latest commit on `main`. This project wraps locally
installed Claude Code and CLIProxyAPI executables; it does not redistribute
either upstream binary.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do
not include OAuth credentials, refresh tokens, local client tokens, or raw
credential files in a report. Include redacted logs and reproduction steps.

If a credential may have been exposed, stop the dedicated proxy, remove the
affected credential from `~/.local/share/claudex/auth/`, and repeat the
CLIProxyAPI Codex OAuth login. Never post the credential in a GitHub issue.

## Trust boundaries

- Install Claude Code only through Anthropic's official distribution.
- Install CLIProxyAPI from its official Homebrew formula or a release artifact
  whose checksum matches the official release checksums.
- Keep exactly one Codex OAuth credential in the dedicated claudex auth
  directory so the proxy route and displayed quota refer to one account.
- The quota renderer uses an internal, undocumented ChatGPT endpoint. It may
  change without notice and is not a stable public API.

Before each public release, scan the current tree and complete reachable Git
history for credentials, machine-specific paths, and unintended identity data.
