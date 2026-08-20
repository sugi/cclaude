#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat >"$test_dir/claude" <<'EOF'
#!/bin/bash
printf 'claude\0%s\0' "$@" >"$ENTRYPOINT_RESULT"
EOF

cat >"$test_dir/codex" <<'EOF'
#!/bin/bash
printf 'codex\0%s\0' "$@" >"$ENTRYPOINT_RESULT"
EOF

cat >"$test_dir/setpriv" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$SETPRIV_RESULT"
while [[ $# -gt 0 && "$1" != -- ]]; do shift; done
shift
exec "$@"
EOF

chmod +x "$test_dir/claude" "$test_dir/codex" "$test_dir/setpriv"
result="$test_dir/result"

USER= ENTRYPOINT_RESULT="$result" PATH="$test_dir:/usr/bin:/bin" \
  "$repo_dir/entrypoint" codex --version

mapfile -d '' actual <"$result"
[[ "${actual[0]}" == codex ]] || {
  printf 'FAIL: entrypoint selected %s\n' "${actual[0]}" >&2
  exit 1
}
[[ "${actual[1]}" == --version ]] || {
  printf 'FAIL: entrypoint changed Codex arguments\n' >&2
  exit 1
}

# setpriv resolves the user through /etc/passwd, so the drop has to be
# rehearsed with a name that actually exists.
test_user="$(id -un)"
mkdir -p "$test_dir/home"
USER="$test_user" HOME="$test_dir/home" ENTRYPOINT_RESULT="$result" \
  SETPRIV_RESULT="$test_dir/setpriv-result" \
  PATH="$test_dir:/usr/bin:/bin" \
  "$repo_dir/entrypoint" codex --version

mapfile -d '' setpriv_actual <"$test_dir/setpriv-result"

setpriv_has() {
  local expected="$1" arg
  for arg in "${setpriv_actual[@]}"; do
    [[ "$arg" == "$expected" ]] && return 0
  done
  printf 'FAIL: entrypoint dropped privileges without %s\n' "$expected" >&2
  exit 1
}

setpriv_has "--reuid=$test_user"
setpriv_has "--regid=$(id -g "$test_user")"
setpriv_has --init-groups
# newuidmap is setuid root and needs these four; dropping sys_admin here breaks
# rootless Podman just as surely as dropping the capability from docker run.
setpriv_has --bounding-set=-all,+sys_admin,+setuid,+setgid,+dac_override

mapfile -d '' actual <"$result"
[[ "${actual[0]}" == codex && "${actual[1]}" == --version ]] || {
  printf 'FAIL: entrypoint lost Codex command after dropping privileges\n' >&2
  exit 1
}

printf 'entrypoint tests passed\n'
