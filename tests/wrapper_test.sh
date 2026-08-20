#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
fake_bin="$test_dir/bin"
args_file="$test_dir/docker.args"
env_file="$test_dir/docker.env"
mkdir -p "$test_home/lib/node_modules/.bin" "$fake_bin"

cat >"$test_home/lib/node_modules/.bin/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$test_home/lib/node_modules/.bin/codex"

cat >"$fake_bin/docker" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$DOCKER_ARGS_FILE"
printf '%s' "${HERDR_AGENT-}" >"$DOCKER_ENV_FILE"
EOF
chmod +x "$fake_bin/docker"

cat >"$fake_bin/timedatectl" <<'EOF'
#!/bin/sh
printf '%s\n' Asia/Tokyo
EOF
chmod +x "$fake_bin/timedatectl"

run_wrapper() {
  : >"$args_file"
  HOME="$test_home" \
    PATH="$test_home/lib/node_modules/.bin:$fake_bin:/usr/bin:/bin" \
    DOCKER_ARGS_FILE="$args_file" \
    DOCKER_ENV_FILE="$env_file" \
    "$@"
  mapfile -d '' docker_args <"$args_file"
}

contains_arg() {
  local expected="$1" arg
  for arg in "${docker_args[@]}"; do
    [[ "$arg" == "$expected" ]] && return 0
  done
  return 1
}

not_contains_arg() {
  ! contains_arg "$1"
}

assert_docker_env() {
  [[ "$(<"$env_file")" == "$1" ]] || fail "Docker process environment differs"
}

assert_tail() {
  local -a expected=("$@") actual=()
  local image_index=-1 i
  for i in "${!docker_args[@]}"; do
    if [[ "${docker_args[i]}" == reg.nemui.org/cclaude/cclaude ]]; then
      image_index=$i
      break
    fi
  done
  ((image_index >= 0)) || fail "Docker image missing from argument vector"
  actual=("${docker_args[@]:image_index}")
  if ((${#actual[@]} != ${#expected[@]})); then
    fail "Docker tail length differs"
  fi
  for i in "${!expected[@]}"; do
    [[ "${actual[i]}" == "${expected[i]}" ]] || {
      printf 'FAIL: Docker tail differs at index %s: expected <%q>, got <%q>\n' \
        "$i" "${expected[i]}" "${actual[i]}" >&2
      exit 1
    }
  done
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_wrapper "$repo_dir/cclaude" --version
contains_arg reg.nemui.org/cclaude/cclaude || fail "Claude image missing"
contains_arg seccomp=unconfined || fail "Claude seccomp compatibility option missing"
contains_arg apparmor=unconfined || fail "Claude AppArmor compatibility option missing"
not_contains_arg HERDR_AGENT || fail "Claude forwarded HERDR_AGENT to the container"
assert_docker_env claude
assert_tail reg.nemui.org/cclaude/cclaude --version

run_wrapper "$repo_dir/ccodex" "prompt with spaces"
contains_arg seccomp=unconfined || fail "Codex seccomp compatibility option missing"
contains_arg apparmor=unconfined || fail "Codex AppArmor compatibility option missing"
not_contains_arg HERDR_AGENT || fail "Codex forwarded HERDR_AGENT to the container"
assert_docker_env codex
assert_tail reg.nemui.org/cclaude/cclaude codex "prompt with spaces"

run_wrapper "$repo_dir/ccodex" exec -- --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec -- --yolo

run_wrapper "$repo_dir/ccodex" --future-option --sandbox danger-full-access
assert_tail reg.nemui.org/cclaude/cclaude codex --future-option --sandbox danger-full-access

printf 'wrapper tests passed\n'
