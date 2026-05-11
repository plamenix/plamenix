# 0006. Microkernel — core surfaces stay in core

Status: Accepted
Date:   2026-05-11

## Context

Plugin-first projects sometimes try to make "everything a plugin"
(Atom is the cautionary example). The core surfaces — login, settings,
data grid, schema views — get pushed into plugins that must load
before the app is usable. The result is slow boots, fragmented UX, and
chicken-and-egg bootstrap problems.

VSCode learned this lesson: its **core** is the workbench, command
palette, file explorer, keybinding system, theme engine. "Built-in
extensions" exist (TypeScript IntelliSense, Markdown preview) but they
**augment**, they do not replace.

## Decision

Plamenix follows the same split:

**Core (always present, native React, no WASM crossing):**

- Window chrome, splash, menus, tabs, status bar
- Connection / login (auth methods are pluggable)
- Sidebar navigation
- Data grid + inline edit
- SQL editor
- Schema views for tables / views / procedures / triggers / generators
  / domains
- Settings page (panels are pluggable)
- Plugin manager UI (must work to disable broken plugins)
- Theme engine (themes are pluggable; engine is core)
- Command palette + keybinding registry
- Toast / dialog / file picker primitives

**Plugins (extend, add, replace augment-only):**

- Data cell renderers / editors per type
- Export and import format handlers
- Sidebar sections, dashboard widgets
- Context menu items
- Toolbar buttons
- Custom commands
- Settings panels (each plugin contributes its own panel under the
  core Settings page)
- Connection auth methods
- DB driver variants
- SQL dialect converters
- Object detail tabs and inspectors
- SQL formatters, linters, completion sources
- Themes, icon packs, editor modes

## Alternatives considered

- **Everything-a-plugin** — Atom-style. Bootstrap paradox (login needs
  to work before the plugin host can load), security inversion (login
  needs unsandboxed access), WASM call overhead on every interaction,
  API surface explosion. Rejected.
- **Closed core, no plugin system** — gives up the community
  extensibility story that Firebird Foundation funding expects.
- **Plugins extend pluggable core surfaces (mixed model)** — what we
  chose. Best of both.

## Consequences

- Plugin authors think in terms of **contribution points**, not "wrap
  the whole UI." Bounded API surface; easier to keep stable.
- Core is fast because main flows are native React with zero WASM
  crossing.
- Plugin failure isolation: disabling a plugin empties its slots; the
  app keeps working.
- Adding a new contribution point is a deliberate act (manifest
  schema + registry + slot consumer + docs).

## References

- VSCode contribution points documentation.
- Atom plugin system post-mortems.
- `docs/contribution-points.md`, `docs/plugin-system.md`.
