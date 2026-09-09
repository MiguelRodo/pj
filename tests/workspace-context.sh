#!/usr/bin/env bash

operator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
installer="$operator_dir/install.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
workspace="$home/planning"
bin_dir="$home/.local/bin"
config_home="$home/.config"
fake_bin="$tmp/bin"
mkdir -p "$workspace" "$bin_dir" "$fake_bin" \
  "$home/.codex/rules" "$home/.copilot" "$home/.gemini" || exit 1

for tool in codex agy copilot; do
  cat > "$fake_bin/$tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/$tool" || exit 1
done

cat > "$home/AGENTS.md" <<'EOF'
# My own home guidance

<!-- managed-projects:start -->
Old home-level managed guidance.
<!-- managed-projects:end -->

Keep this home-authored line intact.
EOF
chmod 0640 "$home/AGENTS.md" || exit 1

cat > "$workspace/AGENTS.md" <<'EOF'
# My own planning notes

Keep this user-authored line intact.
EOF
chmod 0600 "$workspace/AGENTS.md" || exit 1

# Simulate the known older/current backend files that the installer owns and
# should migrate to one canonical home instruction file.
cat > "$home/.codex/AGENTS.md" <<'EOF'
<!-- managed-projects:start -->
## Miguel's managed projects

Old Codex-managed project guidance.
<!-- managed-projects:end -->
EOF

cat > "$home/.copilot/copilot-instructions.md" <<'EOF'
<!-- pj-managed-projects:start -->
Old Copilot pj guidance.
<!-- pj-managed-projects:end -->
EOF

cat > "$home/.gemini/GEMINI.md" <<'EOF'
<!-- pj-managed-projects:start -->
Old Antigravity pj guidance.
<!-- pj-managed-projects:end -->
EOF

cat > "$home/.codex/rules/default.rules" <<'EOF'
# Keep this user-authored Codex rule intact.
prefix_rule(pattern = ["git", "status"], decision = "allow")
EOF
chmod 0644 "$home/.codex/rules/default.rules" || exit 1

run_installer() {
  HOME="$home" \
    XDG_CONFIG_HOME="$config_home" \
    PATH="$bin_dir:$fake_bin:/usr/bin:/bin" \
    bash "$installer" >/dev/null
}

run_installer || exit 1

[ -x "$bin_dir/pj-update-skills" ] || exit 1
grep -Fq '# My own home guidance' "$home/AGENTS.md" || exit 1
grep -Fq 'Keep this home-authored line intact.' "$home/AGENTS.md" || exit 1
[ "$(grep -Fc '<!-- managed-projects:start -->' "$home/AGENTS.md")" -eq 0 ] || exit 1
[ "$(stat -c '%a' "$home/AGENTS.md")" = 640 ] || exit 1
grep -Fq '<!-- pj-managed-projects:start -->' "$home/AGENTS.md" || exit 1
grep -Fq 'pj-update-skills' "$home/AGENTS.md" || exit 1
grep -Fq 'Optional `agy` subagent delegation' "$home/AGENTS.md" || exit 1
grep -Fq 'Only Codex and GitHub Copilot CLI may use `agy`' "$home/AGENTS.md" || exit 1
grep -Fq 'Antigravity itself must not invoke `agy` recursively' "$home/AGENTS.md" || exit 1
grep -Fq 'gemini-3.8-flash-high' "$home/AGENTS.md" || exit 1
grep -Fq 'explicitly authorises' "$home/AGENTS.md" || exit 1
grep -Fq -- '--add-dir "/absolute/repository/root"' "$home/AGENTS.md" || exit 1
grep -Fq 'not ask the operator again merely to approve that narrow rule' "$home/AGENTS.md" || exit 1
grep -Fq 'Never add broad wildcard tool permissions' "$home/AGENTS.md" || exit 1

grep -Fq '# My own planning notes' "$workspace/AGENTS.md" || exit 1
grep -Fq 'Keep this user-authored line intact.' "$workspace/AGENTS.md" || exit 1
grep -Fq '<!-- pj-managed-projects:start -->' "$workspace/AGENTS.md" || exit 1
grep -Fq 'Natural-language' "$workspace/AGENTS.md" || exit 1
grep -Fq 'process the implementation issues for X' "$workspace/AGENTS.md" || exit 1
grep -Fq 'references/local-implementation-queue.md' "$workspace/AGENTS.md" || exit 1
grep -Fq 'pj-update-skills' "$workspace/AGENTS.md" || exit 1
[ "$(stat -c '%a' "$workspace/AGENTS.md")" = 600 ] || exit 1

for context in \
    "$home/.codex/AGENTS.md" \
    "$home/.copilot/copilot-instructions.md" \
    "$home/.gemini/GEMINI.md"; do
  [ -L "$context" ] || exit 1
  [ "$(readlink -f "$context")" = "$(readlink -f "$home/AGENTS.md")" ] || exit 1
done

grep -Fq '# Keep this user-authored Codex rule intact.' "$home/.codex/rules/default.rules" || exit 1
grep -Fq '# pj-agy-subagent:start' "$home/.codex/rules/default.rules" || exit 1
grep -Fq 'pattern = ["agy"]' "$home/.codex/rules/default.rules" || exit 1
grep -Fq 'decision = "allow"' "$home/.codex/rules/default.rules" || exit 1
[ "$(stat -c '%a' "$home/.codex/rules/default.rules")" = 644 ] || exit 1

# Reinstalling replaces only the managed blocks instead of duplicating them or
# overwriting user-authored home/workspace content or Codex rules.
cp "$home/AGENTS.md" "$tmp/home-before-reinstall" || exit 1
cp "$workspace/AGENTS.md" "$tmp/workspace-before-reinstall" || exit 1
cp "$home/.codex/rules/default.rules" "$tmp/rules-before-reinstall" || exit 1
run_installer || exit 1
[ "$(grep -Fc '<!-- pj-managed-projects:start -->' "$home/AGENTS.md")" -eq 1 ] || exit 1
[ "$(grep -Fc '<!-- pj-managed-projects:start -->' "$workspace/AGENTS.md")" -eq 1 ] || exit 1
[ "$(grep -Fc '# pj-agy-subagent:start' "$home/.codex/rules/default.rules")" -eq 1 ] || exit 1
grep -Fq 'Keep this home-authored line intact.' "$home/AGENTS.md" || exit 1
grep -Fq 'Keep this user-authored line intact.' "$workspace/AGENTS.md" || exit 1
grep -Fq '# Keep this user-authored Codex rule intact.' "$home/.codex/rules/default.rules" || exit 1
cmp "$tmp/home-before-reinstall" "$home/AGENTS.md" || exit 1
cmp "$tmp/workspace-before-reinstall" "$workspace/AGENTS.md" || exit 1
cmp "$tmp/rules-before-reinstall" "$home/.codex/rules/default.rules" || exit 1

# Genuine backend-specific content stays in a regular file. The installer
# removes obsolete copies and hard-updates exactly one current managed block.
custom_home="$tmp/custom-home"
mkdir -p "$custom_home/planning" "$custom_home/.local/bin" \
  "$custom_home/.codex" "$custom_home/.copilot" "$custom_home/.gemini" || exit 1
cat > "$custom_home/.codex/AGENTS.md" <<'EOF'
# Bespoke Codex-only instruction

Keep this Codex line.
EOF
cat > "$custom_home/.copilot/copilot-instructions.md" <<'EOF'
# Bespoke Copilot-only instruction

Keep this line before the shared block.

<!-- managed-projects:start -->
Obsolete installer-managed backend copy.
<!-- managed-projects:end -->

Keep this line after the shared block.
EOF
chmod 0640 "$custom_home/.copilot/copilot-instructions.md" || exit 1
cat > "$custom_home/.gemini/GEMINI.md" <<'EOF'
# Bespoke Gemini-only instruction

Keep this Gemini line.
EOF
HOME="$custom_home" \
  XDG_CONFIG_HOME="$custom_home/.config" \
  PATH="$custom_home/.local/bin:$fake_bin:/usr/bin:/bin" \
  bash "$installer" >/dev/null 2>"$tmp/custom-warning" || exit 1
[ ! -L "$custom_home/.copilot/copilot-instructions.md" ] || exit 1
for context in \
    "$custom_home/.codex/AGENTS.md" \
    "$custom_home/.copilot/copilot-instructions.md" \
    "$custom_home/.gemini/GEMINI.md"; do
  [ ! -L "$context" ] || exit 1
  [ "$(grep -Fc '<!-- pj-managed-projects:start -->' "$context")" -eq 1 ] || exit 1
done
grep -Fq 'Keep this Codex line.' "$custom_home/.codex/AGENTS.md" || exit 1
grep -Fq 'Keep this line before the shared block.' "$custom_home/.copilot/copilot-instructions.md" || exit 1
grep -Fq 'Keep this line after the shared block.' "$custom_home/.copilot/copilot-instructions.md" || exit 1
grep -Fq 'Keep this Gemini line.' "$custom_home/.gemini/GEMINI.md" || exit 1
[ "$(stat -c '%a' "$custom_home/.copilot/copilot-instructions.md")" = 640 ] || exit 1
grep -Fq '<!-- pj-managed-projects:start -->' "$custom_home/.copilot/copilot-instructions.md" || exit 1
[ "$(grep -Fc '<!-- pj-managed-projects:start -->' "$custom_home/.copilot/copilot-instructions.md")" -eq 1 ] || exit 1
[ "$(grep -Fc '<!-- managed-projects:start -->' "$custom_home/.copilot/copilot-instructions.md")" -eq 0 ] || exit 1
grep -Fq -- '--add-dir "/absolute/repository/root"' "$custom_home/.copilot/copilot-instructions.md" || exit 1
grep -Fq 'preserved custom backend instructions and refreshed the shared managed block' "$tmp/custom-warning" || exit 1
awk '
  /<!-- pj-managed-projects:end -->/ { managed_end = NR }
  /Keep this line after the shared block\./ { custom_after = NR }
  END { exit !(managed_end > 0 && custom_after > managed_end) }
' "$custom_home/.copilot/copilot-instructions.md" || exit 1

sed -n '/<!-- pj-managed-projects:start -->/,/<!-- pj-managed-projects:end -->/p' \
  "$custom_home/AGENTS.md" > "$tmp/home-managed-block" || exit 1
sed -n '/<!-- pj-managed-projects:start -->/,/<!-- pj-managed-projects:end -->/p' \
  "$custom_home/.copilot/copilot-instructions.md" > "$tmp/copilot-managed-block" || exit 1
cmp "$tmp/home-managed-block" "$tmp/copilot-managed-block" || exit 1

cp "$custom_home/.copilot/copilot-instructions.md" "$tmp/copilot-before-reinstall" || exit 1
HOME="$custom_home" \
  XDG_CONFIG_HOME="$custom_home/.config" \
  PATH="$custom_home/.local/bin:$fake_bin:/usr/bin:/bin" \
  bash "$installer" >/dev/null 2>"$tmp/custom-reinstall-warning" || exit 1
[ ! -L "$custom_home/.copilot/copilot-instructions.md" ] || exit 1
grep -Fq 'Keep this line before the shared block.' "$custom_home/.copilot/copilot-instructions.md" || exit 1
grep -Fq 'Keep this line after the shared block.' "$custom_home/.copilot/copilot-instructions.md" || exit 1
[ "$(grep -Fc '<!-- pj-managed-projects:start -->' "$custom_home/.copilot/copilot-instructions.md")" -eq 1 ] || exit 1
cmp "$tmp/copilot-before-reinstall" "$custom_home/.copilot/copilot-instructions.md" || exit 1

# An unrelated symlink may encode a deliberate backend arrangement. Leave both
# the link and its target untouched rather than rewriting through it.
mkdir -p "$custom_home/custom-agent" || exit 1
cat > "$custom_home/custom-agent/GEMINI.md" <<'EOF'
# Deliberate external Gemini instructions
EOF
rm -f "$custom_home/.gemini/GEMINI.md" || exit 1
ln -s "$custom_home/custom-agent/GEMINI.md" "$custom_home/.gemini/GEMINI.md" || exit 1
HOME="$custom_home" \
  XDG_CONFIG_HOME="$custom_home/.config" \
  PATH="$custom_home/.local/bin:$fake_bin:/usr/bin:/bin" \
  bash "$installer" >/dev/null 2>"$tmp/unrelated-link-warning" || exit 1
[ -L "$custom_home/.gemini/GEMINI.md" ] || exit 1
[ "$(readlink "$custom_home/.gemini/GEMINI.md")" = "$custom_home/custom-agent/GEMINI.md" ] || exit 1
[ "$(grep -Fc '<!-- pj-managed-projects:start -->' "$custom_home/custom-agent/GEMINI.md")" -eq 0 ] || exit 1
grep -Fq 'preserving unrelated instruction symlink' "$tmp/unrelated-link-warning" || exit 1

# Canonical home/workspace files and Codex rules may themselves be maintained
# through a dotfiles symlink. Update the targets without replacing those links
# or changing their modes.
linked_home="$tmp/linked-home"
linked_files="$tmp/linked-dotfiles"
mkdir -p "$linked_home/planning" "$linked_home/.local/bin" \
  "$linked_home/.codex/rules" "$linked_files" || exit 1
printf '# Linked home guidance\n' > "$linked_files/AGENTS.md" || exit 1
printf '# Linked workspace guidance\n' > "$linked_files/planning-AGENTS.md" || exit 1
printf '# Linked Codex rules\n' > "$linked_files/default.rules" || exit 1
chmod 0640 "$linked_files/AGENTS.md" || exit 1
chmod 0600 "$linked_files/planning-AGENTS.md" || exit 1
chmod 0644 "$linked_files/default.rules" || exit 1
ln -s "$linked_files/AGENTS.md" "$linked_home/AGENTS.md" || exit 1
ln -s "$linked_files/planning-AGENTS.md" "$linked_home/planning/AGENTS.md" || exit 1
ln -s "$linked_files/default.rules" "$linked_home/.codex/rules/default.rules" || exit 1
HOME="$linked_home" \
  XDG_CONFIG_HOME="$linked_home/.config" \
  PATH="$linked_home/.local/bin:$fake_bin:/usr/bin:/bin" \
  bash "$installer" >/dev/null || exit 1
[ -L "$linked_home/AGENTS.md" ] || exit 1
[ -L "$linked_home/planning/AGENTS.md" ] || exit 1
[ -L "$linked_home/.codex/rules/default.rules" ] || exit 1
grep -Fq '<!-- pj-managed-projects:start -->' "$linked_files/AGENTS.md" || exit 1
grep -Fq 'Shared `pj` planning workspace' "$linked_files/planning-AGENTS.md" || exit 1
grep -Fq '# pj-agy-subagent:start' "$linked_files/default.rules" || exit 1
[ "$(stat -c '%a' "$linked_files/AGENTS.md")" = 640 ] || exit 1
[ "$(stat -c '%a' "$linked_files/planning-AGENTS.md")" = 600 ] || exit 1
[ "$(stat -c '%a' "$linked_files/default.rules")" = 644 ] || exit 1

# A broken backend symlink is ambiguous. Surface it as a failure and leave it
# in place rather than silently claiming the shared guidance is installed.
broken_home="$tmp/broken-home"
mkdir -p "$broken_home/planning" "$broken_home/.local/bin" "$broken_home/.codex" || exit 1
ln -s "$broken_home/missing-codex-instructions" "$broken_home/.codex/AGENTS.md" || exit 1
if HOME="$broken_home" \
    XDG_CONFIG_HOME="$broken_home/.config" \
    PATH="$broken_home/.local/bin:$fake_bin:/usr/bin:/bin" \
    bash "$installer" >/dev/null 2>"$tmp/broken-link-warning"; then
  printf 'installer unexpectedly accepted a broken backend instruction symlink\n' >&2
  exit 1
fi
[ -L "$broken_home/.codex/AGENTS.md" ] || exit 1
[ "$(readlink "$broken_home/.codex/AGENTS.md")" = "$broken_home/missing-codex-instructions" ] || exit 1
grep -Fq 'instruction symlink' "$tmp/broken-link-warning" || exit 1

# Malformed managed markers are ambiguous. Fail without replacing or truncating
# the operator's canonical file.
malformed_home="$tmp/malformed-home"
mkdir -p "$malformed_home/planning" "$malformed_home/.local/bin" || exit 1
cat > "$malformed_home/AGENTS.md" <<'EOF'
# Keep all of this content

<!-- pj-managed-projects:start -->
Incomplete managed block that must not consume the rest of the file.
EOF
cp "$malformed_home/AGENTS.md" "$tmp/malformed-agents-before" || exit 1
if HOME="$malformed_home" \
    XDG_CONFIG_HOME="$malformed_home/.config" \
    PATH="$malformed_home/.local/bin:$fake_bin:/usr/bin:/bin" \
    bash "$installer" >/dev/null 2>"$tmp/malformed-warning"; then
  printf 'installer unexpectedly accepted malformed managed markers\n' >&2
  exit 1
fi
cmp "$tmp/malformed-agents-before" "$malformed_home/AGENTS.md" || exit 1
grep -Fq 'malformed managed block markers' "$tmp/malformed-warning" || exit 1

# PJ_WORKSPACE moves the managed workspace contract to the same directory that
# pj will use, without assuming ~/planning. Home-level maintenance and agy
# delegation guidance remain at ~/AGENTS.md.
custom_workspace="$home/custom-planning"
mkdir -p "$custom_workspace" || exit 1
HOME="$home" \
  XDG_CONFIG_HOME="$config_home" \
  PJ_WORKSPACE='~/custom-planning/' \
  PATH="$bin_dir:$fake_bin:/usr/bin:/bin" \
  bash "$installer" >/dev/null || exit 1

grep -Fq '<!-- pj-managed-projects:start -->' "$custom_workspace/AGENTS.md" || exit 1
grep -Fq 'Shared `pj` planning workspace' "$custom_workspace/AGENTS.md" || exit 1
grep -Fq 'pj-update-skills' "$home/AGENTS.md" || exit 1
grep -Fq 'Optional `agy` subagent delegation' "$home/AGENTS.md" || exit 1

printf 'workspace AGENTS context tests passed\n'
