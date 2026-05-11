# Look & feel + branding

Plamenix inherits its visual style from the
[`firebird-web-client`](https://github.com/Ascent-Systemes/firebird-web-client)
MVP — the same one the MVP shipped in `0.0.1-beta`. The MVP lives
locally at `~/Projects/firebird/` and is the canonical reference
for every visual decision Plamenix has not yet redesigned.

Brand assets (logo, favicons, social images, OG banners) live in a
separate sibling repository — `plamenix-branding` — so the product
repos never carry binary art. Each Plamenix edition consumes the
branding repo by path, not by vendoring.

## Where things live

| Concern | Source of truth |
|---------|-----------------|
| Logo, flame icon, lockups, favicons, OG banners | `../plamenix-branding/` |
| Colour palette, accent colours, typography choices | `../plamenix-branding/docs/branding.html` |
| Application visual style (forms, panels, grid, sidebar, themes) | `~/Projects/firebird/client/` (MVP) until ported into `plamenix-ui` |
| Component look-and-feel decisions Plamenix has already redesigned | `plamenix-ui/src/db/*.tsx` |

## Port plan from `firebird-web-client`

The MVP's React client carries finished work Plamenix needs to bring
across. These items are tracked under M1's "Carryover features"
section in [`../MILESTONES.md`](../MILESTONES.md):

- Darcula / IntelliJ themes (dark + light) plus 10 accent colours.
- Collapsible left sidebar.
- TanStack Table data grid — pagination, sorting, filtering, inline
  cell editing, bulk row operations, column-resize persistence.
- CodeMirror 6 SQL editor — already brought across with a Firebird
  dialect; theme polish still to come.
- Schema management panes for procedures, triggers, generators,
  domains. Only tables + views are surfaced in Plamenix today.
- Query history with search.
- Wildcard search + 11 per-column filter operators.
- 5-format export (CSV / JSON / SQL / XML / XLSX).

When porting, copy the *visual result*, not the codebase: the MVP
uses CRA + plain CSS in spots, while Plamenix is Vite + Tailwind 4.
The aim is "looks indistinguishable to a returning MVP user", not a
literal file-by-file port.

The MVP's logo is **legacy** and is not reused — the brand has been
redesigned. See the branding repo's `docs/history/` for the
generation log.

## Consuming `plamenix-branding`

`plamenix-branding/` is cloned as a sibling under the workspace dir
(`~/Projects/plamenix/plamenix-branding/`). Each edition pulls the
files it needs from there at build time; nothing is checked into
the product repos:

### Desktop (Tauri)

- `src-tauri/tauri.conf.json` `bundle.icon` paths point at
  pre-built PNGs under `../plamenix-branding/build/macos/`,
  `../plamenix-branding/build/windows/`,
  `../plamenix-branding/build/linux/`, and the `.icns` / `.ico`
  outputs Tauri's bundler needs.
- Splash window and main window favicons come from
  `../plamenix-branding/build/favicon/`.
- A small `just refresh-icons` recipe in `plamenix-desktop/justfile`
  symlinks or copies the per-platform icon set into
  `src-tauri/icons/` before a release build. The `src-tauri/icons/`
  directory is in `.gitignore`; it is treated as a build artefact.

### Web (Fastify + Vite client)

- The Vite client's `public/` favicon set is symlinked from
  `../../../plamenix-branding/build/favicon/` (relative to
  `packages/client/`).
- The Fastify server's static asset path serves the OG image and
  square social variants from the branding repo's `build/` tree.

### Shared React library (`@plamenix/ui`)

- Never bundles logo artwork. Components that need a logo accept a
  React node prop (e.g. `<SplashWindow logo={...}>`), and the
  edition supplies the right asset.

## Cloning the branding repo

```sh
cd ~/Projects/plamenix
git clone git@github.com:plamenix/plamenix-branding.git
```

The `scripts/setup.sh` helper in this meta-workspace should clone
the branding repo alongside the other siblings if it is missing.

## Why this split

- Brand assets churn on a different cadence than product code. Tagging
  a Plamenix release should not require touching binary art.
- Keeping the branding repo standalone lets the marketing site
  (`plamenix.dev`) deploy from it directly without dragging in the
  IDE source.
- Multiple downstream consumers (Plamenix itself, the website, future
  press kits) all read from one source, so the icon a user sees in
  the dock matches the one on the landing page.
