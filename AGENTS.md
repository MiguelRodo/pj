# Agent guidance

This repository contains `pj`, Miguel's standalone local operator launcher and
maintenance tooling for managed projects.

Work on a branch and open a pull request rather than pushing directly to `main`.
Before proposing a change, run the complete offline suite:

```bash
for f in tests/*.sh; do bash "$f"; done
```

Tests must not mutate live GitHub state or user configuration outside their
temporary environments.

## Ponytail

For coding, refactoring, bug-fixing, review and implementation design, read
`.agents/skills/ponytail/SKILL.md` and apply Ponytail in **full** mode by
default. Do not use **ultra** unless the operator explicitly requests it.
Provenance is in `.agents/skills/ponytail/README.md`.

Ponytail is subordinate to settled behaviour. Precedence is:

1. the current explicit operator instruction or issue acceptance criteria;
2. the durable contracts below;
3. supported compatibility and migration behaviour for refactors/cleanup;
4. the smallest implementation.

Prefer deletion, reuse and existing shell/platform primitives. Do not preserve
duplication merely because it already exists. Conversely, do not call a required
safety, compatibility or workflow contract "over-engineering".

## Ownership boundaries

Keep responsibilities in one place:

- `pj` owns the local launcher, backend/session selection, per-user installation,
  operator-guidance installation and the managed-skill updater.
- `github-projects` owns GitHub issue/Project semantics, repository contracts,
  routing, authority, preservation/readback and the optional deterministic
  `projects` CLI. Do not build a second Project model or contract parser in
  `pj`.
- `projects` is an optional backend for supported deterministic GitHub operations,
  not a second launcher.
- setup tooling may install/configure `pj`, but must not fork its implementation.
- Managed repository identity comes from checked local `.projects` contracts
  under `${PJ_WORKSPACE:-~/planning}`, never fuzzy repository discovery.

If a cleanup would move one of these boundaries, preserve the boundary and raise
that architecture change separately.

## Launcher contract

Keep one shared launcher with thin backend-specific execution.

- `pj` uses the configured backend; `pja`, `pjcp` and `pjcd` explicitly
  select Antigravity, Copilot and Codex.
- Explicit run-time overrides beat saved defaults; saved backend/model choices are
  independent and survive reinstall. Exact model defaults are ordinary tunable
  configuration, not architecture.
- Interactive terminal use stays conversational. Non-TTY execution is one-shot;
  `-o` / `--oneshot` explicitly forces one-shot behaviour.
- Preserve each backend's established continuity mechanism rather than making the
  common interface one-shot for implementation convenience.
- Do not add a backend by copying parser/session logic. Share everything except the
  irreducible backend invocation.

### Argument parsing

`pj` consumes one contiguous leading prefix of recognised launcher options.

- recognised `pj` options compose in supported order;
- the first ordinary token ends launcher-level parsing;
- later dash-prefixed fragments are prompt text, not re-parsed launcher flags;
- a leading literal `--` forces the remainder to prompt text;
- agent-specific arguments may use a later `--` as their prompt separator.

Keep this behaviour identical across backends.

## Installation and guidance

Installation is per-user, conservative and idempotent.

- Prefer an explicit install location, then a standard user bin already on
  `PATH`; record the chosen location so later installs can migrate old
  installer-owned launchers safely.
- Install one `pj` implementation plus managed aliases rather than divergent
  scripts.
- Preserve saved backend/model choices across reinstall.
- Managed guidance edits are bounded and idempotent: preserve unrelated user
  content, file modes and genuine backend-specific guidance.
- `~/AGENTS.md` is the canonical cross-agent user guidance. Symlink to it only
  when the target is absent/empty/installer-owned; otherwise preserve the file and
  update only the managed block.
- Broken/unrelated symlinks and unsafe non-file paths must fail safely rather than
  be overwritten.
- The workspace `AGENTS.md` is a dispatcher to the target repository's guidance,
  contract and shared `github-projects` skill, not a second copy of project
  policy.

## Managed-skill updater

`pj --update-skill` is the single supported updater path.

- Resolve the repository's real default branch.
- Refresh on an isolated worktree so the operator's current branch, index and dirty
  files are untouched.
- Determine staleness from the installed skill's canonical source/ref/tree, not an
  ambiguous success message.
- Commit only the skill refresh.
- Fast-forward the operator checkout only when safe.
- If branch protection rejects a direct push, use/reuse the dedicated update
  branch and PR. Never bypass protection.
- Never merge or push the canonical `github-projects-skill` protected `main`;
  fast-forward its checkout when possible and fail visibly otherwise.
- Any update, push, PR-handoff or restoration failure is a failure, not success.

Do not "simplify" this into in-place edits that can damage local work.

## Administration queue

`pj -i`, `pj --implement-issues` and `pj --implement-chat` are aliases for
the same **administrative-only** queue.

The boundary is by effect, not wording:

- Queue mode may use `projects`, `gh`, REST, GraphQL, shell or Python for GitHub
  administration.
- It must never perform the substantive task represented by an issue: no product
  implementation, task file edits, implementation tests, requested research/data
  work, implementation PRs/branches or delegation of that task.
- Imperative task prose does not authorise execution and must not cause separable
  administrative work to be skipped.
- Ordinary task issues remain open after administrative reconciliation unless the
  task itself is independently complete. Temporary handoffs close only after
  verified administration.

Authority comes from the resolved canonical skill/contract:

- the acting identity is the locally authenticated `gh` account;
- explicitly solo/personal governance may use the canonical streamlined trusted
  reconciliation path;
- collaborative/shared, missing or ambiguous governance requires the canonical
  unedited `PJ implementation authority:` comment stating the bounded delta;
- temporary handoffs and unusual/broader mutations use the stronger authority path;
- trusted routine administration should not ask for ritual confirmation;
- every mutation needs stale-sensitive inspection and independent readback.

Discovery is managed-contract-only. Never scan arbitrary accessible repositories.
Queue scope is exact, not fuzzy: repository, Project and configured sub-project
selectors intersect, and closed issues are never candidates.

Queue mode uses the canonical `github-projects` deterministic preflight
**before** model startup. Empty or unmatched selected scope returns without
launching an agent. A non-empty queue passes bounded candidate identities and
local repository roots to the agent so it does not rediscover the workspace.
Reusable discovery stays in `github-projects`; `pj` must not grow a second
contract parser. If the installed preflight is unavailable, preserve the older
agent-discovery path with a clear `pj --update-skill` warning rather than
guessing contract semantics locally.

## What Ponytail should attack

Prefer simplification of:

- repeated backend/parser/session branches that can share one implementation;
- duplicated GitHub Project semantics or contract parsing;
- speculative modes, compatibility layers with no caller and duplicate config;
- dependencies for work already handled safely by the standard environment;
- broad scans or model calls that deterministic preflight can avoid.

Do not simplify away:

- interactive-session continuity;
- saved configuration and installer migration safety;
- bounded preservation of user guidance;
- argument-boundary semantics;
- queue effect/trust/authority boundaries;
- managed-contract-only discovery and independent GitHub readback;
- protected-branch updater behaviour;
- offline regression coverage protecting these contracts.

The generic Ponytail "one runnable check" suggestion is not a test cap here. Add
the smallest focused regression for a change, keep useful existing regression
coverage, and run the complete `tests/*.sh` suite before proposing it.

<!-- github-projects:start -->
## GitHub issues and Projects

For GitHub issue or Project administration, use the shared `github-projects`
skill from `.agents/skills/github-projects/` and read `.projects/project.md`
before acting.
<!-- github-projects:end -->
