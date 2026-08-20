#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
fake_bin="$test_dir/bin"
args_file="$test_dir/docker.args"
env_file="$test_dir/docker.env"
seccomp_file="$test_dir/docker.seccomp"
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
for arg in "$@"; do
  case "$arg" in
    seccomp=*) cat "${arg#seccomp=}" >"$DOCKER_SECCOMP_FILE" 2>/dev/null ;;
  esac
done
EOF
chmod +x "$fake_bin/docker"

cat >"$fake_bin/timedatectl" <<'EOF'
#!/bin/sh
printf '%s\n' Asia/Tokyo
EOF
chmod +x "$fake_bin/timedatectl"

run_wrapper() {
  : >"$args_file"
  : >"$seccomp_file"
  HOME="$test_home" \
    PATH="$test_home/lib/node_modules/.bin:$fake_bin:/usr/bin:/bin" \
    DOCKER_ARGS_FILE="$args_file" \
    DOCKER_ENV_FILE="$env_file" \
    DOCKER_SECCOMP_FILE="$seccomp_file" \
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

assert_seccomp_denylist() {
  local label="$1" profile syscall
  profile="$(<"$seccomp_file")"
  [[ -n "$profile" ]] || fail "$label seccomp profile was not passed to docker"
  [[ "$profile" == *'"defaultAction": "SCMP_ACT_ALLOW"'* ]] ||
    fail "$label seccomp profile is not a denylist"
  for syscall in bpf init_module io_uring_setup keyctl perf_event_open userfaultfd; do
    [[ "$profile" == *"\"$syscall\""* ]] || fail "$label seccomp profile no longer denies $syscall"
  done
  # The nested sandboxes need these; denying them defeats the point of the profile.
  for syscall in clone3 mount pivot_root setns unshare; do
    [[ "$profile" != *"\"$syscall\""* ]] || fail "$label seccomp profile denies $syscall"
  done
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
assert_seccomp_denylist Claude
contains_arg apparmor=unconfined || fail "Claude AppArmor compatibility option missing"
not_contains_arg HERDR_AGENT || fail "Claude forwarded HERDR_AGENT to the container"
assert_docker_env claude
assert_tail reg.nemui.org/cclaude/cclaude --version

run_wrapper "$repo_dir/ccodex" "prompt with spaces"
assert_seccomp_denylist Codex
contains_arg apparmor=unconfined || fail "Codex AppArmor compatibility option missing"
not_contains_arg HERDR_AGENT || fail "Codex forwarded HERDR_AGENT to the container"
assert_docker_env codex
assert_tail reg.nemui.org/cclaude/cclaude codex "prompt with spaces"

run_wrapper "$repo_dir/ccodex" exec -- --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec -- --yolo

run_wrapper "$repo_dir/ccodex" --future-option --sandbox danger-full-access
assert_tail reg.nemui.org/cclaude/cclaude codex --future-option --sandbox danger-full-access

printf 'wrapper tests passed\n'
