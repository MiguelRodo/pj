#!/usr/bin/env bash

operator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
pj="$operator_dir/pj"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home/planning" "$tmp/bin" || exit 1

cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'codex'
for arg in "$@"; do
  printf '\n<%s>' "$arg"
done
printf '\n'
EOF

cat > "$tmp/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf 'copilot'
for arg in "$@"; do
  printf '\n<%s>' "$arg"
done
printf '\n'
EOF

chmod +x "$tmp/bin/codex" "$tmp/bin/copilot" || exit 1

run_pj() {
  HOME="$tmp/home" \
    PJ_WORKSPACE="$tmp/home/planning" \
    XDG_CONFIG_HOME="$tmp/home/.config" \
    PATH="$tmp/bin:$PATH" \
    bash "$pj" "$@"
}

assert_contains() {
  output="$1"
  expected="$2"
  case "$output" in
    *"$expected"*) ;;
    *)
      printf 'Expected output to contain: %s\nActual output:\n%s\n' "$expected" "$output" >&2
      exit 1
      ;;
  esac
}

assert_not_contains() {
  output="$1"
  unexpected="$2"
  case "$output" in
    *"$unexpected"*)
      printf 'Expected output not to contain: %s\nActual output:\n%s\n' "$unexpected" "$output" >&2
      exit 1
      ;;
    *) ;;
  esac
}

# -o is the short pj-level alias for --oneshot.
oneshot="$(PJ_BACKEND=copilot PJ_SESSION_MODE=interactive run_pj -o -- 'Exit after this turn')" || exit 1
assert_contains "$oneshot" 'copilot'
assert_contains "$oneshot" '<-p>'
assert_not_contains "$oneshot" '<-i>'
assert_contains "$oneshot" '<Exit after this turn>'

# pj-owned options can be combined in either order before request text begins.
queue_oneshot_short="$(PJ_BACKEND=copilot PJ_SESSION_MODE=interactive run_pj -i -o)" || exit 1
assert_contains "$queue_oneshot_short" 'copilot'
assert_contains "$queue_oneshot_short" '<-p>'
assert_not_contains "$queue_oneshot_short" '<-i>'
assert_contains "$queue_oneshot_short" 'Process the Chat implementation queue across the managed repositories in this workspace.'

queue_oneshot_long="$(PJ_BACKEND=copilot PJ_SESSION_MODE=interactive run_pj -i --oneshot --repo projects)" || exit 1
assert_contains "$queue_oneshot_long" '<-p>'
assert_not_contains "$queue_oneshot_long" '<-i>'
assert_contains "$queue_oneshot_long" "Restrict queue discovery to the repository selector 'projects'"

queue_mixed_order="$(PJ_SESSION_MODE=interactive run_pj -r projects --backend copilot -i -o)" || exit 1
assert_contains "$queue_mixed_order" 'copilot'
assert_contains "$queue_mixed_order" '<-p>'
assert_not_contains "$queue_mixed_order" '<-i>'
assert_contains "$queue_mixed_order" "Restrict queue discovery to the repository selector 'projects'"

# Queue mode accepts a bare repository name through -r/--repo.
bare_repo="$(PJ_BACKEND=codex run_pj -i -r issues)" || exit 1
assert_contains "$bare_repo" '<exec>'
assert_contains "$bare_repo" "Restrict queue discovery to the repository selector 'issues'"
assert_contains "$bare_repo" 'local-implementation-queue.md'

# owner/repo is accepted as the exact managed repository selector form.
full_repo="$(PJ_BACKEND=codex run_pj --implement-chat --repo MiguelRodo/projects)" || exit 1
assert_contains "$full_repo" "Restrict queue discovery to the repository selector 'MiguelRodo/projects'"

# --repo=REPOSITORY is equivalent.
equals_repo="$(PJ_BACKEND=codex run_pj --implement-chat --repo=projects)" || exit 1
assert_contains "$equals_repo" "Restrict queue discovery to the repository selector 'projects'"

# No selector preserves the cross-repository queue request.
all_repos="$(PJ_BACKEND=codex run_pj --implement-issues)" || exit 1
assert_contains "$all_repos" 'Process the Chat implementation queue across the managed repositories in this workspace.'
assert_not_contains "$all_repos" 'Restrict queue discovery to the repository selector'

# Queue mode remains narrow: ordinary text is not another pj parameter. Once
# encountered, pj-level option ingestion stops and later dash-prefixed text is
# not reconsidered as a flag.
set +e
queue_boundary_error="$(PJ_BACKEND=codex run_pj -i xosdfa -a 2>&1)"
queue_boundary_status=$?
set -e
if [ "$queue_boundary_status" -eq 0 ]; then
  echo 'pj -i unexpectedly accepted prompt text' >&2
  exit 1
fi
assert_contains "$queue_boundary_error" 'unexpected argument: xosdfa'
assert_not_contains "$queue_boundary_error" 'unexpected argument: -a'

if PJ_BACKEND=codex run_pj -i issues >/dev/null 2>&1; then
  echo 'pj -i unexpectedly accepted a positional repository selector' >&2
  exit 1
fi

if PJ_BACKEND=codex run_pj -i -r '../issues' >/dev/null 2>&1; then
  echo 'pj -i unexpectedly accepted an invalid repository selector' >&2
  exit 1
fi

# Without an explicit -- separator, the first ordinary token starts prompt
# text and all later dash-prefixed fragments stay in that prompt.
prompt_boundary="$(PJ_BACKEND=codex run_pj -a prompt-text -b)" || exit 1
assert_contains "$prompt_boundary" '<-a>'
assert_contains "$prompt_boundary" '<prompt-text -b>'
assert_not_contains "$prompt_boundary" '<-b>'

# A literal -- still allows agent options with separate non-dash values.
agent_value="$(PJ_BACKEND=codex run_pj --model test-model -- 'Prompt - with dash')" || exit 1
assert_contains "$agent_value" '<--model>'
assert_contains "$agent_value" '<test-model>'
assert_contains "$agent_value" '<Prompt - with dash>'

printf 'pj queue option tests passed\n'
