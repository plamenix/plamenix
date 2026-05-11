# 0019. Defer Plamenix-as-client-keyholder integration

Status: Accepted
Date:   2026-05-11

## Context

`docs/encryption.md` describes Plamenix's M1 encryption posture: connect
to already-encrypted databases, surface `MON$CRYPT_STATE`, enforce
`encryption_required`, and capture an encryption key in the connect
dialog (optionally persisted via the OS keyring).

A natural follow-up — and a recurring user request — is "end-to-end
DbCrypt": Plamenix itself acts as the client-side `KeyHolder`, ships
the key to the server's `DbCrypt` plugin, and never relies on a
sidecar `KeyHolder.conf` + `keyholder.dll` installation. The user
asked whether this could land in the current session.

Three concrete blockers prevent shipping that end-to-end picture in
the `1.0.0-beta` window:

1. **rsfbclient pure-Rust mode has no KeyHolder API.** The wire-
   protocol implementation in `rsfbclient-rust` never carried the
   crypt-key handshake. Adding it requires an upstream PR that
   teaches the Rust wire protocol to participate in
   `IDbCryptPlugin` ↔ `IKeyHolderPlugin` exchanges, including the
   post-auth key transport encrypted by the wire crypt key.
2. **Native mode needs a C++ keyholder shim.** `fbclient` looks up
   `IKeyHolderPlugin` implementations in its plugin directory and
   loads them as shared libraries. A Plamenix-resident keyholder
   means shipping a small C++ `.so`/`.dll`/`.dylib` that proxies the
   key callback back into the host process. We do not currently ship
   any C++ artefacts and have no per-platform cross-compile pipeline
   set up for one.
3. **Server-side DbCrypt is still BYO.** The reference Docker image
   (`firebirdsql/firebird:5`) ships no `DbCrypt` plugin. The two
   widely-used real plugins (IBSurgeon EPF, IBExpert) are
   commercial. Without a documented installable open-source option,
   we cannot ship a single-command demo path even after blockers 1
   and 2 are cleared.

## Decision

**Defer client-keyholder integration past `1.0.0-beta`.** Track the
work as three independent arcs that can land in any order, each
unblocking a portion of the end-to-end picture:

| # | Arc | Owner | Output |
|---|-----|-------|--------|
| 1 | rsfbclient KeyHolder API (pure-Rust) | Foundation-funded upstream PR | rsfbclient ≥ 0.27 exposes a `KeyHolder` callback hook on the connection builder |
| 2 | `plamenix-keyholder` C shim (native) | Plamenix | Small C++ project producing `plamenix_keyholder.{so,dll,dylib}` that bridges fbclient's `IKeyHolderPlugin` into a Plamenix-supplied callback |
| 3 | Bundled DbCrypt option | Plamenix docs + packaging | Decision matrix and install path for one open-source DbCrypt plugin (community-maintained option, or document IBSurgeon EPF as the supported commercial path) |

The M1 `KeyHolder.conf` mechanism described in `docs/encryption.md`
remains the supported integration path until at least arcs 1 + 2
land.

## Alternatives considered

- **Build a stub XOR DbCrypt + KeyHolder pair for demo purposes.**
  Educational, not production-safe. Risk of users mistaking the
  stub for a usable plugin outweighs the value. Rejected.
- **Ship a real AES-backed DbCrypt plugin from Plamenix.** Multi-
  week engineering effort with cryptographic-design responsibility,
  audit needs, and per-platform signing. Outside Plamenix's scope as
  an IDE; the ecosystem already has commercial plugins that own this
  surface. Rejected.
- **Patch rsfbclient ad hoc in our fork without upstreaming.**
  Workable short-term but compounds the cost of every future
  rsfbclient bump. Rejected in favour of a Foundation-funded
  upstream contribution.

## Consequences

- M1 users who need encrypted connections must continue installing
  `keyholder.dll` + `KeyHolder.conf` in fbclient's plugin path. The
  setup guide remains the supported workflow.
- Pure-Rust mode does not work against encrypted databases that
  require a client-supplied key until arc 1 lands. The connect
  dialog's "Pure-Rust mode" checkbox grows a footnote noting this
  once we ship the related UI polish.
- `MILESTONES.md` gains an `M2: Encryption end-to-end` entry that
  groups the three arcs.
- The end-to-end demo path remains "user installs a third-party
  DbCrypt plugin server-side"; we will not gate the M1 release on
  shipping a server-side plugin ourselves.

## References

- `docs/encryption.md` — M1 encryption spec (kept current).
- ADR 0016 — Encryption + OS keyring from day one.
- `docs/firebird-driver.md` — rsfbclient native + pure-Rust
  backends.
- Firebird `IDbCryptPlugin` / `IKeyHolderPlugin` interfaces:
  `src/include/firebird/Interface.h` in the upstream Firebird repo.
