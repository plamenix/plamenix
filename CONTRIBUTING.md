# Contributing to Plamenix

Thanks for your interest in contributing. Plamenix is community-driven and
funded by the [Firebird Foundation](https://firebirdsql.org/en/firebird-foundation/).
Contributions of every shape — code, documentation, plugins, bug reports,
design feedback — are welcome.

## Code of Conduct

By participating, you agree to the [Code of Conduct](./CODE_OF_CONDUCT.md).
Be kind and assume good faith.

## Repository layout

Plamenix is a **polyrepo**. This `plamenix/` repo is the meta-workspace; the
actual code lives in four sibling repositories that sit next to it in the
parent directory:

```
<parent-dir>/
├── plamenix/              ← this repo
├── plamenix-core/         ← shared Rust crates
├── plamenix-ui/           ← shared React library
├── plamenix-desktop/      ← Tauri desktop edition
└── plamenix-web/          ← Fastify + React web edition
```

Each sibling repo has its own `CONTRIBUTING.md` with build, test, and code
style specifics. Start there once you know which area you want to work on.

## Local development setup

Required tools:

- Rust **1.95** stable (via [rustup](https://rustup.rs/))
- Node **24 LTS** + [pnpm](https://pnpm.io/)
- [just](https://github.com/casey/just) command runner
- A working Firebird server for runtime testing (Firebird 3, 4, or 5)

To bootstrap the workspace:

```sh
cd <parent-dir>/plamenix
just setup
```

`just setup` clones the four sibling repos next to this one and wires local
path overrides so changes in one repo are picked up by the others without
republishing. Until the public release infrastructure is live, sibling repos
are local only and must be initialised by hand.

## Working on a change

1. Decide which sibling repo owns the change. Cross-repo work is rare; if
   yours touches more than one, open a tracking issue first.
2. Inside the relevant sibling repo, create a branch from `main`:
   - `feat/<slug>` — new feature
   - `fix/<slug>` — bug fix
   - `docs/<slug>` — documentation only
   - `chore/<slug>` — tooling, deps, build
   - `refactor/<slug>` — non-behavioural change
3. Make the change. Keep PRs small and focused.
4. Run the sibling repo's `just fmt`, `just lint`, and `just test` recipes.
5. Open a pull request. Describe **why** the change is needed, not just
   **what** it does. Link the tracking issue if one exists.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(db): add INT128 support
fix(ui): handle null PK in table grid
docs(plugin-sdk): example for cell renderer
chore: bump rustc to 1.95.1
```

Scope is optional but encouraged. Breaking changes carry a `!` after the
type (`feat(db)!:`) and a `BREAKING CHANGE:` footer.

## Versioning

Plamenix follows [SemVer 2.0.0](https://semver.org/). The current release
line is `1.0.0-beta`. All five sibling repos move in lockstep until further
notice. Breaking changes between beta releases are permitted; the public API
freezes at `1.0.0-rc.1`.

## Licence

By contributing, you agree that your contributions are dual-licensed under
**MIT OR Apache-2.0**, matching the project licence. Add yourself to the
contributors list in any relevant repo if you wish.

## Asking questions

For now, file an issue in the repo most relevant to your question. Once
community channels are live, this section will be updated with the
preferred forum.
