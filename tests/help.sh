#!/usr/bin/env bash

operator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
. "$operator_dir/tests/helpers.sh"

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/workspace" || exit 1
cp "$operator_dir/pj" "$tmp/bin/pj" || exit 1
chmod +x "$tmp/bin/pj" || exit 1
ln -s pj "$tmp/bin/pja" || exit 1

for tool in codex agy copilot; do
  cat > "$tmp/bin/$tool" <<EOF
#!/usr/bin/env bash
touch "$tmp/backend-called"
printf '%s backend should not have been invoked\n' '$tool' >&2
exit 99
EOF
  chmod +x "$tmp/bin/$tool" || exit 1
done

run_help() {
  HOME="$tmp/home" \
    PJ_WORKSPACE="$1" \
    PATH="$tmp/bin:$PATH" \
    "$2" "${@:3}"
}

# Top-level help must be owned by pj and work without a valid workspace.
help_long="$(run_help "$tmp/missing-workspace" "$tmp/bin/pj" --help)" || exit 1
assert_contains "$help_long" 'Usage:'
assert_contains "$help_long" 'pj [pj options] [agent options] [--] [prompt]'
assert_contains "$help_long" '--backend BACKEND'
assert_contains "$help_long" '--set-default BACKEND'
assert_contains "$help_long" '--show-models'
assert_contains "$help_long" '--implement-issues'
assert_contains "$help_long" '--update-skill'
assert_not_contains "$help_long" 'Usage of agy:'
[ ! -e "$tmp/backend-called" ] || exit 1

help_short="$(run_help "$tmp/missing-workspace" "$tmp/bin/pj" -h)" || exit 1
[ "$help_short" = "$help_long" ] || {
  echo 'pj -h and pj --help returned different help text' >&2
  exit 1
}
[ ! -e "$tmp/backend-called" ] || exit 1

# Backend shorthand launchers are still pj entry points, so their help is pj help.
help_alias="$(run_help "$tmp/missing-workspace" "$tmp/bin/pja" --help)" || exit 1
[ "$help_alias" = "$help_long" ] || {
  echo 'pja --help did not return pj help' >&2
  exit 1
}
[ ! -e "$tmp/backend-called" ] || exit 1

# Help remains launcher-owned when it follows other recognised pj options.
help_after_backend="$(run_help "$tmp/workspace" "$tmp/bin/pj" --backend copilot --help)" || exit 1
[ "$help_after_backend" = "$help_long" ] || {
  echo 'pj --backend copilot --help did not return pj help' >&2
  exit 1
}
[ ! -e "$tmp/backend-called" ] || exit 1

bash -n "$operator_dir/pj" || exit 1

printf 'pj help tests passed\n'
