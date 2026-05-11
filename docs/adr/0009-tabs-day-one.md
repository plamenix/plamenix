# 0009. Tabs from day one

Status: Accepted
Date:   2026-05-11

## Context

The MVP supported a single active connection per window. DBA workflows
routinely require multiple connections open at once (dev vs prod,
multiple databases on one server, side-by-side comparisons). Adding
tabs after-the-fact requires a large state-model refactor.

## Decision

Plamenix supports **multiple tabs from `1.0.0-beta`**. Each tab owns
its own:

- `SessionId` and Firebird attachment.
- Per-tab query queue (serialises driver calls per attachment).
- Per-tab Zustand store (`useTabStore(tabId)`).
- Per-tab routing scope (`/tab/<tabId>/...`).
- Per-tab TanStack Query namespace (tab ID is always part of the
  query key).

Per-tab UI features include drag-and-drop reordering, "unsaved
changes" prompts on close, and tab color tagging for visually
distinguishing dev / staging / prod (from the M1 quick-wins list).

## Alternatives considered

- **Single tab v1.0, multi-tab in M2** — would require a deep refactor
  of state, routing, and query keys after the fact. Cheaper to do it
  up front.
- **Multi-window instead of multi-tab** — Tauri supports multi-window,
  but DBA flows benefit from a single window with tab navigation
  (Spaces / Sets pattern). Multi-window may be added later as a
  preference.
- **Tabs only on desktop** — web users want them too; we share the
  state model across editions.

## Consequences

- Per-tab state model adds complexity from day one.
- Memory cost: N tabs × small per-tab footprint. Manageable.
- Routing must be tab-scoped end-to-end.
- TanStack Query keys must include `tabId`; an ESLint rule (custom)
  flags accidental cross-tab data sharing.
- "Multi-tab improvements" remains on the M3 list — drag-out-to-window,
  tab pinning, tab groups — but the foundation is laid in M1.

## References

- `docs/state-model.md`, `MILESTONES.md`.
