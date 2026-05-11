# 0002. rsfbclient native, loaded via `with_dyn_load`

Status: Accepted
Date:   2026-05-11

## Context

Plamenix needs to talk to Firebird from Rust. It must support Firebird
3.0 through 5.0, including features the MVP could not (MON$ monitoring
tables, BLOB streaming, ARRAY columns natively, DECFLOAT, time zones,
encryption callbacks). Users install many different Firebird versions;
Plamenix should not force a particular client library on the host
system.

## Decision

Use [`rsfbclient`](https://github.com/fernandobatels/rsfbclient) in
**native mode with runtime loading**:

```rust
ConnectionBuilder::builder_native()
    .with_dyn_load("/path/to/bundled/fbclient/libfbclient.dylib")
    ...
```

Plamenix bundles fbclient binaries per platform + per major Firebird
version under `resources/fbclient/v{25,30,40,50}/` and selects the
right one at connect time. Pure-Rust mode is retained as a fallback
when the bundled binary is unavailable or fails to load.

## Alternatives considered

- **`rsfbclient` pure-Rust only** — zero install friction but misses
  MON$ tables, encryption callbacks, BLOB streaming, ARRAY, DECFLOAT
  in the medium term. Too many MVP-style workarounds.
- **`firebirust`** — younger crate, smaller community, no equivalent
  of `with_dyn_load`, weaker feature coverage. Kept as a B-tier
  fallback only.
- **Direct `libfbclient` FFI** — reinventing rsfbclient. No.
- **Compile-time link to system fbclient** — forces every user to
  install Firebird client libraries before running Plamenix. Bad UX.

## Consequences

- Installer size grows by ~5–10 MB per fbclient flavour bundled.
- Plamenix gains MON$ access, BLOB streaming, ARRAY support, DECFLOAT
  and time-zone types out of the box.
- Encryption callbacks remain unavailable through rsfbclient's current
  API; we work around this via client-side `KeyHolder.conf` until an
  upstream PR adds the DPB parameter.
- Multi-version support requires testing each fbclient flavour against
  matching Firebird major versions.
- A `pure-Rust` toggle in the connect dialog provides a fallback path
  when the bundled binary is missing.

## References

- `docs/firebird-driver.md`, `docs/firebird-quirks.md`,
  `docs/encryption.md`.
- rsfbclient API docs: https://docs.rs/rsfbclient/
