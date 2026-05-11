# 0016. Encryption + OS keyring from day one

Status: Accepted
Date:   2026-05-11

## Context

The MVP at `/Users/zlatan/Projects/firebird` shipped without encryption
support. Encrypted Firebird databases are common in enterprise
deployments (especially Brazil and Eastern Europe), and Plamenix is
backed by the Firebird Foundation, so encryption is a first-class
requirement.

Two related questions:

1. Do we ship encryption in `1.0.0-beta` (M1), or defer it?
2. Do we ship OS keyring integration in M1, or defer it?

## Decision

**Encryption and OS keyring both ship in `1.0.0-beta`.**

Scope is constrained — see `docs/encryption.md` for the full M1
inclusion list. The short version:

- Plamenix can connect to an already-encrypted Firebird database.
- Encryption key entry, plugin path selector, status badge driven by
  `MON$DATABASE.MON$CRYPT_STATE`, and `encryption_required` flag on
  connection profiles all ship.
- `ALTER DATABASE ENCRYPT / DECRYPT`, key rotation flows, and EPF-
  specific UX defer to M2.

OS keyring uses the **`keyring` crate** on desktop, which wraps:

- macOS Keychain (via Security framework)
- Windows Credential Manager
- Linux Secret Service (libsecret / GNOME Keyring / KWallet)

Keyring storage is **opt-in per connection profile**, never automatic.

Web edition has no keyring; keys live in memory for the session only.

## Alternatives considered

- **Defer encryption to M2** — would have shrunk M1 scope but breaks
  the Foundation's premise that Plamenix supports realistic enterprise
  workloads from `1.0.0-beta`. Rejected.
- **Plaintext password storage on disk** — never acceptable. Rejected
  immediately.
- **Custom secret store implementation** — building a cross-platform
  secret store is a tar pit. `keyring` crate is mature, MIT licensed,
  and handles every supported platform.
- **In-memory only, no persistence** — was the MVP behaviour. Pushing
  one notch beyond MVP is what `1.0.0-beta` is for.

## Consequences

- Plamenix depends on the `keyring` crate from M1.
- Encryption documentation and a sample `KeyHolder.conf` ship with M1
  installers.
- Plamenix bundles OpenSSL and Firebird plugin libraries on every
  platform (see `docs/encryption.md`). Increases installer size.
- `THIRD-PARTY-NOTICES.md` includes OpenSSL attribution.
- rsfbclient currently lacks the `isc_dpb_crypt_key` parameter; M1
  works around it via the client-side `KeyHolder.conf` mechanism.
  A Foundation-funded upstream PR is planned within M1 timeframe.
- Web edition forces per-session re-entry of encryption keys, which is
  documented as the security trade-off (no server-side secret store).

## References

- `docs/encryption.md` — full encryption spec.
- `docs/firebird-driver.md` — rsfbclient encryption status.
- `keyring` crate: https://crates.io/crates/keyring
