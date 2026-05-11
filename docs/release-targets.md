# Release targets

Plamenix targets a full release matrix for `1.0.0-beta`. Until the
public CI infrastructure is live, releases are produced locally for
testing only.

## Desktop edition

| Platform | Architecture | Artifact | Signing |
|----------|--------------|----------|---------|
| Windows | x86_64 | MSI installer | SignPath (activates **after** `1.0.0-beta` ships) |
| macOS | arm64 (Apple Silicon) | DMG | Ad-hoc until Apple Developer Program enrolment (post 2026-08-08) |
| macOS | x86_64 (Intel) | DMG | Ad-hoc until Apple Developer Program enrolment |
| Linux | x86_64 | AppImage + `.deb` | Detached SHA-256 checksums per release |
| Linux | aarch64 | AppImage | SHA-256 checksums |

macOS x86_64 is best-effort; Apple Silicon is primary. Linux aarch64 is
provided when CI capacity allows.

## Web edition

| Artifact | Notes |
|----------|-------|
| Docker image (Debian-slim base) | Multi-arch (amd64 + arm64). Includes bundled fbclient libs per arch. |
| Source tarball | For administrators who prefer building from source. |

The Docker image bundles Node, the Fastify server, and the
pre-built React bundle. Firebird itself is **not** bundled — operators
point Plamenix at their own Firebird server.

## fbclient bundling

Each desktop installer ships native fbclient binaries for all
supported Firebird major versions (2.5, 3.0, 4.0, 5.0) under
`Plamenix/resources/fbclient/v{25,30,40,50}/`. The connect dialog
selects the right one based on target version.

OpenSSL libraries required by certain encryption plugins are bundled
alongside fbclient. Third-party licence acknowledgements ship in
`THIRD-PARTY-NOTICES.md`.

## Signing strategy

| Platform | Strategy | Timeline |
|----------|----------|----------|
| Windows | SignPath open-source code signing | Activates after first public `1.0.0-beta` release. Free for OSS, requires application + approval. |
| macOS | Ad-hoc signing | For development and Foundation-internal testing. Until Apple Developer Program enrolment. |
| macOS | Notarised signing | Once Apple Developer Program enrolment completes (post 2026-08-08). |
| Linux | Detached SHA-256 checksums + signed releases | Maintainer GPG key once published. |

## GitHub Actions CI/CD

A workflow matrix will be defined later, but the shape is:

```yaml
jobs:
  test-rust:
    matrix:
      os: [ubuntu-latest, macos-latest, windows-latest]
      rust: [stable]
    steps:
      - cargo fmt --check
      - cargo clippy --workspace --all-targets -- -D warnings
      - cargo test --workspace

  test-ui:
    matrix:
      os: [ubuntu-latest]
      node: [20, 22]
    steps:
      - pnpm install
      - pnpm lint
      - pnpm typecheck
      - pnpm test
      - pnpm build

  build-desktop:
    needs: [test-rust, test-ui]
    matrix:
      target: [win-x64, mac-arm64, mac-x64, linux-x64, linux-arm64]

  build-web:
    needs: [test-rust, test-ui]
    steps:
      - build & push Docker image (multi-arch)
```

## Auto-updater

Desktop edition uses `tauri-plugin-updater`. The updater fetches
release metadata from GitHub Releases. Signing posture matches the
platform (SignPath / notarised macOS / GPG-signed Linux).

## Not yet in scope

- Snap, Flatpak, MS Store, Mac App Store distribution — possible later
  but not required for M1.
- ARM Windows builds — not in M1.
- Embedded Firebird in the Docker image — out of scope; we run against
  an external Firebird.

## Release rhythm

- Beta cadence: as fixes land, when the patch line accumulates real
  fixes. Not on a fixed schedule.
- RC: when no breaking changes are queued.
- Stable: when the RC has run unchanged in production for a
  conservative window.

`MILESTONES.md` tracks the high-level dates; this document only
describes the *release machinery*.
