# cclaude

A shared Docker image and wrapper scripts for running Claude Code or Codex in a
container, with common development tools (git, gh, ripgrep, jq, Python, Node.js,
Rust, and Fastly CLI) bundled in.

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
denials minus the namespace and mount syscalls. Codex sandboxes with Landlock
and needs neither.

The container is not a security boundary for its mounts. Either CLI can read
mounted credentials and sockets, interact with mounted devices and reachable
network endpoints, and modify writable host content. In particular, writable
language toolchains and global Node packages can be changed in the container
and later executed on the host.
