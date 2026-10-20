# projects Project configuration

| Key | Value |
| --- | --- |
| Contract version | 1 |
| Sub-project storage | field |
| Sub-project field | Sub-project |
| Sub-project field type | SINGLE_SELECT |
| Mode | single |
| Issue repository | MiguelRodo/pj |
| Project owner | MiguelRodo |
| Project number | 40 |
| Project title | projects |
| Routing | membership |
| Privacy | public repository with a private user Project |

## Field locations

| Common dimension | Provider location | Provider field |
| --- | --- | --- |
| Class | project field | Class |
| Priority | project field | Priority |
| Status | project field | Status |
| Due date | project field | Target date |
| Parent | native issue relationship | Parent issue |
| Sub-project | project field | Sub-project |

## Governance

- This repository contributes only to MiguelRodo Project #40 (`projects`). Repository identity is sufficient routing, so do not add a `project:*` label merely to duplicate Project membership.
- Native Project auto-add may match this repository directly. Agent-created issues should ensure Project #40 membership explicitly rather than depending on auto-add timing.
- The repository is public and the Project is private. Keep private material out of issues, pull requests, commits, logs and public reports.
- `pj:implement-chat` is the historical handoff label for the administrative-only `pj` queue, not a Project-routing label. Queue issues are temporary administration handoffs and are not Project items by default.
- Labels must not duplicate Class, Priority or Status.
- Assignment is explicit only.
- Exact requested administration and organising existing issues to this declared shape require no external source.

## Storage authority

- The field includes a schema-only `Not assigned` option. Leave unclassified item values blank; clearing does not select that option.
- `Sub-project` is the sole writable grouping representation. Legacy grouping labels are read-only migration artifacts until verified cleanup.
- Resolve field and option IDs freshly; require the exact configured name, SINGLE_SELECT type and vocabulary mapping. Stop if the expected field is missing or inaccessible.
- Multiple memberships require explicit Project context unless exactly one relevant managed membership resolves it. An explicit add-membership request may name its target before placement.
