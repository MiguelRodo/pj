#!/usr/bin/env bash

# Regression tests for `pj --update-skill` failures seen in a real run:
#  1. the canonical ~/planning/github-projects-skill checkout must never have a
#     merge commit manufactured on its protected main and pushed;
#  2. an installed github-projects copy pinned to an old tag must not be treated
#     as current just because `gh skill update` reported "All skills are up to
#     date", and neither must a copy whose canonical main content has moved on.

operator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
updater="$operator_dir/update-managed-skills.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

fake_bin="$tmp/bin"
mkdir -p "$fake_bin" || exit 1

# A gh stand-in that mirrors the real CLI: an unpinned install resolves the
# latest tagged release, `skill update` claims everything is up to date without
# touching a tagged copy, and only an explicit `--pin main` installs canonical
# main.
cat > "$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash

if [ "$1" = 'auth' ] && [ "$2" = 'status' ]; then
  exit 0
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
    printf '%s\n' 'description: canonical skill'
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
    printf '%s\n' 'canonical main queue semantics'
  } > .agents/skills/github-projects/SKILL.md
  exit 0
fi

if [ "$1" = 'skill' ] && [ "$2" = 'update' ] && \
   [ "$3" = 'github-projects' ] && [ "$4" = '--all' ]; then
  printf 'All skills are up to date\n'
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

protect_remote() {
  local bare="$1"
  local log="$2"
  cat > "$bare/hooks/pre-receive" <<EOF
#!/usr/bin/env bash
printf 'push attempted\n' >> "$log"
printf 'protected main rejects direct pushes\n' >&2
exit 1
EOF
  chmod +x "$bare/hooks/pre-receive" || exit 1
}

# ---------------------------------------------------------------------------
# Scenario 1: the canonical checkout is simply behind the remote. It must be
# fast-forwarded, must not gain a merge commit, and must never be pushed to.
# ---------------------------------------------------------------------------
ws_a="$tmp/ws-a/planning"
mkdir -p "$ws_a" || exit 1
remote_a="$tmp/canonical-a.git"
seed_a="$tmp/canonical-a-seed"
push_log_a="$tmp/canonical-a-pushes.log"

git init --bare "$remote_a" >/dev/null 2>&1 || exit 1
git init -b main "$seed_a" >/dev/null || exit 1
git_identity "$seed_a"
mkdir -p "$seed_a/skills/github-projects" || exit 1
cat > "$seed_a/skills/github-projects/SKILL.md" <<'EOF'
---
description: canonical skill
metadata:
    github-path: skills/github-projects
    github-ref: refs/heads/main
    github-repo: https://github.com/MiguelRodo/github-projects-skill
name: github-projects
---
# GitHub Project administration

canonical revision one
EOF
git -C "$seed_a" add . || exit 1
git -C "$seed_a" commit -m 'canonical revision one' >/dev/null || exit 1
git -C "$seed_a" remote add origin "$remote_a" || exit 1
git -C "$seed_a" push -u origin main >/dev/null 2>&1 || exit 1
git --git-dir="$remote_a" symbolic-ref HEAD refs/heads/main || exit 1

git clone "$remote_a" "$ws_a/github-projects-skill" >/dev/null 2>&1 || exit 1
git_identity "$ws_a/github-projects-skill"

# The remote moves ahead while the canonical checkout stays behind.
cat > "$seed_a/skills/github-projects/SKILL.md" <<'EOF'
---
description: canonical skill
metadata:
    github-path: skills/github-projects
    github-ref: refs/heads/main
    github-repo: https://github.com/MiguelRodo/github-projects-skill
name: github-projects
---
# GitHub Project administration

canonical revision two
EOF
git -C "$seed_a" commit -am 'canonical revision two' >/dev/null || exit 1
git -C "$seed_a" push origin main >/dev/null 2>&1 || exit 1

# Protected main now rejects any direct push, recording each attempt.
protect_remote "$remote_a" "$push_log_a"

output_a="$(HOME="$tmp/home-a" \
  PJ_WORKSPACE="$ws_a" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" 2>&1)" || {
  printf 'Scenario 1: updater failed unexpectedly:\n%s\n' "$output_a" >&2
  exit 1
}

case "$output_a" in
  *'Fast-forwarding github-projects-skill'*) ;;
  *)
    printf 'Scenario 1: expected a fast-forward sync.\nActual output:\n%s\n' "$output_a" >&2
    exit 1
    ;;
esac

[ ! -e "$push_log_a" ] || {
  printf 'Scenario 1: a push was attempted against protected canonical main.\n' >&2
  exit 1
}
grep -Fq 'canonical revision two' "$ws_a/github-projects-skill/skills/github-projects/SKILL.md" || exit 1
[ "$(git -C "$ws_a/github-projects-skill" rev-parse HEAD)" = \
  "$(git --git-dir="$remote_a" rev-parse main)" ] || exit 1
[ "$(git -C "$ws_a/github-projects-skill" rev-list --count --merges HEAD)" = '0' ] || exit 1

# ---------------------------------------------------------------------------
# Scenario 2: the canonical checkout has diverged from protected main. The
# updater must stop and report instead of merging locally and pushing.
# ---------------------------------------------------------------------------
ws_b="$tmp/ws-b/planning"
mkdir -p "$ws_b" || exit 1
remote_b="$tmp/canonical-b.git"
seed_b="$tmp/canonical-b-seed"
push_log_b="$tmp/canonical-b-pushes.log"

git init --bare "$remote_b" >/dev/null 2>&1 || exit 1
git init -b main "$seed_b" >/dev/null || exit 1
git_identity "$seed_b"
mkdir -p "$seed_b/skills/github-projects" || exit 1
printf 'canonical revision one\n' > "$seed_b/skills/github-projects/SKILL.md"
git -C "$seed_b" add . || exit 1
git -C "$seed_b" commit -m 'canonical revision one' >/dev/null || exit 1
git -C "$seed_b" remote add origin "$remote_b" || exit 1
git -C "$seed_b" push -u origin main >/dev/null 2>&1 || exit 1
git --git-dir="$remote_b" symbolic-ref HEAD refs/heads/main || exit 1

git clone "$remote_b" "$ws_b/github-projects-skill" >/dev/null 2>&1 || exit 1
git_identity "$ws_b/github-projects-skill"

# Local commit not on the remote: the histories now diverge.
printf 'local work\n' > "$ws_b/github-projects-skill/local-only.txt"
git -C "$ws_b/github-projects-skill" add local-only.txt || exit 1
git -C "$ws_b/github-projects-skill" commit -m 'local divergence' >/dev/null || exit 1
local_head_b="$(git -C "$ws_b/github-projects-skill" rev-parse HEAD)"

printf 'canonical revision two\n' > "$seed_b/skills/github-projects/SKILL.md"
git -C "$seed_b" commit -am 'canonical revision two' >/dev/null || exit 1
git -C "$seed_b" push origin main >/dev/null 2>&1 || exit 1
remote_head_b="$(git --git-dir="$remote_b" rev-parse main)"

protect_remote "$remote_b" "$push_log_b"

# Pre-existing uncommitted work must survive the failed run.
printf 'uncommitted local work\n' > "$ws_b/github-projects-skill/scratch.txt"

if HOME="$tmp/home-b" \
   PJ_WORKSPACE="$ws_b" \
   PATH="$fake_bin:/usr/bin:/bin" \
   bash "$updater" >"$tmp/scenario-b.out" 2>&1; then
  printf 'Scenario 2: updater unexpectedly succeeded on a diverged canonical checkout.\n' >&2
  cat "$tmp/scenario-b.out" >&2
  exit 1
fi

grep -Fq 'diverged' "$tmp/scenario-b.out" || {
  printf 'Scenario 2: expected a divergence report.\nActual output:\n%s\n' "$(cat "$tmp/scenario-b.out")" >&2
  exit 1
}
[ ! -e "$push_log_b" ] || {
  printf 'Scenario 2: a push was attempted against protected canonical main.\n' >&2
  exit 1
}
[ "$(git -C "$ws_b/github-projects-skill" rev-parse HEAD)" = "$local_head_b" ] || {
  printf 'Scenario 2: the canonical checkout moved despite divergence.\n' >&2
  exit 1
}
[ "$(git -C "$ws_b/github-projects-skill" rev-list --count --merges HEAD)" = '0' ] || exit 1
[ "$(git --git-dir="$remote_b" rev-parse main)" = "$remote_head_b" ] || exit 1
[ "$(cat "$ws_b/github-projects-skill/scratch.txt")" = 'uncommitted local work' ] || exit 1
[ -z "$(git -C "$ws_b/github-projects-skill" stash list)" ] || exit 1

# ---------------------------------------------------------------------------
# Scenario 3: managed repositories with stale installs. `gh skill update`
# claims everything is up to date, so the updater must detect the stale
# metadata itself and reconcile each copy with canonical main.
# ---------------------------------------------------------------------------
ws_c="$tmp/ws-c/planning"
mkdir -p "$ws_c" || exit 1
canonical_remote="$tmp/skill-canonical.git"
canonical_seed="$tmp/skill-canonical-seed"

git init --bare "$canonical_remote" >/dev/null 2>&1 || exit 1
git init -b main "$canonical_seed" >/dev/null || exit 1
git_identity "$canonical_seed"
mkdir -p "$canonical_seed/skills/github-projects" || exit 1
cat > "$canonical_seed/skills/github-projects/SKILL.md" <<'EOF'
---
description: canonical skill
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

git clone "$canonical_remote" "$ws_c/github-projects-skill" >/dev/null 2>&1 || exit 1
git_identity "$ws_c/github-projects-skill"
canonical_tree_sha="$(git -C "$ws_c/github-projects-skill" rev-parse refs/remotes/origin/main:skills/github-projects)" || exit 1

make_managed_repo() {
  local name="$1"
  local ref="$2"
  local tree_sha="$3"
  local body="$4"
  local bare="$tmp/$name.git"
  local seed="$tmp/$name-seed"

  git init --bare "$bare" >/dev/null 2>&1 || exit 1
  git init -b main "$seed" >/dev/null || exit 1
  git_identity "$seed"
  mkdir -p "$seed/.agents/skills/github-projects" || exit 1
  {
    printf '%s\n' '---'
    printf '%s\n' 'description: Administer GitHub issues and Projects from short outcome requests.'
    printf '%s\n' 'metadata:'
    printf '%s\n' '    github-path: skills/github-projects'
    printf '    github-ref: %s\n' "$ref"
    printf '%s\n' '    github-repo: https://github.com/MiguelRodo/github-projects-skill'
    printf '    github-tree-sha: %s\n' "$tree_sha"
    printf '%s\n' 'name: github-projects'
    printf '%s\n' '---'
    printf '%s\n' '# GitHub Project administration'
    printf '\n'
    printf '%s\n' "$body"
  } > "$seed/.agents/skills/github-projects/SKILL.md"
  printf '%s baseline\n' "$name" > "$seed/local.txt"
  git -C "$seed" add . || exit 1
  git -C "$seed" commit -m "Initial $name repository" >/dev/null || exit 1
  git -C "$seed" remote add origin "$bare" || exit 1
  git -C "$seed" push -u origin main >/dev/null 2>&1 || exit 1
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/main || exit 1

  git clone "$bare" "$ws_c/$name" >/dev/null 2>&1 || exit 1
  git_identity "$ws_c/$name"
}

# Pinned to an old tag, exactly like the copies reported as "up to date".
make_managed_repo stale_demo refs/tags/v0.3.0 b2825c98f6d903c7d3fa4bf78540ce1fae3da17f \
  'old tagged queue semantics'
# Tracks main but still carries the content of an older canonical main.
make_managed_repo stale_main_demo refs/heads/main 0000000000000000000000000000000000000000 \
  'older canonical main queue semantics'
# Already matches canonical main and must be left alone.
make_managed_repo current_demo refs/heads/main "$canonical_tree_sha" \
  'canonical main queue semantics'

HOME="$tmp/home-c" \
  PJ_WORKSPACE="$ws_c" \
  GH_SKILL_TEST_CANONICAL_DIR="$ws_c/github-projects-skill" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" >/dev/null || exit 1

# The tag-pinned install was migrated to canonical main and pushed.
grep -Fq 'github-ref: refs/heads/main' "$ws_c/stale_demo/.agents/skills/github-projects/SKILL.md" || exit 1
grep -Fq "github-tree-sha: $canonical_tree_sha" "$ws_c/stale_demo/.agents/skills/github-projects/SKILL.md" || exit 1
grep -Fq 'canonical main queue semantics' "$ws_c/stale_demo/.agents/skills/github-projects/SKILL.md" || exit 1
! grep -Fq 'refs/tags/v0.3.0' "$ws_c/stale_demo/.agents/skills/github-projects/SKILL.md" || exit 1
[ "$(git -C "$ws_c/stale_demo" log -1 --pretty=%s)" = 'Update github-projects skill' ] || exit 1
git --git-dir="$tmp/stale_demo.git" show main:.agents/skills/github-projects/SKILL.md \
  | grep -Fq 'canonical main queue semantics' || exit 1

# A main-tracking copy behind canonical main content is refreshed too.
grep -Fq "github-tree-sha: $canonical_tree_sha" "$ws_c/stale_main_demo/.agents/skills/github-projects/SKILL.md" || exit 1
grep -Fq 'canonical main queue semantics' "$ws_c/stale_main_demo/.agents/skills/github-projects/SKILL.md" || exit 1
[ "$(git -C "$ws_c/stale_main_demo" log -1 --pretty=%s)" = 'Update github-projects skill' ] || exit 1

# A copy already matching canonical main is not churned.
[ "$(git -C "$ws_c/current_demo" log -1 --pretty=%s)" = 'Initial current_demo repository' ] || exit 1
grep -Fq 'canonical main queue semantics' "$ws_c/current_demo/.agents/skills/github-projects/SKILL.md" || exit 1

stale_commits="$(git -C "$ws_c/stale_demo" rev-list --count HEAD)"
stale_main_commits="$(git -C "$ws_c/stale_main_demo" rev-list --count HEAD)"

# Running again is idempotent: nothing is refreshed forever.
HOME="$tmp/home-c" \
  PJ_WORKSPACE="$ws_c" \
  GH_SKILL_TEST_CANONICAL_DIR="$ws_c/github-projects-skill" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" >/dev/null || exit 1
[ "$(git -C "$ws_c/stale_demo" rev-list --count HEAD)" = "$stale_commits" ] || exit 1
[ "$(git -C "$ws_c/stale_main_demo" rev-list --count HEAD)" = "$stale_main_commits" ] || exit 1
[ "$(git -C "$ws_c/current_demo" log -1 --pretty=%s)" = 'Initial current_demo repository' ] || exit 1

printf 'canonical skill updater tests passed\n'
