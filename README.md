# pen

Run coding harnesses (Claude Code, and more) inside isolated Docker containers, enabling `--dangerously-skip-permissions` safely. Each git worktree gets its own container; credentials and preferences are shared across all of them.

## How it works

- Mounts only the current worktree (and parent repo `.git` dir for linked worktrees) — nothing else on your filesystem is accessible
- Runs as your host UID so file ownership is correct on mounted volumes
- All containers for a given harness share `~/.pen/<harness>/` for credentials, settings, and memory
- For Claude: `~/.claude/CLAUDE.md` and `~/.claude/commands/` are mounted read-only from the host — always current, no manual sync needed

## Prerequisites

- Docker Desktop
- `bats-core` for running tests: `brew install bats-core`

## Installation

### Homebrew (recommended)

```sh
brew install kjhaber/tap/pen
```

### Manual

```sh
make build    # build the Docker image(s)
make install  # install the pen script to ~/.local/bin
```

Ensure `~/.local/bin` is on your `PATH`.

## First-time setup (one-time only, Claude harness)

The first time you run `pen`, Claude will prompt for:

1. **Theme** — pick your preference; saved to `~/.pen/claude/settings.json`
2. **Login** — complete the Claude.ai login flow; credentials are saved to `~/.pen/claude/`

These prompts only appear once. All subsequent containers — including new worktrees — reuse the saved credentials and settings from `~/.pen/claude/`.

If you have an `ANTHROPIC_API_KEY` set in your shell, it is passed through automatically and the login prompt is skipped.

## Usage

```sh
# From any git worktree directory:
pen                            # start container (if needed) and launch default harness
pen "fix the bug in auth"      # launch with an initial prompt
pen --print "explain X"        # non-interactive output (any harness flag works)
pen --harness=cursor           # override harness for this invocation
pen exec                       # open a shell in the container for $PWD
pen exec [name]                # open a shell in any named container
pen stop                       # stop and remove the container for $PWD
pen stop [name]                # stop any named container
pen list                       # list all pen containers with status
pen sync-settings              # preview drift from host settings and prompt to apply (claude only)
pen sync-settings --yes        # apply without prompting
```

Container names are `pen_<basename>` derived from the directory name (e.g. `pen_myproject_auth-refactor`), matching the naming convention of `mkworktree`. `exec` and `stop` validate that the named container was created by pen before acting on it.

## Harness selection

Resolved in priority order:

1. `--harness=<name>` CLI flag
2. `.pen.toml` in the git root: `harness = "cursor"`
3. `~/.pen/config.toml` user default: `harness = "claude"`
4. Default: `claude`

## Git worktrees

Works with both the main worktree and linked worktrees. For linked worktrees, the parent repo's `.git` directory is also mounted so git operations work correctly.

## Configuration

`~/.pen/claude/` is the pen-managed Claude config dir, mounted as `/home/devcon/.claude` in every container. It holds:

| Path | Origin | Notes |
|---|---|---|
| `sessions/`, `session-env/` | In-container login (one-time) | Isolated from host; macOS Keychain is inaccessible in containers |
| `settings.json` | Seeded from host, then pen-owned | Keep MCP server config and hooks here; run `sync-settings` to pull host preference changes |
| `CLAUDE.md` | Live mount from `~/.claude/CLAUDE.md` | Always reflects current host global instructions |
| `commands/` | Live mount from `~/.claude/commands/` | Always reflects current host custom commands |

`CLAUDE.md` and `commands/` are mounted read-only at container start — no sync needed and changes are reflected immediately on next launch.

`settings.json` is intentionally pen-owned so you can configure a restricted set of MCPs independently of your host settings. Run `pen sync-settings` to pull non-MCP, non-hook fields (theme, env vars, etc.) from `~/.claude/settings.json` into `~/.pen/claude/settings.json`. Pen's own `hooks` and `mcpServers` are always preserved.

## Customization

| Variable | Default | Description |
|---|---|---|
| `PEN_IMAGE` | `pen-claude:latest` | Docker image to use (overrides harness default) |

To customize the Claude image (add tools, change Go/Node versions), edit `docker/claude/Dockerfile` and run `make build`.

## Testing

```sh
make test          # run all tests (requires bats-core)
make test-script   # unit tests for the launcher script
make test-image    # verify the Docker image has required tools
```
