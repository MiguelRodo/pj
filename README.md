# Local `pj` operator

`pj` is Miguel's standalone local operator launcher and maintenance tooling for managed projects. It runs the configured local agent against `${PJ_WORKSPACE:-~/planning}`. The backend shorthands are `pja` for Google Antigravity, `pjcp` for GitHub Copilot CLI and `pjcd` for Codex.

`pj` is not an alias for the optional `projects` Go CLI. The launcher chooses an
agent and keeps its conversation open; `projects` handles supported deterministic
GitHub Project operations. An agent started by `pj` may use that binary when it
is installed, then follow the repository scripts or direct GitHub path when it
is not. See the
[`projects` CLI guide](https://github.com/MiguelRodo/github-projects-skill/blob/main/docs/cli.md)
for installation and read-only update checks.

## Installation

Run the installer from a local checkout:

```bash
git clone https://github.com/MiguelRodo/pj.git
cd pj
bash install.sh
```

Alternatively, if `setupmjr` is installed:

```bash
setupmjr project --pj
```

The installer prefers `~/.local/bin` when it is already on `PATH`, then `~/bin`
when that is the configured standard user bin directory. If neither is on
`PATH`, it prefers an existing `~/.local/bin` or `~/bin`, in that order, and
otherwise creates `~/.local/bin`. The selected directory is recorded in
`${XDG_CONFIG_HOME:-~/.config}/pj/install-bin-dir` so a later reinstall can
safely migrate an older installer-managed location rather than leave a stale
launcher shadowing the current one.

Set `PJ_BIN_DIR` to choose a different absolute or home-relative location for an
install, for example:

```bash
PJ_BIN_DIR='~/.local/bin' bash install.sh
PJ_BIN_DIR='~/tools/bin' bash install.sh
```

A new install starts with Codex as the `pj` default. Change or inspect that saved
default with:

```bash
pj --set-default antigravity
pj --set-default copilot
pj --set-default codex
pj --show-default
```

The saved choice lives at `${XDG_CONFIG_HOME:-~/.config}/pj/default-backend` and
is preserved when the installer is rerun. `PJ_DEFAULT_BACKEND` can override the
saved default for the current environment, while `PJ_BACKEND` remains the
one-run generic `pj` override. An explicit `--backend` flag has the highest
precedence and can also override a shorthand launcher.

### Per-backend model defaults

`pj` keeps model selection separate for each backend. Built-in model defaults are:

- Codex: `gpt-5.6-luna`, with `xhigh` reasoning effort;
- Copilot: `mai-code-1.1-flash`;
- Antigravity: provider default, unpinned.

Inspect and configure model choices with:

```bash
pj --show-models
pj --show-model codex
pj --set-model codex gpt-5.6-luna
pj --reset-model codex
```

Environment variables `PJ_CODEX_MODEL`, `PJ_COPILOT_MODEL` and `PJ_ANTIGRAVITY_MODEL`
override saved and built-in defaults for one invocation.

## Managed agent guidance

The installer maintains bounded `pj` blocks in `~/AGENTS.md` and `${PJ_WORKSPACE:-~/planning}/AGENTS.md`. The home-level file is the canonical cross-agent user guidance: it tells agents about local operator maintenance, including the shared skill updater, and contains user-level rules that apply regardless of backend. The workspace-level file gives every backend the same natural-language GitHub task and Project vocabulary for conversational follow-ups. It tells the agent to resolve the target managed repository, read that repository's own `AGENTS.md` and `.projects` contract, follow `github-projects`, and independently verify mutations. Content outside the managed blocks is preserved on reinstall.

Where it is safe to do so, the installer links each backend's documented user-level instruction entrypoint back to the same canonical `~/AGENTS.md`:

```text
~/.codex/AGENTS.md                  -> ~/AGENTS.md
~/.copilot/copilot-instructions.md -> ~/AGENTS.md
~/.gemini/GEMINI.md                -> ~/AGENTS.md
```

The installer chooses the least surprising migration for each backend entrypoint:

- an absent, empty or installer-owned file becomes a symlink to `~/AGENTS.md`;
- a regular file with genuine backend-specific content remains a regular file,
  keeps that content and its mode, and receives one hard-updated copy of the
  canonical managed block at the existing block position; and
- an unrelated symlink or non-file path is preserved unchanged and reported.

Known older installer-managed blocks are removed during either migration. A
reinstall refreshes, rather than duplicates, the managed block. This lets a
straightforward installation use one physical file while respecting an existing
backend-specific arrangement.

`~/AGENTS.md`, the workspace `AGENTS.md` and the Codex rules file may themselves
be symlinks into a dotfiles checkout. The installer writes through those links,
keeps them in place and preserves each target file's mode. It stops on a broken
managed-file or backend instruction symlink, because success would otherwise be
misleading.

## Optional `agy` delegation

The canonical home guidance advertises `agy` as an opt-in external subagent to Codex and GitHub Copilot CLI only. Antigravity itself must not invoke `agy` recursively under this facility. Codex or Copilot may delegate bounded mechanical or investigative work only after the operator explicitly authorises `agy` for the current task or conversation. Conversation-level authorisation covers repeated useful calls without repeated prompts. The default delegated model is `gemini-3.8-flash-high`; the primary agent remains responsible for design, consequential decisions, verification and integration.

Delegated repository inspection should pass the repository explicitly, for
example:

```bash
agy -p "<self-contained delegated task>" \
  --model gemini-3.8-flash-high \
  --add-dir "/absolute/repository/root"
```

`--add-dir` registers the repository as an Antigravity workspace instead of
requiring a broad global file-read permission.

The installer also maintains a bounded Codex exec-policy rule in `~/.codex/rules/default.rules` allowing the `agy` executable. The natural-language opt-in rule in `~/AGENTS.md` still controls when Codex may choose to use it.

## Conversational and one-shot sessions

Prompt-launched terminal sessions are conversational by default. Use `-o` (or `--oneshot`) anywhere in the leading `pj`-owned option prefix, before agent-specific options or prompt text, to force a single-turn run:

```bash
pj -o "Update the issue and verify it"
pjcp -o -- "Check this Project state once"
```

`pj` stops ingesting launcher options at the first token that is not a recognised `pj` option or a required value for one. From that point, later dash-prefixed fragments are not reconsidered as launcher flags. For agent-specific options, a literal `--` remains the unambiguous separator when an option takes a separate non-dash value.

## Update the shared Project skill everywhere

The canonical entry point is:

```bash
pj --update-skill
```

A legacy `pj-update-skills` shim remains for older shell setups, but the maintained interface is `pj --update-skill`. Run it when you want to refresh `github-projects` across the managed repositories under `${PJ_WORKSPACE:-~/planning}`. The updater:

1. resolves each repository's real default branch - the hosting provider's answer, then the remote HEAD recorded by the clone, then `main`/`master` - instead of treating whichever branch happens to be checked out as the target;
2. fetches the remote and refreshes the skill on a temporary, isolated worktree of that default branch, so the operator's checked-out branch, index and dirty working state are never touched;
3. reconciles the installed `github-projects` copy with canonical `main`, reinstalling it with `gh skill install ... --pin main` when it is missing, still sourced from `MiguelRodo/projects`, pinned to an older ref such as `refs/tags/v0.3.0`, or carrying the tree SHA of an older canonical `main`;
4. commits only the resulting skill refresh as `Update github-projects skill`;
5. pushes the commit directly to the default branch when repository rules allow it, fast-forwarding the operator's own checkout when it already sits on that branch and git can apply the fast-forward without disturbing local work; and
6. when repository rules reject the direct push, preserves the same commit on the `pj/update-github-projects-skill` branch, pushes it and opens a pull request targeting the default branch, reusing an existing open skill-update pull request on reruns instead of opening a duplicate or leaving the local default branch ahead, and rewriting that branch when it no longer carries only `.agents/skills` changes.

The installed copy's own metadata decides whether it is current. `gh skill update github-projects --all` is not treated as the source of truth: it reports a tag-pinned copy as "All skills are up to date", and an unpinned `gh skill install` resolves the latest tagged release before the default branch, so the updater pins its reinstall to `main` and compares the recorded tree SHA with the canonical `main` checkout it just synced.

The canonical `github-projects-skill` repository is special-cased: it is not asked to install its own skill, and it is never merged or pushed on its protected `main`. When the remote has simply moved ahead it is fast-forwarded; when its history has diverged from the remote it is left untouched and reported as a failure instead of manufacturing a merge commit. A repository that cannot resolve its default branch, merge, update, push or restore its stash is reported as a failure rather than silently treated as successful.

Agents launched under the home or planning `AGENTS.md` guidance are told to use `pj --update-skill` when the operator explicitly asks them to update the shared skill across local repositories, instead of building another one-off shell loop.

## Chat administration queue

These compatibility forms are equivalent:

```bash
pj -i
pj --implement-issues
pj --implement-chat
```

Despite the historical option and label names, queue mode is **administrative-only**.
It asks the selected backend to process trusted `pj:implement-chat` temporary
handoffs for bounded GitHub issue/Project mutations using `github-projects` and
the managed repositories discovered from local `.projects` contracts.

Queue mode never authorises repository implementation. It must not edit
repository files, change application/repository configuration, run implementation
tests, create or update implementation branches or pull requests, or delegate
coding work to another agent. Implementation requires a separate explicit
non-queue invocation.

Pass one optional repository selector with `-r` or `--repo` to restrict queue discovery:

```bash
pj -i -r projects
pj -i --repo issues
pj -i --repo example-user/projects
```

A bare selector such as `issues` matches every managed issue repository with
that exact repository name regardless of owner. An `owner/repo` selector
matches that exact managed repository. Matching never broadens beyond
repositories declared by local managed-project contracts.

Queue mode composes with other `pj`-owned options in the leading prefix:

```bash
pj -o -i -r projects
pj -i -o -r projects
pj -i -r projects --oneshot
```

The launcher does not implement queue discovery itself. It validates and passes
the selector to the agent, while the canonical matching, trust, administrative
mutation and readback rules remain in `github-projects`. The launcher also
injects the no-implementation rule directly as a defence against stale installed
skill guidance.

## Testing

Run the test suite offline:

```bash
for f in tests/*.sh; do bash "$f"; done
```
