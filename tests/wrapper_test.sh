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
contains_arg HERDR_AGENT=claude || fail "Claude agent environment missing"
assert_tail reg.nemui.org/cclaude/cclaude --version

run_wrapper "$repo_dir/ccodex" "prompt with spaces"
contains_arg seccomp=unconfined || fail "default Codex seccomp option missing"
contains_arg apparmor=unconfined || fail "default Codex AppArmor option missing"
contains_arg HERDR_AGENT=codex || fail "Codex agent environment missing"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request "prompt with spaces"

run_wrapper "$repo_dir/ccodex" -a never
contains_arg seccomp=unconfined || fail "never mode lost inner sandbox support"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write -a never

run_wrapper "$repo_dir/ccodex" -a --yolo
contains_arg seccomp=unconfined || fail "approval value was reinterpreted as yolo"
contains_arg apparmor=unconfined || fail "approval value disabled Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write -a --yolo

run_wrapper "$repo_dir/ccodex" --dangerously-bypass-approvals-and-sandbox
not_contains_arg seccomp=unconfined || fail "bypass relaxed Docker seccomp"
not_contains_arg apparmor=unconfined || fail "bypass relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --dangerously-bypass-approvals-and-sandbox

run_wrapper "$repo_dir/ccodex" --yolo
not_contains_arg seccomp=unconfined || fail "yolo relaxed Docker seccomp"
not_contains_arg apparmor=unconfined || fail "yolo relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --yolo

run_wrapper "$repo_dir/ccodex" --sandbox --yolo
contains_arg seccomp=unconfined || fail "sandbox value was reinterpreted as yolo"
contains_arg apparmor=unconfined || fail "sandbox value disabled Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --ask-for-approval on-request --sandbox --yolo

run_wrapper "$repo_dir/ccodex" --sandbox read-only
contains_arg seccomp=unconfined || fail "read-only mode cannot start bwrap"
assert_tail reg.nemui.org/cclaude/cclaude codex --ask-for-approval on-request --sandbox read-only

run_wrapper "$repo_dir/ccodex" -s danger-full-access
not_contains_arg seccomp=unconfined || fail "full access relaxed Docker seccomp"
not_contains_arg apparmor=unconfined || fail "full access relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --ask-for-approval on-request -s danger-full-access

run_wrapper "$repo_dir/ccodex" -sdanger-full-access
not_contains_arg seccomp=unconfined || fail "attached full access relaxed Docker seccomp"
not_contains_arg apparmor=unconfined || fail "attached full access relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --ask-for-approval on-request -sdanger-full-access

run_wrapper "$repo_dir/ccodex" -anever
contains_arg seccomp=unconfined || fail "attached approval lost inner sandbox support"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write -anever

run_wrapper "$repo_dir/ccodex" --sandbox=read-only --ask-for-approval=never
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox=read-only --ask-for-approval=never

run_wrapper "$repo_dir/ccodex" -s=read-only -a=never
assert_tail reg.nemui.org/cclaude/cclaude codex -s=read-only -a=never

run_wrapper "$repo_dir/ccodex" -s read-only --sandbox danger-full-access
assert_tail reg.nemui.org/cclaude/cclaude codex --ask-for-approval on-request -s read-only --sandbox danger-full-access

run_wrapper "$repo_dir/ccodex" --sandbox danger-full-access -s read-only
contains_arg seccomp=unconfined || fail "last sandbox policy was not applied"
assert_tail reg.nemui.org/cclaude/cclaude codex --ask-for-approval on-request --sandbox danger-full-access -s read-only

run_wrapper "$repo_dir/ccodex" -s
contains_arg seccomp=unconfined || fail "missing sandbox value unconfined Docker"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request -s

run_wrapper "$repo_dir/ccodex" -a
contains_arg seccomp=unconfined || fail "missing approval value unconfined Docker"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request -a

run_wrapper "$repo_dir/ccodex" --future-option --sandbox danger-full-access
contains_arg seccomp=unconfined || fail "unknown option relaxed Docker security"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request --future-option --sandbox danger-full-access

run_wrapper "$repo_dir/ccodex" -i first.png sandbox --yolo
not_contains_arg seccomp=unconfined || fail "variadic image values hid yolo"
not_contains_arg apparmor=unconfined || fail "variadic image values relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex -i first.png sandbox --yolo

run_wrapper "$repo_dir/ccodex" -i --yolo
contains_arg seccomp=unconfined || fail "missing image value bypassed inner sandbox"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request -i --yolo

run_wrapper "$repo_dir/ccodex" --image= --yolo
contains_arg seccomp=unconfined || fail "empty image value bypassed inner sandbox"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request --image= --yolo

run_wrapper "$repo_dir/ccodex" exec -- --yolo
contains_arg seccomp=unconfined || fail "exec payload bypassed inner sandbox"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request exec -- --yolo

run_wrapper "$repo_dir/ccodex" sandbox command --yolo
contains_arg seccomp=unconfined || fail "sandbox command payload bypassed inner sandbox"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request sandbox command --yolo

run_wrapper "$repo_dir/ccodex" exec -sdanger-full-access -anever prompt
assert_tail reg.nemui.org/cclaude/cclaude codex exec -sdanger-full-access -anever prompt

run_wrapper "$repo_dir/ccodex" resume -s read-only -a never --last
contains_arg seccomp=unconfined || fail "resume policy lost inner sandbox support"
assert_tail reg.nemui.org/cclaude/cclaude codex resume -s read-only -a never --last

run_wrapper "$repo_dir/ccodex" fork --sandbox=danger-full-access --ask-for-approval=never --last
assert_tail reg.nemui.org/cclaude/cclaude codex fork --sandbox=danger-full-access --ask-for-approval=never --last

printf 'wrapper tests passed\n'
