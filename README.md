# AI Agents Push Notifications

Desktop notification installer for Codex CLI and Claude Code on Ubuntu-like systems.

The repository has a single entrypoint: `install.sh`.

- Running `./install.sh` from a clone uses the local `lib/` and `templates/` files.
- Running `install.sh` through `wget ... | bash` bootstraps the same repository files into a temporary directory and then runs the same modular installer.
- There is no generated `dist/install.sh` and no second wrapper script to maintain.

## Remote Install

Use `bash`, not `sh`, because the installer uses Bash arrays and `[[ ... ]]`.

```bash
wget -qO- https://raw.githubusercontent.com/antonbsa/install-ai-agents-push-notifications/main/install.sh | bash
```

For non-interactive automation, explicitly opt in to the prompts:

```bash
wget -qO- https://raw.githubusercontent.com/antonbsa/install-ai-agents-push-notifications/main/install.sh | AI_NOTIFICATIONS_ASSUME_YES=1 bash
```

After installing, test the configured notifications:

```bash
wget -qO- https://raw.githubusercontent.com/antonbsa/install-ai-agents-push-notifications/main/install.sh | bash -s -- --test
```

When `install.sh` is executed from a pipe, it cannot read local `lib/` and `templates/` files. In that mode it downloads the repository archive from:

```bash
https://github.com/antonbsa/install-ai-agents-push-notifications/archive/refs/heads/main.tar.gz
```

For forks or pinned releases, override it:

```bash
wget -qO- https://raw.githubusercontent.com/<user>/<repo>/<ref>/install.sh | AI_NOTIFICATIONS_REPO_ARCHIVE_URL=https://github.com/<user>/<repo>/archive/refs/tags/v1.0.0.tar.gz bash
```

## Local Install

Clone the repo, edit templates if desired, then run:

```bash
./install.sh
./install.sh --test
```

## Repository Layout

- `install.sh`: the only entrypoint, for local installs and `wget ... | bash`.
- `lib/common.sh`: CLI args, prompts, install summary, and main flow.
- `lib/dependencies.sh`: dependency detection and package installation.
- `lib/filesystem.sh`: backups, directory creation, and template writes.
- `lib/templates.sh`: template loading and placeholder rendering.
- `lib/claude.sh`: Claude Code helper installation and settings merge.
- `lib/codex.sh`: Codex hook installation and TOML merge.
- `lib/test.sh`: `--test` validation and notification checks.
- `templates/`: editable installed files and managed config snippets.

## Editing Templates

Most user-facing behavior lives in `templates/`:

- `templates/ai-notify.sh`: common completion notification helper.
- `templates/claude-notify-filter.py`: Claude Code permission notification filter.
- `templates/codex-notify.sh`: Codex hook handler.
- `templates/claude-settings-hooks.json`: managed Claude hooks.
- `templates/codex-config-managed.toml`: managed Codex TOML entries.

No generated installer is checked in. Changes to `lib/` and `templates/` are used directly by local installs and by piped installs after the repository archive is fetched.

## Installed Files

The installer writes these files:

- `~/.local/bin/ai-notify`
- `~/.local/bin/claude-notify-filter`
- `~/.codex/hooks/notify.sh`

It also updates these config files, creating timestamped backups first when they already exist:

- `~/.claude/settings.json`
- `~/.codex/config.toml`

## Test Mode

`--test` does not install, overwrite, or create config files. It validates an existing installation and sends two simulated notifications:

- one Codex completion notification;
- one Claude Code permission notification.
