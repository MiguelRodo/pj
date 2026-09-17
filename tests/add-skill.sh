#!/usr/bin/env bash

operator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
pj="$operator_dir/pj"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

workspace="$tmp/home/planning"
target="$tmp/target"
mkdir -p "$workspace" "$target/subdir" "$tmp/bin" || exit 1

git init -b main "$target" >/dev/null 2>&1 || exit 1

cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" > "$PJ_TEST_GH_PWD"
printf '<%s>' "$@" > "$PJ_TEST_GH_ARGS"
if [ "$1" = skill ] && [ "$2" = install ]; then
  mkdir -p .agents/skills/github-projects/scripts
  printf '%s\n' '# github-projects test skill' > .agents/skills/github-projects/SKILL.md
  cat > .agents/skills/github-projects/scripts/init-project.sh <<'INIT_EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" > "$PJ_TEST_INIT_PWD"
INIT_EOF
  chmod +x .agents/skills/github-projects/scripts/init-project.sh
  exit 0
fi
exit 2
EOF
chmod +x "$tmp/bin/gh" || exit 1

args_log="$tmp/gh.args"
pwd_log="$tmp/gh.pwd"

output="$(
  cd "$target/subdir" &&
  HOME="$tmp/home" \
    PJ_WORKSPACE="$workspace" \
    PJ_TEST_GH_ARGS="$args_log" \
    PJ_TEST_GH_PWD="$pwd_log" \
    PATH="$tmp/bin:$PATH" \
    bash "$pj" --add-skill
)" || exit 1

[ "$(cat "$pwd_log")" = "$target" ] || exit 1
[ "$(cat "$args_log")" = '<skill><install><MiguelRodo/github-projects-skill><github-projects><--agent><universal><--scope><project><--pin><main>' ] || exit 1
[ -f "$target/.agents/skills/github-projects/SKILL.md" ] || exit 1
case "$output" in
  *"pj: added github-projects to $target"*) ;;
  *) exit 1 ;;
esac
case "$output" in
  *"bash .agents/skills/github-projects/scripts/init-project.sh"*) ;;
  *) exit 1 ;;
esac

: > "$args_log"
second="$(
  cd "$target" &&
  HOME="$tmp/home" \
    PJ_WORKSPACE="$workspace" \
    PJ_TEST_GH_ARGS="$args_log" \
    PJ_TEST_GH_PWD="$pwd_log" \
    PATH="$tmp/bin:$PATH" \
    bash "$pj" --add-skill
)" || exit 1
[ ! -s "$args_log" ] || exit 1
case "$second" in
  *"already has github-projects; use 'pj --update-skill' to refresh it"*) ;;
  *) exit 1 ;;
esac

if (
  cd "$target" &&
  HOME="$tmp/home" PJ_WORKSPACE="$workspace" PATH="$tmp/bin:$PATH" bash "$pj" --add-skill unexpected
) >/dev/null 2>&1; then
  echo 'pj --add-skill unexpectedly accepted an argument' >&2
  exit 1
fi

outside="$tmp/outside"
mkdir -p "$outside"
if (
  cd "$outside" &&
  HOME="$tmp/home" PJ_WORKSPACE="$workspace" PATH="$tmp/bin:$PATH" bash "$pj" --add-skill
) >/dev/null 2>&1; then
  echo 'pj --add-skill unexpectedly accepted a non-repository directory' >&2
  exit 1
fi

init_target="$tmp/init-target"
mkdir -p "$init_target/subdir"
git init -b main "$init_target" >/dev/null 2>&1 || exit 1
init_args_log="$tmp/init-gh.args"
init_pwd_log="$tmp/init-gh.pwd"
init_script_pwd_log="$tmp/init-script.pwd"

init_output="$(
  cd "$init_target/subdir" &&
  HOME="$tmp/home" \
    PJ_WORKSPACE="$workspace" \
    PJ_TEST_GH_ARGS="$init_args_log" \
    PJ_TEST_GH_PWD="$init_pwd_log" \
    PJ_TEST_INIT_PWD="$init_script_pwd_log" \
    PATH="$tmp/bin:$PATH" \
    bash "$pj" --init
)" || exit 1

[ "$(cat "$init_pwd_log")" = "$init_target" ] || exit 1
[ "$(cat "$init_script_pwd_log")" = "$init_target" ] || exit 1
[ "$(cat "$init_args_log")" = '<skill><install><MiguelRodo/github-projects-skill><github-projects><--agent><universal><--scope><project><--pin><main>' ] || exit 1
case "$init_output" in
  *"pj: added github-projects to $init_target"*) ;;
  *) exit 1 ;;
esac

if (
  cd "$init_target" &&
  HOME="$tmp/home" PJ_WORKSPACE="$workspace" PATH="$tmp/bin:$PATH" bash "$pj" --init unexpected
) >/dev/null 2>&1; then
  echo 'pj --init unexpectedly accepted an argument' >&2
  exit 1
fi

printf 'add-skill and init tests passed\n'
