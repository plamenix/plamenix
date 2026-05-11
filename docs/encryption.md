# Firebird encryption

Plamenix supports connecting to encrypted Firebird databases from
`1.0.0-beta`. Deeper integration with the IBSurgeon Encryption Plugin
Framework (EPF) lands later when EPF access is available.

## Firebird encryption recap

Three distinct layers, often confused:

| Layer | Description |
|-------|-------------|
| **At-rest** | Database file is encrypted page-level via a `DbCrypt` plugin (server-side). Built-in or third-party (EPF). |
| **Wire**    | TCP traffic encrypted via ChaCha / SRP-256 (negotiated automatically; separate concern from at-rest). |
| **Per-table** | **Not** a distinct Firebird concept. At-rest encryption is database-wide. |

Plamenix's M1 work concerns at-rest encryption. Wire encryption is
handled by fbclient and the server transparently.

## Plugin architecture

Two plugin roles defined by the Firebird 3+ DbCrypt API:

| Plugin | Role |
|--------|------|
| **`DbCrypt`** | Server-side. Encrypts and decrypts pages. |
| **`KeyHolder`** | Dual role: server-side key file management *and* client-side callback that returns the key to fbclient when the server requests it. |

Built-in: ChaCha, Arc4. Third-party: IBSurgeon EPF (AES256 over
OpenSSL).

## Two key-delivery paths

1. **Callback** (native C/C++/Delphi pattern). Client calls
   `fbcrypt_key()` before `isc_attach_database()`. Thread-local
   storage. fbclient loads `keyholder.dll` and invokes the callback
   when the server requests the key.
2. **DPB parameter** (Java/.NET pattern). Pass `dbCryptConfig=KeyName:0xhexvalue`
   via the connection's Database Parameter Block. fbclient handles the
   callback internally.

## rsfbclient status (May 2026)

`rsfbclient` v0.26.0 does **not** currently expose the encryption DPB
parameter or callback FFI. `build_dpb()` covers user, password, role,
and charset; it omits `isc_dpb_crypt_key` and any callback registration
path.

Until a PR lands upstream exposing these, Plamenix relies on the
**client-side KeyHolder.conf** mechanism:

- User installs `keyholder.dll` (or `keyholder.so`) and OpenSSL
  dependencies in fbclient's plugin search path.
- User configures `KeyHolder.conf` alongside fbclient.
- fbclient auto-loads the plugin and resolves keys without any
  parameter from rsfbclient.

Plamenix documents this requirement to users and ships a sample
`KeyHolder.conf`. Upstream PR to add `isc_dpb_crypt_key` is scheduled
as Foundation-funded contribution back in M1 timeframe.

End-to-end "Plamenix-as-client-keyholder" (driver acts as the key
holder, no sidecar `keyholder.dll` needed) is deferred past
`1.0.0-beta` — see ADR
[`0019-defer-client-keyholder-integration.md`](./adr/0019-defer-client-keyholder-integration.md)
for the three blocking arcs (rsfbclient KeyHolder API, native
keyholder C shim, bundled DbCrypt option).

## M1 scope (`1.0.0-beta`)

**MUST ship:**

- Connect to an already-encrypted database.
- Optional encryption-key textbox in the connect dialog. Stored
  encrypted in the OS keyring opt-in (`keyring` crate).
- Plugin library path selector in the advanced settings of the connect
  dialog (`fbclient.dll`, `fbcrypt.dll` / `keyholder.dll`,
  `openssl*.dll`).
- Encryption status badge driven by `MON$DATABASE.MON$CRYPT_STATE`:
  - `0` — unencrypted
  - `1` — encrypted
  - `2` — decrypt in progress
  - `3` — encrypt in progress
- `encryption_required` flag on connection profiles. When set, refuse
  to connect to databases whose `MON$CRYPT_STATE` is not `1`.
- Short user-facing setup guide ("How to set up Firebird encryption
  plugins for Plamenix").

**DEFER beyond M1:**

- `ALTER DATABASE ENCRYPT / DECRYPT` UI (M2: Daily DBA tooling).
- Key generation and rotation flows (M2).
- EPF-specific affordances (blocked on EPF access).
- Live encrypt / decrypt progress via `MON$CRYPT_PAGE` (M2 monitoring
  dashboard).
- Automated plugin discovery (M2; manual paths in M1).

## Bundling

- Firebird (IDPL) permits redistribution.
- OpenSSL requires attribution acknowledgement.
- Plamenix bundles fbclient + OpenSSL + plugin-discovery scaffold per
  platform and ships notices in `THIRD-PARTY-NOTICES.md`.
- DLL search order on Windows: fbclient looks in its own `bin/`
  subdirectory for plugins; ship the layout so it works without user
  intervention for the built-in case.

## Risks to de-risk early in M1

- Validate rsfbclient + KeyHolder.conf auto-discovery against a test
  encrypted database. Prove the chain works end-to-end before main UI
  work.
- File rsfbclient upstream issue requesting `isc_dpb_crypt_key`
  exposure; track its resolution. Plamenix can switch to direct
  parameter passing once available.
- Identify whether EPF customers need any preview affordances in M1
  beyond the generic plugin path selector. Foundation funding may
  push specific requests.

## Cross-edition behaviour

| Capability | Desktop | Web |
|------------|---------|-----|
| Bundle fbclient + plugins | Per platform in installer | Server admin installs in fbclient plugin path |
| Encryption key entry | Connect dialog | Connect dialog (per-session) |
| OS keyring | Yes (per user, opt-in) | No — encryption keys remain in-memory per session |
| Encryption status badge | Yes | Yes |
| `encryption_required` flag | Yes | Yes |
