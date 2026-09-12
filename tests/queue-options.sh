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
assert_contains "$queue_oneshot_short" 'Process the Chat administration queue across the managed repositories in this workspace.'
assert_contains "$queue_oneshot_short" 'references/local-implementation-queue.md'
assert_contains "$queue_oneshot_short" 'without asking for a routine preview'

# The queue safeguard is an effect boundary, not a request-type filter. Keeping
# the substantive work out is what matters; the mechanisms available for
# administration are deliberately not restricted.
assert_contains "$queue_oneshot_short" 'Queue mode is an effect boundary, not a tooling restriction'
assert_contains "$queue_oneshot_short" 'may freely use the projects CLI, gh, REST, GraphQL and shell or Python helpers'
assert_contains "$queue_oneshot_short" 'Queue mode must NEVER perform the substantive task itself'
assert_contains "$queue_oneshot_short" 'do not edit application or repository files for the underlying task'
assert_contains "$queue_oneshot_short" 'implement product, code or configuration changes'
assert_contains "$queue_oneshot_short" 'run implementation tests merely to do the task'
assert_contains "$queue_oneshot_short" 'collect measurements or perform research, analysis or data work the task requests'
assert_contains "$queue_oneshot_short" 'create implementation branches or pull requests'
assert_contains "$queue_oneshot_short" 'delegate the substantive task to another coding agent'

# Imperative task prose is a task description, never queue execution authority,
# and it must not suppress the administrative work that accompanies it.
assert_contains "$queue_oneshot_short" "Ordinary task prose such as 'Build X', 'Implement Y', 'Fix Z', 'Measure A', 'Analyse B' or 'Test C' describes the work the task represents"
assert_contains "$queue_oneshot_short" "must never cause the issue's administration to be skipped"
assert_contains "$queue_oneshot_short" 'An issue is administered even when it names substantive work'
assert_contains "$queue_oneshot_short" "'Build X' with an explicit Class, Priority or Status metadata line asks for exactly that metadata to be applied and verified, not for X to be built"
assert_contains "$queue_oneshot_short" "'Measure production behaviour' may still be classified, routed or otherwise administered, but no measurement is performed"
assert_contains "$queue_oneshot_short" "'Fix bug Y' may still have its membership, fields and hierarchy administered, but repository files, tests and implementation pull requests stay untouched"
assert_contains "$queue_oneshot_short" 'Perform every separable authorised GitHub issue/Project administrative operation for the queued item while leaving the substantive task untouched'
assert_contains "$queue_oneshot_short" 'When an issue contains both substantive work and administrative work, perform and independently verify the administrative portion instead of skipping the whole issue because substantive work is present'

# Authority is delegated to the canonical skill's resolved governance rather
# than restated as a competing launcher model.
assert_contains "$queue_oneshot_short" "Defer to that skill's resolved governance and authority rules instead of substituting a second authority model for them"
assert_contains "$queue_oneshot_short" "Treat the 'currently authenticated user' as the GitHub account reported by the local authenticated gh session used by pj"
assert_contains "$queue_oneshot_short" 'checked solo or personal administration'
assert_contains "$queue_oneshot_short" "a trusted task issue authored by that account and carrying the configured queue label may use the skill's streamlined reconciliation path"
assert_contains "$queue_oneshot_short" 'Under collaborative or shared governance, or when governance is missing or ambiguous, the stronger rule applies'
assert_contains "$queue_oneshot_short" "'PJ implementation authority:' must state the bounded administrative delta itself rather than referring back to mutable issue-body text"
assert_contains "$queue_oneshot_short" 'Temporary administrative handoffs always use that stronger authority-comment path'

# Completion is shape-specific: only a temporary handoff closes.
assert_contains "$queue_oneshot_short" 'remove the queue label and close a temporary handoff, but do not close an ordinary task issue merely because its administration is complete'

# The request-type wording that skipped an item's administration is gone.
assert_not_contains "$queue_oneshot_short" 'skip that implementation'
assert_not_contains "$queue_oneshot_short" 'requires a separate explicit non-queue invocation'
assert_not_contains "$queue_oneshot_short" 'NEVER edit repository files'

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
assert_contains "$all_repos" 'Process the Chat administration queue across the managed repositories in this workspace.'
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
