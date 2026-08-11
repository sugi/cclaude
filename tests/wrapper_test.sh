#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
fake_bin="$test_dir/bin"
args_file="$test_dir/docker.args"
error_file="$test_dir/wrapper.err"
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

run_rejected_wrapper() {
  : >"$args_file"
  : >"$error_file"
  if HOME="$test_home" \
    PATH="$test_home/lib/node_modules/.bin:$fake_bin:/usr/bin:/bin" \
    DOCKER_ARGS_FILE="$args_file" \
    "$@" >"$test_dir/wrapper.out" 2>"$error_file"; then
    fail "ambiguous Codex arguments unexpectedly reached Docker"
  fi
  [[ ! -s "$args_file" ]] || fail "ambiguous Codex arguments invoked Docker"
  rg -q '^ccodex: cannot safely classify Codex arguments:' "$error_file" || \
    fail "ambiguous Codex arguments lacked a concise diagnostic"
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
  assert_security_pairs "${expected[@]}"
}

assert_security_pairs() {
  local -a tail=("$@") actual=() expected=()
  local image_index=-1 i sandbox_value="" bypass=false codex_tail=false tail_mode=root
  for i in "${!docker_args[@]}"; do
    if [[ "${docker_args[i]}" == reg.nemui.org/cclaude/cclaude ]]; then
      image_index=$i
      break
    fi
  done
  ((image_index >= 0)) || fail "Docker image missing from argument vector"
  for ((i = 0; i < image_index; i++)); do
    if [[ "${docker_args[i]}" == --security-opt ]]; then
      ((i + 1 < image_index)) || fail "Docker security option lacks a value"
      actual+=("${docker_args[i]}" "${docker_args[i + 1]}")
      ((i += 1))
    fi
  done
  for ((i = 0; i < ${#tail[@]}; i++)); do
    [ "${tail[i]}" = -- ] && break
    [ "${tail[i]}" = codex ] && codex_tail=true
    case "${tail[i]}" in
      reg.nemui.org/cclaude/cclaude)
        continue
        ;;
      codex)
        continue
        ;;
      --dangerously-bypass-approvals-and-sandbox|--yolo)
        bypass=true
        ;;
      --sandbox|-s)
        ((i + 1 < ${#tail[@]})) || continue
        sandbox_value="${tail[i + 1]}"
        ((i += 1))
        ;;
      --sandbox=*|-s=*)
        sandbox_value="${tail[i]#*=}"
        ;;
      -s?*)
        sandbox_value="${tail[i]:2}"
        ;;
      --ask-for-approval|-a)
        ((i + 1 < ${#tail[@]})) && ((i += 1))
        ;;
      --image|-i)
        while ((i + 1 < ${#tail[@]})) && [[ "${tail[i + 1]}" != -- && "${tail[i + 1]}" != -* ]]; do
          ((i += 1))
        done
        ;;
      --image=*|-i?*)
        while ((i + 1 < ${#tail[@]})) && [[ "${tail[i + 1]}" != -- && "${tail[i + 1]}" != -* ]]; do
          ((i += 1))
        done
        ;;
      -*)
        ;;
      *)
        case "$tail_mode:${tail[i]}" in
          root:exec|root:resume|root:fork)
            tail_mode=agent
            ;;
          root:review|root:login|root:logout|root:mcp|root:plugin|root:mcp-server|root:app-server|root:remote-control|root:completion|root:update|root:doctor|root:sandbox|root:debug|root:apply|root:archive|root:delete|root:unarchive|root:cloud|root:exec-server|root:features|root:help)
            break
            ;;
          root:*)
            tail_mode=interactive
            ;;
        esac
        ;;
    esac
  done
  if [ "$codex_tail" = true ] && [ "$bypass" = false ] && [ "$sandbox_value" != danger-full-access ]; then
    expected=(--security-opt seccomp=unconfined --security-opt apparmor=unconfined)
  fi
  if ((${#actual[@]} != ${#expected[@]})); then
    fail "Docker security pair count differs"
  fi
  for i in "${!expected[@]}"; do
    [[ "${actual[i]}" == "${expected[i]}" ]] || fail "Docker security pairs differ"
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

run_rejected_wrapper "$repo_dir/ccodex" -a --yolo

run_wrapper "$repo_dir/ccodex" --dangerously-bypass-approvals-and-sandbox
not_contains_arg seccomp=unconfined || fail "bypass relaxed Docker seccomp"
not_contains_arg apparmor=unconfined || fail "bypass relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --dangerously-bypass-approvals-and-sandbox

run_wrapper "$repo_dir/ccodex" --yolo
not_contains_arg seccomp=unconfined || fail "yolo relaxed Docker seccomp"
not_contains_arg apparmor=unconfined || fail "yolo relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex --yolo

run_rejected_wrapper "$repo_dir/ccodex" --sandbox --yolo

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

run_rejected_wrapper "$repo_dir/ccodex" -s

run_rejected_wrapper "$repo_dir/ccodex" -a

run_rejected_wrapper "$repo_dir/ccodex" --future-option --sandbox danger-full-access

run_wrapper "$repo_dir/ccodex" -i first.png sandbox --yolo
not_contains_arg seccomp=unconfined || fail "variadic image values hid yolo"
not_contains_arg apparmor=unconfined || fail "variadic image values relaxed Docker AppArmor"
assert_tail reg.nemui.org/cclaude/cclaude codex -i first.png sandbox --yolo

run_rejected_wrapper "$repo_dir/ccodex" -i --yolo

run_rejected_wrapper "$repo_dir/ccodex" --image= --yolo

run_rejected_wrapper "$repo_dir/ccodex" -i '' --yolo

run_wrapper "$repo_dir/ccodex" exec -- --yolo
contains_arg seccomp=unconfined || fail "exec payload bypassed inner sandbox"
assert_tail reg.nemui.org/cclaude/cclaude codex --sandbox workspace-write --ask-for-approval on-request exec -- --yolo

run_wrapper "$repo_dir/ccodex" exec - --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec - --yolo

run_wrapper "$repo_dir/ccodex" - --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex - --yolo

run_wrapper "$repo_dir/ccodex" resume - --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex resume - --yolo

run_wrapper "$repo_dir/ccodex" fork - --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex fork - --yolo

run_wrapper "$repo_dir/ccodex" --psp --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex --psp --yolo

run_wrapper "$repo_dir/ccodex" exec review --uncommitted --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec review --uncommitted --yolo

run_wrapper "$repo_dir/ccodex" exec review --base main --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec review --base main --yolo

run_wrapper "$repo_dir/ccodex" exec review --commit abc123 --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec review --commit abc123 --yolo

run_wrapper "$repo_dir/ccodex" exec review --title title --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec review --title title --yolo

run_wrapper "$repo_dir/ccodex" exec -o - --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec -o - --yolo

run_wrapper "$repo_dir/ccodex" exec -i - --yolo
assert_tail reg.nemui.org/cclaude/cclaude codex exec -i - --yolo

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
