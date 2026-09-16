# Agent guidance

This repository contains `pj`, Miguel's standalone local operator launcher and
maintenance tooling for managed projects.

Work on a branch and open a pull request rather than pushing directly to `main`.
Before proposing a change, run the test suite:

```bash
for f in tests/*.sh; do bash "$f"; done
```

Tests must run offline and must not mutate live GitHub state or user
configurations outside their temporary environments.

## Ponytail and implementation simplicity

For coding, refactoring, bug-fixing, review and implementation design, read
`.agents/skills/ponytail/SKILL.md` and apply Ponytail in **full** mode by
default. Do not use **ultra** unless the operator explicitly requests it.
Vendoring and provenance are documented in
`.agents/skills/ponytail/README.md`.

Ponytail is a simplicity discipline, not authority to discard settled `pj`
behaviour. Apply this precedence when a shorter implementation conflicts with
another rule:

1. the current explicit operator instruction or issue acceptance criteria;
2. the durable architecture and behavioural contracts in this file;
3. existing supported behaviour and migration compatibility when the task is a
   refactor, simplification or maintenance change;
4. Ponytail's preference for the smallest implementation.

Prefer deletion, reuse, shell/platform primitives and existing helpers over new
frameworks. Challenge duplicated state, provider-specific branches, speculative
abstractions, compatibility layers with no remaining caller, and repeated parsing
that belongs in one canonical place. Do not use YAGNI to remove or weaken the
contracts below.

## Product and repository boundaries

Keep ownership deliberately narrow:

- `MiguelRodo/pj` owns the local launcher, its installer, backend/session/model
  selection, operator guidance installation and the managed-skill updater.
- `github-projects` owns GitHub issue/Project semantics, repository contracts,
  routing, authority rules, preservation/readback behaviour and the optional
  `projects` CLI execution surface. Do not create a second Project model in
  `pj`.
- The `projects` CLI is an optional deterministic backend for operations the
  shared skill supports. It does not replace `pj`, become a second launcher or
  define repository topology.
- `setupmjr` may install/configure `pj`, but the canonical launcher and updater
  implementation remains here. Do not duplicate `pj` logic into setup tooling.
- The default operator workspace is `${PJ_WORKSPACE:-~/planning}`. Managed
  repository identity comes from checked local `.projects` contracts, not from
  remembered clone names or fuzzy guesses.

When a change appears to require moving one of these boundaries, keep the current
boundary and raise the architectural change explicitly instead of smuggling it
into a cleanup.

## Launcher and backend contract

Preserve one shared launcher with thin backend-specific execution:

- `pj` selects the configured backend.
- `pja`, `pjcp` and `pjcd` explicitly select Antigravity, GitHub Copilot CLI
  and Codex respectively.
- Explicit `--backend` overrides a shorthand/default for that run. Environment
  overrides remain one-run controls; saved defaults survive installer reruns.
- Built-in model defaults are Codex `gpt-5.6-luna` with `xhigh` reasoning,
  Copilot `mai-code-1.1-flash`, and no Antigravity model pin so Antigravity may
  follow its provider default/current Flash model. Per-backend saved choices and
  environment overrides are independent.
- Do not add a new backend by copying launcher logic. Extend the common parsing and
  session contract, with only the irreducible backend invocation kept specific.

Normal prompt-launched terminal use is conversational:

- Codex starts its seeded interactive TUI.
- Copilot uses its interactive initial-prompt mode.
- Antigravity seeds one headless turn and immediately resumes that same workspace
  conversation in the TUI because it has no equivalent initial-prompt flag.
- Non-TTY execution is one-shot automatically.
- `-o` / `--oneshot` explicitly requests one-shot execution.
- Do not make ordinary terminal invocations exit after the first response merely
  to simplify implementation.
- Antigravity must not recursively invoke `agy` through the optional delegation
  facility. Delegation from Codex/Copilot remains operator-authorised, not an
  implicit launcher behaviour.

## Argument parsing contract

`pj` consumes one contiguous leading prefix of recognised `pj` options. Keep
this deterministic and identical across backends:

- recognised `pj` options may be composed in any supported order;
- the first token that is not a recognised `pj` option, or the required value
  for one, ends launcher-level option ingestion;
- after that boundary, later dash-prefixed fragments are prompt text and must not
  be reconsidered as `pj` flags;
- a leading literal `--` forces all remaining arguments to prompt text;
- when agent-specific options are used, a later literal `--` remains the
  unambiguous separator when an agent option consumes a separate non-dash value.

Do not replace this with clever reparsing or backend-specific parsers.

## Installer and operator-guidance contract

Installation is per-user, conservative and idempotent:

- An explicit `PJ_BIN_DIR` wins. Otherwise prefer a standard user bin already on
  `PATH`, with `~/.local/bin` preferred over `~/bin`; create a sensible user
  bin only when needed.
- Record the selected install location so reruns can migrate an older
  installer-owned location without leaving stale launchers that shadow the current
  one.
- Preserve the configured default backend and per-backend model choices across
  reinstall.
- Install `pj` once and create the managed aliases rather than maintaining four
  divergent scripts.
- Managed guidance updates must be bounded and idempotent. Preserve unrelated
  operator-authored content and file modes.
- `~/AGENTS.md` is the canonical cross-agent user-level guidance. Where safe,
  documented backend instruction entrypoints should point to it rather than
  duplicate it.
- An absent, empty or installer-owned backend guidance file may become a symlink.
  A genuine backend-specific file keeps its content and receives only the bounded
  managed block. Unrelated/broken symlinks or unsafe non-file paths must be
  preserved or fail clearly rather than overwritten.
- The workspace `AGENTS.md` remains a dispatcher: resolve the managed target,
  then defer to that repository's `AGENTS.md`, `.projects` contract and shared
  `github-projects` guidance.

Installer simplification must not silently discard custom guidance, model/default
configuration, aliases, recorded install location or migration safety.

## Managed-skill updater contract

`pj --update-skill` is the canonical user-facing updater. Keep one updater
implementation rather than ad hoc repository loops.

The updater must preserve the operator's working state:

- resolve each repository's real default branch rather than assuming the checked
  out branch;
- fetch and refresh on an isolated temporary worktree so the operator's branch,
  index and dirty files are not touched;
- treat the installed skill's recorded source/ref/tree as authority for whether it
  is stale;
- reinstall `github-projects` from canonical `main` when a managed copy is
  missing, stale or tag-pinned, rather than trusting an ambiguous "already up to
  date" message;
- commit only the skill refresh;
- fast-forward an operator checkout only when that is safe and non-destructive;
- when repository protection rejects a direct push, preserve the skill-only change
  on the dedicated update branch and open/reuse a PR instead of bypassing
  protection;
- never merge or push the canonical `github-projects-skill` repository's
  protected `main`; fast-forward that checkout when possible and otherwise report
  the failure;
- fail visibly when default-branch resolution, update, push, PR handoff or state
  restoration fails.

Do not shorten this by editing managed repositories in place or by discarding
rollback/preservation behaviour.

## Administration queue contract

`pj -i`, `pj --implement-issues` and `pj --implement-chat` are compatibility
aliases for the same **administrative-only** local queue.

The boundary is an effect boundary:

- Queue mode may use the `projects` CLI, `gh`, REST, GraphQL, shell or Python to
  administer GitHub.
- It must never perform the substantive task represented by an issue: no product
  or repository implementation, file edits for the task, implementation tests,
  task-requested measurement/research/data analysis, implementation branches/PRs
  or delegation of substantive work.
- Imperative issue prose such as "build", "fix", "measure" or "analyse" describes
  the task. It does not authorise queue execution and must not cause separable
  administrative work to be skipped.
- Existing ordinary task issues remain ordinary work items. After successful
  administrative reconciliation, remove the queue label when appropriate but do
  not close the task merely because its administration is complete.
- Temporary administrative handoffs close only after the requested mutation has
  been independently read back and verified.

Authority belongs to the resolved canonical skill/contract, not to a second model
inside the launcher:

- The acting identity is the account reported by the local authenticated `gh`
  session.
- Under explicitly checked solo/personal governance, a matching issue author plus
  queue label may use the streamlined reconciliation path.
- Under collaborative/shared governance, or missing/ambiguous governance, require
  an unedited comment by that authenticated account beginning exactly
  `PJ implementation authority:` and stating the bounded administrative delta
  itself.
- Temporary handoffs and unusual/broader mutations always use the stronger
  authority-comment path.
- Trusted routine administration should not ask for a ritual preview. Untrusted,
  suspicious or genuinely ambiguous items require review.
- Every mutation requires stale-sensitive inspection and independent readback.

Queue discovery is limited to issue repositories and Projects declared by local
managed `.projects` contracts. Never scan arbitrary repositories merely because
the authenticated account can access them.

Queue scoping is designed as exact intersection, not fuzzy search:

- repository selectors match exact managed repository identity under the canonical
  selector rules;
- Project selectors match exact managed Project identity;
- sub-project selectors match only configured sub-project vocabulary;
- combined selectors narrow by intersection;
- closed issues are never queue candidates.

The launcher should remain thin. The preferred performance direction is a
deterministic, contract-aware queue preflight **before** model startup: if no
matching open queue item exists, return without launching Antigravity/Codex/Copilot;
if work exists, pass the bounded candidate identities/scope to the agent so it does
not rediscover the whole workspace. Put reusable contract-aware discovery in the
canonical `github-projects` / `projects` surface rather than adding another
contract parser to `pj`.

## Simplicity rules specific to pj

Ponytail should aggressively question:

- repeated backend branches that can share one parser/helper;
- duplicated model/default/session logic;
- handwritten GitHub Project logic that belongs to `github-projects`;
- new config files when an existing recorded setting already owns the value;
- extra launcher modes that can be expressed by the existing option-prefix model;
- new dependencies for shell/file/config work already handled safely by the
  standard environment;
- broad scans or model calls when a deterministic preflight can cheaply prove a
  no-op.

Ponytail must not simplify away:

- interactive-session continuity;
- saved configuration and installer migration behaviour;
- bounded managed-file preservation;
- exact option-boundary semantics;
- queue trust/authority/effect boundaries;
- managed-contract-only discovery;
- independent GitHub readback;
- protected-branch updater behaviour;
- offline/hermetic tests that guard these contracts.

The generic Ponytail suggestion that one runnable check can be enough does not
override this repository's regression requirement. Run the complete
`tests/*.sh` suite before proposing a change. Add the smallest focused regression
that proves a new branch or bug fix, but do not delete useful migration, parser,
session or queue tests merely to reduce line count.

<!-- github-projects:start -->
## GitHub issues and Projects

For GitHub issue or Project administration, use the shared `github-projects`
skill from `.agents/skills/github-projects/` and read `.projects/project.md`
before acting.
<!-- github-projects:end -->
