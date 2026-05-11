# Plamenix — Milestones

Versioning: [SemVer 2.0.0](https://semver.org/). First public release is `1.0.0-beta`.

---

## Milestone #1 — Plamenix MVP

**Target:** early-to-mid June 2026
**Release:** `1.0.0-beta`

### Architectural port

- Tauri 2.x shell + Rust backend with `rsfbclient`
- Shared `react-shared` library, dependency-injected transport
- Web edition (Fastify + React) and desktop edition (Tauri + Rust + React) building from one source
- Bundled `fbclient` per platform; in-app fetcher for alternate Firebird major versions

### Connection-time encryption support

- Encryption key field in connection dialog
- Library selector for plugin libraries (e.g. for IBSurgeon EPF: `fbclient.dll`, `fbcrypt.dll`, `opensslXX.dll`)
- Encryption key callback handling via `rsfbclient`
- Encrypted connection profiles stored in OS keyring
- Encryption status visible in UI (`MON$DATABASE.MON$CRYPT_STATE`)

### Carryover features from `firebird-web-client` v0.0.1-beta

- Connection profiles with timestamps, auto-reconnect, server health monitoring
- `databases.conf` discovery for self-hosted/local installations
- TanStack Table data grid: server-side pagination/sorting/filtering, inline cell editing, bulk row operations, column resize persistence
- Schema management: tables, views, procedures, triggers, generators, domains; DDL inspection; modal schema editing
- CodeMirror 6 SQL editor with custom Firebird dialect (250+ keywords), Darcula/IntelliJ themes, query history with search
- Global wildcard search + 11 per-column filter operators
- Export in 5 formats: CSV, JSON, SQL (with optional DDL), XML, XLSX
- Dark/light themes, 10 accent colors, collapsible sidebar

### Limitations eliminated by native fbclient

- `MON$` monitoring tables fully supported
- BLOB streaming (text + binary)
- ARRAY columns handled natively
- Charset/collation gaps closed
- Full Firebird 4 / 5 type support (DECFLOAT, time zones)

### Quick wins pulled forward into M1

- **Inline BLOB editor** — mime detection, text editor, hex editor, image preview
- **Database statistics dashboard** — pages, transactions, sweep interval, OAT/OST/Next, forced writes
- **Connection color tagging** — visually distinguish dev/staging/prod tabs
- **Drag-and-drop from object explorer to SQL editor**
- **SQL editor bookmarks** — `Ctrl+Shift+0–9` set, `Ctrl+0–9` jump
- **Recompute index selectivity** — one-button `SET STATISTICS INDEX`
- **RECREATE TABLE** option in schema editor

### Release operations

- GitHub Actions build matrix: Windows MSI, macOS DMG, Linux AppImage + .deb, Docker images for web edition
- Linux: SHA-256 checksums per release
- Windows: SignPath signing pipeline activates post-1.0.0-beta
- macOS: ad-hoc signing for testing only until Apple Developer Program registration (post-Aug 8, 2026)

---

## Milestone #2 — Daily DBA tooling

**Target:** September 2026

- **Plan Analyzer + Performance dashboard** — visual `EXPLAIN PLAN`, index usage statistics, query cost estimates
- **Grant Manager / User Manager UI** — manage GRANT/REVOKE, users, roles, system privileges
- **Encryption management** — `ALTER DATABASE ENCRYPT WITH ... KEY ...` and `DECRYPT` operations from the IDE; live progress monitoring via `MON$CRYPT_PAGE`

---

## Milestone #3 — Heavier features and depth

**Target:** January 2027

- **Test data generator** — full Firebird 4 / 5 type support (DECFLOAT, time zones, BINARY/VARBINARY, BLOB)
- **Web-style metadata search** — search across all DDL with operators (`AND`, `OR`, exclusion, quoted phrases)
- **Stored script library (local)** — named, searchable, SQLite-backed saved-query collection
- **Workflow niceties** — refined drag-drop behaviors, multi-tab improvements, additional editor shortcuts

---

## FUTURE_TODO — Heavier features deferred beyond M3

Order will be re-evaluated as the userbase grows and clearer demand signals emerge.

### High-value but deceptively deep

- **Schema and metadata comparison & sync** — compare two databases structurally, generate ALTER scripts. Edge cases (trailing whitespace in VARCHAR, collation differences, dependency ordering) are weeks of work each.
- **Table data comparison** — same family of edge cases, paired with schema comparison.
- **Live trace sessions** — system audit tracing via the Services API.

### Visual / explorer features

- **ER diagram visualization** — read-only auto-layout from existing schema first; editable later.
- **Stored script library — git integration** — commit your script collection to a repo, sync across machines, share with team. Planned for 2.x.

### IBSurgeon Encryption Plugin Framework integration

- **EPF-specific support** — UI affordances designed around how IBSurgeon EPF customers actually use it.
- **Status:** blocked on getting EPF access from IBSurgeon for development and testing.
- Will be re-prioritized once EPF is in hand.

### Long-horizon flagship features

- **PSQL debugger** — step-through debugging of stored procedures and triggers with breakpoints, watches, step-into. Likely M5+.
- **Replication monitoring** — Firebird 4+ built-in replication monitoring views and dashboard.

---

## POLL_TODO — Features pending user validation

Will be polled on `firebirdsql.org`, GitHub Discussions, and via direct user feedback once Plamenix has a userbase. Build only with evidence of demand.

- **Visual query builder** — drag tables, pick columns, generate SQL. Even IBExpert's own implementation is limited and Alexey questioned whether anyone actually wants it. SQL editor remains the power surface either way.
- **ARRAY column UX polish** — Firebird ARRAY columns are technically supported but production usage is essentially nil. Native fbclient fixes the underlying blocker; spending UX cycles on ARRAY editing only makes sense if real users ask for it.
