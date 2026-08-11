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

chmod +x "$test_dir/claude" "$test_dir/codex"
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

printf 'entrypoint tests passed\n'
