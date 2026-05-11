# 0011. Zustand for shared React state, not Context

Status: Accepted
Date:   2026-05-11

## Context

The React shell holds shared state (theme, tabs, settings, plugin
registry, command palette state, toast queue, per-tab selection and
filter state). React's built-in Context API is technically able to
serve all of these. Practical experience and benchmarks show Context
re-renders the entire subtree under a provider on any state change,
which scales poorly for a data-grid-heavy app like Plamenix.

## Decision

Use [Zustand](https://zustand-demo.pmnd.rs/) for **all shared UI
state**. Two scopes:

- **Global stores** — singletons (`useAppStore`, `useSettingsStore`,
  `usePluginRegistry`, `useCommandRegistry`, `useToastStore`,
  `useTabsStore`).
- **Per-tab stores** — factory keyed by `TabId`
  (`useTabStore(tabId)`). Instantiated on tab open; disposed on tab
  close.

Server state belongs in **TanStack Query**, not Zustand.

React Context is used only for **dependency injection** of stable
values that never change after boot (e.g., the `Transport` instance).

## Alternatives considered

- **React Context for everything** — re-render explosions for dense
  components. Documented limitation; common cause of perf issues in
  large React apps.
- **Redux Toolkit** — solid but verbose; reducers / actions / thunks
  add overhead for the size of state Plamenix has.
- **Jotai / Recoil** — atom-based; powerful but unfamiliar to most
  contributors, and Recoil is no longer maintained.
- **MobX** — observer-based; mismatches React's pull-based render
  model and contributors with mixed backgrounds find it surprising.

## Consequences

- Tiny mental model: `create` returns a hook and a `getState` /
  `setState` pair. No providers, actions, reducers, or thunks.
- Selectors subscribe only to the slices that matter; unrelated state
  changes do not trigger re-renders.
- Per-tab stores must be explicitly cleaned up on tab close to avoid
  leaks.
- ESLint rule (custom, future) flags accidental Context use for
  non-trivial state.

## References

- `docs/state-model.md`.
- Zustand docs and Dan Abramov on why Context is not a state-manager.
