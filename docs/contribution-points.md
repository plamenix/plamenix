# Contribution points

Plugins extend Plamenix by filling **contribution points** — typed
slots in the React shell and the Rust core. Plugins do not replace
core surfaces (login, settings, table view); they augment them.

Contribution points are an enumerated, bounded surface. Adding a new
contribution point is a deliberate act that requires updating the
manifest schema, the host registry, the slot consumer, the
documentation, and an RFC (once the RFC process is live).

## Categories

### Data grid contributions

| Point | Purpose |
|-------|---------|
| `data.cell-renderer` | Render cells of a given column type with custom UI (JSON tree, geometry map, image preview, hex viewer). |
| `data.cell-editor` | Provide a type-aware inline editor. |
| `data.row-action` | Add entries to the row context menu. |
| `data.column-action` | Add entries to the column context menu. |
| `data.toolbar-button` | Add buttons to the data grid toolbar. |
| `data.export-format` | Register an additional export format (Parquet, Markdown table, custom CSV flavour). |
| `data.import-source` | Register an importer (CSV/Excel/JSON → table wizard). |
| `data.filter-operator` | Contribute custom WHERE-clause operators. |

### Schema and object contributions

| Point | Purpose |
|-------|---------|
| `object.detail-tab` | Add a tab to the detail view of a tables/views/procedures/triggers/etc. object. |
| `object.inspector` | Custom inspector panel for an object type. |
| `object.action` | Toolbar action on an object (e.g., "Backup this table", "Generate Postgres DDL"). |
| `schema.object-type` | Register a brand-new object type (rare; useful when Firebird adds something in a future version). |
| `ddl.formatter` | Contribute a DDL pretty-printer. |

### Sidebar and dashboard

| Point | Purpose |
|-------|---------|
| `sidebar.section` | Add a custom sidebar section (Favorites, Recent, Bookmarks, custom dashboards). |
| `dashboard.widget` | Add a tile to the dashboard. |

### Editor

| Point | Purpose |
|-------|---------|
| `editor.toolbar-button` | Add a button to the SQL editor toolbar. |
| `editor.completion-source` | Contribute autocompletion suggestions. |
| `editor.formatter` | Register a SQL formatter. |
| `editor.linter` | Register a SQL linter. |
| `editor.mode` | Editor mode (Vim, multi-cursor, etc.). |

### Connection

| Point | Purpose |
|-------|---------|
| `connection.auth-method` | Register an authentication variant (Windows Credential Manager, Kerberos, OAuth, custom SRP). |
| `connection.driver` | Provide an alternative DB driver implementation (different rsfbclient mode, native FFI to libfbclient, etc.). |

### Conversion

| Point | Purpose |
|-------|---------|
| `db.dialect-converter` | Convert Firebird DDL/SQL to another dialect (Postgres, MySQL, SQLite, etc.). |

### Application surface

| Point | Purpose |
|-------|---------|
| `settings.panel` | Add a configuration panel to the Settings page. |
| `command` | Register a command for the command palette and key-binding system. |
| `theme` | Register a colour theme. |
| `icon-pack` | Register an icon pack. |
| `keybinding.context` | Contribute key bindings scoped to a context. |

## Manifest shape (excerpt)

```toml
[contributions.ui]
"data.cell-renderer" = [
    { for = "BLOB:SUB_TYPE_TEXT", component = "MarkdownPreview" },
]
"data.export-format" = [
    { id = "parquet", label = "Apache Parquet", command = "export.parquet" },
]
"sidebar.section" = [
    { id = "favorites", label = "Favorites", icon = "star", component = "FavoritesPanel" },
]
"connection.auth-method" = [
    { id = "win-cred", label = "Windows Credential Manager",
      form = "WinCredForm", handler = "win_cred_login" },
]
"settings.panel" = [
    { id = "my-plugin", label = "My Plugin", component = "MyPluginSettings" },
]

[contributions.db]
"db.dialect-converter" = [
    { id = "fb-to-pg", source = "firebird", target = "postgresql",
      handler = "convert_ddl" },
]
```

## Discovery in the React shell

Components read contributions through:

```tsx
<PluginOutlet point="sidebar.section" />
<PluginOutlet point="object.detail-tab" target="table" tableName={name} />
<PluginOutlet point="data.cell-renderer" type={columnType} value={value} />

const renderers = useContribution('data.cell-renderer', columnType);
```

Each `<PluginOutlet>` queries the in-memory registry, dynamically
imports the plugin's UI bundle on first use, and wraps each
contribution in an error boundary. Disabling a plugin empties its slots
without crashing the host.

## Discipline rules

- The contribution-point set is **bounded**. Plugins cannot register
  arbitrary new categories.
- Each point has a typed record shape. No free-form blobs.
- A contribution point lives forever once shipped. Adding one is
  permanent surface.
- Removing a contribution point requires a major-version bump in the
  plugin API (`plugin-api@2.0`).
- The same plugin may fill multiple points across categories.
