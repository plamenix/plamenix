# Git workflow

## Polyrepo coordination

Plamenix lives across five independent git repositories sharing a
single parent workspace directory. Each repo:

- Has its own `git` history, branches, and tags.
- Has its own `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`.
- Is independently buildable and testable.

Cross-repo coupling is done via **published artifacts** (crates.io for
Rust, npm for TypeScript), not submodules. Local development overrides
use Cargo `[patch]` sections and `pnpm link` so changes in one repo
flow into consumers without republishing.

## No git submodules

Git submodules are an anti-pattern for OSS polyrepos in 2026 and are
not used here. Reasons:

- Newcomer friction (empty submodule directories, forgotten
  `--init --recursive`).
- Detached-HEAD confusion.
- Parent-repo pin to specific submodule SHA introduces a two-step
  commit dance for every cross-repo change.
- Code-review tools handle submodules poorly.

See [adr/0007-polyrepo-no-submodules.md](./adr/0007-polyrepo-no-submodules.md).

## Branches

- `main` — trunk. Always green.
- `feat/<short-slug>` — new feature.
- `fix/<short-slug>` — bug fix.
- `docs/<short-slug>` — documentation only.
- `chore/<short-slug>` — tooling, dependencies, build.
- `refactor/<short-slug>` — non-behavioural change.
- `test/<short-slug>` — tests only.

Use slashes, not dots. Lowercase. Hyphen-separated. Keep under ~40
characters.

## Conventional Commits

Subject line: `<type>(<scope>): <imperative description>`. Required.

Types:

- `feat` — user-visible new feature
- `fix` — user-visible bug fix
- `docs` — documentation only
- `chore` — tooling, dependencies, build, release
- `refactor` — non-behavioural change
- `test` — tests only
- `perf` — performance-only change

Scope is optional but encouraged. Examples of scopes per repo:

- `plamenix-core`: `db`, `plugin-host`, `types`, `schema`, `export`,
  `secret`, `plugin-sdk`
- `plamenix-ui`: `transport`, `data-grid`, `sql-editor`, `splash`,
  `tabs`
- `plamenix-desktop`: `tauri`, `tray`, `updater`, `keychain`
- `plamenix-web`: `fastify`, `napi`, `auth`, `docker`

Breaking changes carry a `!` after the type/scope and a
`BREAKING CHANGE:` footer:

```
feat(db)!: drop pure-Rust mode

BREAKING CHANGE: Connections that explicitly set
ConnectionConfig.use_pure_rust = true now panic. The pure-Rust path
is retained only for fallback when bundled native fbclient cannot be
located.
```

Subject line under 50 characters; body wrapped at 72 columns when
present. Body is optional for trivial commits.

Co-author trailers are allowed but **no AI-tool signature** trailers
are added automatically.

## Pull requests

- One PR per logical change. Don't bundle unrelated work.
- Cross-repo work: open one PR per repo, reference a tracking issue
  from each.
- Title follows the same Conventional Commits format.
- Description states **why** the change is needed. The diff already
  shows **what**.
- Every PR runs the local CI pipeline (`just all`) before submission.

## Tags and releases

- Tags are created once a release is cut: `v1.0.0-beta`,
  `v1.0.0-beta.1`, etc.
- Tags are signed (GPG) when the maintainer's identity is settled.
- Each sibling repo tags independently but uses the same version line
  for lockstep releases.

## Local workflow inside the parent workspace

```
<parent-dir>/
├── plamenix/             # `cd plamenix/ && git status` — meta-workspace only
├── plamenix-core/        # `cd plamenix-core/ && git status` — Rust crates
├── plamenix-ui/          # `cd plamenix-ui/ && git status` — React lib
├── plamenix-desktop/     # `cd plamenix-desktop/ && git status` — Tauri app
└── plamenix-web/         # `cd plamenix-web/ && git status` — Fastify + React
```

`cd` into the repo that owns the change. The parent directory is just
a workspace; it has no `.git/` of its own.

## Lockfile policy

- `Cargo.lock` is **committed** in every Rust repo (modern guidance:
  reproducible builds across CI runs, even for libraries).
- `pnpm-lock.yaml` is **committed** in every TypeScript repo.
- `package-lock.json` and `yarn.lock` are **gitignored** — pnpm is the
  only supported package manager.

## Hooks

Pre-commit hooks (Husky or `cargo-husky`) will be added once CI is
live. Until then, contributors run `just all` manually before pushing.
