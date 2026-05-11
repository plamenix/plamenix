# 0008. JetBrains-style splash window on desktop

Status: Accepted
Date:   2026-05-11

## Context

Plamenix has real boot work: native fbclient verification, plugin
manifest scanning, WASM host initialisation, config migration,
session restoration. During this work the desktop application must
present *something* to the user. The two options are a separate splash
window (JetBrains / IntelliJ pattern) or an inline loading state
inside the main window (modern minimalist pattern, e.g., VSCode,
Cursor).

## Decision

Use a **separate splash window** on the desktop edition, modelled on
JetBrains IntelliJ / DataGrip / RustRover.

The splash:

- Is frameless, transparent, always-on-top, centred, ~500 × 320 px.
- Shows the Plamenix logo, version, edition, and current loading step
  + plugin name.
- Streams progress via Tauri events.
- Closes when the main window is ready to display.

The web edition uses an inline loading state in the main page instead
(no separate window possible in a browser).

## Alternatives considered

- **No splash, hidden main window until ready, branded loading state
  inside main window** — VSCode-style. Cleaner two-window flicker
  story, but loses the JetBrains-class identity moment during boot
  and feels less "premium" for an IDE.
- **Native OS splash via Tauri's `splashscreen` plugin** — limited
  customisation, no plugin-loading status feedback.
- **Skip splash entirely if boot is fast** — adopted as a tweak: the
  splash is suppressed when boot completes in under 200 ms.

## Consequences

- The desktop edition feels professional from launch; identity is
  visible before the main window paints.
- Two windows must be coordinated: the splash dispatches `boot:ready`
  to itself when the main window mounts.
- A separate Vite entry (`splash.html`) keeps the splash bundle tiny
  (<50 KB).
- The web edition's inline loading state must match the splash's
  information density so the two editions feel similar.
- Plugin loading visibility doubles as a debugging aid for plugin
  authors (`--dev-plugins` flag keeps the splash visible).

## References

- `docs/splash-window.md`.
- JetBrains splash screens (IntelliJ, RustRover, DataGrip) as
  reference.
