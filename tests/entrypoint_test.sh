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

cat >"$test_dir/sudo" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$SUDO_RESULT"
shift
[[ "$1" == -u ]] || exit 2
shift 2
exec "$@"
EOF

chmod +x "$test_dir/claude" "$test_dir/codex" "$test_dir/sudo"
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

mkdir -p "$test_dir/home"
USER=codexuser HOME="$test_dir/home" ENTRYPOINT_RESULT="$result" SUDO_RESULT="$test_dir/sudo-result" \
  PATH="$test_dir:/usr/bin:/bin" \
  "$repo_dir/entrypoint" codex --version

mapfile -d '' sudo_actual <"$test_dir/sudo-result"
[[ "${sudo_actual[0]}" == -E && "${sudo_actual[1]}" == -u && "${sudo_actual[2]}" == codexuser ]] || {
  printf 'FAIL: entrypoint did not drop privileges through sudo\n' >&2
  exit 1
}
mapfile -d '' actual <"$result"
[[ "${actual[0]}" == codex && "${actual[1]}" == --version ]] || {
  printf 'FAIL: entrypoint lost Codex command after sudo\n' >&2
  exit 1
}

printf 'entrypoint tests passed\n'
