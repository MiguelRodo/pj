#!/usr/bin/env bash

workspace="${PJ_WORKSPACE:-$HOME/planning}"
skill_name="github-projects"
legacy_skill_name="github-project-admin"
canonical_skill_dir="$workspace/github-projects-skill"
canonical_skill_repo="MiguelRodo/github-projects-skill"
canonical_skill_repo_url="https://github.com/$canonical_skill_repo"
canonical_skill_ref="refs/heads/main"
canonical_skill_pin="main"
canonical_skill_tree_sha=""

is_canonical_skill_repo() {
  local path="$1"
  [ "$path" = "$canonical_skill_dir" ] || \
  [ -f "$path/skills/$skill_name/SKILL.md" ] || \
  [ -f "$path/skills/$legacy_skill_name/SKILL.md" ] || \
  git -C "$path" remote get-url origin 2>/dev/null | grep -Eq '(github-projects-skill|MiguelRodo/projects-skill)'
}

# `gh skill install` resolves the latest tagged release before the default
# branch, so a plain install records refs/tags/v0.3.0 and `gh skill update`
# reports "All skills are up to date" while canonical main keeps moving. Record
# the tree SHA of the canonical skill on main so installs can be checked against
# the real current content instead of that success message.
resolve_canonical_skill_tree_sha() {
  [ -d "$canonical_skill_dir/.git" ] || return 0
  canonical_skill_tree_sha="$(
    git -C "$canonical_skill_dir" rev-parse --verify --quiet \
      "refs/remotes/origin/main:skills/$skill_name" 2>/dev/null || true
  )"
}

# An installed copy is only current when it is sourced from the canonical
# repository on main and, when the canonical checkout is available, matches the
# current canonical main tree SHA. Tag-pinned installs such as refs/tags/v0.3.0
# are therefore stale even though `gh skill update` calls them up to date.
installed_skill_is_current() {
  local repo_path="$1"
  local skill_file="$repo_path/.agents/skills/$skill_name/SKILL.md"
  local installed_sha

  [ -f "$skill_file" ] || return 1
  grep -Fq "github-repo: $canonical_skill_repo_url" "$skill_file" 2>/dev/null || return 1
  grep -Fq "github-ref: $canonical_skill_ref" "$skill_file" 2>/dev/null || return 1

  if [ -n "$canonical_skill_tree_sha" ]; then
    installed_sha="$(sed -n 's/^[[:space:]]*github-tree-sha:[[:space:]]*//p' "$skill_file" | head -n1)"
    [ "$installed_sha" = "$canonical_skill_tree_sha" ] || return 1
  fi

  return 0
}

if [ "$(basename "$0")" = "pj-update-skills" ] && command -v pj >/dev/null 2>&1; then
  exec pj --update-skill "$@"
fi

if ! command -v git >/dev/null 2>&1; then
  echo "pj --update-skill: git is required." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "pj --update-skill: GitHub CLI (gh) is required." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "pj --update-skill: gh is not authenticated." >&2
  echo "Run 'gh auth status' for details, authenticate, then retry." >&2
  exit 1
fi

if [ ! -d "$workspace" ]; then
  echo "pj --update-skill: workspace does not exist: $workspace" >&2
  exit 1
fi

cd "$workspace" || exit 1

updated_count=0
unchanged_count=0
failed_count=0

restore_stash() {
  local repo_path="$1"
  local had_stash="$2"

  [ "$had_stash" -eq 1 ] || return 0

  echo "Restoring previous local changes..."
  if git -C "$repo_path" stash pop; then
    return 0
  fi

  echo "ERROR: saved local changes conflicted while restoring in $repo_path" >&2
  echo "The stash has been retained. Resolve that repository manually." >&2
  return 1
}

restore_skills() {
  local repo_path="$1"
  local backup_dir="$2"

  git -C "$repo_path" reset --quiet -- ".agents/skills" 2>/dev/null || true
  git -C "$repo_path" checkout --quiet -- ".agents/skills" 2>/dev/null || true
  git -C "$repo_path" clean -fd --quiet -- ".agents/skills" 2>/dev/null || true

  rm -rf "$repo_path/.agents/skills"
  if [ -d "$backup_dir/skills" ]; then
    mkdir -p "$repo_path/.agents"
    cp -a "$backup_dir/skills" "$repo_path/.agents/skills"
  fi
  rm -rf "$backup_dir"
}

update_repo() {
  local repo_path="$1"
  local repo_name
  local had_stash=0
  local branch
  local upstream
  local repo_updated=0

  repo_name="$(basename "$repo_path")"

  echo
  echo "============================================================"
  echo "Updating: $repo_name"
  echo "============================================================"

  if [ -n "$(git -C "$repo_path" status --porcelain)" ]; then
    echo "Stashing existing local changes..."
    if ! git -C "$repo_path" stash push -u \
      -m "Automatic stash before $skill_name update $(date '+%Y-%m-%d %H:%M:%S')"; then
      echo "ERROR: could not stash local changes in $repo_name" >&2
      return 1
    fi
    had_stash=1
  fi

  branch="$(git -C "$repo_path" branch --show-current)"
  if [ -z "$branch" ]; then
    echo "ERROR: detached HEAD in $repo_name" >&2
    restore_stash "$repo_path" "$had_stash" || true
    return 1
  fi

  local is_canonical=0
  if is_canonical_skill_repo "$repo_path"; then
    is_canonical=1
  fi

  echo "Fetching..."
  if ! git -C "$repo_path" fetch --prune; then
    echo "ERROR: fetch failed in $repo_name" >&2
    restore_stash "$repo_path" "$had_stash" || true
    return 1
  fi

  if [ "$is_canonical" -eq 1 ]; then
    resolve_canonical_skill_tree_sha
  fi

  upstream="$(git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

  if [ -z "$upstream" ] && \
     git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    upstream="origin/$branch"
    if ! git -C "$repo_path" branch --set-upstream-to="$upstream" "$branch"; then
      echo "ERROR: could not set upstream for $repo_name" >&2
      restore_stash "$repo_path" "$had_stash" || true
      return 1
    fi
  fi

  if [ -n "$upstream" ]; then
    if git -C "$repo_path" merge-base --is-ancestor "$upstream" HEAD; then
      echo "Already contains latest $upstream."
      if [ "$is_canonical" -eq 1 ] && \
         ! git -C "$repo_path" merge-base --is-ancestor HEAD "$upstream"; then
        echo "WARNING: $repo_name has local commits not on $upstream; leaving them for a pull request." >&2
      fi
    elif [ "$is_canonical" -eq 1 ]; then
      # The canonical skill repository protects its main branch and requires pull
      # requests, so never manufacture or push a merge commit there. Fast-forward
      # when the remote simply moved ahead, and stop when the histories diverged.
      if git -C "$repo_path" merge-base --is-ancestor HEAD "$upstream"; then
        echo "Fast-forwarding $repo_name to $upstream..."
        if ! git -C "$repo_path" merge --ff-only "$upstream"; then
          echo "ERROR: fast-forward failed in $repo_name" >&2
          restore_stash "$repo_path" "$had_stash" || true
          return 1
        fi
      else
        echo "ERROR: canonical skill repository $repo_name has diverged from $upstream." >&2
        echo "Refusing to create or push a merge commit on its protected branch." >&2
        echo "Synchronise $repo_name manually, for example through a pull request, then retry." >&2
        restore_stash "$repo_path" "$had_stash" || true
        return 1
      fi
    else
      echo "Merging $upstream..."
      if ! git -C "$repo_path" merge --no-ff "$upstream" \
        -m "Merge $upstream before updating $skill_name skill"; then
        echo "ERROR: merge failed in $repo_name; aborting merge." >&2
        git -C "$repo_path" merge --abort 2>/dev/null || true
        restore_stash "$repo_path" "$had_stash" || true
        return 1
      fi
    fi
  else
    echo "WARNING: no upstream configured for $repo_name; remote sync skipped." >&2
  fi

  if [ "$is_canonical" -eq 1 ]; then
    echo "Canonical skill repository: skipping installed-skill refresh and push."
  else
    local legacy_installed=0
    if [ -d "$repo_path/.agents/skills/$legacy_skill_name" ] || \
       [ -f "$repo_path/.agents/skills/$legacy_skill_name/SKILL.md" ]; then
      legacy_installed=1
    fi

    local needs_migration=0
    local migration_reason=""
    if [ "$legacy_installed" -eq 1 ]; then
      needs_migration=1
      migration_reason="$legacy_skill_name is still installed"
    elif [ ! -f "$repo_path/.agents/skills/$skill_name/SKILL.md" ]; then
      needs_migration=1
      migration_reason="$skill_name is not installed"
    elif ! installed_skill_is_current "$repo_path"; then
      needs_migration=1
      migration_reason="$skill_name does not match $canonical_skill_repo main"
    fi

    local skills_backup
    skills_backup="$(mktemp -d)"
    if [ -d "$repo_path/.agents/skills" ]; then
      cp -a "$repo_path/.agents/skills" "$skills_backup/skills"
    fi

    if [ "$needs_migration" -eq 1 ]; then
      # Pin to main explicitly: an unpinned install resolves the latest tagged
      # release and would put the stale copy straight back.
      echo "Installing $skill_name from $canonical_skill_repo@$canonical_skill_pin ($migration_reason)..."
      if ! (cd "$repo_path" && gh skill install "$canonical_skill_repo" "$skill_name" \
              --agent universal --scope project --force --pin "$canonical_skill_pin") || \
         ! installed_skill_is_current "$repo_path"; then
        echo "ERROR: skill installation/migration failed in $repo_name; the installed skill is still not current." >&2
        restore_skills "$repo_path" "$skills_backup"
        restore_stash "$repo_path" "$had_stash" || true
        return 1
      fi
    else
      # `gh skill update` is deliberately not trusted here: it reports tagged
      # copies as up to date and would resolve the latest tag for the rest.
      # Reconciliation happens by comparing against canonical main above.
      echo "$skill_name already matches $canonical_skill_repo main."
    fi

    if [ -e "$repo_path/.agents/skills/$legacy_skill_name" ]; then
      rm -rf "$repo_path/.agents/skills/$legacy_skill_name"
    fi
    rm -rf "$skills_backup"

    if ! git -C "$repo_path" diff --quiet -- ".agents/skills" || \
       ! git -C "$repo_path" diff --cached --quiet -- ".agents/skills" || \
       [ -n "$(git -C "$repo_path" ls-files --others --exclude-standard -- ".agents/skills")" ]; then
      git -C "$repo_path" add -A -- ".agents/skills" || {
        restore_stash "$repo_path" "$had_stash" || true
        return 1
      }
      if ! git -C "$repo_path" commit -m "Update $skill_name skill"; then
        echo "ERROR: skill commit failed in $repo_name" >&2
        restore_stash "$repo_path" "$had_stash" || true
        return 1
      fi
      repo_updated=1
    else
      echo "Skill already current; nothing to commit."
    fi
  fi

  if [ "$is_canonical" -eq 1 ]; then
    echo "Canonical skill repository: push skipped; protected main is updated through pull requests."
  elif git -C "$repo_path" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    echo "Pushing $repo_name..."
    if ! git -C "$repo_path" push; then
      echo "ERROR: push failed in $repo_name" >&2
      restore_stash "$repo_path" "$had_stash" || true
      return 1
    fi
  elif git -C "$repo_path" remote get-url origin >/dev/null 2>&1; then
    echo "Pushing $repo_name and setting upstream..."
    if ! git -C "$repo_path" push -u origin "$branch"; then
      echo "ERROR: push failed in $repo_name" >&2
      restore_stash "$repo_path" "$had_stash" || true
      return 1
    fi
  else
    echo "WARNING: no origin remote in $repo_name; push skipped." >&2
  fi

  if ! restore_stash "$repo_path" "$had_stash"; then
    return 1
  fi

  if [ "$repo_updated" -eq 1 ]; then
    updated_count=$((updated_count + 1))
  else
    unchanged_count=$((unchanged_count + 1))
  fi

  return 0
}

found=0

process_workspace_entry() {
  local entry="$1"

  [ -d "$entry/.git" ] || return 0
  if is_canonical_skill_repo "$entry" || \
     [ -f "$entry/.agents/skills/$skill_name/SKILL.md" ] || \
     [ -f "$entry/.agents/skills/$legacy_skill_name/SKILL.md" ]; then
    found=1
    if ! update_repo "$entry"; then
      failed_count=$((failed_count + 1))
    fi
  fi
}

# Sync the canonical skill checkout first: the main tree SHA it resolves is the
# reference every installed copy is compared against.
if [ -d "$canonical_skill_dir" ]; then
  process_workspace_entry "$canonical_skill_dir"
fi

for entry in "$workspace"/*; do
  [ "$entry" = "$canonical_skill_dir" ] && continue
  process_workspace_entry "$entry"
done

if [ "$found" -eq 0 ]; then
  echo "pj --update-skill: no managed repositories found under $workspace" >&2
  exit 1
fi

echo
echo "============================================================"
echo "Managed skill update finished"
echo "============================================================"
echo "Updated repositories:   $updated_count"
echo "Already current/synced: $unchanged_count"
echo "Failed repositories:    $failed_count"
echo "Workspace:              $workspace"

if [ "$failed_count" -gt 0 ]; then
  exit 1
fi
