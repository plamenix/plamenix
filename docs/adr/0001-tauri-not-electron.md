# 0001. Tauri shell, not Electron

Status: Accepted
Date:   2026-05-11

## Context

Plamenix needs a cross-platform desktop application that hosts a React
UI and a Rust backend. The MVP (`firebird-web-client`) was a Fastify +
React + node-firebird stack served via a browser; the new project wants
a true desktop binary plus a separate web edition.

## Decision

Use **Tauri 2** as the desktop shell. The Rust backend lives next to
the Tauri runtime, the React UI runs in the system WebView (WebKit on
macOS, WebView2 on Windows, WebKitGTK on Linux), and Tauri's IPC layer
bridges the two.

## Alternatives considered

- **Electron** — mature ecosystem but bundles Chromium, leading to
  ~100 MB installers, high RAM use, and a Node.js runtime inside the
  app. Conflicts with our goal of a small, lean desktop binary.
- **Wails** — Go-based equivalent of Tauri; smaller ecosystem and we
  prefer Rust as the core language.
- **Qt / SwiftUI / native per-platform** — high cost, no shared UI
  with the web edition.
- **Pure browser + local server** — what the MVP did; loses native
  features (system tray, OS keychain, file system access, native
  dialogs) that we want.

## Consequences

- Small installer (~10–15 MB target).
- Rust-first backend, plays well with `rsfbclient` and `wasmtime`.
- System WebView quirks per platform need testing (especially Linux
  WebKitGTK).
- The React UI must be transport-agnostic so the web edition can reuse
  it; this is enforced via the `Transport` abstraction in
  `plamenix-ui`.
- Tauri 2 has explicit support for plugins, capabilities, and mobile
  (future option).

## References

- Tauri docs: https://v2.tauri.app/
- See `docs/architecture.md` and `docs/transport.md`.
