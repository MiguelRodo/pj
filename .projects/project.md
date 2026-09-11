# projects Project configuration

| Key | Value |
| --- | --- |
| Contract version | 1 |
| Mode | single |
| Issue repository | MiguelRodo/pj |
| Project owner | MiguelRodo |
| Project number | 40 |
| Project title | projects |
| Routing | Project 40 membership; no routing label |
| Privacy | public repository with a private user Project |
| Issue write-up style | tidy |
| Issue prose style | natural-direct |
| Chat implementation label | pj:implement-chat |

## Field locations

| Common dimension | Provider location | Provider field |
| --- | --- | --- |
| Class | project field | Class |
| Priority | project field | Priority |
| Status | project field | Status |
| Due date | project field | Target date |
| Parent | native issue relationship | Parent issue |

## Priority mapping

This Project uses the common names directly.

| Common value | Provider value |
| --- | --- |
| P0 | P0 |
| P1 | P1 |
| P2 | P2 |
| P3 | P3 |

## Class values

| Option | Colour |
| --- | --- |
| Task | YELLOW |
| Bug | RED |
| Enhancement | GREEN |
| Data | PINK |
| Analysis | PURPLE |
| Deliverable | ORANGE |
| Documentation | GRAY |
| Epic | BLUE |

## Status mapping

| Common value | Provider value |
| --- | --- |
| Todo | Todo |
| In progress | In progress |
| Done | Done |

## Governance

- This repository contributes only to MiguelRodo Project #40 (`projects`). Repository identity is sufficient routing, so do not add a `project:*` label merely to duplicate Project membership.
- Native Project auto-add may match this repository directly. Agent-created issues should ensure Project #40 membership explicitly rather than depending on auto-add timing.
- The repository is public and the Project is private. Keep private material out of issues, pull requests, commits, logs and public reports.
- `pj:implement-chat` is the historical handoff label for the administrative-only `pj` queue, not a Project-routing label. Queue issues are temporary administration handoffs and are not Project items by default.
- Labels must not duplicate Class, Priority or Status.
- Assignment is explicit only.
- Exact requested administration and organising existing issues to this declared shape require no external source.
