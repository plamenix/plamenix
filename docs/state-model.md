# State model

Plamenix supports multiple open tabs from `1.0.0-beta`. The state model
is built around per-tab isolation enforced by typed identifiers.

## Rust side

Per-tab state lives in `tauri::State<TabRegistry>` on desktop and in a
server-side session store on web. Conceptually:

```rust
pub struct TabRegistry {
    tabs: DashMap<TabId, Mutex<Tab>>,
}

pub struct Tab {
    pub session: SessionId,
    pub db_handle: Box<dyn DbDriver>,
    pub queue: QueryQueue,        // serialises per-tab queries
    pub current_database: String,
    // ...
}
```

- Each tab owns its own `DbDriver` attachment and its own query queue.
- Per-tab operations serialise via the per-tab mutex / queue, mirroring
  the MVP's pattern to avoid driver-level deadlocks.
- Tabs **never** share mutable state. Closer to actor model than global
  shared state.
- Drop on tab close: detach DB, drop queue, drop mutex. Memory bounded
  by the number of open tabs.

## React side

Zustand stores. Two scopes:

| Scope | Store type | Examples |
|-------|------------|----------|
| Global | Singleton | `useAppStore` (theme, accent, sidebar state, command palette open), `useSettingsStore`, `usePluginRegistry`, `useCommandRegistry`, `useToastStore`. |
| Per-tab | Factory keyed by `TabId` | `useTabStore(tabId)` — selection, scroll position, filters, pagination, current view. |

```ts
// Global
const theme = useAppStore((s) => s.theme);

// Per-tab
const tabId = useCurrentTabId();
const currentTable = useTabStore(tabId, (s) => s.selection?.tableName);
```

Per-tab stores are created lazily on tab open and destroyed on tab
close. They never outlive their tab.

## Why Zustand, not React Context

- Context re-renders the entire subtree on any change. For dense
  components like the data grid this is a real perf hit.
- Zustand selectors subscribe only to the slices that matter; unrelated
  state changes do not trigger renders.
- API is tiny: a `create` call returns a hook plus a `getState` /
  `setState` pair. No providers, no actions, no reducers, no thunks.
- TanStack Query covers all server-state needs. Zustand handles only
  UI / session state.

## TanStack Query keys

All server-fetched data goes through TanStack Query. Keys follow a
strict shape so tabs cannot accidentally share cached data:

```
['rows',    tabId, tableName, page, pageSize, orderBy, orderDir, filterHash]
['schema',  tabId, tableName]
['ddl',     tabId, tableName]
['sidebar', tabId]
['server-info', tabId]
['view', tabId, viewName]
['procedure', tabId, procName]
['trigger', tabId, triggerName]
```

`tabId` is always present after the leading key. Invalidations target
the right tab and do not cross-talk.

Default query options (set in the QueryClient at root):

```ts
{ retry: 1, refetchOnWindowFocus: false }
```

Mirrors MVP behaviour; tuned per query when concrete need arises.

## Routing

Plain `history.pushState` / `popstate` with a routes table; no router
library. Path shape is tab-scoped:

```
/tab/<tabId>/dashboard
/tab/<tabId>/sql
/tab/<tabId>/table/<NAME>
/tab/<tabId>/view/<NAME>
/tab/<tabId>/procedure/<NAME>
/tab/<tabId>/trigger/<NAME>
/tab/<tabId>/generators
/tab/<tabId>/domains
/tab/<tabId>/history
/tab/<tabId>/settings
/tab/<tabId>/plugins
```

A future plugin contribution point may register additional routes.

## Tab lifecycle

| Event | Effect |
|-------|--------|
| New tab | `TabId::new()`, allocate per-tab Zustand store, register tab in `useTabsStore`. |
| Switch tab | Update `currentTabId` in `useAppStore`. UI rerenders against the tab's stores. |
| Close tab | Confirm if there are unsaved changes, detach DB (desktop) or terminate session (web), drop per-tab store, deregister from `useTabsStore`. |
| Reorder | Tab `TabId` is stable; only the ordering array in `useTabsStore` changes. |

## Discipline rules

- Per-tab state never escapes into global stores.
- Global state never depends on `currentTabId`. Components that need
  tab-aware data take the `TabId` as a prop or read it via
  `useCurrentTabId()`.
- Per-tab stores instantiate lazily and clean up explicitly. No
  leaks across tab close.
- TanStack Query keys always include `tabId` after the namespace.
- An ESLint rule (custom, to be added) flags accidental cross-scope
  access.
