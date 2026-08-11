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

Normal Codex runs use `workspace-write` plus `on-request`. Docker seccomp and
AppArmor are relaxed for normal Codex mode so Codex can create its inner
`bwrap` sandbox.

`--dangerously-bypass-approvals-and-sandbox` and `--yolo` skip approval
prompts and the inner sandbox. `--sandbox danger-full-access` disables the
inner filesystem sandbox, but does not itself disable approvals: the explicit
approval policy still applies, or `on-request` remains the default. These
danger modes keep Docker's default seccomp and AppArmor profiles, but they do
not make the container a security boundary for its mounts. Codex can read the
mounted credentials and sockets, interact with mounted devices and reachable
network endpoints, and modify writable host content. In particular, writable
language toolchains and global Node packages can be changed in the container
and later executed on the host.
