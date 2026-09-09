#!/usr/bin/env bash

operator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
updater="$operator_dir/update-managed-skills.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
workspace="$home/planning"
remote="$tmp/remote.git"
seed="$tmp/seed"
legacy_remote="$tmp/legacy-remote.git"
legacy_seed="$tmp/legacy-seed"
fake_bin="$tmp/bin"
mkdir -p "$workspace" "$fake_bin" || exit 1

# Setup modern repository with github-projects already installed
git init --bare "$remote" >/dev/null || exit 1
git init -b main "$seed" >/dev/null || exit 1
git -C "$seed" config user.name 'Test User'
git -C "$seed" config user.email 'test@example.invalid'
mkdir -p "$seed/.agents/skills/github-projects" || exit 1
printf 'old skill\n' > "$seed/.agents/skills/github-projects/SKILL.md"
printf 'remote baseline\n' > "$seed/local.txt"
git -C "$seed" add . || exit 1
git -C "$seed" commit -m 'Initial managed repository' >/dev/null || exit 1
git -C "$seed" remote add origin "$remote" || exit 1
git -C "$seed" push -u origin main >/dev/null || exit 1
git --git-dir="$remote" symbolic-ref HEAD refs/heads/main || exit 1

git clone "$remote" "$workspace/demo" >/dev/null || exit 1
git -C "$workspace/demo" config user.name 'Test User'
git -C "$workspace/demo" config user.email 'test@example.invalid'
printf 'local unfinished work\n' > "$workspace/demo/local.txt"

# Setup realistic legacy repository with github-project-admin sourced from old MiguelRodo/projects
git init --bare "$legacy_remote" >/dev/null || exit 1
git init -b main "$legacy_seed" >/dev/null || exit 1
git -C "$legacy_seed" config user.name 'Test User'
git -C "$legacy_seed" config user.email 'test@example.invalid'
mkdir -p "$legacy_seed/.agents/skills/github-project-admin" || exit 1
cat > "$legacy_seed/.agents/skills/github-project-admin/SKILL.md" <<'EOF'
---
description: Administer GitHub issues and Projects from short outcome requests.
metadata:
    github-path: skills/github-project-admin
    github-ref: refs/tags/v0.2.0
    github-repo: https://github.com/MiguelRodo/projects
    github-tree-sha: 2b2a5377c6dae86bf7a04222d3057a6628e2db64
name: github-project-admin
---
# GitHub Project administration
EOF
printf 'legacy remote baseline\n' > "$legacy_seed/local.txt"
git -C "$legacy_seed" add . || exit 1
git -C "$legacy_seed" commit -m 'Initial legacy repository' >/dev/null || exit 1
git -C "$legacy_seed" remote add origin "$legacy_remote" || exit 1
git -C "$legacy_seed" push -u origin main >/dev/null || exit 1
git --git-dir="$legacy_remote" symbolic-ref HEAD refs/heads/main || exit 1

git clone "$legacy_remote" "$workspace/legacy_demo" >/dev/null || exit 1
git -C "$workspace/legacy_demo" config user.name 'Test User'
git -C "$workspace/legacy_demo" config user.email 'test@example.invalid'
printf 'legacy unfinished work\n' > "$workspace/legacy_demo/local.txt"

cat > "$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash

if [ "$1" = 'auth' ] && [ "$2" = 'status' ]; then
  exit 0
fi

if [ "$1" = 'skill' ] && [ "$2" = 'install' ] && \
   [ "$3" = 'MiguelRodo/github-projects-skill' ] && [ "$4" = 'github-projects' ] && \
   [ "$5" = '--agent' ] && [ "$6" = 'universal' ] && \
   [ "$7" = '--scope' ] && [ "$8" = 'project' ] && [ "$9" = '--force' ]; then
  if [ -n "$FAIL_SKILL_INSTALL" ]; then
    mkdir -p .agents/skills/github-projects
    printf 'corrupted partial state\n' > .agents/skills/github-projects/PARTIAL.tmp
    printf 'ERROR: simulated gh skill install failure\n' >&2
    exit 1
  fi
  mkdir -p .agents/skills/github-projects
  cat > .agents/skills/github-projects/SKILL.md <<'SKILL_EOF'
---
description: Administer GitHub issues and Projects from short outcome requests.
metadata:
    github-path: skills/github-projects
    github-ref: refs/heads/main
    github-repo: https://github.com/MiguelRodo/github-projects-skill
    github-tree-sha: 4a0ba7bbb344ceca8ac5ef7336ccae5fb5a82242
name: github-projects
---
# GitHub Project administration
SKILL_EOF
  exit 0
fi

if [ "$1" = 'skill' ] && [ "$2" = 'update' ] && \
   [ "$3" = 'github-projects' ] && [ "$4" = '--all' ]; then
  mkdir -p .agents/skills/github-projects
  cat > .agents/skills/github-projects/SKILL.md <<'SKILL_EOF'
---
description: Administer GitHub issues and Projects from short outcome requests.
metadata:
    github-path: skills/github-projects
    github-ref: refs/heads/main
    github-repo: https://github.com/MiguelRodo/github-projects-skill
    github-tree-sha: 4a0ba7bbb344ceca8ac5ef7336ccae5fb5a82242
name: github-projects
---
# GitHub Project administration
SKILL_EOF
  exit 0
fi

if [ "$1" = 'skill' ] && [ "$2" = 'update' ] && [ "$3" = 'github-project-admin' ]; then
  printf 'ERROR: attempted to update legacy skill from wrong repo\n' >&2
  exit 2
fi

printf 'unexpected gh invocation:' >&2
printf ' <%s>' "$@" >&2
printf '\n' >&2
exit 2
EOF
chmod +x "$fake_bin/gh" || exit 1

# Regression test: simulated failed gh skill install during migration must be transactional
if HOME="$home" \
   PJ_WORKSPACE="$workspace" \
   FAIL_SKILL_INSTALL=1 \
   PATH="$fake_bin:/usr/bin:/bin" \
   bash "$updater" >/dev/null 2>&1; then
  echo "ERROR: updater unexpectedly succeeded when gh skill install failed" >&2
  exit 1
fi

# Assertions after failed migration on legacy_demo:
# 1. Non-zero exit (verified above)
# 2. Legacy skill preserved
[ -f "$workspace/legacy_demo/.agents/skills/github-project-admin/SKILL.md" ] || exit 1
grep -Fq 'name: github-project-admin' "$workspace/legacy_demo/.agents/skills/github-project-admin/SKILL.md" || exit 1
grep -Fq 'github-repo: https://github.com/MiguelRodo/projects' "$workspace/legacy_demo/.agents/skills/github-project-admin/SKILL.md" || exit 1

# 3. No half-installed replacement state committed or pushed or left on disk
[ ! -e "$workspace/legacy_demo/.agents/skills/github-projects" ] || exit 1
[ "$(git -C "$workspace/legacy_demo" log -1 --pretty=%s)" = 'Initial legacy repository' ] || exit 1
! git --git-dir="$legacy_remote" rev-parse --verify main:.agents/skills/github-projects/SKILL.md >/dev/null 2>&1 || exit 1

# 4. Pre-existing uncommitted work restored
[ "$(cat "$workspace/legacy_demo/local.txt")" = 'legacy unfinished work' ] || exit 1
[ -n "$(git -C "$workspace/legacy_demo" status --porcelain -- local.txt)" ] || exit 1
git --git-dir="$legacy_remote" show main:local.txt | grep -Fxq 'legacy remote baseline' || exit 1

# Subsequent retry / successful run succeeds
HOME="$home" \
  PJ_WORKSPACE="$workspace" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" >/dev/null || exit 1

# Modern repo: skill refresh was committed and pushed.
[ "$(cat "$workspace/demo/.agents/skills/github-projects/SKILL.md")" = "$(cat <<'SKILL_EOF'
---
description: Administer GitHub issues and Projects from short outcome requests.
metadata:
    github-path: skills/github-projects
    github-ref: refs/heads/main
    github-repo: https://github.com/MiguelRodo/github-projects-skill
    github-tree-sha: 4a0ba7bbb344ceca8ac5ef7336ccae5fb5a82242
name: github-projects
---
# GitHub Project administration
SKILL_EOF
)" ] || exit 1
[ "$(git -C "$workspace/demo" log -1 --pretty=%s)" = 'Update github-projects skill' ] || exit 1
git --git-dir="$remote" show main:.agents/skills/github-projects/SKILL.md | grep -Fq 'github-repo: https://github.com/MiguelRodo/github-projects-skill' || exit 1

# Pre-existing local work was restored and was not included in the pushed commit.
[ "$(cat "$workspace/demo/local.txt")" = 'local unfinished work' ] || exit 1
[ -n "$(git -C "$workspace/demo" status --porcelain -- local.txt)" ] || exit 1
git --git-dir="$remote" show main:local.txt | grep -Fxq 'remote baseline' || exit 1

# Legacy repo regression test:
# 1. Legacy github-project-admin directory is removed
[ ! -e "$workspace/legacy_demo/.agents/skills/github-project-admin" ] || exit 1
# 2. Resulting installed skill is github-projects sourced from MiguelRodo/github-projects-skill
[ -f "$workspace/legacy_demo/.agents/skills/github-projects/SKILL.md" ] || exit 1
grep -Fq 'name: github-projects' "$workspace/legacy_demo/.agents/skills/github-projects/SKILL.md" || exit 1
grep -Fq 'github-repo: https://github.com/MiguelRodo/github-projects-skill' "$workspace/legacy_demo/.agents/skills/github-projects/SKILL.md" || exit 1
[ "$(git -C "$workspace/legacy_demo" log -1 --pretty=%s)" = 'Update github-projects skill' ] || exit 1

# 3. Pushed to remote and legacy skill removed from remote
git --git-dir="$legacy_remote" show main:.agents/skills/github-projects/SKILL.md | grep -Fq 'github-repo: https://github.com/MiguelRodo/github-projects-skill' || exit 1
! git --git-dir="$legacy_remote" rev-parse --verify main:.agents/skills/github-project-admin/SKILL.md >/dev/null 2>&1 || exit 1

# 4. Pre-existing uncommitted work was restored
[ "$(cat "$workspace/legacy_demo/local.txt")" = 'legacy unfinished work' ] || exit 1
[ -n "$(git -C "$workspace/legacy_demo" status --porcelain -- local.txt)" ] || exit 1
git --git-dir="$legacy_remote" show main:local.txt | grep -Fxq 'legacy remote baseline' || exit 1

# Running again is idempotent across both repositories
HOME="$home" \
  PJ_WORKSPACE="$workspace" \
  PATH="$fake_bin:/usr/bin:/bin" \
  bash "$updater" >/dev/null || exit 1
[ "$(git -C "$workspace/demo" log -1 --pretty=%s)" = 'Update github-projects skill' ] || exit 1
[ "$(git -C "$workspace/legacy_demo" log -1 --pretty=%s)" = 'Update github-projects skill' ] || exit 1
[ "$(cat "$workspace/demo/local.txt")" = 'local unfinished work' ] || exit 1
[ "$(cat "$workspace/legacy_demo/local.txt")" = 'legacy unfinished work' ] || exit 1

printf 'managed skill updater tests passed\n'
