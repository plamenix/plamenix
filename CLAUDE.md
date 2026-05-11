# plamenix — meta-workspace

This repo orchestrates the five Plamenix repositories. It holds no product
code. Its job: documentation, roadmap, contributor onboarding, and local
dev tooling that wires the sibling repos together.

## What lives here

- `MILESTONES.md` — single source of truth for the roadmap. Update as
  milestones land.
- `README.md` — user-facing project overview.
- `CONTRIBUTING.md` — how to set up a local dev environment across all
  five repos.
- `CODE_OF_CONDUCT.md` — Contributor Covenant.
- `LICENSE-MIT`, `LICENSE-APACHE` — dual licence text.
- `docs/` — architectural specs, design notes, and ADRs. Deep technical
  context that should outlive any single conversation lives here. See
  `docs/README.md` for the index and `docs/adr/` for the decision
  records.
- `justfile` — entry point for cross-repo commands (`just setup`,
  `just dev`, `just build`, `just test`).
- `scripts/setup.sh` — wires sibling repos for local development.
- `.editorconfig` — universal indent / EOL conventions inherited by
  contributors' editors.
- `.gitignore` — keeps the meta-workspace clean.

## What does not live here

- Application code (Tauri shell, web server, React components, plugin host)
  lives in the sibling `plamenix-*` repos.
- Per-repo build, test, and code-style rules live in each sibling repo's
  own `CLAUDE.md`.
- Per-repo API documentation that mirrors source code lives in the
  relevant sibling repo, alongside the code it documents.

Cross-repo architectural decisions and design specs DO live here in
`docs/`. That is what `docs/` is for — durable context that spans the
whole project and must survive conversation refreshes.

## Workflow

1. Clone every sibling repo into the parent workspace dir (the dir holding
   `plamenix/`, `plamenix-core/`, etc.). The `scripts/setup.sh` helper does
   this.
2. Inside each sibling repo, follow that repo's `README.md` and
   `CONTRIBUTING.md`.
3. Cross-repo coordinated changes: open one PR per repo; reference the
   tracking issue from each PR.

## Editing rules for this repo

- This repo never contains source code. If a file would be source code, it
  belongs in a sibling repo.
- Keep `MILESTONES.md` accurate. When a milestone ships, move its line
  items to a "shipped" section or delete and rely on the CHANGELOG.
- Keep `README.md` minimal (under ~200 words). Detailed docs go in sibling
  repos.

## Commands worth knowing

```
just setup     # clone siblings (if not present) + wire local path overrides
just dev       # run the desktop edition against local sibling repos
just web       # run the web edition (Fastify + React) against local siblings
just test      # run every sibling repo's test suite
just fmt       # run rustfmt + prettier across all repos
just lint      # run clippy + eslint across all repos
```

Recipes are aspirational at this stage; expand `justfile` as the project
grows.
