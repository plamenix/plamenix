# Plamenix

A community-driven open-source IDE for Firebird databases.

Plamenix ships as a **desktop application** (Tauri 2 + Rust) and a
**web edition** (Fastify + React) from a shared codebase. Both editions
talk to Firebird through [`rsfbclient`](https://github.com/fernandobatels/rsfbclient).

## Repositories

This repo (`plamenix/`) is the **meta-workspace**. The actual product is
spread across five sibling repositories that live next to this one in the
same parent directory:

| Repo | Contents |
|------|----------|
| `plamenix/` | This repo — orchestration, milestones, contributor docs. |
| `plamenix-core/` | Shared Rust crates: types, db driver wrapper, plugin host, plugin SDK. |
| `plamenix-ui/` | Shared React library: shell, components, hooks, transport abstraction. |
| `plamenix-desktop/` | Tauri 2 desktop edition. |
| `plamenix-web/` | Fastify + React web edition (self-hostable). |

## Installing

Prebuilt installers for macOS, Windows and Linux are on the
[latest release](https://github.com/plamenix/plamenix-desktop/releases).
They are built in the open by
[GitHub Actions](https://github.com/plamenix/plamenix-desktop/blob/main/.github/workflows/release.yml) from the tagged
commit — no binary is uploaded from anyone's laptop.

**On macOS and Windows we currently recommend building from source
instead.** The releases are not code-signed, and we would rather say
plainly what that means than tell you how to click past a warning:

- macOS reports *"cannot be opened because the developer cannot be
  verified"*, and Windows shows a SmartScreen prompt. Those warnings are
  correct. Nothing has vouched for the binary.
- Getting past them means overriding your operating system's judgement
  about software from a stranger on the internet. That is a habit worth
  keeping, not one to spend on us.
- Signing certificates cost money the project does not currently have.
  When that changes, the workflow already has the hooks and this section
  goes away.

If you do use the installers, the release notes carry the workaround for
each platform. Linux packages are unaffected — `.deb`, `.rpm` and the
AppImage carry no equivalent signing expectation.

Either way, [building from source](#building-from-source) is mostly
unattended: the first build compiles the full Rust dependency tree and
takes a while, and every build after that is incremental. You end up
trusting a toolchain you installed rather than a file you downloaded.

## Building from source

Full instructions:

- [Build prerequisites](./docs/build-prerequisites.md) — toolchains,
  platform libraries, repository layout. Start here.
- [Building the desktop edition](./docs/build-desktop.md)
- [Building the web edition](./docs/build-web.md)

The short version, once the prerequisites are installed and all five
repositories are cloned as siblings:

```sh
cd plamenix && just setup          # verifies layout and toolchains
cd ../plamenix-ui && pnpm install && pnpm build
cd ../plamenix-desktop && just setup && just dev
```

Building `plamenix-ui` first is not optional: the desktop and web
editions import its built output, and a fresh clone does not have it.

## Roadmap

See [`MILESTONES.md`](./MILESTONES.md). Current target: `1.0.0-beta` in
mid-June 2026.

## Licence

Plamenix is dual-licensed under **MIT OR Apache-2.0**. Choose whichever
suits your use.

See [`LICENSE-MIT`](./LICENSE-MIT) and [`LICENSE-APACHE`](./LICENSE-APACHE).

## Code of Conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md).
By participating, you agree to abide by its terms.
