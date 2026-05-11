# Firebird driver

Plamenix uses [`rsfbclient`](https://github.com/fernandobatels/rsfbclient)
as the single canonical driver across both editions.

## Why rsfbclient

- Five-year track record, actively maintained (latest `v0.26.0`,
  October 2025; zero open issues at audit time).
- Three builder modes: native dynamic-link, native dynamic-load (load
  fbclient from a user-supplied path), and pure-Rust wire protocol.
- MIT licensed, compatible with Plamenix's MIT-or-Apache-2.0 dual
  licence.
- Ecosystem: `r2d2_firebird` pool, `rsfbclient-diesel` adapter,
  Firebird Foundation aware (listed in driver updates).
- Sole serious competitor (`firebirust`) is newer, smaller community,
  more limited feature surface. Kept as a fallback option only.

## Native + pure-Rust dual mode

```rust
use rsfbclient::ConnectionBuilder;

// 1. Native, system fbclient (compile- and run-time dependency)
let conn = ConnectionBuilder::builder_native()
    .with_dyn_link()
    .host("localhost").user("SYSDBA").pass("masterkey")
    .db_name("/var/lib/firebird/data/employee.fdb")
    .connect()?;

// 2. Native, bundled fbclient (runtime-only path; this is Plamenix's main mode)
let conn = ConnectionBuilder::builder_native()
    .with_dyn_load("/Applications/Plamenix.app/Contents/Resources/fbclient/v5/libfbclient.dylib")
    .host("localhost").user("SYSDBA").pass("masterkey")
    .db_name("/var/lib/firebird/data/employee.fdb")
    .connect()?;

// 3. Pure-Rust wire protocol (no fbclient on disk)
let conn = ConnectionBuilder::builder_pure_rust()
    .host("localhost").user("SYSDBA").pass("masterkey")
    .db_name("/var/lib/firebird/data/employee.fdb")
    .connect()?;
```

## Plamenix's bundling strategy

- Ship native fbclient + plugin libraries per platform in the installer.
- Default mode: `builder_native().with_dyn_load(<bundled-path>)`.
- Pure-Rust mode is kept available as a fallback in case the bundled
  fbclient is missing or removed. Connect dialog exposes a "Use
  pure-Rust" toggle.
- The user may override `fbclient_path` in `ConnectionConfig` to point
  at a different fbclient (e.g., a Firebird 2.5 client for a legacy
  database).

## Multi-version support

Different fbclient binaries handle different Firebird major versions
better than others. Plamenix ships fbclient builds for Firebird 2.5,
3.0, 4.0, and 5.0 side by side under `resources/fbclient/v25/`,
`/v30/`, `/v40/`, `/v50/`. The connect dialog picks one based on
target version or lets the user choose explicitly.

## Async wrapping

`rsfbclient` is synchronous. Plamenix wraps every call in
`tokio::task::spawn_blocking` from a worker thread pool inside the
plamenix-db crate:

```rust
async fn query(driver: Arc<dyn DbDriver>, sql: String) -> Result<QueryResult, DbError> {
    tokio::task::spawn_blocking(move || driver.query_sync(&sql)).await?
}
```

Per-session query queue (mirroring the MVP) serialises queries against
the same attachment so we never call into rsfbclient concurrently for
one session.

## Connection pooling

Initial mode: one attachment per tab. Reuse is handled at the tab level
(see [state-model.md](./state-model.md)). A pool layer
(`r2d2_firebird`) may land in M2 if profiling shows benefit; M1 does
not need it because tab count is modest.

## Feature coverage notes

| Feature | Native fbclient | Pure-Rust |
|---------|-----------------|-----------|
| `MON$` monitoring tables | Yes | Yes |
| BLOB streaming (text + binary) | Yes | Limited |
| ARRAY columns | Yes | Partial |
| BOOLEAN | Yes | Yes |
| DECFLOAT (FB 4+) | Yes | TBD; file rsfbclient issue if missing |
| INT128 (FB 4+) | Yes | TBD |
| TIME ZONE types (FB 4+) | Yes | TBD |
| Encryption (DbCrypt + KeyHolder) | Yes via fbclient | No (no callback API exposed) |
| Events (`POST_EVENT` / register) | Yes | Limited |
| Service API (gbak, gstat, user manager) | Yes | No |
| Multi-statement / EXECUTE BLOCK | Yes | Yes |
| RDB$ system tables | Yes | Yes |

Native fbclient eliminates all known node-firebird quirks the MVP had
to work around (see [firebird-quirks.md](./firebird-quirks.md)).

## NAPI bindings

Web edition uses Node + Fastify and accesses rsfbclient through a NAPI
binding published as `@plamenix/fbclient-node`. The binding exposes the
same `DbDriver` surface to Node.js so we ship one driver, one quirks
list, one truth. See [napi-rsfbclient.md](./napi-rsfbclient.md).

## Upstream contributions planned

- Expose `isc_dpb_crypt_key` and the encryption callback path (required
  to drop the KeyHolder.conf workaround). Foundation-funded contribution.
- Verify DECFLOAT / INT128 / TIME ZONE coverage in pure-Rust mode and
  file PRs where gaps exist.
- Wire encryption negotiation surface (SRP-256, ChaCha) audit.
