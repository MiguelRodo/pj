#!/usr/bin/env bash

# Regression tests for the default-branch policy of `pj --update-skill`:
#
#  1. the refresh targets the repository's real default branch, never the branch
#     that happens to be checked out, and never commits on feature-branch work;
#  2. an unprotected default branch receives the skill-only commit directly;
#  3. a protected default branch receives the commit on a dedicated branch plus
#     a pull request instead of a local default branch left ahead of its remote;
#  4. the operator's branch, index and dirty working state survive untouched;
#  5. rerunning reuses an already-open equivalent skill-update pull request
#     instead of opening another one.

operator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
updater="$operator_dir/update-managed-skills.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

fake_bin="$tmp/bin"
mkdir -p "$fake_bin" || exit 1

# The canonical skill checkout the fake gh copies from. It lives outside every
# test workspace so the scenarios stay focused on ordinary managed repositories.
canonical_remote="$tmp/canonical.git"
canonical_seed="$tmp/canonical-seed"
canonical_checkout="$tmp/canonical-checkout"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Fake gh: resolves the default branch when the scenario provides one, installs
# canonical main content for `skill install`, and keeps pull requests in a flat
# state file so reuse and duplication are directly observable.
# ---------------------------------------------------------------------------
cat > "$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash

if [ "$1" = 'auth' ] && [ "$2" = 'status' ]; then
  exit 0
fi

if [ "$1" = 'repo' ] && [ "$2" = 'view' ]; then
  if [ -n "${GH_TEST_DEFAULT_BRANCH:-}" ]; then
    printf '%s\n' "$GH_TEST_DEFAULT_BRANCH"
    exit 0
  fi
  exit 1
fi

if [ "$1" = 'skill' ] && [ "$2" = 'install' ] && \
   [ "$3" = 'MiguelRodo/github-projects-skill' ] && [ "$4" = 'github-projects' ] && \
   [ "$5" = '--agent' ] && [ "$6" = 'universal' ] && \
   [ "$7" = '--scope' ] && [ "$8" = 'project' ] && [ "$9" = '--force' ] && \
   [ "${10}" = '--pin' ] && [ "${11}" = 'main' ]; then
  canonical_dir="${GH_SKILL_TEST_CANONICAL_DIR:?}"
  tree_sha="$(git -C "$canonical_dir" rev-parse refs/remotes/origin/main:skills/github-projects)"
  mkdir -p .agents/skills/github-projects
  {
    printf '%s\n' '---'
    printf '%s\n' 'description: Administer GitHub issues and Projects from short outcome requests.'
    printf '%s\n' 'metadata:'
    printf '%s\n' '    github-path: skills/github-projects'
    printf '%s\n' '    github-pinned: main'
    printf '%s\n' '    github-ref: refs/heads/main'
    printf '%s\n' '    github-repo: https://github.com/MiguelRodo/github-projects-skill'
    printf '    github-tree-sha: %s\n' "$tree_sha"
    printf '%s\n' 'name: github-projects'
    printf '%s\n' '---'
    printf '%s\n' '# GitHub Project administration'
    printf '\n'
    printf '%s\n' "${GH_TEST_SKILL_BODY:-canonical main queue semantics}"
  } > .agents/skills/github-projects/SKILL.md
  exit 0
fi

if [ "$1" = 'pr' ] && [ "$2" = 'list' ]; then
  head=""
  base=""
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --head)
        head="$2"
        shift 2
        ;;
      --base)
        base="$2"
        shift 2
        ;;
      --state|--json|--jq)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  if [ -n "${GH_TEST_PR_STATE:-}" ] && [ -f "$GH_TEST_PR_STATE" ]; then
    awk -v h="$head" -v b="$base" '$2 == h && $3 == b { print $1 " " $4; exit }' "$GH_TEST_PR_STATE"
  fi
  exit 0
fi

if [ "$1" = 'pr' ] && [ "$2" = 'create' ]; then
  head=""
  base=""
  title=""
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --head)
        head="$2"
        shift 2
        ;;
      --base)
        base="$2"
        shift 2
        ;;
      --title)
        title="$2"
        shift 2
        ;;
      --body)
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  state="${GH_TEST_PR_STATE:?}"
  number=1
  if [ -f "$state" ]; then
    number=$(( $(wc -l < "$state") + 1 ))
  fi
  url="https://example.invalid/pull/$number"
  printf '%s %s %s %s %s\n' "$number" "$head" "$base" "$url" "$title" >> "$state"
  printf '%s\n' "$url"
  exit 0
fi

printf 'unexpected gh invocation:' >&2
printf ' <%s>' "$@" >&2
printf '\n' >&2
exit 2
EOF
chmod +x "$fake_bin/gh" || exit 1

git_identity() {
  git -C "$1" config user.name 'Test User'
  git -C "$1" config user.email 'test@example.invalid'
}

write_stale_skill() {
  mkdir -p "$1/.agents/skills/github-projects" || return 1
  cat > "$1/.agents/skills/github-projects/SKILL.md" <<'EOF'
---
description: Administer GitHub issues and Projects from short outcome requests.
metadata:
    github-path: skills/github-projects
    github-ref: refs/tags/v0.3.0
    github-repo: https://github.com/MiguelRodo/github-projects-skill
    github-tree-sha: b2825c98f6d903c7d3fa4bf78540ce1fae3da17f
name: github-projects
---
# GitHub Project administration

old tagged queue semantics
EOF
}

# make_repo NAME [protect-main]
make_repo() {
  local name="$1"
  local protect="${2:-}"
  local bare="$tmp/$name.git"
  local seed="$tmp/$name-seed"

  git init --bare "$bare" >/dev/null 2>&1 || exit 1
  git init -b main "$seed" >/dev/null 2>&1 || exit 1
  git_identity "$seed"
  write_stale_skill "$seed"
  printf '%s baseline\n' "$name" > "$seed/local.txt"
  printf '%s feature baseline\n' "$name" > "$seed/feature.txt"
  git -C "$seed" add . || exit 1
  git -C "$seed" commit -m "Initial $name repository" >/dev/null || exit 1
  git -C "$seed" remote add origin "$bare" || exit 1
  git -C "$seed" push -u origin main >/dev/null 2>&1 || exit 1
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/main || exit 1

  if [ "$protect" = 'protect-main' ]; then
    cat > "$bare/hooks/pre-receive" <<EOF
#!/usr/bin/env bash
while read -r old_sha new_sha ref; do
  printf '%s %s\n' "\$ref" "\$new_sha" >> "$tmp/$name-pushes.log"
  case "\$ref" in
    refs/heads/main)
      printf 'remote: error: GH006: Protected branch update failed for refs/heads/main.\n' >&2
      printf 'remote: error: At least 1 approving review is required by reviewers with write access.\n' >&2
      exit 1
      ;;
  esac
done
exit 0
EOF
    chmod +x "$bare/hooks/pre-receive" || exit 1
  fi
}

clone_repo() {
  local name="$1"
  local workspace="$2"

  git clone "$tmp/$name.git" "$workspace/$name" >/dev/null 2>&1 || exit 1
  git_identity "$workspace/$name"
}

# Every path touched by the given ref must live under .agents/skills.
assert_skill_only_commit() {
  local bare="$1"
  local ref="$2"
  local path

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      .agents/skills/*) ;;
      *) fail "commit $ref changed non-skill path: $path" ;;
    esac
  done < <(git --git-dir="$bare" show --pretty=format: --name-only "$ref")
}

# Every path changed between two refs must live under .agents/skills.
assert_skill_only_diff() {
  local bare="$1"
  local base="$2"
  local ref="$3"
  local path

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      .agents/skills/*) ;;
      *) fail "commit $ref changed non-skill path against $base: $path" ;;
    esac
  done < <(git --git-dir="$bare" diff --no-renames --name-only "$base" "$ref")
}

refresh_canonical_fixture() {
  git init --bare "$canonical_remote" >/dev/null 2>&1 || exit 1
  git init -b main "$canonical_seed" >/dev/null 2>&1 || exit 1
  git_identity "$canonical_seed"
  mkdir -p "$canonical_seed/skills/github-projects" || exit 1
  cat > "$canonical_seed/skills/github-projects/SKILL.md" <<'EOF'
---
description: Administer GitHub issues and Projects from short outcome requests.
metadata:
    github-path: skills/github-projects
    github-ref: refs/heads/main
    github-repo: https://github.com/MiguelRodo/github-projects-skill
name: github-projects
---
# GitHub Project administration

canonical main queue semantics
EOF
  git -C "$canonical_seed" add . || exit 1
  git -C "$canonical_seed" commit -m 'Canonical skill' >/dev/null || exit 1
  git -C "$canonical_seed" remote add origin "$canonical_remote" || exit 1
  git -C "$canonical_seed" push -u origin main >/dev/null 2>&1 || exit 1
  git --git-dir="$canonical_remote" symbolic-ref HEAD refs/heads/main || exit 1
  git clone "$canonical_remote" "$canonical_checkout" >/dev/null 2>&1 || exit 1
  git_identity "$canonical_checkout"
}

refresh_canonical_fixture

# ---------------------------------------------------------------------------
# Scenario 1: a feature branch is checked out with a local commit, an index and
# dirty working state. The refresh must land on the default branch only.
# ---------------------------------------------------------------------------
ws1="$tmp/ws1/planning"
mkdir -p "$ws1" || exit 1
make_repo feature_demo
clone_repo feature_demo "$ws1"
repo1="$ws1/feature_demo"
remote1="$tmp/feature_demo.git"

git -C "$repo1" switch -c feature/in-progress >/dev/null 2>&1 || exit 1
printf 'feature work in progress\n' > "$repo1/feature.txt"
git -C "$repo1" add feature.txt || exit 1
git -C "$repo1" commit -m 'Feature work in progress' >/dev/null || exit 1
git -C "$repo1" push -u origin feature/in-progress >/dev/null 2>&1 || exit 1
feature_sha="$(git -C "$repo1" rev-parse HEAD)" || exit 1
local_main_before="$(git -C "$repo1" rev-parse refs/heads/main)" || exit 1
remote_main_before="$(git --git-dir="$remote1" rev-parse main)" || exit 1

printf 'staged work\n' > "$repo1/staged.txt"
git -C "$repo1" add staged.txt || exit 1
printf 'unstaged work\n' > "$repo1/local.txt"
printf 'untracked work\n' > "$repo1/untracked.txt"
status_before="$(git -C "$repo1" status --porcelain)" || exit 1

output1="$(HOME="$tmp/home-1" \
  PJ_WORKSPACE="$ws1" \
  GH_TEST_DEFAULT_BRANCH=main \
  GH_TEST_PR_STATE="$tmp/prs-1.txt" \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 1: updater failed unexpectedly:\n%s\n' "$output1" >&2
  exit 1
}

[ "$(git --git-dir="$remote1" rev-parse main)" != "$remote_main_before" ] || \
  fail 'Scenario 1: default branch was not updated'
[ "$(git --git-dir="$remote1" log -1 --pretty=%s main)" = 'Update github-projects skill' ] || \
  fail 'Scenario 1: default branch tip is not the skill commit'
git --git-dir="$remote1" show main:.agents/skills/github-projects/SKILL.md \
  | grep -Fq 'canonical main queue semantics' || \
  fail 'Scenario 1: default branch does not carry canonical main content'
assert_skill_only_commit "$remote1" main

# The feature branch, its remote ref and the local default branch were not
# dragged into the infrastructure refresh.
[ "$(git --git-dir="$remote1" rev-parse refs/heads/feature/in-progress)" = "$feature_sha" ] || \
  fail 'Scenario 1: remote feature branch moved'
! git --git-dir="$remote1" merge-base --is-ancestor "$feature_sha" main || \
  fail 'Scenario 1: feature work was attached to the default branch'
[ "$(git -C "$repo1" branch --show-current)" = 'feature/in-progress' ] || \
  fail 'Scenario 1: checked-out branch changed'
[ "$(git -C "$repo1" rev-parse HEAD)" = "$feature_sha" ] || \
  fail 'Scenario 1: checked-out feature branch moved'
[ "$(git -C "$repo1" rev-parse refs/heads/main)" = "$local_main_before" ] || \
  fail 'Scenario 1: local default branch was rewritten while on a feature branch'
[ "$(git -C "$repo1" status --porcelain)" = "$status_before" ] || \
  fail 'Scenario 1: dirty working state was not preserved'

# A direct push to an unprotected default branch means no pull request and no
# leftover update branch.
! git --git-dir="$remote1" rev-parse --verify --quiet refs/heads/pj/update-github-projects-skill || \
  fail 'Scenario 1: unexpected skill-update branch was pushed'
[ ! -e "$tmp/prs-1.txt" ] || fail 'Scenario 1: unexpected pull request was opened'

# ---------------------------------------------------------------------------
# Scenario 2: the default branch is protected and currently checked out with
# dirty state. The skill-only commit must reach a dedicated branch and an open
# pull request, leaving the local default branch level with its remote.
# ---------------------------------------------------------------------------
ws2="$tmp/ws2/planning"
mkdir -p "$ws2" || exit 1
make_repo protected_demo protect-main
clone_repo protected_demo "$ws2"
repo2="$ws2/protected_demo"
remote2="$tmp/protected_demo.git"
push_log2="$tmp/protected_demo-pushes.log"

local_head_before="$(git -C "$repo2" rev-parse HEAD)" || exit 1
remote_main_before="$(git --git-dir="$remote2" rev-parse main)" || exit 1

printf 'staged work\n' > "$repo2/staged.txt"
git -C "$repo2" add staged.txt || exit 1
printf 'unstaged work\n' > "$repo2/local.txt"
printf 'untracked work\n' > "$repo2/untracked.txt"
status_before="$(git -C "$repo2" status --porcelain)" || exit 1

output2="$(HOME="$tmp/home-2" \
  PJ_WORKSPACE="$ws2" \
  GH_TEST_DEFAULT_BRANCH=main \
  GH_TEST_PR_STATE="$tmp/prs-2.txt" \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 2: updater failed unexpectedly:\n%s\n' "$output2" >&2
  exit 1
}

case "$output2" in
  *'rejected by repository rules'*) ;;
  *) fail "Scenario 2: no repository-rule handoff was reported. Output:\n$output2" ;;
esac
case "$output2" in
  *'Opened skill-update pull request: https://example.invalid/pull/1'*) ;;
  *) fail "Scenario 2: pull request handoff was not reported. Output:\n$output2" ;;
esac

[ "$(git --git-dir="$remote2" rev-parse main)" = "$remote_main_before" ] || \
  fail 'Scenario 2: protected default branch moved'
git --git-dir="$remote2" show main:.agents/skills/github-projects/SKILL.md \
  | grep -Fq 'old tagged queue semantics' || \
  fail 'Scenario 2: protected default branch content changed'

branch2="refs/heads/pj/update-github-projects-skill"
branch_sha="$(git --git-dir="$remote2" rev-parse "$branch2")" || \
  fail 'Scenario 2: dedicated skill-update branch was not pushed'
[ "$(git --git-dir="$remote2" log -1 --pretty=%s "$branch2")" = 'Update github-projects skill' ] || \
  fail 'Scenario 2: dedicated branch tip is not the skill commit'
[ "$(git --git-dir="$remote2" rev-parse "$branch2^")" = "$remote_main_before" ] || \
  fail 'Scenario 2: dedicated branch is not based on the default branch'
git --git-dir="$remote2" show "$branch2:.agents/skills/github-projects/SKILL.md" \
  | grep -Fq 'canonical main queue semantics' || \
  fail 'Scenario 2: dedicated branch does not carry canonical main content'
assert_skill_only_commit "$remote2" "$branch2"

[ "$(git -C "$repo2" branch --show-current)" = 'main' ] || \
  fail 'Scenario 2: checked-out branch changed'
[ "$(git -C "$repo2" rev-parse HEAD)" = "$local_head_before" ] || \
  fail 'Scenario 2: local default branch was moved by the pull-request handoff'
[ "$(git -C "$repo2" rev-list --count 'origin/main..HEAD')" = '0' ] || \
  fail 'Scenario 2: local default branch was left ahead of origin/main'
[ "$(git -C "$repo2" status --porcelain)" = "$status_before" ] || \
  fail 'Scenario 2: dirty working state was not preserved'

[ "$(wc -l < "$tmp/prs-2.txt")" = '1' ] || fail 'Scenario 2: expected exactly one pull request'
grep -Fq 'refs/heads/main' "$push_log2" || fail 'Scenario 2: no direct push to main was attempted'
[ "$(grep -c 'refs/heads/main' "$push_log2")" = '1' ] || \
  fail 'Scenario 2: the protected default branch was pushed more than once'
[ "$(grep -c "$branch2" "$push_log2")" = '1' ] || \
  fail 'Scenario 2: the dedicated branch was pushed more than once'

# Rerunning must reuse the open pull request instead of opening another one or
# churning the dedicated branch.
output2_rerun="$(HOME="$tmp/home-2" \
  PJ_WORKSPACE="$ws2" \
  GH_TEST_DEFAULT_BRANCH=main \
  GH_TEST_PR_STATE="$tmp/prs-2.txt" \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 2 rerun: updater failed unexpectedly:\n%s\n' "$output2_rerun" >&2
  exit 1
}

case "$output2_rerun" in
  *'Reusing existing skill-update pull request #1: https://example.invalid/pull/1'*) ;;
  *) fail "Scenario 2 rerun: existing pull request was not reused. Output:\n$output2_rerun" ;;
esac
[ "$(wc -l < "$tmp/prs-2.txt")" = '1' ] || \
  fail 'Scenario 2 rerun: a duplicate pull request was opened'
[ "$(git --git-dir="$remote2" rev-parse "$branch2")" = "$branch_sha" ] || \
  fail 'Scenario 2 rerun: the dedicated branch was rewritten'
[ "$(grep -c "$branch2" "$push_log2")" = '1' ] || \
  fail 'Scenario 2 rerun: the dedicated branch was pushed again'
[ "$(git -C "$repo2" status --porcelain)" = "$status_before" ] || \
  fail 'Scenario 2 rerun: dirty working state was not preserved'

# A newer canonical skill revision must refresh the same pull request branch
# instead of opening another pull request.
output2_update="$(HOME="$tmp/home-2" \
  PJ_WORKSPACE="$ws2" \
  GH_TEST_DEFAULT_BRANCH=main \
  GH_TEST_PR_STATE="$tmp/prs-2.txt" \
  GH_TEST_SKILL_BODY='refreshed canonical queue semantics' \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 2 update: updater failed unexpectedly:\n%s\n' "$output2_update" >&2
  exit 1
}

case "$output2_update" in
  *'Updated existing skill-update pull request #1: https://example.invalid/pull/1'*) ;;
  *) fail "Scenario 2 update: existing pull request was not refreshed. Output:\n$output2_update" ;;
esac
[ "$(wc -l < "$tmp/prs-2.txt")" = '1' ] || \
  fail 'Scenario 2 update: a duplicate pull request was opened'
branch_sha="$(git --git-dir="$remote2" rev-parse "$branch2")" || \
  fail 'Scenario 2 update: dedicated branch disappeared'
[ "$(git --git-dir="$remote2" log -1 --pretty=%s "$branch2")" = 'Update github-projects skill' ] || \
  fail 'Scenario 2 update: dedicated branch tip is not the skill commit'
[ "$(git --git-dir="$remote2" rev-parse "$branch2^")" = "$remote_main_before" ] || \
  fail 'Scenario 2 update: dedicated branch jumped off the default branch'
git --git-dir="$remote2" show "$branch2:.agents/skills/github-projects/SKILL.md" \
  | grep -Fq 'refreshed canonical queue semantics' || \
  fail 'Scenario 2 update: dedicated branch was not refreshed'
assert_skill_only_commit "$remote2" "$branch2"
[ "$(git -C "$repo2" rev-parse HEAD)" = "$local_head_before" ] || \
  fail 'Scenario 2 update: local default branch moved'
[ "$(git -C "$repo2" status --porcelain)" = "$status_before" ] || \
  fail 'Scenario 2 update: dirty working state was not preserved'

# ---------------------------------------------------------------------------
# Scenario 3: the default branch is unprotected and checked out cleanly, so the
# skill commit is pushed directly and the local checkout is fast-forwarded.
# ---------------------------------------------------------------------------
ws3="$tmp/ws3/planning"
mkdir -p "$ws3" || exit 1
make_repo direct_demo
clone_repo direct_demo "$ws3"
repo3="$ws3/direct_demo"
remote3="$tmp/direct_demo.git"

remote_main_before="$(git --git-dir="$remote3" rev-parse main)" || exit 1

output3="$(HOME="$tmp/home-3" \
  PJ_WORKSPACE="$ws3" \
  GH_TEST_PR_STATE="$tmp/prs-3.txt" \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 3: updater failed unexpectedly:\n%s\n' "$output3" >&2
  exit 1
}

case "$output3" in
  *'Pushed Update github-projects skill to origin/main'*) ;;
  *) fail "Scenario 3: direct push was not reported. Output:\n$output3" ;;
esac
[ "$(git --git-dir="$remote3" rev-parse main)" != "$remote_main_before" ] || \
  fail 'Scenario 3: default branch was not updated'
[ "$(git -C "$repo3" rev-parse HEAD)" = "$(git --git-dir="$remote3" rev-parse main)" ] || \
  fail 'Scenario 3: local default branch was not fast-forwarded to the pushed commit'
[ "$(git -C "$repo3" log -1 --pretty=%s)" = 'Update github-projects skill' ] || \
  fail 'Scenario 3: local default branch tip is not the skill commit'
grep -Fq 'canonical main queue semantics' "$repo3/.agents/skills/github-projects/SKILL.md" || \
  fail 'Scenario 3: checked-out skill was not refreshed'
[ -z "$(git -C "$repo3" status --porcelain)" ] || \
  fail 'Scenario 3: clean checkout became dirty'
! git --git-dir="$remote3" rev-parse --verify --quiet refs/heads/pj/update-github-projects-skill || \
  fail 'Scenario 3: unexpected skill-update branch was pushed'
[ ! -e "$tmp/prs-3.txt" ] || fail 'Scenario 3: unexpected pull request was opened'

# ---------------------------------------------------------------------------
# Scenario 4: the reported real-world shape for the `actions` repository - a
# feature branch is checked out while the default branch requires a pull
# request. The feature branch must keep its work and the default branch must not
# be left ahead.
# ---------------------------------------------------------------------------
ws4="$tmp/ws4/planning"
mkdir -p "$ws4" || exit 1
make_repo feature_protected protect-main
clone_repo feature_protected "$ws4"
repo4="$ws4/feature_protected"
remote4="$tmp/feature_protected.git"

git -C "$repo4" switch -c feature/github-projects-adoption >/dev/null 2>&1 || exit 1
printf 'adoption work in progress\n' > "$repo4/feature.txt"
git -C "$repo4" add feature.txt || exit 1
git -C "$repo4" commit -m 'Adoption work in progress' >/dev/null || exit 1
feature_sha="$(git -C "$repo4" rev-parse HEAD)" || exit 1
local_main_before="$(git -C "$repo4" rev-parse refs/heads/main)" || exit 1
status_before="$(git -C "$repo4" status --porcelain)" || exit 1

output4="$(HOME="$tmp/home-4" \
  PJ_WORKSPACE="$ws4" \
  GH_TEST_PR_STATE="$tmp/prs-4.txt" \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 4: updater failed unexpectedly:\n%s\n' "$output4" >&2
  exit 1
}

case "$output4" in
  *'Opened skill-update pull request: https://example.invalid/pull/1'*) ;;
  *) fail "Scenario 4: pull request handoff was not reported. Output:\n$output4" ;;
esac
[ "$(git -C "$repo4" branch --show-current)" = 'feature/github-projects-adoption' ] || \
  fail 'Scenario 4: checked-out branch changed'
[ "$(git -C "$repo4" rev-parse HEAD)" = "$feature_sha" ] || \
  fail 'Scenario 4: feature branch moved'
[ "$(git -C "$repo4" rev-parse refs/heads/main)" = "$local_main_before" ] || \
  fail 'Scenario 4: local default branch moved'
[ "$(git --git-dir="$remote4" rev-parse main)" = "$local_main_before" ] || \
  fail 'Scenario 4: protected default branch moved'
[ "$(git -C "$repo4" rev-list --count 'origin/main..refs/heads/main')" = '0' ] || \
  fail 'Scenario 4: local default branch was left ahead of origin/main'
[ "$(git -C "$repo4" status --porcelain)" = "$status_before" ] || \
  fail 'Scenario 4: working state changed'
git --git-dir="$remote4" show refs/heads/pj/update-github-projects-skill:.agents/skills/github-projects/SKILL.md \
  | grep -Fq 'canonical main queue semantics' || \
  fail 'Scenario 4: dedicated branch does not carry canonical main content'

# ---------------------------------------------------------------------------
# Scenario 5: an open skill-update pull request whose .agents/skills tree is
# correct but which gained an unrelated change must not be reused unchanged. The
# updater rewrites the dedicated branch with the freshly generated skill-only
# commit so the PR never stops being a skill-only refresh.
# ---------------------------------------------------------------------------
ws5="$tmp/ws5/planning"
mkdir -p "$ws5" || exit 1
make_repo contaminated_demo protect-main
clone_repo contaminated_demo "$ws5"
repo5="$ws5/contaminated_demo"
remote5="$tmp/contaminated_demo.git"
branch5="refs/heads/pj/update-github-projects-skill"
main_sha5="$(git --git-dir="$remote5" rev-parse main)" || exit 1

HOME="$tmp/home-5" \
  PJ_WORKSPACE="$ws5" \
  GH_TEST_PR_STATE="$tmp/prs-5.txt" \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" >/dev/null 2>&1 || fail 'Scenario 5: initial pull-request handoff failed'

clean_sha="$(git --git-dir="$remote5" rev-parse "$branch5")" || \
  fail 'Scenario 5: initial skill-update branch was not pushed'
clean_skill_tree="$(git --git-dir="$remote5" rev-parse "$clean_sha:.agents/skills")" || \
  fail 'Scenario 5: initial skill-update branch has no skill tree'

# Contaminate the pull request branch with an unrelated change on top of the
# skill commit, exactly as an accidental edit or bad merge would.
contamination="$tmp/contaminated-branch"
git clone --quiet --branch pj/update-github-projects-skill --single-branch \
  "$remote5" "$contamination" >/dev/null 2>&1 || fail 'Scenario 5: could not clone the update branch'
git_identity "$contamination"
printf 'contaminated baseline\n' > "$contamination/local.txt"
printf 'unrelated addition\n' > "$contamination/scratch-notes.txt"
git -C "$contamination" add local.txt scratch-notes.txt || exit 1
git -C "$contamination" commit -m 'Accidental unrelated change' >/dev/null || exit 1
git -C "$contamination" push origin HEAD:refs/heads/pj/update-github-projects-skill >/dev/null 2>&1 || \
  fail 'Scenario 5: could not contaminate the update branch'

# Precondition: only the non-skill diff can stop reuse here.
[ "$(git --git-dir="$remote5" rev-parse "$branch5:.agents/skills")" = "$clean_skill_tree" ] || \
  fail 'Scenario 5: contamination changed the skill tree'
[ "$(git --git-dir="$remote5" rev-parse "$branch5")" != "$clean_sha" ] || \
  fail 'Scenario 5: contamination did not move the update branch'

output5="$(HOME="$tmp/home-5" \
  PJ_WORKSPACE="$ws5" \
  GH_TEST_PR_STATE="$tmp/prs-5.txt" \
  GH_SKILL_TEST_CANONICAL_DIR="$canonical_checkout" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 5: updater failed unexpectedly:\n%s\n' "$output5" >&2
  exit 1
}

case "$output5" in
  *'Reusing existing skill-update pull request'*)
    fail 'Scenario 5: contaminated pull request branch was reused unchanged'
    ;;
esac
case "$output5" in
  *'Updated existing skill-update pull request #1: https://example.invalid/pull/1'*) ;;
  *) fail "Scenario 5: contaminated branch was not rewritten. Output:\n$output5" ;;
esac
[ "$(wc -l < "$tmp/prs-5.txt")" = '1' ] || \
  fail 'Scenario 5: a duplicate pull request was opened'

# The rewritten branch is a clean skill-only commit on the default-branch tip.
assert_skill_only_diff "$remote5" "$main_sha5" "$branch5"
[ "$(git --git-dir="$remote5" rev-parse "$branch5^")" = "$main_sha5" ] || \
  fail 'Scenario 5: rewritten branch is not based on the default branch tip'
[ "$(git --git-dir="$remote5" rev-parse "$branch5:.agents/skills")" = "$clean_skill_tree" ] || \
  fail 'Scenario 5: rewritten branch lost the canonical skill content'
! git --git-dir="$remote5" cat-file -e "$branch5:scratch-notes.txt" 2>/dev/null || \
  fail 'Scenario 5: rewritten branch still carries the unrelated addition'
git --git-dir="$remote5" show "$branch5:local.txt" | grep -Fxq 'contaminated_demo baseline' || \
  fail 'Scenario 5: rewritten branch still carries the unrelated modification'

# The operator checkout and the protected default branch were untouched.
[ "$(git --git-dir="$remote5" rev-parse main)" = "$main_sha5" ] || \
  fail 'Scenario 5: protected default branch moved'
[ "$(git -C "$repo5" rev-parse HEAD)" = "$main_sha5" ] || \
  fail 'Scenario 5: operator checkout moved'
[ -z "$(git -C "$repo5" status --porcelain)" ] || \
  fail 'Scenario 5: operator checkout became dirty'

printf 'default-branch skill updater tests passed\n'
