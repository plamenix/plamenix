# Bundled-plugins smoke checklist (I9.11)

Manual walkthrough of every first-party bundled plugin on **both
editions**, with one screenshot captured per `(plugin × edition)`. The
checklist must run green before tagging `1.0.0-beta` (I9.13).

## What this covers

The nine first-party plugins planned in
[`plugin-architecture.md`](./plugin-architecture.md) §16 / I4 ship in
M1 as either:

- **In-binary built-ins** (eight of nine) — registered via
  `registerBuiltin*` from `@plamenix/ui`. The cross-cutting smoke at
  `plamenix-ui/src/db/builtins/bundled-plugins-smoke.test.tsx` proves
  every registrar lands at its expected extension point without
  collision. This checklist proves each one renders + works in the
  live shell on both editions.
- **A `.plx` example bundle** (one of nine) — the JSON cell renderer
  under `plamenix-core/crates/plamenix-plugin-host/examples/json-cell-renderer/`.
  The cross-edition activator smoke at
  `plamenix-plugin-host/tests/json_renderer_smoke.rs` (I9.2) proves
  both `Edition::Desktop` and `Edition::Web` accept the bundle; this
  checklist proves the live `<pre>` render appears in both shells.

## Why this is a manual step

The shell-rendered UI verification — does the BLOB button look right,
does the export wizard fire its download, does the JSON cell pretty-
print actual data — requires a live Firebird instance, a real
result-table, and a browser/Tauri webview running. Automated component
tests cover each built-in in isolation (per `plamenix-ui/src/**/*.test.{ts,tsx}`),
but the cross-edition golden path is captured by hand for the M1 tag.

After M1, automated visual regression (Playwright + per-bundle
fixtures) is a 1.x scope decision.

## Prerequisites

1. **Desktop edition** — `cd plamenix-desktop && just dev`. Splash
   window opens, then the connection screen. Connect to a local
   Firebird 3.0+ employee.fdb or equivalent fixture DB.
2. **Web edition** — `cd plamenix-web && just web`. Open
   `http://localhost:3000` in Chrome 120+ or Safari 17+. Connect to
   the same fixture DB.
3. **Screenshot capture** — macOS `Cmd+Shift+4` (region) per slot.
   Save each as PNG into `plamenix/docs/screenshots/bundled-plugins/`
   following the slot naming below. Create the directory on first
   run; commit alongside the I9.11 sign-off note.
4. **One result-table tab open** per session — the export-format
   plugins and the BLOB renderer all surface in the `ResultTable`'s
   toolbar. Run a query that returns at least one BLOB column and at
   least one JSON-shaped VARCHAR column. `SELECT * FROM RDB$FIELDS`
   on a Firebird system schema works as a fallback.

## Per-plugin checklist

The first column maps each plugin to its I4 tracker item and source
location. The screenshot slot column is the PNG path to commit.

### 1 — `@plamenix-builtin/blob-renderer` (I4.1)

Source: `plamenix-ui/src/db/builtins/blob-cell-renderer.tsx`.
Extension point: `cell_renderers`. Renders BLOB cells as a tinted
button that opens the BLOB viewer modal.

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Run a query returning a BLOB column. Locate the BLOB cell in the result table. | Cell renders `BLOB 0x<8-byte-hex>…` button with warning-tinted background. Click opens the BLOB viewer modal with hex/text/preview tabs. | `screenshots/bundled-plugins/blob-renderer-desktop.png` |
| Web | Same query in the web edition. | Same render + click behaviour. Tinted button, hex preview, modal opens. | `screenshots/bundled-plugins/blob-renderer-web.png` |

### 2 — `@plamenix-builtin/csv-export` (I4.2)

Source: `plamenix-ui/src/db/builtins/csv-export.ts`. Extension point:
`export_formats`. The CSV button in the result-table toolbar.

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Click the **CSV** button on the result-table toolbar (top of the result tab). | Browser download fires `plamenix-result-YYYYMMDD-HHMMSS.csv`. Open the file: comma-delimited, RFC 4180 quoting around any text with commas or newlines. | `screenshots/bundled-plugins/csv-export-desktop.png` (toolbar + downloaded file open) |
| Web | Same button in the web edition. | Same filename pattern, same content. | `screenshots/bundled-plugins/csv-export-web.png` |

### 3 — `@plamenix-builtin/json-export` (I4.3)

Source: `plamenix-ui/src/db/builtins/json-export.ts`. Extension point:
`export_formats`.

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Click **JSON** in the result-table toolbar. | `plamenix-result-….json` downloads. Body is `JSON.parse`-able, 2-space indented, columns mapped to keys, blobs rendered as `"BLOB(N bytes, peek=0x…)"`. | `screenshots/bundled-plugins/json-export-desktop.png` |
| Web | Same. | Same. | `screenshots/bundled-plugins/json-export-web.png` |

### 4 — `@plamenix-builtin/sql-export` (I4.4)

Source: `plamenix-ui/src/db/builtins/sql-export.ts`. Extension point:
`export_formats`.

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Click **SQL** in the toolbar. Toggle the **Include DDL** checkbox; export both ways. | Without DDL: `INSERT INTO "TABLE_NAME" (…) VALUES (…);` per row. With DDL: prefixed `CREATE TABLE …` with column defs + `PRIMARY KEY (…)`. Single quotes inside strings escaped as `''`. | `screenshots/bundled-plugins/sql-export-desktop.png` (both buttons + opened file) |
| Web | Same. | Same. | `screenshots/bundled-plugins/sql-export-web.png` |

### 5 — `@plamenix-builtin/xml-export` (I4.5)

Source: `plamenix-ui/src/db/builtins/xml-export.ts`. Extension point:
`export_formats`.

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Click **XML** in the toolbar. | `<?xml version="1.0" encoding="UTF-8"?>` declaration, `<rows>` wrapper, `<row>` per row, `<col name="…">…</col>` per cell. NULL cells use `null="true"` attribute. `&`/`<`/`>`/`"`/`'` escaped in attribute + text contexts. | `screenshots/bundled-plugins/xml-export-desktop.png` |
| Web | Same. | Same. | `screenshots/bundled-plugins/xml-export-web.png` |

### 6 — `@plamenix-builtin/xlsx-export` (I4.6)

Source: `plamenix-ui/src/db/builtins/xlsx-export.ts`. Extension point:
`export_formats`. Loads `write-excel-file/browser` lazily (~250 kB,
gated by user click).

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Click **XLSX** in the toolbar. | `plamenix-result-….xlsx` downloads. Open in Excel/Numbers/LibreOffice; header row matches column names; integers numeric, dates date-typed, strings as text. | `screenshots/bundled-plugins/xlsx-export-desktop.png` (toolbar + Excel preview) |
| Web | Same. | Same. | `screenshots/bundled-plugins/xlsx-export-web.png` |

### 7 — `@plamenix-builtin/firebird-tips` (I4.7)

Source: `plamenix-ui/src/db/builtins/firebird-tips-pack.ts`.
Extension point: `tip_packs`. Surfaces in the WelcomeDashboard's
TipsCard.

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Open Welcome / Dashboard view. Wait for the Tips card to render or click its **Next tip** affordance a few times. | One of 32 Firebird tips renders. Card shows tip title + body. Version-gated tips never surface on a Firebird-2.5 fixture. | `screenshots/bundled-plugins/firebird-tips-desktop.png` |
| Web | Same view in the web edition. | Same render + rotation. | `screenshots/bundled-plugins/firebird-tips-web.png` |

### 8 — `@plamenix-builtin/dba-toolbox` (I4.8)

Source: `plamenix-ui/src/db/builtins/dba-toolbox.ts`. Extension point:
`schema_actions`. Adds `RECREATE TABLE` + `SET STATISTICS for indexes`
to the schema-browser table context menu.

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | In SchemaBrowser, right-click a table. | Context menu shows the legacy items + **RECREATE TABLE** (danger cluster) + **Recompute index statistics**. Click RECREATE → confirm prompt interpolates the table name; canceling does nothing, confirming opens the generated DDL in the SQL editor. | `screenshots/bundled-plugins/dba-toolbox-desktop.png` (open menu + confirm modal) |
| Web | Same right-click in the web edition. | Same items + same confirm flow. | `screenshots/bundled-plugins/dba-toolbox-web.png` |

### 9 — `dev.plamenix.json-cell-renderer` (I4.9)

Source: `plamenix-core/crates/plamenix-plugin-host/examples/json-cell-renderer/`.
Extension point: `cell_renderers`. The only `.plx` of the nine — UI-
only bundle (`targets = ["desktop", "web"]`, no wasm half).
Cross-edition activator coverage already in
`plamenix-plugin-host/tests/json_renderer_smoke.rs` (I9.2).

| Edition | Steps | Pass criteria | Screenshot slot |
|---|---|---|---|
| Desktop | Build the bundle: `plamenix-cli build` in the example dir. Install via the install dialog (file picker → `.plx`). Run a query returning a JSON-shaped VARCHAR column. | The cell renders as a `<pre>` block with pretty-printed JSON (2-space indent). Non-JSON VARCHAR cells fall through to the default text render. | `screenshots/bundled-plugins/json-cell-renderer-desktop.png` |
| Web | Build once; install via `POST /api/plugins/install` (admin panel). Same query. | Same `<pre>` render; same fallback behaviour. | `screenshots/bundled-plugins/json-cell-renderer-web.png` |

## Sign-off block

When the 18 screenshots are in `plamenix/docs/screenshots/bundled-plugins/`
+ visual checks above all pass, add a sign-off entry to the I9.11
tracker block (`PLUGIN_TRACKER.md`) with the date + the commit hash
the screenshots landed in. That sign-off unblocks I9.13 (tag
`1.0.0-beta`).

## See also

- [`plugin-architecture.md`](./plugin-architecture.md) — §16 / I4
  enumerates the nine plugins.
- [`edition-targeting.md`](./edition-targeting.md) — `targets`
  field semantics behind the desktop/web split.
- `plamenix-ui/src/db/builtins/bundled-plugins-smoke.test.tsx` —
  cross-cutting registrar smoke (vitest, 4 tests).
- `plamenix-plugin-host/tests/json_renderer_smoke.rs` — cross-edition
  activator smoke for plugin #9.
