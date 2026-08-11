#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
fake_bin="$test_dir/bin"
args_file="$test_dir/docker.args"
mkdir -p "$test_home/lib/node_modules/.bin" "$fake_bin"

cat >"$test_home/lib/node_modules/.bin/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$test_home/lib/node_modules/.bin/codex"

cat >"$fake_bin/docker" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$DOCKER_ARGS_FILE"
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

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_wrapper "$repo_dir/cclaude" --version
contains_arg reg.nemui.org/cclaude/cclaude || fail "Claude image missing"
not_contains_arg codex || fail "Claude unexpectedly selected Codex"

run_wrapper "$repo_dir/ccodex" "prompt with spaces"
contains_arg seccomp=unconfined || fail "default Codex seccomp option missing"
contains_arg apparmor=unconfined || fail "default Codex AppArmor option missing"
contains_arg workspace-write || fail "default Codex sandbox missing"
contains_arg on-request || fail "default Codex approval missing"
contains_arg "prompt with spaces" || fail "spaced argument was split"

run_wrapper "$repo_dir/ccodex" -a never
contains_arg seccomp=unconfined || fail "never mode lost inner sandbox support"
contains_arg never || fail "never approval option missing"
not_contains_arg on-request || fail "default approval conflicts with explicit policy"

run_wrapper "$repo_dir/ccodex" -a --yolo
contains_arg seccomp=unconfined || fail "approval value was reinterpreted as yolo"
contains_arg apparmor=unconfined || fail "approval value disabled Docker AppArmor"

run_wrapper "$repo_dir/ccodex" --dangerously-bypass-approvals-and-sandbox
not_contains_arg seccomp=unconfined || fail "bypass disabled Docker seccomp"
not_contains_arg apparmor=unconfined || fail "bypass disabled Docker AppArmor"
not_contains_arg workspace-write || fail "bypass retained default sandbox"
not_contains_arg on-request || fail "bypass retained default approval"

run_wrapper "$repo_dir/ccodex" --yolo
not_contains_arg seccomp=unconfined || fail "yolo disabled Docker seccomp"
not_contains_arg apparmor=unconfined || fail "yolo disabled Docker AppArmor"

run_wrapper "$repo_dir/ccodex" --sandbox --yolo
contains_arg seccomp=unconfined || fail "sandbox value was reinterpreted as yolo"
contains_arg apparmor=unconfined || fail "sandbox value disabled Docker AppArmor"

run_wrapper "$repo_dir/ccodex" --sandbox read-only
contains_arg seccomp=unconfined || fail "read-only mode cannot start bwrap"
not_contains_arg workspace-write || fail "explicit read-only mode got default sandbox"

run_wrapper "$repo_dir/ccodex" -s danger-full-access
not_contains_arg seccomp=unconfined || fail "full access disabled Docker seccomp"
not_contains_arg apparmor=unconfined || fail "full access disabled Docker AppArmor"
contains_arg on-request || fail "full access lost default approval"

printf 'wrapper tests passed\n'
