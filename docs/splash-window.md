# Splash window

Plamenix opens a JetBrains-style splash window during boot, modelled on
IntelliJ IDEA / RustRover / DataGrip. The splash exists for desktop
only; the web edition uses an inline loading state inside the main
page (no separate window possible in a browser).

## Why a separate splash window

- Plamenix has real boot work: native libfbclient verification, plugin
  manifest scanning, WASM module discovery, config migration, recent
  connection restoration.
- A JetBrains-style splash communicates progress and identity during
  that boot, instead of showing a blank or unstyled window.
- Locked in early so we never end up with a "white flash" boot.

## Anatomy

```
┌─────────────────────────────────────┐
│ [icon]   Plamenix                   │
│          Firebird IDE               │
│                                     │
│            [hero artwork]           │
│                                     │
│    1.0.0-beta · Community Edition   │
│                                     │
│   Loading plugin: csv-exporter      │
│   ●●●○○○○                           │
│                                     │
│   © 2026 Firebird Foundation        │
└─────────────────────────────────────┘
```

- Frameless, no titlebar, no resize, centred.
- Approx 500 × 320 logical pixels.
- Always on top during boot.
- Branded background artwork.
- Status line shows the current loading step + plugin name.
- Optional thin progress bar.

## Tauri configuration

Two windows declared in `tauri.conf.json`:

```jsonc
{
  "app": {
    "windows": [
      {
        "label": "splash",
        "url": "splash.html",
        "width": 500, "height": 320,
        "decorations": false,
        "transparent": true,
        "alwaysOnTop": true,
        "resizable": false,
        "center": true,
        "skipTaskbar": false,
        "visible": true
      },
      {
        "label": "main",
        "url": "index.html",
        "width": 1400, "height": 900,
        "visible": false,
        "title": "Plamenix"
      }
    ]
  }
}
```

The main window is created hidden. Once boot finishes, the orchestrator
sends `boot:ready`, the splash window closes, and the main window
becomes visible. No two-window flash if both transitions are scheduled
in the same frame.

## Boot sequence

1. Rust `main()` runs (panic handler, logger, config load, command
   registration). Splash is already visible by this time because
   Tauri spawns windows during builder setup.
2. Splash JS subscribes to events:
   - `boot:step` (`"Loading config"`, `"Scanning plugins"`,
     `"Initialising plugin host"`)
   - `boot:plugin-loading` (plugin name + version)
   - `boot:plugin-loaded` (plugin name + version)
   - `boot:plugin-failed` (plugin name + reason)
   - `boot:progress` (n / total)
   - `boot:ready`
3. The Rust orchestrator emits events as it scans plugins, validates
   manifests, and stages registries.
4. Plugin WASM modules are **not** instantiated during splash. Only
   manifests are parsed; UI contributions are registered for later
   dynamic import.
5. The main React app starts loading in the hidden main window in
   parallel.
6. When both the host registry is ready and the main React tree has
   mounted, the orchestrator emits `boot:ready`.
7. Splash receives `boot:ready`, fades out, and closes. Main window
   becomes visible.

## Splash bundle constraints

- Splash is a separate Vite entry: `splash.html` + a tiny
  `splash.tsx`. Kept under 50 KB JS + CSS.
- No React Query, no Zustand, no Tailwind. Vanilla React or even
  plain HTML + a few lines of JS. Splash is a read-only display.
- Splash only depends on `@tauri-apps/api/event` to listen for boot
  events.

## Skip-if-fast

If the entire boot completes in under 200 ms (typical on cold installs
with no plugins), the splash closes before fully rendering and the user
never sees it. Avoids a flicker for the fast path.

## Failure and cancellation

- A plugin that fails to load is reported via `boot:plugin-failed`.
  Splash adds it to the list with a red mark and "Disable" / "Retry"
  actions.
- A plugin that takes longer than 5 seconds shows a "Skip" button to
  finish boot without it.
- Fatal failures (config corrupted, host crashed) replace the splash
  content with an error pane and a "Show log" affordance.

## Dev-mode flag

`--dev-plugins` keeps the splash visible permanently and dumps detailed
plugin diagnostics to it. Useful for plugin authors debugging their
own bundle.

## Web edition equivalent

Web cannot spawn a separate window, so the same flow renders inside
the main page during the initial mount:

- Branded loading panel covers the entire viewport.
- Progress events streamed via Server-Sent Events or a `bootstrap`
  endpoint returning a streamed JSON list.
- Replaces itself with the main shell once `boot:ready` fires.
