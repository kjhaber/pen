# claude-devcon

## Test command

```sh
make test
```

Runs `bats tests/test_script.bats` (unit tests) and `bash tests/test_image.sh` (Docker image checks). Requires `bats-core` (`brew install bats-core`) and a built image (`make build`).

## Architecture decisions

**`sleep infinity` + `docker exec`** — The container's main process is `sleep infinity`, not `claude`. Claude is exec'd in on each invocation. This means Claude can exit without stopping the container, and multiple sessions can be opened into the same container (`claude-devcon exec` for a shell, re-running `claude-devcon` for a new Claude session).

**Mounting strategy for git worktrees** — Worktrees have a `.git` *file* (not directory) containing an absolute host path to the main repo's `.git` dir. To keep the blast radius tight while still letting git work, we mount only:
  - The current worktree dir at its exact host path (preserves the absolute path in the `.git` file)
  - The main repo's `.git` dir at its host path (for linked worktrees only)

  We deliberately do NOT mount the parent directory containing all worktrees — that would expose unrelated projects to `--dangerously-skip-permissions`.

**`~/.claude-devcon/` as shared config** — All containers (regardless of worktree) mount `~/.claude-devcon/` as `/home/devcon/.claude`. This means credentials, settings, and memory are shared across all devcon containers. `CLAUDE_CONFIG_DIR` is set explicitly because Claude doesn't always find the config from `HOME` alone inside a container.

**macOS Keychain limitation** — On macOS, Claude Code stores auth credentials in the macOS Keychain, which is inaccessible from Linux Docker containers. The session files in `~/.claude/sessions/` are stubs; the real token is in the Keychain. Consequence: a one-time in-container login is required on first use. After that, credentials are stored as plain files in `~/.claude-devcon/` and reused by all containers.

**Running as host UID** — `--user $(id -u):$(id -g)` is required because Claude Code refuses `--dangerously-skip-permissions` as root. It also ensures files created in the mounted worktree are owned by the correct user on the host (Docker Desktop on macOS handles the UID mapping transparently).

**Container naming** — Container names are derived from `basename $PWD`, matching the `mkworktree` convention of naming worktree dirs `{project}_{branch}`. A container named `devcon_auth-refactor` corresponds to the worktree at `~/projects/devcon_auth-refactor`.

**Explicit container name args** — `cmd_exec` and `cmd_stop` accept an optional container name argument. When provided, `_is_devcon_container` validates the name against `docker ps --filter label=claude-devcon=true` before acting, so they can never operate on a container not created by claude-devcon. Without an argument they fall back to `container_name()` (derived from `$PWD`), where no validation is needed since we created the name ourselves.

**Prompt/flag passthrough** — The `case` dispatch routes everything that isn't `exec`, `stop`, or `list` to `cmd_launch "$@"`. This means any `claude` flag or positional prompt (e.g. `claude-devcon "fix the bug"`, `claude-devcon --print "..."`) is forwarded directly to `claude --dangerously-skip-permissions "$@"` inside the container. There is no usage-error path for unrecognized args.

**`cmd_list --names-only`** — Outputs one container name per line with no header, used by the shell completion scripts to populate `exec`/`stop` completions.

## Things to be careful about

- Do not widen the mount scope (e.g., mounting `~/projects/`) — it defeats the isolation purpose.
- `_ensure_config` only seeds `~/.claude-devcon/` if the directory doesn't exist yet. If the dir was created empty by an earlier run, seeding is skipped. Manual seeding: copy `settings.json`, `sessions/`, `session-env/`, `CLAUDE.md` from `~/.claude/`.
- Both `cmd_stop` and `cmd_exec` use `docker rm -f` / `docker exec` respectively. Stopped containers are removed and recreated on next launch rather than restarted — this avoids issues with stale container configs from previous script versions.
