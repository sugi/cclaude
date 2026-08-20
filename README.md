# cclaude

A shared Docker image and wrapper scripts for running Claude Code or Codex in a
container, with common development tools (git, gh, ripgrep, jq, Python, Node.js,
Rust, Fastly CLI, and Podman) bundled in.

## Build

```sh
docker compose build
```

## Run

```sh
./cclaude [claude-args...]
./ccodex [codex-args...]
./ccodex -a never
./ccodex --dangerously-bypass-approvals-and-sandbox
./ccodex --sandbox danger-full-access
```

`ccodex` requires the Codex command on the host, installed in either
`~/.local/bin` or `~/lib/node_modules/.bin`. Both locations are mounted into
the container, together with the current directory and relevant host
configuration (including Claude/Codex state, git/gh configuration, and
language toolchains).

The wrapper passes Codex arguments through unchanged and leaves its approval
and sandbox policy to Codex. Claude Code sandboxes with bubblewrap, which needs
unprivileged user namespaces, so the wrapper turns off Docker's AppArmor profile
and swaps its seccomp profile for a denylist carrying Docker's own default
denials minus the namespace and mount group. Codex sandboxes with Landlock
and needs neither.

## Containers inside the container

`docker` is podman-docker over rootless Podman, and `docker compose` is
Compose v2, so the usual commands work unchanged. The image store lives in
`~/.local/share/cclaude/containers` on the host and appears at the usual
`~/.local/share/containers` inside, which keeps images across `--rm` runs
without disturbing the host's own Podman store, whose ids are mapped
differently.

The first `docker compose` command of a session starts Podman's API service in
the background, since Compose speaks the Docker API and the container has no
systemd to socket-activate it.

Three things differ from Docker on the host:

- Resource limits are ignored. `--memory` and `--cpus` are accepted and have no
  effect, because `/sys/fs/cgroup` is mounted read-only and Podman does not
  report the failure.
- Published ports land on the cclaude container, not on the host's localhost.
  Reach them from the host through the container's address, which
  `docker inspect` will report for the running cclaude container.
- Stored layers are owned by subordinate ids, which the host user cannot remove
  directly. Clear them from inside the container with `podman rmi -a`, or
  `podman unshare rm -rf ~/.local/share/containers` to drop the store entirely.

Rootless Podman needs more room than bubblewrap does, so the wrapper also grants
CAP_SYS_ADMIN (`newuidmap` cannot otherwise write a uid_map for a namespace it
does not own) and unmasks the system paths under `/proc` (a masked `/proc`
blocks the nested procfs mount). To keep that reach away from the agent, the
entrypoint drops to the user through `setpriv` with a bounding set holding only
the four capabilities `newuidmap` needs, and the image ships no setuid binaries
apart from `newuidmap` and `newgidmap`. Containers started by Podman are
unaffected by that bounding set, since a new user namespace resets it.

The container is not a security boundary for its mounts. Either CLI can read
mounted credentials and sockets, interact with mounted devices and reachable
network endpoints, and modify writable host content. In particular, writable
language toolchains and global Node packages can be changed in the container
and later executed on the host.
