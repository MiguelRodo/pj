# GitHub Copilot instructions

This repository contains `pj`, a Bash-based local operator launcher, installer and maintenance tool.

- Read and follow the root `AGENTS.md` before editing. For GitHub issue or Project administration, also follow `.agents/skills/github-projects/` and `.projects/project.md`.
- Treat the assigned issue as the bounded outcome. Re-read it before making changes and do not invent extra scope.
- Preserve public launcher and installer compatibility unless the issue explicitly changes it. Be especially careful with existing user configuration, installer migration behaviour, compatibility shims and files that may be user-owned.
- Keep tests offline. Tests must not mutate live GitHub state or real user configuration outside temporary test directories.
- Add or update regression coverage for behaviour changes when practical.
- Before proposing a PR, run the complete test suite:

  ```bash
  for f in tests/*.sh; do bash "$f"; done
  ```

- Keep changes narrow and use plain Bash consistent with the existing scripts. Do not add dependencies unless the issue requires them.
- Never add credentials, tokens or private task content to the repository, test output or PR.
- In the PR description, state the requested change, the implementation, and the tests run. Do not claim success if tests or verification failed.
