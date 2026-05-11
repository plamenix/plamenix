# 0007. Polyrepo with no git submodules

Status: Accepted
Date:   2026-05-11

## Context

Plamenix is split into five sibling git repositories (`plamenix`,
`plamenix-core`, `plamenix-ui`, `plamenix-desktop`, `plamenix-web`).
The team considered how to coordinate them. Options ranged from a
single monorepo to git submodules to lightweight cross-repo tooling.

## Decision

Use **independent repositories coordinated via published artifacts**
(crates.io and npm) plus **Cargo `[patch]`** / **`pnpm link`** for
local development. No git submodules.

Optional convenience layer: a meta-workspace repo (`plamenix/`)
provides a `justfile` and `scripts/setup.sh` that clones the sibling
repos next to it and wires path overrides.

## Alternatives considered

- **Monorepo** — simplifies cross-repo refactors but conflicts with
  independent versioning, independent publishing, and per-repo
  contributor scoping that an OSS plugin ecosystem benefits from.
- **Git submodules** — anti-pattern for OSS in 2024–2026. Sources of
  pain documented across HN, Lobsters, and timhutt.co.uk's
  "Reasons to avoid Git submodules". GitHub's own polyrepo guidance
  recommends meta-repo + manifest patterns instead.
- **Git subtree** — slightly less painful than submodules but still
  imposes a strange mental model on contributors.
- **Heavyweight multi-repo tools** (Google `repo`, ROS `vcstool`) —
  more than we need for five repos.

## Consequences

- Each repo has its own `git`, its own `CLAUDE.md`, its own build,
  its own version line (currently lockstep on `1.0.0-beta`).
- Contributors clone one repo to start; the meta-workspace is
  optional.
- Cross-repo coordinated changes use a tracking issue and one PR per
  repo.
- Versioning across repos uses `release-plz` (Rust) and `changesets`
  (npm). `covector` is on the watchlist if multi-repo coordination
  becomes tedious.
- Local development uses path overrides:
  - Cargo `[patch.crates-io]` to point at sibling repo paths.
  - `pnpm link --global` between `@plamenix/ui` and consumers.

## References

- `docs/git-workflow.md`.
- Tim Hutt, "Reasons to avoid Git submodules":
  https://blog.timhutt.co.uk/against-submodules/
- Lobsters "Never use git submodules" thread.
- GitHub Well-Architected polyrepo guidance.
