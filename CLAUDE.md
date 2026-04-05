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

**`~/.pen/<harness>/` as shared config** — All containers (regardless of worktree) mount `~/.pen/<harness>/` as the harness config dir inside the container. This means credentials, settings, and memory are shared across all pen containers for a given harness. For Claude, `CLAUDE_CONFIG_DIR` is set explicitly because Claude doesn't always find the config from `HOME` alone inside a container.

**macOS Keychain limitation** — On macOS, Claude Code stores auth credentials in the macOS Keychain, which is inaccessible from Linux Docker containers. The session files in `~/.claude/sessions/` are stubs; the real token is in the Keychain. Consequence: a one-time in-container login is required on first use. After that, credentials are stored as plain files in `~/.pen/claude/` and reused by all containers.

**Running as host UID** — `--user $(id -u):$(id -g)` is required because Claude Code refuses `--dangerously-skip-permissions` as root. It also ensures files created in the mounted worktree are owned by the correct user on the host (Docker Desktop on macOS handles the UID mapping transparently).

**Container naming** — Container names are `pen_<basename>` derived from `basename $PWD`, matching the `mkworktree` convention of naming worktree dirs `{project}_{branch}`. A container named `pen_myproject_auth-refactor` corresponds to the worktree at `~/projects/myproject_auth-refactor`. One container per worktree — switching harnesses stops and replaces the container.

**Harness selection** — Resolved in priority order: `--harness=<name>` CLI flag → `.pen.toml` in git root → `~/.pen/config.toml` user default → hardcoded default `claude`. TOML is parsed with grep/sed (no external dependencies).

**Explicit container name args** — `cmd_exec` and `cmd_stop` accept an optional container name argument. When provided, `_is_pen_container` validates the name against `docker ps --filter label=pen=true` before acting, so they can never operate on a container not created by pen. Without an argument they fall back to `container_name()` (derived from `$PWD`), where no validation is needed since we created the name ourselves.

**Prompt/flag passthrough** — The `case` dispatch routes everything that isn't `exec`, `stop`, `list`, or `sync-settings` to `cmd_launch "${passthrough_args[@]}"`. The `--harness=` flag is stripped before dispatch. This means any harness flag or positional prompt is forwarded directly to the harness command inside the container. There is no usage-error path for unrecognized args.

**`cmd_list --names-only`** — Outputs one container name per line with no header, used by the shell completion scripts to populate `exec`/`stop` completions.

**`sync-settings` is claude-only** — `cmd_sync` errors immediately if `$HARNESS != claude`. Other harnesses can add their own sync commands when needed.

**Separate image per harness** — `pen-claude:latest` for Claude, `pen-cursor:latest` for Cursor (when implemented), etc. The `PEN_IMAGE` env var overrides the image for any harness.

## Things to be careful about

- Do not widen the mount scope (e.g., mounting `~/projects/`) — it defeats the isolation purpose.
- `_ensure_config` only seeds `~/.pen/<harness>/` if the directory doesn't exist yet. If the dir was created empty by an earlier run, seeding is skipped. Manual seeding for claude: copy `settings.json`, `sessions/`, `session-env/`, `CLAUDE.md` from `~/.claude/`.
- Both `cmd_stop` and `cmd_exec` use `docker rm -f` / `docker exec` respectively. Stopped containers are removed and recreated on next launch rather than restarted — this avoids issues with stale container configs from previous script versions.
- `configure_harness` is only called at the main entry point (after `BASH_SOURCE[0] == ${0}` check). Tests must set `HARNESS`, `HARNESS_IMAGE`, `HARNESS_CONFIG`, `HARNESS_CONTAINER_CONFIG` directly in `setup()` or per-test.
