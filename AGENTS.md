# Agent guidance

This repository contains `pj`, Miguel's standalone local operator launcher and maintenance tooling for managed projects.

Work on a branch and open a pull request rather than pushing directly to `main`. Before proposing a change, run the test suite:

```bash
for f in tests/*.sh; do bash "$f"; done
```

Tests must run offline and must not mutate live GitHub state or user configurations outside their temporary environments.

<!-- github-projects:start -->
## GitHub issues and Projects

For GitHub issue or Project administration, use the shared `github-projects` skill from `.agents/skills/github-projects/` and read `.projects/project.md` before acting.
<!-- github-projects:end -->
