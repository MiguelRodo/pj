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

# Ordinary managed repositories receive this stable, pj-owned branch when
# repository rules reject a direct push to their default branch. The stable name
# is what lets a rerun reuse an open pull request instead of opening a second one
# for the same skill refresh.
skill_update_branch="pj/update-github-projects-skill"
skill_commit_subject="Update $skill_name skill"

updated_count=0
unchanged_count=0
skipped_count=0
failed_count=0
opened_pr_count=0
reused_pr_count=0
found=0

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

# Describe why the installed copy on a default-branch worktree is not the
# canonical main content. Prints nothing when it is already current.
skill_refresh_reason() {
  local repo_path="$1"

  if [ -d "$repo_path/.agents/skills/$legacy_skill_name" ] || \
     [ -f "$repo_path/.agents/skills/$legacy_skill_name/SKILL.md" ]; then
    printf '%s is still installed\n' "$legacy_skill_name"
  elif [ ! -f "$repo_path/.agents/skills/$skill_name/SKILL.md" ]; then
    printf '%s is not installed\n' "$skill_name"
  elif ! installed_skill_is_current "$repo_path"; then
    printf '%s does not match %s main\n' "$skill_name" "$canonical_skill_repo"
  fi
}

# The skill refresh must target the repository's default branch, never whatever
# branch happens to be checked out. Prefer the hosting provider's answer, then
# the remote HEAD recorded by the clone, then the conventional names. Only a
# branch that has a real remote-tracking ref is returned.
resolve_default_branch() {
  local repo_path="$1"
  local candidate
  local candidates=()

  candidate="$(cd "$repo_path" && gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
  [ -n "$candidate" ] && candidates+=("$candidate")

  candidate="$(git -C "$repo_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$candidate" ] && candidates+=("${candidate#origin/}")

  candidates+=(main master)

  for candidate in "${candidates[@]}"; do
    [ -n "$candidate" ] || continue
    if git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# A failed direct push is only handed to the pull-request path when the remote
# rejected it because of repository rules. Network, authentication and
# non-fast-forward failures stay failures, and protection is never bypassed.
push_rejection_is_rules_based() {
  printf '%s\n' "$1" | grep -Eqi \
    'GH006|GH013|protected branch|branch protection|repository rule|pre-receive hook declined|remote rejected|required status check|required review|review is required|pull request'
}

# The worktrees live in fresh mktemp directories. Remove them without ever
# following a path this script did not create.
remove_worktree() {
  local repo_path="$1"
  local worktree_dir="$2"

  [ -n "$worktree_dir" ] || return 0
  [ -d "$worktree_dir" ] || return 0

  git -C "$repo_path" worktree remove --force "$worktree_dir" >/dev/null 2>&1 || true
  if [ -d "$worktree_dir" ]; then
    case "$worktree_dir" in
      */pj-skill-update.*)
        rm -rf -- "$worktree_dir"
        ;;
      *)
        echo "ERROR: refusing to remove unexpected worktree path: $worktree_dir" >&2
        return 1
        ;;
    esac
  fi
  git -C "$repo_path" worktree prune >/dev/null 2>&1 || true
}

# Best-effort sync of the operator's own checkout when it already sits on the
# default branch. The fast-forward only happens when the local branch is a pure
# ancestor of the freshly pushed commit; local commits, local edits and every
# other branch are left untouched.
sync_local_default_branch() {
  local repo_path="$1"
  local default_branch="$2"
  local new_sha="$3"
  local current_branch

  current_branch="$(git -C "$repo_path" branch --show-current)"
  [ "$current_branch" = "$default_branch" ] || return 0

  if ! git -C "$repo_path" merge-base --is-ancestor "refs/heads/$default_branch" "$new_sha"; then
    echo "WARNING: local $default_branch has commits not on origin/$default_branch; leaving it unchanged." >&2
    return 0
  fi

  if git -C "$repo_path" merge --ff-only "$new_sha" >/dev/null 2>&1; then
    echo "Fast-forwarded the local $default_branch checkout to include the skill update."
  else
    echo "WARNING: could not fast-forward the local $default_branch checkout; run 'git pull' when convenient." >&2
  fi
}

# Push the skill commit to the dedicated update branch. A leftover branch from an
# interrupted earlier run can make the plain push non-fast-forward; that branch
# only ever carries this refresh, so update it under an explicit lease instead of
# creating another branch or opening another pull request.
push_skill_update_branch() {
  local worktree_dir="$1"
  local remote_branch="refs/heads/$skill_update_branch"
  local expected output

  output="$(git -C "$worktree_dir" push origin "HEAD:$remote_branch" 2>&1)" && return 0

  expected="$(git -C "$worktree_dir" ls-remote origin "$remote_branch" 2>/dev/null | awk '{print $1}' | head -n1)"
  output="$(git -C "$worktree_dir" push "--force-with-lease=$remote_branch:$expected" origin "HEAD:$remote_branch" 2>&1)" && return 0

  printf '%s\n' "$output" >&2
  return 1
}

# True when the open pull request's branch already carries exactly the installed
# .agents/skills tree this run would push, so rerunning is a no-op instead of
# commit churn on the existing pull request.
update_branch_is_reusable() {
  local worktree_dir="$1"
  local remote_ref="refs/remotes/origin/$skill_update_branch"
  local desired_sha existing_sha

  git -C "$worktree_dir" fetch --quiet --force origin \
    "+refs/heads/$skill_update_branch:$remote_ref" 2>/dev/null || return 1

  desired_sha="$(git -C "$worktree_dir" rev-parse --verify --quiet 'HEAD:.agents/skills' 2>/dev/null)" || return 1
  existing_sha="$(git -C "$worktree_dir" rev-parse --verify --quiet "$remote_ref:.agents/skills" 2>/dev/null)" || return 1

  [ -n "$desired_sha" ] && [ "$desired_sha" = "$existing_sha" ]
}

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

# The canonical skill repository protects its main branch and requires pull
# requests, so never manufacture or push a merge commit there. Fast-forward when
# the remote simply moved ahead, and stop when the histories diverged.
update_canonical_repo() {
  local repo_path="$1"
  local repo_name="$2"
  local branch upstream
  local had_stash=0

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

  upstream="$(git -C "$repo_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

  if [ -z "$upstream" ] && \
     git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    upstream="origin/$branch"
  fi

  if [ -n "$upstream" ]; then
    if git -C "$repo_path" merge-base --is-ancestor "$upstream" HEAD; then
      echo "Already contains latest $upstream."
      if ! git -C "$repo_path" merge-base --is-ancestor HEAD "$upstream"; then
        echo "WARNING: $repo_name has local commits not on $upstream; leaving them for a pull request." >&2
      fi
    elif git -C "$repo_path" merge-base --is-ancestor HEAD "$upstream"; then
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
    echo "WARNING: no upstream configured for $repo_name; remote sync skipped." >&2
  fi

  echo "Canonical skill repository: skipping installed-skill refresh and push."

  if ! restore_stash "$repo_path" "$had_stash"; then
    return 1
  fi

  return 0
}

# Ordinary managed repositories are refreshed on an isolated worktree of their
# default branch, so the operator's checked-out branch and dirty state are never
# touched. The skill-only commit is pushed directly when repository rules allow
# it; otherwise it is preserved on the dedicated update branch and handed over
# through a pull request.
#
# Return codes: 0 updated, 1 failed, 2 already current, 3 skipped, 4 reused an
# existing open skill-update pull request.
update_managed_repo() {
  local repo_path="$1"
  local repo_name="$2"
  local default_branch remote_default
  local worktree_dir=""
  local refresh_reason
  local push_output push_status
  local new_sha
  local pr_info pr_output pr_status pr_number pr_url
  local pr_body

  if ! git -C "$repo_path" remote get-url origin >/dev/null 2>&1; then
    echo "WARNING: no origin remote in $repo_name; skill refresh skipped." >&2
    return 3
  fi

  default_branch="$(resolve_default_branch "$repo_path")" || true
  if [ -z "$default_branch" ]; then
    echo "ERROR: could not determine the default branch for $repo_name." >&2
    return 1
  fi
  remote_default="refs/remotes/origin/$default_branch"

  echo "Default branch: $default_branch"

  worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/pj-skill-update.XXXXXXXX")" || {
    echo "ERROR: could not create a temporary worktree directory for $repo_name." >&2
    return 1
  }

  if ! git -C "$repo_path" worktree add --detach "$worktree_dir" "$remote_default" >/dev/null 2>&1; then
    echo "ERROR: could not create an isolated worktree for origin/$default_branch in $repo_name." >&2
    remove_worktree "$repo_path" "$worktree_dir"
    return 1
  fi

  refresh_reason="$(skill_refresh_reason "$worktree_dir")"

  if [ -z "$refresh_reason" ]; then
    remove_worktree "$repo_path" "$worktree_dir"
    echo "$skill_name already matches $canonical_skill_repo main on $default_branch; nothing to commit."
    return 2
  fi

  # Pin to main explicitly: an unpinned install resolves the latest tagged
  # release and would put the stale copy straight back.
  echo "Installing $skill_name from $canonical_skill_repo@$canonical_skill_pin on $default_branch ($refresh_reason)..."
  if ! (cd "$worktree_dir" && gh skill install "$canonical_skill_repo" "$skill_name" \
          --agent universal --scope project --force --pin "$canonical_skill_pin") || \
     ! installed_skill_is_current "$worktree_dir"; then
    echo "ERROR: skill installation/migration failed in $repo_name; the installed skill is still not current." >&2
    remove_worktree "$repo_path" "$worktree_dir"
    return 1
  fi

  if [ -e "$worktree_dir/.agents/skills/$legacy_skill_name" ]; then
    rm -rf -- "$worktree_dir/.agents/skills/$legacy_skill_name"
  fi

  if ! git -C "$worktree_dir" diff --quiet -- ".agents/skills" || \
     ! git -C "$worktree_dir" diff --cached --quiet -- ".agents/skills" || \
     [ -n "$(git -C "$worktree_dir" ls-files --others --exclude-standard -- ".agents/skills")" ]; then
    if ! git -C "$worktree_dir" add -A -- ".agents/skills" || \
       ! git -C "$worktree_dir" commit -m "$skill_commit_subject" >/dev/null; then
      echo "ERROR: skill commit failed in $repo_name" >&2
      remove_worktree "$repo_path" "$worktree_dir"
      return 1
    fi
  else
    remove_worktree "$repo_path" "$worktree_dir"
    echo "$skill_name already matches $canonical_skill_repo main on $default_branch; nothing to commit."
    return 2
  fi

  echo "Pushing $skill_commit_subject to origin/$default_branch..."
  push_output="$(git -C "$worktree_dir" push origin "HEAD:refs/heads/$default_branch" 2>&1)"
  push_status=$?

  if [ "$push_status" -eq 0 ]; then
    new_sha="$(git -C "$worktree_dir" rev-parse HEAD)"
    remove_worktree "$repo_path" "$worktree_dir"
    echo "Pushed $skill_commit_subject to origin/$default_branch."
    sync_local_default_branch "$repo_path" "$default_branch" "$new_sha"
    return 0
  fi

  if ! push_rejection_is_rules_based "$push_output"; then
    echo "ERROR: push to origin/$default_branch failed in $repo_name." >&2
    printf '%s\n' "$push_output" >&2
    remove_worktree "$repo_path" "$worktree_dir"
    return 1
  fi

  echo "Direct push to origin/$default_branch was rejected by repository rules; handing the skill-only commit to a pull request instead."

  pr_info="$(cd "$repo_path" && gh pr list --head "$skill_update_branch" --base "$default_branch" \
              --state open --json number,url --jq '.[0] | "\(.number) \(.url)"' 2>/dev/null)"
  pr_status=$?

  if [ "$pr_status" -ne 0 ]; then
    echo "ERROR: could not check for an existing skill-update pull request in $repo_name." >&2
    remove_worktree "$repo_path" "$worktree_dir"
    return 1
  fi

  if [ -n "$pr_info" ]; then
    pr_info="$(printf '%s\n' "$pr_info" | awk 'NF { print; exit }')"
    pr_number="${pr_info%% *}"
    pr_url="${pr_info#* }"

    if ! printf '%s\n' "$pr_number" | grep -Eq '^[0-9]+$'; then
      echo "ERROR: could not parse the existing skill-update pull request in $repo_name: $pr_info" >&2
      remove_worktree "$repo_path" "$worktree_dir"
      return 1
    fi

    if update_branch_is_reusable "$worktree_dir"; then
      remove_worktree "$repo_path" "$worktree_dir"
      echo "Reusing existing skill-update pull request #$pr_number: $pr_url"
      reused_pr_count=$((reused_pr_count + 1))
      return 4
    fi

    if ! push_skill_update_branch "$worktree_dir"; then
      echo "ERROR: could not update the existing skill-update branch in $repo_name." >&2
      remove_worktree "$repo_path" "$worktree_dir"
      return 1
    fi

    remove_worktree "$repo_path" "$worktree_dir"
    echo "Updated existing skill-update pull request #$pr_number: $pr_url"
    reused_pr_count=$((reused_pr_count + 1))
    return 4
  fi

  if ! push_skill_update_branch "$worktree_dir"; then
    echo "ERROR: could not push $skill_update_branch in $repo_name." >&2
    remove_worktree "$repo_path" "$worktree_dir"
    return 1
  fi

  pr_body="$(printf '%s\n\n%s\n' \
    "Automated skill-only refresh of $skill_name from $canonical_skill_repo@$canonical_skill_pin." \
    "Direct pushes to $default_branch are rejected by repository rules, so pj --update-skill preserved the refresh on $skill_update_branch and opened this pull request. The branch contains only .agents/skills changes.")"

  pr_output="$(cd "$repo_path" && gh pr create \
    --base "$default_branch" \
    --head "$skill_update_branch" \
    --title "$skill_commit_subject" \
    --body "$pr_body" 2>&1)"
  pr_status=$?

  if [ "$pr_status" -ne 0 ]; then
    echo "ERROR: pushed $skill_update_branch but could not open a pull request in $repo_name." >&2
    printf '%s\n' "$pr_output" >&2
    remove_worktree "$repo_path" "$worktree_dir"
    return 1
  fi

  pr_url="$(printf '%s\n' "$pr_output" | grep -Eo 'https?://[^[:space:]]+' | tail -n1)"
  if [ -z "$pr_url" ]; then
    pr_url="$pr_output"
  fi

  remove_worktree "$repo_path" "$worktree_dir"
  echo "Opened skill-update pull request: $pr_url"
  opened_pr_count=$((opened_pr_count + 1))
  return 0
}

update_repo() {
  local repo_path="$1"
  local repo_name
  local rc

  repo_name="$(basename "$repo_path")"

  echo
  echo "============================================================"
  echo "Updating: $repo_name"
  echo "============================================================"

  echo "Fetching..."
  if ! git -C "$repo_path" fetch --prune; then
    echo "ERROR: fetch failed in $repo_name" >&2
    failed_count=$((failed_count + 1))
    return 1
  fi

  if is_canonical_skill_repo "$repo_path"; then
    resolve_canonical_skill_tree_sha
    if update_canonical_repo "$repo_path" "$repo_name"; then
      unchanged_count=$((unchanged_count + 1))
      return 0
    fi
    failed_count=$((failed_count + 1))
    return 1
  fi

  update_managed_repo "$repo_path" "$repo_name"
  rc=$?

  case "$rc" in
    0)
      updated_count=$((updated_count + 1))
      ;;
    2|4)
      unchanged_count=$((unchanged_count + 1))
      ;;
    3)
      skipped_count=$((skipped_count + 1))
      ;;
    *)
      failed_count=$((failed_count + 1))
      return 1
      ;;
  esac

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

process_workspace_entry() {
  local entry="$1"

  [ -d "$entry/.git" ] || return 0
  if is_canonical_skill_repo "$entry" || \
     [ -f "$entry/.agents/skills/$skill_name/SKILL.md" ] || \
     [ -f "$entry/.agents/skills/$legacy_skill_name/SKILL.md" ]; then
    found=1
    update_repo "$entry" || true
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
echo "Skipped repositories:   $skipped_count"
echo "Skill-update PRs:       $opened_pr_count opened, $reused_pr_count reused"
echo "Failed repositories:    $failed_count"
echo "Workspace:              $workspace"

if [ "$failed_count" -gt 0 ]; then
  exit 1
fi
