# Plamenix Project Review & Improvements Plan — 2026-09-15

Independent review written from hands-on experience: over 2026-09-14/15 all
seven open desktop issues were triaged and fixed (PRs desktop#8–#14,
ui#1–#6, core#1–#3), two features landed (SYSDBA default-password probe,
export save-dialog), a local release build was produced from the fixed
sources, and every repo was exercised end-to-end. This document **builds on**
the [2026-08-06 architecture review](./architecture-review-2026-08-06.md) and
its [remediation plan](./remediation-plan-2026-08-06.md) — waves 0–5 landed,
waves 6–7 remain — and deliberately **does not re-litigate** the 49 findings
there. Scope here: engineering process, CI/release engineering, cross-repo
consumption, developer experience, and performance/product gaps observed
post-beta. Nothing below duplicates the August review; the two findings that
touch its items are marked.

---

## 1. Where the project stands

The post-beta state is strong in the ways that are hardest to retrofit:

- **Issue velocity with tests.** All eight post-release issues were fixed
  within days, each with regression tests at the layer that owns the bug
  (driver, vendored driver, UI library, shell). No fix was a workaround.
- **A real test culture where it counts.** `plamenix-ui` runs 1,048 tests;
  `plamenix-core` pins driver behaviour with engine-gated live suites
  against real Firebird 2.5–5.0; the desktop suite guards the failure
  policies (keyring failover, secret-store semantics).
- **Documentation discipline.** Per-repo `CLAUDE.md`, ADRs, capability
  model, plugin authoring guide — above average for a project this age.
- **Willingness to fix drivers at the source.** The vendored
  `rsfbclient` patches (exact NUMERIC fidelity, OCTETS columns) are the
  right instinct for a database IDE; see finding F3 for the missing half.

The gaps below are dominated by one theme: **the project's quality lives in
its developers' hands, not in its pipeline.** Nothing automated guards it.

---

## 2. New findings

### F1 · [HIGH] No CI exists on any repository

Only `plamenix-desktop` has a workflow (`release.yml` — a build/publish
matrix). `plamenix-core`, `plamenix-ui`, `plamenix-web`, and `plamenix`
have none. `docs/git-workflow.md` requires main to stay green, but main is
**not branch-protected** (verified via API: 404 on the protection
endpoint), and there is no CI to make "green" meaningful. Consequences
already visible on `main` today:

- `plamenix-desktop`: ~40 pre-existing `cargo clippy -D warnings` errors
  (pedantic/nursery profile, Rust 1.95).
- `plamenix-ui`: 314 eslint errors — including a broken config
  (`eslint.config.js:45` duplicate key `languageOptions`) and the
  type-check project service unable to parse any `*.test.tsx` file
  (tsconfig excludes tests), so lint is failing at the tooling level, not
  just the code level.

**Fix.** Add a test+lint workflow per repo (the desktop `release.yml`
already documents the sibling-checkout job to copy), start
non-blocking, then flip to required as the baselines below are burned
down. Add Firebird service containers (2.5 and 5.0 matrix) so the
`--ignored` live suites in `plamenix-db` actually run somewhere. Enable
branch protection once green.

### F2 · [HIGH] Cross-repo consumption is path/link-based; nothing is published

`plamenix-ui` is consumed via `link:../plamenix-ui`, `plamenix-core` via
eight Cargo `path` dependencies. The release workflow reconstructs the
sibling layout with a PAT (its comment notes the secret becomes deletable
now the repos are public — it can be). Consequences: every cross-repo
feature requires coordinated merge ordering (this week's export-sink work
was ui#6 → desktop#13 by hand), external contributors cannot build the
desktop shell at all, and the web edition depends on unpublished local
paths too.

**Fix.** The repos are public — publish `@plamenix/ui` to npm and swap
`link:` for a SemVer range (the repo's own docs planned exactly this).
Consider publishing `plamenix-types`/`plamenix-db` to crates.io or pinning
releases by tag per repo.

### F3 · [MEDIUM-HIGH] Vendored driver patches have no upstream strategy

Two vendored crates (`rsfbclient-native`, `rsfbclient-rust`) carry
PLAMENIX PATCH markers: exact NUMERIC scale fidelity, OCTETS columns as
bytes (core#1), plus the dyn-load resolver. `docs/firebird-driver.md`
records that upstream reports were *drafted*, but there is no owner, no
tracking issue, and no rebase procedure — every future `rsfbclient`
upgrade re-applies these by hand and risks silent loss.

**Fix.** Open upstream issues/PRs against rsfbclient 0.26 for the
behavioural patches (the OCTETS fix and the numeric-scale patch are
generally useful, not Plamenix-specific). Keep the vendored crates as
fallback, and add a `vendor/README.md` listing each patch, its upstream
status, and the rebase checklist.

### F4 · [MEDIUM] Schema describe latency is O(round-trips), not O(tables)

`run_describe_schema` runs one large join over `RDB$RELATIONS` ×
`RDB$RELATION_FIELDS` × `RDB$FIELDS` (fine), but **samples every generator
with a separate `SELECT GEN_ID(...) FROM RDB$DATABASE` round-trip**
(`rsfb/mod.rs:1227`), plus separate queries for primary keys, procedures,
triggers, generators, domains, and functions — all sequential on one
connection. On a remote server with 100+ generators this is hundreds of
serial round-trips: the "a minute or two with 200 tables" of issue #2.
The loading spinner (ui#1) hides it; it does not shorten it.

**Fix directions** (in rising effort): batch generator values into one
`EXECUTE BLOCK` returning name/value pairs; sample generator values
lazily when the Generators section is expanded instead of at describe
time; measure with a large synthetic fixture so regressions are caught.

### F5 · [MEDIUM] Release engineering sharp edges

- The version string `1.0.0-beta` **breaks the WiX/MSI target** ("pre-release
  identifier must be numeric-only" — reproduced locally); NSIS bundles fine,
  so the Windows MSI silently does not exist.
- Artifacts are unsigned (documented in `release.yml`); SmartScreen/Gatekeeper
  friction for every user.
- No changelog automation; release notes are hand-written.
- One version string is duplicated across five repos and must move in
  lockstep (it was aligned manually once already).

**Fix.** Move to numeric pre-releases (`1.0.0-beta.1`) or drop the msi
target; adopt conventional-commit → changelog generation; decide the
signing story (even self-signed + documented fingerprint beats unsigned).

### F6 · [MEDIUM] Developer bootstrap is three undocumented steps

`just setup` assumes `plamenix-core/` and `plamenix-ui/` are already
cloned as siblings and does not populate `resources/fbclient`. First run
fails with an opaque missing-fbclient panic (the metadata store needs a
client library) — this cost real time even for a reviewer who had read
the docs, and the README only mentions it as of desktop#11.
`engines.node >= 24` warns but does not stop Node 22.

**Fix.** Add `just bootstrap` (clone siblings, `fetch-fbclient`, install,
fetch) and set `engine-strict=true` in `.npmrc`. One command, reproducible
from a clean machine.

### F7 · [MEDIUM] Line-ending and editor hygiene churns every diff

No `.gitattributes`; committers run `core.autocrlf=true`, so `cargo fmt`
rewrites whole files' endings, `rustfmt --check` fails repo-wide, and
`generated.ts` carries mixed CRLF/LF. Every Rust diff this week carried
spurious whole-file churn risk.

**Fix.** Add `.gitattributes` (`*.rs`, `*.ts`, `*.tsx`, `*.toml`, `*.md`
→ `text eol=lf`; icons/packages binary), an `.editorconfig`, and a
one-time renormalize commit (`git add --renormalize .`).

### F8 · [LOW-MEDIUM] Issue intake has no structure

All seven launch issues arrived without versions, engine, OS, or logs;
every one needed a follow-up question (or a repro from context) before
work could start. `.github/ISSUE_TEMPLATE` does not exist. Discussions are
disabled.

**Fix.** Add a bug-report issue form (app version, Firebird engine+version,
OS, connection mode, minimal repro) and enable Discussions for the
roadmap conversations the meta repo's docs invite.

### F9 · [LOW] Web edition error transparency parity (unverified)

The desktop transport wrapped every failure in
`Tauri command 'x' failed` and hid the cause until desktop#8. The web
edition's fetch transport appears to wrap errors the same way
(`packages/client/src/transport/fetch.ts`); not verified end-to-end, but
the same one-line fix almost certainly applies.

### F10 · [LOW] No diagnostics story for bug reports

No command to export a diagnostic bundle (app version, engine versions,
sanitised settings, recent error log). Combined with F8 this makes
remote debugging conversational. The tracing infrastructure already
records everything needed; it is just not reachable by users.

---

## 3. Alignment with the 2026-08-06 review

- Waves 0–5 of the remediation plan are confirmed landed (this session's
  work built directly on their output — the shared `use-connection-actions`
  hook and `use-session-refreshers` are where two of this week's fixes
  landed, exactly as that plan intended).
- **Waves 6–7 remain open** and are carried into the plan below: the
  App.tsx orchestration de-duplication, transport v2 (cancellation + push
  channel), and the docs reconciliation (capability grammar, WIT world
  tiering, subprocess escape hatch).
- None of the eight post-beta issues overlap the August review's 49
  findings — they are all new user-facing surface, which is expected and
  healthy for a fresh release.

---

## 4. Improvements plan

### P0 — this week (pipeline foundations)

1. **CI on every repo.** Copy the sibling-checkout job from
   `release.yml`; run `pnpm test` + `tsc` for ui, `cargo test` for
   core/desktop with a Firebird 5 service container, adding the 2.5
   matrix leg where the gated suites support it. Start
   non-blocking; flip to required as each baseline is burned down.
2. **Burn the lint baselines.** Fix the two ui eslint-config defects
   (duplicate key, test-file project membership), then clear the 314
   errors (mostly mechanical). Desktop clippy: clear the ~40 errors or
   scope the nursery lints; target `-D warnings` green on 1.95.
3. **Hygiene commit.** `.gitattributes` + `.editorconfig` +
   `git add --renormalize .`.
4. **Issue intake.** Bug-report issue form (version, engine, OS, mode,
   repro); enable Discussions.
5. **Branch protection on main** once CI is required.

### P1 — this month (release & plumbing)

6. Publish `@plamenix/ui` to npm; swap `link:` for SemVer in desktop/web;
   delete the PAT secret from `release.yml`.
7. Numeric pre-release version (`1.0.0-beta.1`) or drop msi; changelog
   generation from conventional commits.
8. `just bootstrap` one-command dev setup; `engine-strict`.
9. Web transport error parity (port desktop#8's cause-surfacing).
10. Schema describe performance: batch generator sampling (EXECUTE
    BLOCK), lazy generator values, and a perf fixture to catch
    regressions (issue #2's root cause).

### P2 — next quarter (strategy)

11. **Wave 6:** de-duplicate the two `App.tsx` orchestration copies into a
    headless hook in `plamenix-ui`; transport v2 (cancellation + push
    channel) — this also unlocks a query-cancel button.
12. **Wave 7:** docs reconciliation (capability grammar, WIT tiering,
    subprocess escape hatch decision) and the adversarial re-review.
13. Upstream the vendored `rsfbclient` patches; document the rebase
    procedure in `vendor/README.md`.
14. Signing (Windows cert / macOS notarization) and a Tauri updater
    channel for beta users.
15. Diagnostic-bundle command for bug reports (F10).
16. Decide the web edition's beta scope (auth/deploy path) — remediation
    plan §3 decisions Q1–Q3.

---

## 5. Suggested tracking

Convert P0 items 1–5 into issues on their respective repos this week, with
P1/P2 items as milestones (`1.0.0`, `1.1`). The Aug-06 review's findings
tracker and this plan can share one project board; the definition of done
from remediation §6 (production call path + shell-level test) should be
quoted in the milestone descriptions.
