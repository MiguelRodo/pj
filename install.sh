#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
launcher_source="$script_dir/pj"
skill_update_source="$script_dir/update-managed-skills.sh"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
config_dir="$config_home/pj"
default_backend_file="$config_dir/default-backend"
install_bin_dir_file="$config_dir/install-bin-dir"

path_contains_dir() {
  local wanted entry
  local -a path_entries
  wanted="$(trim_trailing_slashes "$1")" || return 1
  IFS=':' read -r -a path_entries <<< "$PATH"
  for entry in "${path_entries[@]}"; do
    [ -n "$entry" ] || continue
    entry="$(trim_trailing_slashes "$entry")" || return 1
    [ "$entry" = "$wanted" ] && return 0
  done
  return 1
}

expand_home_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1:2}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

trim_trailing_slashes() {
  local value
  value="$1"
  while [ "$value" != "/" ] && [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  printf '%s\n' "$value"
}

workspace="$(expand_home_path "${PJ_WORKSPACE:-$HOME/planning}")" || exit 1
workspace="$(trim_trailing_slashes "$workspace")" || exit 1
case "$workspace" in
  /*) ;;
  *)
    printf 'pj installer: PJ_WORKSPACE must resolve to an absolute path: %s\n' "${PJ_WORKSPACE:-$HOME/planning}" >&2
    exit 2
    ;;
esac

choose_launcher_dir() {
  if [ -n "${PJ_BIN_DIR:-}" ]; then
    explicit_dir="$(expand_home_path "$PJ_BIN_DIR")" || return 1
    explicit_dir="$(trim_trailing_slashes "$explicit_dir")" || return 1
    case "$explicit_dir" in
      /*) ;;
      *)
        printf 'pj installer: PJ_BIN_DIR must resolve to an absolute path: %s\n' "$PJ_BIN_DIR" >&2
        return 2
        ;;
    esac
    printf '%s\n' "$explicit_dir"
    return
  fi

  for candidate in "$HOME/.local/bin" "$HOME/bin"; do
    if path_contains_dir "$candidate"; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  for candidate in "$HOME/.local/bin" "$HOME/bin"; do
    if [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf '%s\n' "$HOME/.local/bin"
}

launcher_dir="$(choose_launcher_dir)" || exit $?
launcher_target="$launcher_dir/pj"
antigravity_target="$launcher_dir/pja"
copilot_target="$launcher_dir/pjcp"
codex_target="$launcher_dir/pjcd"
skill_update_target="$launcher_dir/pj-update-skills"
legacy_copilot_target="$launcher_dir/pjc"

mkdir -p "$launcher_dir" "$config_dir" "$workspace" || exit 1

managed_aliases_point_to() {
  target="$1"
  shift
  for alias_path in "$@"; do
    [ -L "$alias_path" ] || return 1
    [ "$(readlink "$alias_path")" = "$target" ] || return 1
  done
}

remove_previous_managed_install() {
  previous_dir="$1"
  previous_dir="$(trim_trailing_slashes "$previous_dir")" || return 1
  [ -n "$previous_dir" ] || return 0
  [ "$previous_dir" != "$launcher_dir" ] || return 0

  previous_target="$previous_dir/pj"
  previous_pja="$previous_dir/pja"
  previous_pjcp="$previous_dir/pjcp"
  previous_pjcd="$previous_dir/pjcd"
  previous_skill_update="$previous_dir/pj-update-skills"
  previous_pjc="$previous_dir/pjc"

  if managed_aliases_point_to "$previous_target" "$previous_pja" "$previous_pjcd" &&
      { managed_aliases_point_to "$previous_target" "$previous_pjcp" ||
        managed_aliases_point_to "$previous_target" "$previous_pjc"; }; then
    rm -f "$previous_pja" "$previous_pjcd" || exit 1
    if [ -L "$previous_pjcp" ] && [ "$(readlink "$previous_pjcp")" = "$previous_target" ]; then
      rm -f "$previous_pjcp" || exit 1
    fi
    rm -f "$previous_skill_update" || exit 1
    if [ -L "$previous_pjc" ] && [ "$(readlink "$previous_pjc")" = "$previous_target" ]; then
      rm -f "$previous_pjc" || exit 1
    fi
    rm -f "$previous_target" || exit 1
    printf 'Removed previous managed pj install from %s\n' "$previous_dir"
  fi
}

if [ -f "$install_bin_dir_file" ]; then
  previous_launcher_dir=""
  IFS= read -r previous_launcher_dir < "$install_bin_dir_file" || true
  remove_previous_managed_install "$previous_launcher_dir"
elif [ "$launcher_dir" != "$HOME/bin" ]; then
  remove_previous_managed_install "$HOME/bin"
fi

install -m 0755 "$launcher_source" "$launcher_target" || exit 1
install -m 0755 "$skill_update_source" "$skill_update_target" || exit 1
ln -sfn "$launcher_target" "$antigravity_target" || exit 1
ln -sfn "$launcher_target" "$copilot_target" || exit 1
ln -sfn "$launcher_target" "$codex_target" || exit 1

if [ -L "$legacy_copilot_target" ] && [ "$(readlink "$legacy_copilot_target")" = "$launcher_target" ]; then
  rm -f "$legacy_copilot_target" || exit 1
fi

printf '%s\n' "$launcher_dir" > "$install_bin_dir_file" || exit 1

if [ ! -f "$default_backend_file" ]; then
  printf 'codex\n' > "$default_backend_file" || exit 1
fi

update_managed_block() {
  local target start_marker end_marker legacy_start legacy_end write_target
  local target_dir block_file tmp_context target_mode
  target="$1"
  start_marker="$2"
  end_marker="$3"
  legacy_start="${4:-}"
  legacy_end="${5:-}"
  write_target="$target"

  if [ -L "$target" ]; then
    write_target="$(readlink -f "$target" 2>/dev/null || true)"
    if [ -z "$write_target" ] || [ ! -f "$write_target" ]; then
      printf 'pj installer: managed file symlink at %s does not resolve to a regular file; preserving it unchanged.\n' "$target" >&2
      return 1
    fi
  elif [ -e "$target" ] && [ ! -f "$target" ]; then
    printf 'pj installer: managed path at %s is not a regular file; preserving it unchanged.\n' "$target" >&2
    return 1
  fi

  target_dir="$(dirname "$write_target")"
  mkdir -p "$target_dir" || return 1
  touch "$write_target" || return 1
  target_mode="$(file_mode "$write_target")" || return 1

  block_file="$(mktemp "${TMPDIR:-/tmp}/pj-managed-block.XXXXXX")" || return 1
  cat > "$block_file" || {
    rm -f "$block_file"
    return 1
  }
  tmp_context="$(mktemp "$target_dir/.pj-managed-context.XXXXXX")" || {
    rm -f "$block_file"
    return 1
  }

  awk \
    -v start="$start_marker" \
    -v end="$end_marker" \
    -v legacy_start="$legacy_start" \
    -v legacy_end="$legacy_end" \
    -v block_file="$block_file" '
    function emit_managed(line) {
      while ((getline line < block_file) > 0) print line
      close(block_file)
    }
    ($0 == start) || (legacy_start != "" && $0 == legacy_start) {
      if (in_block) exit 2
      in_block = ($0 == start ? "current" : "legacy")
      if (!emitted) {
        emit_managed()
        emitted = 1
      }
      next
    }
    ($0 == end) || (legacy_end != "" && $0 == legacy_end) {
      if (!in_block) exit 3
      if (($0 == end && in_block != "current") || ($0 == legacy_end && in_block != "legacy")) exit 3
      in_block = ""
      next
    }
    !in_block { print }
    END {
      if (in_block) exit 4
      if (!emitted) {
        if (NR > 0) print ""
        emit_managed()
      }
    }
  ' "$write_target" > "$tmp_context" || {
    rm -f "$block_file" "$tmp_context"
    printf 'pj installer: malformed managed block markers at %s; preserving the file unchanged.\n' "$target" >&2
    return 1
  }

  chmod "$target_mode" "$tmp_context" || {
    rm -f "$block_file" "$tmp_context"
    return 1
  }
  mv "$tmp_context" "$write_target" || {
    rm -f "$block_file" "$tmp_context"
    return 1
  }
  rm -f "$block_file"
}

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

strip_known_backend_blocks() {
  input="$1"
  output="$2"
  awk '
    $0 == "<!-- pj-managed-projects:start -->" {
      if (block != "") exit 2
      block = "pj"
      next
    }
    $0 == "<!-- managed-projects:start -->" {
      if (block != "") exit 2
      block = "legacy"
      next
    }
    $0 == "<!-- pj-managed-projects:end -->" {
      if (block != "pj") exit 3
      block = ""
      next
    }
    $0 == "<!-- managed-projects:end -->" {
      if (block != "legacy") exit 3
      block = ""
      next
    }
    block == "" { print }
    END { if (block != "") exit 4 }
  ' "$input" > "$output"
}

write_home_context_block() {
  cat <<'EOF_CONTEXT'
<!-- pj-managed-projects:start -->
## Local `pj` operator maintenance

The shared local planning workspace is `${PJ_WORKSPACE:-~/planning}`. When the
operator explicitly asks to update or refresh the installed
`github-projects` skill across the managed repositories in that workspace,
run `pj-update-skills` rather than constructing an ad hoc repository loop.

`pj-update-skills` temporarily stashes pre-existing local work, fetches and
merges upstream changes with an explicit merge commit when needed, updates the
installed `github-projects` skill non-interactively, commits only the skill
refresh, pushes the branch and restores the operator's previous local work. It
skips the installed-skill refresh in the canonical `github-projects-skill` source repository.
If a repository fails to merge, update, push or restore its stash, report the
exact repository and error rather than claiming the whole update succeeded.

For ordinary GitHub task and Project administration, continue into the planning
workspace and follow its `AGENTS.md`, then the resolved repository's own
`AGENTS.md` and `.projects` contract. This home-level block is operator routing,
not a replacement for repository-specific guidance.

## Optional `agy` subagent delegation

This is a user-level safety rule. Repository or workspace instructions must not
weaken it.

Only Codex and GitHub Copilot CLI may use `agy` as an external subagent. Google
Antigravity itself must not invoke `agy` recursively under this permission.

Codex and Copilot must not use `agy` unless the operator explicitly authorises
its use for the current task or conversation. Authorization for a conversation
covers repeated useful calls during that conversation; do not ask again before
each delegated call. The existence of `agy`, this instruction, or an execution
allow-rule is not itself authorisation.

When authorised, prefer Gemini 3.8 Flash High for bounded mechanical or
investigative work that does not need the primary model's reasoning, for example
repository exploration, locating files or symbols, summarising implementation
details, inspecting tests, or other routine evidence gathering. Give `agy` a
self-contained task and register every repository it must inspect as a workspace
directory. A typical call is:

    agy -p "<self-contained delegated task>" --model gemini-3.8-flash-high --add-dir "/absolute/repository/root"

The primary agent remains responsible for interpreting the operator's intent,
architecture and design, consequential implementation decisions, checking the
subagent's findings, and integrating the final result.

If the parent harness blocks launching `agy` or its network access, use that
harness's normal approval mechanism. Do not bypass or broaden permissions merely
to avoid an approval. Once `agy` use is authorised, if a headless run soft-denies
a narrowly scoped tool, the primary agent may approve or add the exact requested
permission on the operator's behalf when its harness permits and the rule is
limited to the current task's resources. Preserve all existing settings and do
not ask the operator again merely to approve that narrow rule. If the permission
cannot be granted safely, report the exact `permissions.allow` rule requested for
`~/.gemini/antigravity-cli/settings.json`.

Never add broad wildcard tool permissions or
`--dangerously-skip-permissions` merely to enable delegation. Those require
separate explicit operator authorisation.
<!-- pj-managed-projects:end -->
EOF_CONTEXT
}

ensure_shared_context_entry() {
  target="$1"
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir" || return 1

  if [ -L "$target" ]; then
    target_resolved="$(readlink -f "$target" 2>/dev/null || true)"
    home_resolved="$(readlink -f "$home_context" 2>/dev/null || true)"
    if [ -n "$target_resolved" ] && [ "$target_resolved" = "$home_resolved" ]; then
      return 0
    fi
    if [ -z "$target_resolved" ] || [ ! -e "$target_resolved" ]; then
      printf 'pj installer: instruction symlink at %s is broken; preserving it, but shared guidance is not installed there.\n' "$target" >&2
      return 1
    fi
    printf 'Note: preserving unrelated instruction symlink at %s; point it to %s to share home guidance.\n' "$target" "$home_context" >&2
    return 0
  fi

  if [ -e "$target" ]; then
    if [ ! -f "$target" ]; then
      printf 'Note: preserving non-file instruction path at %s; cannot replace it with shared guidance.\n' "$target" >&2
      return 0
    fi

    tmp_context="$(mktemp)" || return 1
    strip_known_backend_blocks "$target" "$tmp_context" || {
      rm -f "$tmp_context"
      printf 'pj installer: malformed managed instruction markers at %s; preserving the file unchanged.\n' "$target" >&2
      return 1
    }

    if grep -q '[^[:space:]]' "$tmp_context"; then
      rm -f "$tmp_context"
      write_home_context_block | update_managed_block \
        "$target" \
        '<!-- pj-managed-projects:start -->' \
        '<!-- pj-managed-projects:end -->' \
        '<!-- managed-projects:start -->' \
        '<!-- managed-projects:end -->' || return 1
      printf 'Note: preserved custom backend instructions and refreshed the shared managed block at %s.\n' "$target" >&2
      return 0
    fi

    rm -f "$tmp_context" "$target" || return 1
  fi

  ln -s "$home_context" "$target" || return 1
}

home_context="$HOME/AGENTS.md"
write_home_context_block | update_managed_block \
  "$home_context" \
  '<!-- pj-managed-projects:start -->' \
  '<!-- pj-managed-projects:end -->' \
  '<!-- managed-projects:start -->' \
  '<!-- managed-projects:end -->' || exit 1

workspace_context="$workspace/AGENTS.md"
update_managed_block \
  "$workspace_context" \
  '<!-- pj-managed-projects:start -->' \
  '<!-- pj-managed-projects:end -->' \
  '<!-- managed-projects:start -->' \
  '<!-- managed-projects:end -->' <<'EOF_CONTEXT'
<!-- pj-managed-projects:start -->
## Shared `pj` planning workspace

This directory is the shared local operator workspace used by `pj`. Natural-language
requests to add, update, close or organise GitHub issues, change GitHub Project
fields or membership, or process Chat implementation queue items are GitHub task
and Project-administration requests unless the operator explicitly asks for
repository code changes.

For each such request:

1. resolve the target only from the managed repositories and `.projects`
   contracts available in this workspace;
2. read and follow the target repository's root `AGENTS.md`;
3. read `.projects/project.md` plus the one Project contract it resolves and use
   the shared `github-projects` skill named by the repository guidance;
4. interpret ordinary phrases such as "add an issue to X", "set this to P3" or
   "process the implementation issues for X" through those checked contracts
   rather than inventing provider-specific task logic;
5. preserve unrelated state, stop on consequential ambiguity, and independently
   read back every completed GitHub mutation before reporting success.

If the operator explicitly asks to update or refresh `github-projects`
across the local managed repositories, use `pj-update-skills`. Do not recreate a
one-off loop unless that installed updater is unavailable. Treat this as local
operator maintenance rather than an issue or Project mutation.

For implementation-queue requests, follow `github-projects`'s
`references/local-implementation-queue.md`, including its trust and review rules.
A repository or Project name supplied by the operator narrows resolution to the
corresponding managed target; do not broaden to arbitrary accessible repositories.

This workspace-level guidance is only a dispatcher. A target repository's own
`AGENTS.md`, `.projects` contract and current GitHub state remain authoritative
for that target.
<!-- pj-managed-projects:end -->
EOF_CONTEXT

codex_context="$HOME/.codex/AGENTS.md"
copilot_context="$HOME/.copilot/copilot-instructions.md"
gemini_context="$HOME/.gemini/GEMINI.md"
ensure_shared_context_entry "$codex_context" || exit 1
ensure_shared_context_entry "$copilot_context" || exit 1
ensure_shared_context_entry "$gemini_context" || exit 1

codex_rules="$HOME/.codex/rules/default.rules"
update_managed_block "$codex_rules" '# pj-agy-subagent:start' '# pj-agy-subagent:end' <<'EOF_RULES'
# pj-agy-subagent:start
prefix_rule(
    pattern = ["agy"],
    decision = "allow",
    justification = "Allow the opt-in agy subagent command; ~/AGENTS.md still requires explicit operator authorisation for the task or conversation.",
)
# pj-agy-subagent:end
EOF_RULES

printf 'Installed pj at %s\n' "$launcher_target"
printf 'Installed pja -> pj at %s\n' "$antigravity_target"
printf 'Installed pjcp -> pj at %s\n' "$copilot_target"
printf 'Installed pjcd -> pj at %s\n' "$codex_target"
printf 'Installed pj-update-skills at %s\n' "$skill_update_target"
printf 'Recorded pj install directory in %s\n' "$install_bin_dir_file"
printf 'Configured pj default backend in %s\n' "$default_backend_file"
printf 'Updated canonical home agent guidance at %s\n' "$home_context"
printf 'Updated shared workspace guidance at %s\n' "$workspace_context"
printf 'Linked or hard-updated Codex, Copilot and Antigravity user instructions from %s without replacing custom files.\n' "$home_context"
printf 'Updated Codex agy execution rule at %s\n' "$codex_rules"

if ! command -v codex >/dev/null 2>&1; then
  printf 'Note: codex is not currently on PATH.\n' >&2
fi

if ! command -v agy >/dev/null 2>&1; then
  printf 'Note: agy is not currently on PATH. Install and authenticate Google Antigravity CLI before using pja or delegated agy calls.\n' >&2
fi

if ! command -v copilot >/dev/null 2>&1; then
  printf 'Note: copilot is not currently on PATH. Install and authenticate GitHub Copilot CLI before using pjcp.\n' >&2
fi

if ! command -v projects >/dev/null 2>&1; then
  printf 'Note: the optional projects CLI is not currently on PATH. pj still works; installation instructions are at https://github.com/MiguelRodo/github-projects-skill/blob/main/docs/cli.md.\n' >&2
fi

if ! path_contains_dir "$launcher_dir"; then
  printf 'Note: %s is not currently on PATH. Add it in your shell startup file or rerun with PJ_BIN_DIR set to a suitable user bin directory.\n' "$launcher_dir" >&2
fi
