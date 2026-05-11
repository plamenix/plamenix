# Firebird quirks — past and present

The MVP (`firebird-web-client v0.0.1-beta`) was built on top of
`node-firebird`. It accumulated a list of driver-specific quirks the
client code had to work around. Plamenix is built on top of native
fbclient via rsfbclient, which **eliminates almost every quirk** in
that list. This document captures the delta so we do not accidentally
re-introduce workarounds that are no longer needed.

## Inherited from MVP / node-firebird (NO LONGER REQUIRED)

| Quirk | MVP workaround | Native fbclient status |
|-------|----------------|------------------------|
| Querying `MON$` monitoring tables crashes the driver. | Replaced with `RDB$DATABASE` + `RDB$GET_CONTEXT`. | **Fixed.** `MON$` tables work natively. |
| BLOB fields returned as JavaScript callbacks. | `stripBlobs()` replaced callbacks with `null`. | **Fixed.** BLOB streaming supported. |
| BOOLEAN parameters mis-converted to `"0"` / `"1"` strings. | Inlined as `TRUE` / `FALSE` SQL literals via `buildValuesSQL`. | **Fixed.** Bound parameters work. |
| ARRAY columns returned as `{ low, high }` descriptor objects. | Expanded into separate element columns via `RDB$FIELD_DIMENSIONS`. | **Fixed.** Native fbclient handles arrays; expansion is optional UX, not driver workaround. |
| Raw `CURRENT_TIMESTAMP WITH TIME ZONE` crashes the wire protocol. | `CAST(CURRENT_TIMESTAMP AS VARCHAR(50))`. | **Fixed.** Time-zone types supported (FB 4+). |
| Concurrent queries deadlock the driver per attachment. | Per-session `enqueue()` query queue. | **Partial.** rsfbclient is synchronous, so we still serialise per attachment, but the deadlock class is gone. |

The per-attachment query queue from the MVP is **kept** because
serialising synchronous Rust calls is still good hygiene. The other
workarounds are removed from new code.

## Still relevant in 2026

| Quirk | Status / handling in Plamenix |
|-------|-------------------------------|
| Field names returned with trailing whitespace (Firebird internal padding to 31 bytes for legacy identifiers). | Plamenix trims on read; the MVP convention carries forward. |
| String fields returned with trailing space padding (`CHAR(N)`). | Trim end on display; preserve exact bytes only on round-trip writes. |
| Identifier case-folding: unquoted identifiers stored as upper-case in `RDB$RELATIONS`. | Plamenix always quotes identifiers (`"USERS"`) in generated SQL and treats system catalogue results as upper-case. |
| DPB BOOLEAN type encoding requires inlined literals in SQL, not parameterised values, when used with some legacy drivers. | With native fbclient this is no longer a hard requirement, but we keep the inlined literal path for safety until the wire format is fully audited. |

## rsfbclient-specific status

| Feature | Native fbclient (chosen path) | Pure-Rust mode (fallback) |
|---------|-------------------------------|---------------------------|
| Encryption key callback / DPB | **Not currently exposed by rsfbclient** | Not exposed |
| DECFLOAT (FB 4+) | Supported via fbclient | Coverage to verify; file issue if missing |
| INT128 (FB 4+) | Supported via fbclient | Coverage to verify |
| TIME ZONE (FB 4+) | Supported via fbclient | Coverage to verify |
| Events (`POST_EVENT` / register) | Supported via native client (PR #142 merged 2025) | Limited |
| Service API (gbak, gstat) | Supported via fbclient | Not exposed |

The encryption callback gap is the biggest open item. Mitigation in
[encryption.md](./encryption.md) (rely on client-side
`KeyHolder.conf`) and Foundation-funded upstream PR to add
`isc_dpb_crypt_key` exposure.

## Quirks we will NOT preemptively document

Per the "no speculative documentation" rule, additional driver
quirks live in code comments at the site they are worked around. They
move into this document only after the same quirk has hit Plamenix
**twice** (Rule of Three for documentation, not just code).
