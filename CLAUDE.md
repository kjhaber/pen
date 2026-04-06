# pen

## Test command

```sh
make test
```

Runs `bats tests/test_script.bats` (unit tests) and `bash tests/test_image.sh` (Docker image checks). Requires `bats-core` (`brew install bats-core`) and a built image (`make build`).

## Architecture decisions

**`sleep infinity` + `docker exec`** — The container's main process is `sleep infinity`, not the harness. The harness is exec'd in on each invocation. This means the harness can exit without stopping the container, and multiple sessions can be opened into the same container (`pen exec` for a shell, re-running `pen` for a new harness session).

**Mounting strategy for git worktrees** — Worktrees have a `.git` *file* (not directory) containing an absolute host path to the main repo's `.git` dir. To keep the blast radius tight while still letting git work, we mount only:
  - The current worktree dir at its exact host path (preserves the absolute path in the `.git` file)
  - The main repo's `.git` dir at its host path (for linked worktrees only)

  We deliberately do NOT mount the parent directory containing all worktrees — that would expose unrelated projects to `--dangerously-skip-permissions`.

**`~/.pen/container-shared/` mount layout** — All containers get two mounts at their exact host paths (mirrored, so the path is identical on both sides):
  - `~/.pen/container-shared/ro/` — read-only in container. Contains pen-managed scripts (hooks, etc.). Written by `pen sync-settings`, never writable from inside a container.
  - `~/.pen/container-shared/rw/` — read-write. Contains `claude/` (Claude Code's `CLAUDE_CONFIG_DIR`) and any other shared mutable state. Credentials, settings, memory, history, and session data live here.

  `CLAUDE_CONFIG_DIR` is set explicitly to `~/.pen/container-shared/rw/claude` because Claude Code doesn't reliably derive it from `HOME` inside a container. Since paths are mirrored, `HARNESS_CONFIG` is the same value on host and container — no translation needed.

**macOS Keychain limitation** — On macOS, Claude Code stores auth credentials in the macOS Keychain, which is inaccessible from Linux Docker containers. The session files in `~/.claude/sessions/` are stubs; the real token is in the Keychain. Consequence: a one-time in-container login is required on first use. After that, credentials are stored as plain files in `~/.pen/claude/` and reused by all containers.

**Running as host UID** — `--user $(id -u):$(id -g)` is required because Claude Code refuses `--dangerously-skip-permissions` as root. It also ensures files created in the mounted worktree are owned by the correct user on the host (Docker Desktop on macOS handles the UID mapping transparently).

**Container naming** — Container names are `pen_<basename>` derived from `basename $PWD`, matching the `mkworktree` convention of naming worktree dirs `{project}_{branch}`. A container named `pen_myproject_auth-refactor` corresponds to the worktree at `~/projects/myproject_auth-refactor`. One container per worktree — switching harnesses stops and replaces the container.

**Harness selection** — Resolved in priority order: `--harness=<name>` CLI flag → `.pen.toml` in git root → `~/.pen/config.toml` user default → hardcoded default `claude`. TOML is parsed with grep/sed (no external dependencies).

**Explicit container name args** — `cmd_exec` and `cmd_stop` accept an optional container name argument. When provided, `_is_pen_container` validates the name against `docker ps --filter label=pen=true` before acting, so they can never operate on a container not created by pen. Without an argument they fall back to `container_name()` (derived from `$PWD`), where no validation is needed since we created the name ourselves.

**Prompt/flag passthrough** — The `case` dispatch routes everything that isn't `exec`, `stop`, `list`, or `sync-settings` to `cmd_launch "${passthrough_args[@]}"`. The `--harness=` flag is stripped before dispatch. This means any harness flag or positional prompt is forwarded directly to the harness command inside the container. There is no usage-error path for unrecognized args.

**`cmd_list --names-only`** — Outputs one container name per line with no header, used by the shell completion scripts to populate `exec`/`stop` completions.

**`sync-settings` is claude-only** — `cmd_sync` errors immediately if `$HARNESS != claude`. Other harnesses can add their own sync commands when needed.

**`sync-settings` manages guardrails hook** — Every `pen sync-settings` run creates `~/.pen/container-shared/{ro,rw}/` and writes `~/.pen/container-shared/ro/hooks/pen-guardrails.sh` (always up-to-date, read-only from container). It also injects a `PreToolUse` hook registration into the Claude settings.json. The hook blocks `gh pr create`, `git push --force`, and `git push` to protected branches (main/master/develop). User-owned hooks in other event types (Stop, UserPromptSubmit, etc.) are preserved. Do not hand-edit `pen-guardrails.sh` — it is overwritten on every sync.

**`pen merge`** — Host-side command to merge the current worktree's branch into the main worktree. Run from the feature worktree after reviewing pen's work. Runs entirely on the host (no Docker). Does a `--no-ff` merge into whatever branch is checked out at the main worktree.

**MCP `allowedTools` for read-only access** — `sync-settings` preserves `mcpServers` from the destination `~/.pen/container-shared/rw/claude/settings.json`. Add MCP servers there directly; they will never be overwritten. Use `allowedTools` per server to restrict to read-only operations:

```json
"mcpServers": {
  "slack": {
    "command": "...",
    "allowedTools": ["slack_search_messages", "slack_get_channel_history"]
  },
  "jira": {
    "command": "...",
    "allowedTools": ["jira_get_issue", "jira_search_issues", "jira_get_project"]
  }
}
```

Different machines can have different MCP servers — the field is user-local and not checked into the repo.

**Separate image per harness** — `pen-claude:latest` for Claude, `pen-cursor:latest` for Cursor (when implemented), etc. The `PEN_IMAGE` env var overrides the image for any harness.

## Things to be careful about

- Do not widen the mount scope (e.g., mounting `~/projects/`) — it defeats the isolation purpose.
- `_ensure_config` only seeds `~/.pen/<harness>/` if the directory doesn't exist yet. If the dir was created empty by an earlier run, seeding is skipped. Manual seeding for claude: copy `settings.json`, `sessions/`, `session-env/`, `CLAUDE.md` from `~/.claude/`.
- Both `cmd_stop` and `cmd_exec` use `docker rm -f` / `docker exec` respectively. Stopped containers are removed and recreated on next launch rather than restarted — this avoids issues with stale container configs from previous script versions.
- `configure_harness` is only called at the main entry point (after `BASH_SOURCE[0] == ${0}` check). Tests must set `HARNESS`, `HARNESS_IMAGE`, `HARNESS_CONFIG` directly in `setup()` or per-test. `HARNESS_CONTAINER_CONFIG` no longer exists — all paths mirror the host.
