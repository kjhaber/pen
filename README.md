# claude-devcon

Run [Claude Code](https://claude.ai/code) inside an isolated Docker container, enabling `--dangerously-skip-permissions` safely. Each git worktree gets its own container; credentials and preferences are shared across all of them.

## How it works

- Mounts only the current worktree (and parent repo `.git` dir for linked worktrees) — nothing else on your filesystem is accessible
- Runs as your host UID so file ownership is correct on mounted volumes
- All containers share `~/.claude-devcon/` for credentials, settings, and memory
- `~/.claude/CLAUDE.md` and `~/.claude/commands/` are mounted read-only from the host — always current, no manual sync needed

## Prerequisites

- Docker Desktop
- `bats-core` for running tests: `brew install bats-core`

## Installation

### Homebrew (recommended)

```sh
brew install kjhaber/tap/claude-devcon
```

### Manual

```sh
make build    # build the Docker image
make install  # install the claude-devcon script to ~/.local/bin
```

Ensure `~/.local/bin` is on your `PATH`.

## First-time setup (one-time only)

The first time you run `claude-devcon`, Claude will prompt for:

1. **Theme** — pick your preference; saved to `~/.claude-devcon/settings.json`
2. **Login** — complete the Claude.ai login flow; credentials are saved to `~/.claude-devcon/`

These prompts only appear once. All subsequent containers — including new worktrees — reuse the saved credentials and settings from `~/.claude-devcon/`.

If you have an `ANTHROPIC_API_KEY` set in your shell, it is passed through automatically and the login prompt is skipped.

## Usage

```sh
# From any git worktree directory:
claude-devcon                        # start container (if needed) and launch Claude
claude-devcon "fix the bug in auth"  # launch with an initial prompt
claude-devcon --print "explain X"    # non-interactive output (any claude flag works)
claude-devcon exec                   # open a shell in the container for $PWD
claude-devcon exec [name]            # open a shell in any named container
claude-devcon stop                   # stop and remove the container for $PWD
claude-devcon stop [name]            # stop any named container
claude-devcon list                   # list all claude-devcon containers with status
claude-devcon sync-settings          # preview drift from host settings and prompt to apply
claude-devcon sync-settings --yes    # apply without prompting
```

Container names are derived from the directory basename (e.g. `myproject_auth-refactor`), matching the naming convention of `mkworktree`. `exec` and `stop` validate that the named container was created by claude-devcon before acting on it.

## Git worktrees

Works with both the main worktree and linked worktrees. For linked worktrees, the parent repo's `.git` directory is also mounted so git operations work correctly.

## Configuration

`~/.claude-devcon/` is the devcon-specific Claude config dir, mounted as `/home/devcon/.claude` in every container. It holds:

| Path | Origin | Notes |
|---|---|---|
| `sessions/`, `session-env/` | Devcon login (one-time) | Isolated from host; macOS Keychain is inaccessible in containers |
| `settings.json` | Seeded from host, then devcon-owned | Keep MCP server config and hooks here; run `sync-settings` to pull host preference changes |
| `CLAUDE.md` | Live mount from `~/.claude/CLAUDE.md` | Always reflects current host global instructions |
| `commands/` | Live mount from `~/.claude/commands/` | Always reflects current host custom commands |

`CLAUDE.md` and `commands/` are mounted read-only at container start — no sync needed and changes are reflected immediately on next launch.

`settings.json` is intentionally devcon-owned so you can configure a restricted set of MCPs (e.g. read-only work tools) independently of your host settings. Run `claude-devcon sync-settings` to pull non-MCP, non-hook fields (theme, enabled plugins, env vars, etc.) from `~/.claude/settings.json` into `~/.claude-devcon/settings.json`. Devcon's own `hooks` and `mcpServers` are always preserved.

## Customization

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_DEVCON_IMAGE` | `claude-devcon:latest` | Docker image to use |
| `CLAUDE_DEVCON_CONFIG` | `~/.claude-devcon` | Host path for Claude config/credentials |

To customize the image (add tools, change Go/Node versions), edit the `Dockerfile` and run `make build`.

## Testing

```sh
make test          # run all tests (requires bats-core)
make test-script   # unit tests for the launcher script
make test-image    # verify the Docker image has required tools
```
