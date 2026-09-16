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

cat > "$tmp/preflight" <<'EOF'
#!/usr/bin/env bash
case "${PJ_TEST_PREFLIGHT_STATUS:-ready}" in
  ready)
    printf 'status\tready\n'
    printf 'candidate\tMiguelRodo/issues\t42\thttps://github.com/MiguelRodo/issues/issues/42\tpersonal\tmonitoring\t%s\t%s\n' "$PJ_WORKSPACE/issues_miguel" "$PJ_WORKSPACE/issues_miguel/.projects/projects/personal.md"
    ;;
  empty)
    printf 'status\tempty\n'
    ;;
  unmatched)
    printf 'status\tunmatched\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$tmp/preflight"

cat > "$tmp/executor.py" <<'EOF'
#!/usr/bin/env python3
import json
import os
import sys

status = os.environ.get("PJ_TEST_EXECUTE_STATUS") or "applied_verified"
log = os.environ.get("PJ_TEST_EXECUTE_LOG")
if log:
    with open(log, "a", encoding="utf-8") as handle:
        handle.write("called\n")
if status == "fail":
    raise SystemExit(9)

receipt = {
    "status": status,
    "target": {"repository": "MiguelRodo/issues", "issue": 42},
    "classification": {"classification": "deterministic", "reason": "queue.ready.structured"},
    "planned": [],
    "operations": [],
    "remaining": [],
    "review": None,
}
if status == "needs_agent":
    receipt["agentContext"] = {
        "apiVersion": "github-projects/queue-agent-context/v1",
        "target": {"repository": "MiguelRodo/issues", "issue": 42},
    }
elif status == "review_required":
    receipt["reviewContext"] = {
        "apiVersion": "github-projects/queue-review-context/v1",
        "target": {"repository": "MiguelRodo/issues", "issue": 42},
    }
elif status == "partial_failure":
    receipt["reason"] = "queue.execute.field_mutation_failed"
elif status == "blocked":
    receipt["reason"] = "queue.blocked.authentication"

print(json.dumps(receipt, separators=(",", ":"), sort_keys=True))
EOF
chmod +x "$tmp/executor.py"

run_pj() {
  HOME="$tmp/home" \
    PJ_WORKSPACE="$tmp/home/planning" \
    XDG_CONFIG_HOME="$tmp/home/.config" \
    PATH="$tmp/bin:$PATH" \
    bash "$pj" "$@"
}

run_pj_with_preflight() {
  HOME="$tmp/home" \
    PJ_WORKSPACE="$tmp/home/planning" \
    XDG_CONFIG_HOME="$tmp/home/.config" \
    PJ_QUEUE_PREFLIGHT_SCRIPT="$tmp/preflight" \
    PJ_QUEUE_EXECUTE_SCRIPT="${PJ_QUEUE_EXECUTE_SCRIPT:-}" \
    PJ_TEST_EXECUTE_STATUS="${PJ_TEST_EXECUTE_STATUS:-}" \
    PJ_TEST_EXECUTE_LOG="${PJ_TEST_EXECUTE_LOG:-}" \
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
assert_contains "$queue_oneshot_short" 'treat that guidance as authoritative for governance, trust, discovery, completion and readback'
assert_contains "$queue_oneshot_short" 'without asking for a routine preview'

# pj keeps one defence-in-depth boundary but does not copy the canonical
# skill's governance/authority/completion model into the launcher prompt.
assert_contains "$queue_oneshot_short" 'Queue mode is administrative-only by effect'
assert_contains "$queue_oneshot_short" 'NEVER perform or delegate the substantive task represented by an issue'
assert_contains "$queue_oneshot_short" 'Ordinary task prose must not suppress separable authorised administration'
assert_not_contains "$queue_oneshot_short" 'checked solo or personal administration'
assert_not_contains "$queue_oneshot_short" "'PJ implementation authority:'"
assert_not_contains "$queue_oneshot_short" 'remove the queue label and close a temporary handoff'

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

# Project and sub-project selectors are independently optional.
project_only="$(PJ_BACKEND=codex run_pj -i --project personal)" || exit 1
assert_contains "$project_only" "Restrict queue discovery to the Project selector 'personal'"

subproject_only="$(PJ_BACKEND=codex run_pj -i --subproject monitoring)" || exit 1
assert_contains "$subproject_only" "Restrict queue discovery to the sub-project selector 'monitoring'"

# Selectors compose and are passed as one intersected queue request.
combined="$(PJ_BACKEND=codex run_pj -i --repo MiguelRodo/issues --project personal --subproject monitoring)" || exit 1
assert_contains "$combined" "Restrict queue discovery to the repository selector 'MiguelRodo/issues'"
assert_contains "$combined" "Restrict queue discovery to the Project selector 'personal'"
assert_contains "$combined" "Restrict queue discovery to the sub-project selector 'monitoring'"

# Equals forms are accepted for the new selectors.
equals_scope="$(PJ_BACKEND=codex run_pj -i --project=personal --subproject=monitoring)" || exit 1
assert_contains "$equals_scope" "Restrict queue discovery to the Project selector 'personal'"
assert_contains "$equals_scope" "Restrict queue discovery to the sub-project selector 'monitoring'"

# Single-Project titles may contain spaces; canonical matching still decides
# whether the exact managed title exists.
project_title="$(PJ_BACKEND=codex run_pj -i --project 'Example Project')" || exit 1
assert_contains "$project_title" "Restrict queue discovery to the Project selector 'Example Project'"

# Deterministic preflight stops before backend launch when no work exists.
empty_preflight="$(PJ_BACKEND=codex PJ_TEST_PREFLIGHT_STATUS=empty run_pj_with_preflight -i --project personal)" || exit 1
assert_contains "$empty_preflight" 'pj: queue preflight found no matching open queue items.'
assert_not_contains "$empty_preflight" 'codex'

unmatched_preflight="$(PJ_BACKEND=copilot PJ_TEST_PREFLIGHT_STATUS=unmatched run_pj_with_preflight -i --project missing)" || exit 1
assert_contains "$unmatched_preflight" 'pj: queue preflight matched no managed queue scope.'
assert_not_contains "$unmatched_preflight" 'copilot'

# A ready preflight bounds the agent to the exact candidate and local contract root.
ready_preflight="$(PJ_BACKEND=codex PJ_TEST_PREFLIGHT_STATUS=ready run_pj_with_preflight -i --project personal --subproject monitoring)" || exit 1
assert_contains "$ready_preflight" 'codex'
assert_contains "$ready_preflight" 'Deterministic read-only preflight has already resolved the queue.'
assert_contains "$ready_preflight" 'do not rescan the workspace or rediscover the queue'
assert_contains "$ready_preflight" 'MiguelRodo/issues#42'
assert_contains "$ready_preflight" "Project 'personal'"
assert_contains "$ready_preflight" "sub-project 'monitoring'"
assert_contains "$ready_preflight" "local repository root '$tmp/home/planning/issues_miguel'"
assert_contains "$ready_preflight" "resolved contract '$tmp/home/planning/issues_miguel/.projects/projects/personal.md'"

# Default auto policy executes deterministic items before model startup.
deterministic_auto="$(PJ_QUEUE_EXECUTE_SCRIPT="$tmp/executor.py" PJ_TEST_EXECUTE_STATUS=applied_verified PJ_BACKEND=codex run_pj_with_preflight -i --project personal --subproject monitoring)" || exit 1
assert_contains "$deterministic_auto" 'pj: deterministic queue completed 1 candidate(s); no agent required.'
assert_not_contains "$deterministic_auto" 'codex'

# needs_agent is the capability fallback path: only the bounded receipt reaches
# the agent after deterministic processing.
needs_agent_auto="$(PJ_QUEUE_EXECUTE_SCRIPT="$tmp/executor.py" PJ_TEST_EXECUTE_STATUS=needs_agent PJ_BACKEND=codex run_pj_with_preflight -i --agent=auto --project personal)" || exit 1
assert_contains "$needs_agent_auto" 'codex'
assert_contains "$needs_agent_auto" 'Canonical deterministic processing has already run with queue agent policy'
assert_contains "$needs_agent_auto" 'github-projects/queue-agent-context/v1'
assert_contains "$needs_agent_auto" 'only needs_agent.agentContext and review_required.reviewContext are actionable unfinished work'
assert_contains "$needs_agent_auto" 'Because --agent=auto is active, work only on actionable unfinished packets'

# Mandatory item review is distinct from fallback but still starts an agent in
# auto mode, with the review packet and resume instruction.
review_auto="$(PJ_QUEUE_EXECUTE_SCRIPT="$tmp/executor.py" PJ_TEST_EXECUTE_STATUS=review_required PJ_BACKEND=copilot run_pj_with_preflight -i --agent auto --project personal)" || exit 1
assert_contains "$review_auto" 'copilot'
assert_contains "$review_auto" 'github-projects/queue-review-context/v1'
assert_contains "$review_auto" 'queue-review-result/v1'
assert_contains "$review_auto" '--review-result'

# Blocked/partial deterministic receipts are hard stops, never mutation fallback.
set +e
blocked_auto="$(PJ_QUEUE_EXECUTE_SCRIPT="$tmp/executor.py" PJ_TEST_EXECUTE_STATUS=blocked PJ_BACKEND=codex run_pj_with_preflight -i --project personal 2>&1)"
blocked_status=$?
set -e
if [ "$blocked_status" -eq 0 ]; then
  echo 'pj -i unexpectedly treated a blocked deterministic receipt as success' >&2
  exit 1
fi
assert_contains "$blocked_auto" 'no agent retry was attempted'
assert_contains "$blocked_auto" '"status":"blocked"'
assert_not_contains "$blocked_auto" 'codex'

# before deliberately bypasses the deterministic executor and sends only the
# already-bounded preflight candidates to the agent.
rm -f "$tmp/executor.log"
before_agent="$(PJ_QUEUE_EXECUTE_SCRIPT="$tmp/executor.py" PJ_TEST_EXECUTE_STATUS=fail PJ_TEST_EXECUTE_LOG="$tmp/executor.log" PJ_BACKEND=codex run_pj_with_preflight -i --agent=before --project personal)" || exit 1
assert_contains "$before_agent" 'codex'
if [ -s "$tmp/executor.log" ]; then
  echo 'pj --agent=before unexpectedly invoked the deterministic executor' >&2
  exit 1
fi

# after always starts the agent after deterministic processing and passes the
# exact receipt, even when the item already completed.
after_agent="$(PJ_QUEUE_EXECUTE_SCRIPT="$tmp/executor.py" PJ_TEST_EXECUTE_STATUS=applied_verified PJ_BACKEND=codex run_pj_with_preflight -i --agent after --project personal)" || exit 1
assert_contains "$after_agent" 'codex'
assert_contains "$after_agent" 'Because --agent=after was requested'
assert_contains "$after_agent" '"status":"applied_verified"'
assert_contains "$after_agent" 'review all receipts after deterministic processing, but mutate only actionable unfinished packets'

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

if PJ_BACKEND=codex run_pj -i --project '../personal' >/dev/null 2>&1; then
  echo 'pj -i unexpectedly accepted an invalid Project selector' >&2
  exit 1
fi

if PJ_BACKEND=codex run_pj -i --subproject 'monitoring/child' >/dev/null 2>&1; then
  echo 'pj -i unexpectedly accepted an invalid sub-project selector' >&2
  exit 1
fi

if PJ_BACKEND=codex run_pj -i --project= >/dev/null 2>&1; then
  echo 'pj -i unexpectedly accepted an empty Project selector' >&2
  exit 1
fi

if PJ_BACKEND=codex run_pj --project personal >/dev/null 2>&1; then
  echo 'pj unexpectedly accepted --project outside queue mode' >&2
  exit 1
fi

if PJ_BACKEND=codex run_pj --subproject monitoring >/dev/null 2>&1; then
  echo 'pj unexpectedly accepted --subproject outside queue mode' >&2
  exit 1
fi

if PJ_BACKEND=codex run_pj --agent auto >/dev/null 2>&1; then
  echo 'pj unexpectedly accepted --agent outside queue mode' >&2
  exit 1
fi

if PJ_BACKEND=codex run_pj -i --agent sometimes >/dev/null 2>&1; then
  echo 'pj unexpectedly accepted an invalid queue agent policy' >&2
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
