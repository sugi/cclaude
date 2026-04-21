# cclaude

A Docker image and wrapper script for running the Claude Code CLI in a container, with common development tools (git, gh, ripgrep, jq, python3, rustup, Fastly CLI, etc.) bundled in.

## Build

```sh
docker compose build
```

## Run

```sh
./cclaude [claude-args...]
```

The wrapper mounts the current directory and relevant host configs (Claude state, git/gh/aws configs, language toolchains) into the container.
