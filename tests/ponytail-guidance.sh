#!/usr/bin/env bash
set -e

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
agents="$repo_root/AGENTS.md"
skill="$repo_root/.agents/skills/ponytail/SKILL.md"
vendor="$repo_root/.agents/skills/ponytail/README.md"
license="$repo_root/.agents/skills/ponytail/LICENSE"

[ -f "$skill" ]
[ -f "$vendor" ]
[ -f "$license" ]

grep -Fq 'name: ponytail' "$skill"
grep -Fq 'Default: **full**.' "$skill"
grep -Fq 'DietrichGebert/ponytail' "$vendor"
grep -Fq 'e3ba2aa6f1e6f0bc4d69eb09c9f0d0a93af56156' "$vendor"

grep -Fq '.agents/skills/ponytail/SKILL.md' "$agents"
grep -Fq 'apply Ponytail in **full** mode by default' "$agents"
grep -Fq 'administrative-only' "$agents"
grep -Fq 'deterministic, contract-aware queue preflight' "$agents"
grep -Fq 'Run the complete' "$agents"

printf 'pj Ponytail guidance tests passed\n'
