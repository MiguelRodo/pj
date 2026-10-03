# Local `pj` operator

`pj` is Miguel's local launcher and maintenance tool for managed projects. It runs
the selected local agent in `${PJ_WORKSPACE:-~/planning}`. The backend shorthands
are `pja` for Google Antigravity, `pjcp` for GitHub Copilot CLI and `pjcd` for
Codex.

`pj` is separate from the optional `projects` CLI. `pj` launches and orchestrates
agents; `projects` performs supported deterministic GitHub Project operations.
See the [`projects` CLI guide](https://github.com/MiguelRodo/github-projects-skill/blob/main/docs/cli.md)
for that tool.

## Install

On Debian or Ubuntu, after configuring the
[`apt-miguelrodo`](https://github.com/MiguelRodo/apt-miguelrodo) repository,
install or upgrade the released package with:

```bash
sudo apt-get update
sudo apt-get install -y pj
```

The APT package is imported from a versioned GitHub Release of `pj`; it does not
track unreleased commits on `main`.

Alternatively, with `setupmjr` installed:

```bash
setupmjr project --pj
```

`setupmjr` follows the floating `v0` release tag. For a direct checkout of that
same release line:

```bash
git clone --depth 1 --branch v0 --single-branch https://github.com/MiguelRodo/pj.git
cd pj
bash install.sh
```

The installer chooses a user bin directory and records it so later installs can
migrate installer-owned launchers safely. Set `PJ_BIN_DIR` when you want a
specific absolute or home-relative location:

```bash
PJ_BIN_DIR='~/tools/bin' bash install.sh
```

Reinstalling preserves saved backend/model choices and user-owned guidance. The
detailed installation and migration guarantees live in `AGENTS.md` and the
regression suite rather than being duplicated here.

## Configure the backend and model

Inspect or change the saved default backend:

```bash
pj --show-default
pj --set-default codex
pj --set-default copilot
pj --set-default antigravity
```

Inspect or change per-backend model choices:

```bash
pj --show-models
pj --show-model codex
pj --set-model codex MODEL
pj --reset-model codex
```

`PJ_DEFAULT_BACKEND` overrides the saved default for the current environment;
`PJ_BACKEND` is a one-run generic launcher override. `PJ_CODEX_MODEL`,
`PJ_COPILOT_MODEL` and `PJ_ANTIGRAVITY_MODEL` similarly override model selection
for one invocation.

## Run

Prompt-launched terminal sessions stay conversational by default. Use `-o` or
`--oneshot` in the leading `pj` option prefix for a single-turn run:

```bash
pj "Review this repository"
pj -o "Review this repository once"
pjcp -o -- "Treat -this-fragment as prompt text"
```

`pj` consumes only the contiguous leading prefix of recognised launcher options.
The first ordinary token starts prompt text, so later dash-prefixed fragments are
not re-parsed as `pj` flags. A leading `--` forces the remainder to prompt text;
a later `--` can separate agent-specific options from the prompt.

## Administration queue

These compatibility forms select the same administrative queue:

```bash
pj -i
pj --implement-issues
pj --implement-chat
```

Queue mode is administrative-only by effect. It may administer GitHub issues and
Projects, but it does not perform or delegate the substantive task represented by
an issue. The canonical `github-projects` skill and each repository's resolved
`.projects` contract own routing, authority, mutation and readback semantics;
`pj` only orchestrates them.

Choose a managed Project and, optionally, a sub-project. The checked contracts
resolve where its issues live; you do not need to supply the issue repository.
A repository selector is an optional diagnostic restriction. Selectors combine
by intersection:

```bash
pj -i --project work
pj -i --project work --subproject tools
pj -i --repo example/issues --project work --subproject tools
```

The default agent policy is deterministic-first `auto`:

```bash
pj -i --agent=auto
pj -i --agent=before
pj -i --agent=after
```

`auto` runs the canonical deterministic path first and starts a model only when
canonical fallback or review is required. `before` deliberately gives the
preflight-bounded work to an agent before deterministic execution. `after` runs
deterministic processing first and then starts an agent with the resulting
receipts. Hard-stop receipts are not retry authority.

If the installed canonical queue tooling is unavailable, `pj` keeps processing
bounded and tells the operator to refresh the shared skill rather than inventing
GitHub Project semantics locally.

## Initialise a repository

From inside the implementation repository, express the managed Project and
optional sub-project. For a new Project, use its owner and number from the web
address (the number is prompted when omitted):

```bash
# Issues live in this repository.
pj --init --project work --project-owner example --project-number 40

# Issues live in a central store checked out in PJ_WORKSPACE.
pj --init --project work --issue-store example/issues --project-owner example --project-number 40

# This repository implements a sub-project within that managed Project.
pj --init --project work --issue-store example/issues --subproject tools --project-owner example --project-number 40
```

Onboarding derives the required labels and reconciles both the central store's
configuration and this repository's configuration. It previews changes across
checkouts and asks for confirmation; add `--yes` to confirm that preview in a
script. Existing matching configuration is preserved, repeated setup is a
no-op, and conflicting topology stops before writing. An existing Project's
identity and issue store are reused, so later runs can omit those details.

The central store must already have exactly one local checkout under
`${PJ_WORKSPACE:-~/planning}`, identified by its checked contract or exact
GitHub origin. New configuration is prepared on local onboarding branches
when a checkout is on its default branch. Review, commit and open a PR through
each affected repository's normal workflow; onboarding does not publish these
changes. Existing issues and their Project membership are not migrated.

`pj --init` without options still offers guided setup, including existing
repository-backed single and multiple Projects. Choosing a separate issue
store enters the same semantic reconciliation flow. The canonical skill owns
all contract and routing logic; `pj` installs it when needed and forwards setup
arguments to its `init-project.sh`. Python 3 is required for semantic setup.
Standard fields and the Backlog view can be set up with the optional `projects`
CLI; see the skill's onboarding reference.

For the lower-level operation that only adds the shared skill, use:

```bash
pj --add-skill
```

This installs the skill pinned to `main` at project scope but deliberately leaves
`.projects` setup to the skill initializer. If the skill is already present,
`--add-skill` is a no-op and points to `pj --update-skill`; `--init` continues into
the existing initializer. A legacy `github-project-admin` install is left to the
updater rather than creating two competing skill copies.

## Update the shared Project skill

Use the maintained updater entry point:

```bash
pj --update-skill
```

It refreshes `github-projects` across repositories that already carry the current
or legacy skill while preserving the operator's checked-out work and respecting
protected branches. It does not add the skill to a new repository. The legacy
`pj-update-skills` command remains only as a compatibility shim. Detailed updater
safety and branch-handling contracts live in `AGENTS.md` and the updater tests.

## Managed agent guidance

The installer maintains bounded blocks in `~/AGENTS.md` and
`${PJ_WORKSPACE:-~/planning}/AGENTS.md`, preserving unrelated user content and
handling backend instruction entry points conservatively. The home block carries
user-level operator rules. The workspace block is only a dispatcher into the
target repository's `AGENTS.md`, resolved `.projects` contract and installed
`github-projects` skill.

The home guidance also contains the opt-in `agy` delegation policy. Treat that
installed guidance as authoritative rather than copying its safety and permission
rules into this README.

## Testing

Run the complete offline suite:

```bash
for f in tests/*.sh; do bash "$f"; done
```
