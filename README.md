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
```

`ccodex` requires the Codex command on the host, installed in either
`~/.local/bin` or `~/lib/node_modules/.bin`. Both locations are mounted into
the container, together with the current directory and relevant host
configuration (including Claude/Codex state, git/gh/aws configuration, and
language toolchains).

Normal Codex runs use `workspace-write` plus `on-request`. Docker seccomp and
AppArmor are relaxed only so Codex can create its inner `bwrap` sandbox.
`--dangerously-bypass-approvals-and-sandbox` keeps Docker's default profiles,
but exposes every mounted workspace, configuration directory,
credential/socket, device, and network endpoint to Codex.
