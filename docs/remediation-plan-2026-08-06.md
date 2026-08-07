# Plamenix — Remediation Plan to 1.0.0-beta

Companion to `ARCHITECTURE_REVIEW_2026-08-06.md` (13 critical + 36 major confirmed findings).
Written 2026-08-06 after independently re-establishing build/test truth on this machine.

---

## 0. Status — Wave 0 complete (2026-08-06)

All five dirty repos are committed on branch `feat/plugin-suite`
(`docs/plugin-suite` in the meta repo), and every target now compiles.

| Target | Before | After Wave 0 |
|---|---|---|
| plamenix-core | 198 pass, 2 test targets unbuildable | **225 pass, 0 fail** |
| plamenix-desktop | tsc + cargo clean | unchanged |
| plamenix-ui | 717 pass, 4 fail | unchanged (the 4 are Wave 1/2 work) |
| plamenix-web | **does not build** | **all 4 packages typecheck; server 57/57** |

Branches rather than `main`, because `docs/git-workflow.md` requires main
to stay green and the tree did not build. Merge when the suite is green.

## 1. Verified baseline as found (measured, not claimed)

| Target | Compiles | Tests |
|---|---|---|
| plamenix-core (9 crates, libs) | yes | 198 pass, 0 fail |
| plamenix-core `plamenix-db` tests | **no** — `crypt.rs:18`, `smoke.rs:12` missing `embedded` | cannot run |
| plamenix-desktop `src-tauri` (all targets) | yes | — |
| plamenix-desktop TypeScript | yes | — |
| plamenix-ui TypeScript | yes | 717 pass, **4 fail** in 2 files |
| plamenix-web `fbclient-node` (lib) | **no** — `src/lib.rs:132`, `:401` missing `embedded` | cannot run |
| plamenix-web `plugin-host-node` | yes | — |
| plamenix-web client TypeScript | **no** — `App.tsx:414` missing `embedded` | — |

**The desktop edition builds. The web edition does not build at all** — neither its native DB binding nor its client.

### The two live proofs that "done" was mis-defined

1. **1,804 of 4,991 lines (36%) of the plugin host have zero call sites in either shell.** Measured: `EpochTicker`, `InstanceRegistry`, `Supervisor`, `EventBus`, `handle_event` — all return 0 hits across `plamenix-desktop/src-tauri/src` and `plamenix-web/packages/plugin-host-node/src`. Their own unit tests are part of the 198 that pass.
2. **`plamenix-ui` ships 4 failing tests that document known-broken behavior**, left red rather than fixed:
   - `tabs-store.test.ts` — expects the persisted password to be `''`, gets `'masterkey'`.
   - `default-sections.test.ts` (×3) — expects 4 dashboard sections, code registers 2 (`tips`, `recent-queries`); `Connection` and `Entity counts` were never written. I5.10 is marked done.

Root cause behind both: **the tracker's definition of done was "the module exists and its unit tests pass," not "the product calls it."** Unless that definition changes, the same gap regrows. See §6.

### One finding is worse than the review reported

`plamenix-ui/src/db/tabs-store.ts:187-191` — `sanitiseForm()` does not merely fail to clear the password; it **writes `password: 'masterkey'` into every persisted tab**, and `inflateTab()` (line 216) re-injects it on load. `masterkey` is Firebird's default SYSDBA password. The effect is not leaking the user's secret — it is *injecting a credential* into the form so a user who reloads and clicks Connect authenticates as SYSDBA/masterkey without noticing. The code carries its own instruction: `REMOVE before deploy`.

---

## 2. The 49 findings collapse into 8 root causes

Treating them as 49 independent bugs would triple the work. They are:

| # | Root cause | Findings | Character |
|---|---|---|---|
| A | Plugin runtime is never instantiated — Store dropped after `activate()`, no epoch ticker, no event dispatch, no supervisor | ~13 | one architectural gap |
| B | The `embedded` field rollout was never propagated | 5 | mechanical |
| C | Firebird data fidelity — exact numerics, BIGINT, time zones, schema types | ~6 | type-system change across repos |
| D | SQL statement handling — splitter, SELECT heuristics, `ROWS` injection, no transaction lifecycle | ~5 | bounded, high-confidence |
| E | Web edition was never finished as a product — no auth, no deploy path, no session lifecycle | ~8 | product design, not bugfix |
| F | Plugin trust model is nominal — no signing trust root, self-attested caps and limits | ~6 | design decision + code |
| G | Docs assert behavior the code does not have | ~6 | mostly downstream of A and F |
| H | Shell duplication and dead parallel implementations in the UI | ~5 | refactor |
| I | The destructive write-back path was never reviewed | critic gap | needs a human-eyes pass |

---

## 3. Three decisions only you can make

**DECIDED 2026-08-06.** Answers recorded inline below; §4 and §5 reflect them.

| Question | Decision |
|---|---|
| Q1 web edition | **Localhost-only, single-user** (as recommended) |
| Q2 plugin runtime | **Full runtime including interceptors** — larger than recommended; §4 Wave 4 re-scoped |
| Q3 subprocess hatch | **Delete it** (as recommended) |

My recommendation for each, with reasoning.

### Q1 — Does 1.0.0-beta include the web edition?

Today it does not compile, has **zero authentication on every route** (including SQL execution and plugin admin), lets an unauthenticated request body choose the native library the server `dlopen()`s, never reaps Firebird attachments, buffers whole exports in a process shared by all users, and has 2 tests for the entire server.

**Recommendation: ship it as localhost-only, single-user, with network exposure refused — not as a multi-user web app.**

Bind `127.0.0.1` only and hard-refuse `0.0.0.0`; add Origin/CSRF checks (a page in the user's browser can otherwise reach the local API); remove the request-controlled `dlopen` path; add session reaping and export bounds. That is roughly a week and honors the "two editions" promise. A real auth/multi-tenancy model is a 1.1 project — it is a product design question (who may connect to which server, how credentials are held, what isolation means), not a bug list.

Fallback if you want it simpler: desktop-only beta, web to 1.1.

### Q2 — What is a "plugin" in 1.0.0-beta?

The **TypeScript contribution registry is real and works** — the 9 first-party extractions ride on it and are covered by the 717 passing tests. What is dead is the **WASM runtime**: a plugin can be installed, granted, and activated, then the instance is dropped, so no plugin code can ever run again. No events, no interceptors, no supervision, no CPU preemption.

**Recommendation: wire a minimum real runtime — persistent instance + epoch ticker + event dispatch + supervisor crash handling. Defer interceptors to 1.1.**

The pieces exist and are unit-tested; this is integration, not new subsystem authoring. Plugins are the differentiator you deliberately kept in M1 scope and `docs/plugin-system.md` publicly commits to "first-class plugins from 1.0.0-beta." Shipping a plugin system in which no plugin code can run after activation would cost more credibility than the delay. Estimate 2–3 weeks; the risk is wasmtime `Store` lifetime and `Send`/`Sync` across Tauri state, which `instance.rs` and `concurrency.rs` were written for but never exercised.

Fallback: ship "activation-only" plugins, document the runtime as 1.1, and **delete or feature-gate the 1,804 dead lines** so the codebase stops asserting a runtime it does not have.

### Q3 — The `runtime.subprocess` escape hatch: keep or delete?

`PLUGIN_ARCHITECTURE.md` declares "no `process` capability ever" and records it as a signed-off decision — twice. The code ships it: a plugin's own manifest self-attests the capability and names an arbitrary native binary in its bundle, which the host spawns unconfined. The documented mitigation (a stricter install-time warning) was never implemented.

**Recommendation: delete it for beta.** It voids the sandbox story that is the plugin system's main safety claim, it is desktop-only so it already breaks the tri-state portability promise, and no first-party plugin needs it. Removal is ~163 lines plus a capability variant and a manifest flag, and it makes the canonical document true again. If a real need appears, §17.7 already prescribes the correct shape: narrow host-mediated interfaces, not shell-out.

---

## 4. Wave plan

Waves 0–2 are unconditional — they hold under every answer to Q1/Q2/Q3. Start them regardless.

### Wave 0 — Preserve and make the signal honest (½ day)

1. `.gitignore` the stray `plugin-grants.sqlite*` artifacts in `plamenix-web`.
2. **Commit the current state as-is across the 5 dirty repos**, broken tests and all, with both review documents alongside. 2.5 months of work living only in working trees is the largest unmanaged risk in the project and it is unrelated to any code quality question.
3. Fix the 5 `embedded` sites (`crypt.rs:18`, `smoke.rs:12`, `fbclient-node/src/lib.rs:132` and `:401`, web `App.tsx:414`) and regenerate `generated.ts`.
4. Re-run everything; record the true green/red baseline in the tracker.

After this, "does it build" becomes a meaningful signal for the first time since May.

### Wave 1 — Data fidelity (3–5 days) — PARTIALLY LANDED 2026-08-06

A DB tool that silently changes values is not credible, regardless of what else ships.

**Done:**

- ✅ Inverted TIME/TIMESTAMP WITH TIME ZONE offset decoding. Firebird encodes an offset zone as displacement + 1440, so 1440 is UTC; the code treated 0–1439 as east and 1440–2879 as west, inverting every offset (a `+02:00` value read as `-02:00`). Fixed with tests. The vendored crate could not host tests at all — it is patched in, not a workspace member — so it is now a standalone workspace and `just test` depends on a `test-vendor` recipe.
- ✅ `masterkey` credential injection in `tabs-store.ts`, including clearing secrets on rehydrate so entries already in localStorage are not trusted.
- ✅ Dashboard sections reconciled with the shipped Welcome surface (the tests, not the code, were wrong).

**Still open — exact numerics.** Investigated 2026-08-06; **the approach in this plan needs revision and a decision.**

The original recommendation was "represent NUMERIC and BIGINT as strings on the wire." Investigation shows that is not sufficient on its own:

1. The vendored driver coerces NUMERIC/DECIMAL to `SQL_DOUBLE` at describe time (`row.rs`, the `sqlscale != 0` branch), so precision is lost inside the driver, before any wire type applies. It already has an exact `apply_scale(i64, i8) -> String` helper used for ARRAY elements, and already surfaces FB4 types (INT128, DECFLOAT, TZ) as `SqlType::Text` — so an exact path exists and has precedent.
2. But `SqlType` is defined in **`rsfbclient-core`, which is not vendored** — only `rsfbclient-native` is. Its variants are Text / Integer(i64) / Floating(f64) / Timestamp / Binary / Boolean / Null. There is no exact-decimal variant, so the driver's only lossless channel today is `Text`, and `plamenix-db` then cannot tell a NUMERIC from a VARCHAR.
3. Routing NUMERIC through `Text` anyway is a visible regression: `ResultTable.isNumeric()` keys off `cell.type === 'integer' || 'float'`, so those columns would left-align, sort lexically, and lose the numeric inline editor.
4. Separately, `ts-gen` blanket-remaps `i64`/`u64`/`i128` to TS `number`, justified by a comment claiming every Plamenix integer fits in 2^53. That holds for durations and row counts but **not for `ColumnValue::Integer`, which carries arbitrary BIGINT column values**, nor for generator values.

**Design, revised after upstream research on 2026-08-06.** An earlier draft proposed vendoring `rsfbclient-core` to add a `SqlType::Decimal` variant. **That is unnecessary — do not do it.** Research findings:

1. The `SQL_DOUBLE` coercion is **upstream rsfbclient behaviour, not a Plamenix defect**. Verified against upstream master, and it is present in *both* backends: `rsfbclient-native/src/row.rs` and `rsfbclient-rust/src/xsqlda.rs`, the latter commenting "Is actually a decimal or numeric value, so coerce as double". So it affects `ConnectMode::PureRust` and `ConnectMode::Native` alike.
2. **rsfbclient 0.27.0 shipped 2026-07-03**, newer than the pinned 0.26, but contains only a Windows CI fix and a pure-Rust batch-fetch optimisation. Upgrading does not help. No upstream issue exists for the precision loss; the maintainer is active and merges community PRs.
3. **`rsfbclient_core::Column` already exposes a public `raw_type: u32`** carrying the Firebird type code captured *before* coercion — both backends populate it. `plamenix-db` currently discards it, keeping only `name`. That field is the discriminator: an integer-family `raw_type` arriving as `Floating` can only be a scaled NUMERIC/DECIMAL. No vendored type is needed to tell them apart.

**The problem splits into two halves with very different costs. Do them in this order.**

**Half 1 — BIGINT. ✅ DONE 2026-08-06.** Landed as `plamenix_types::exact_int` plus `plamenix-ui/src/db/exact-int.ts`. `ColumnValue::Integer` and `GeneratorInfo.current_value` now cross the wire as exact decimal text; the ts-gen remap is documented as covering only bounded counters. Both generator editors previously gated on `Number.isSafeInteger` and so refused any generator past 2^53 — they now accept the full signed range. CSV, copy-cell and SQL literals are unchanged; JSON emits integers as quoted text uniformly; XLSX emits real numbers while they fit and falls back to text beyond 2^53. Result-grid ordering was unaffected because sorting and filtering are server-side SQL. Original description follows.

**Half 1 — BIGINT. No vendoring, entirely Plamenix's own types.** `ColumnValue::Integer(i64)` reaches TS as `number` because of the blanket `ts-gen` remap. Demonstrated: Firebird's max BIGINT `9223372036854775807` arrives in the UI as `9223372036854776000`, and `9007199254740993` silently becomes `…992`. This hits BIGINT primary keys, generator values, and MON$ counters — common columns, unambiguous corruption. Fix: carry exact integers as strings on the wire, narrow the remap to the genuinely bounded types, correct the comment asserting the false premise, and update the grid, sorting, filters, exports, and `inline-edit.ts`. **This is the higher-severity half and it is unblocked.**

**Half 2 — NUMERIC/DECIMAL. ✅ DONE 2026-08-06.** `rsfbclient-rust` is vendored alongside `rsfbclient-native`; both stop the `SQL_DOUBLE` coercion and render the scaled integer as exact text. `plamenix-db` discriminates on the preserved `raw_type` and emits `ColumnValue::Decimal(String)`. `rsfbclient-core` was **not** vendored. The upstream report is drafted but unfiled at `upstream-rsfbclient-numeric.md`; these patches are the stopgap until it lands. Original description follows.

**Half 2 — NUMERIC/DECIMAL. Needs a driver patch.** Add `ColumnValue::Decimal(String)`, discriminate on `raw_type`, and stop the coercion in the already-vendored native backend, keeping INT64 plus the scale and rendering through the `apply_scale` helper that file already uses for ARRAY elements. For the pure-Rust backend, which is **not** vendored and is the default in `DEFAULT_FORM`, choose one:

- **Upstream it (recommended).** File the issue and a PR against `fernandobatels/rsfbclient`. The project is funded by the Firebird Foundation, the maintainer merges community contributions, and this removes vendoring debt rather than adding it. Vendor temporarily only if the beta cannot wait for a release.
- Vendor `rsfbclient-rust` as a second patched crate. Still does **not** require vendoring `rsfbclient-core`.

**Severity nuance, so this gets prioritised honestly:** Rust and JS both print floats with shortest-round-trip formatting, so a small value like `12.34` still *displays* as `12.34`. The NUMERIC damage concentrates in values past ~15–16 significant digits — NUMERIC(18,4) being the standard Firebird money type — plus arithmetic and re-serialisation into exports. The BIGINT half, by contrast, corrupts ordinary id columns outright, which is why it goes first.

### Wave 2 — SQL execution correctness (3–4 days) — IN PROGRESS

**Done 2026-08-06:** the statement splitter now honours `SET TERM` and BEGIN/END nesting, so procedures, triggers and `EXECUTE BLOCK` run from the editor; the conflated SELECT predicate is split into `accepts_row_limit` (SELECT/WITH — the `ROWS` grammar) and a three-way `statement_shape` (Cursor / OutputParams / NoResultSet) shared by the driver and both shells. `EXECUTE PROCEDURE` goes through `execute_returnable` because it returns output parameters with no cursor. Verified end to end against the Firebird 5.0.4 container in `crates/plamenix-db/tests/procedural_sql.rs`.

**Transactions done 2026-08-06.** Manual commit alongside autocommit, end to end. Two attachments per session: `work` for the user's statements, and a read-only read-committed `meta` for Plamenix's own schema/dashboard/ping reads, so background chatter never joins the user's transaction and browsing holds nothing open. Isolation (read-committed or snapshot) and lock resolution (`WAIT` with optional timeout, or `NO WAIT`) are exposed; `consistency` is omitted deliberately, since it takes table-level locks. Savepoints are out by decision — additive later, no rework forced. Verified on Firebird 5.0.4 **and** 2.5.9.

**FB 2.5 version gating done 2026-08-06.** Probing both engines showed `MON$OWNER` and `MON$CRYPT_STATE` are the only monitoring columns Plamenix reads that 2.5 lacks. Each session records the engine major version, probed at attach; `MON$OWNER` is substituted below 3.0 and `crypt_state` answers without querying, since 2.5 has no native encryption at all. Covered by `tests/version_gating.rs` on both containers.

**Wave 2 is complete.**

Original description follows.

- `split_statements` needs `SET TERM` and `BEGIN…END` awareness. Today procedures, triggers, and `EXECUTE BLOCK` cannot be run from the editor at all — a headline feature of any Firebird IDE.
- Unify the two divergent `is_select_like` heuristics and stop injecting `ROWS` into `EXECUTE BLOCK` / `EXECUTE PROCEDURE`.
- Decide the transaction story. Today every statement auto-commits and a user-typed `COMMIT`/`ROLLBACK` fails. Explicit transaction control is table stakes for a DBA tool; if it must wait, say so in the docs rather than leaving `COMMIT` erroring.
- Version-gate the `MON$` queries so the dashboard works on FB 2.5 as documented.
- Fix the 2-of-4 dashboard sections, or delete the tests' expectation and the claim.

### Wave 3 — Plugin trust surface — COMPLETE 2026-08-07

Subprocess hatch removed; manifest resource limits clamped to host ceilings; grants refused unless the manifest declared the capability (both editions); `.plx` extraction bounded by entry count, per-entry and total size, with the copy capped rather than trusting the declared header; `VerificationOutcome::Valid` renamed `SelfSigned` and the install dialog's green "Signature verified" replaced with "Signed — publisher not verified". Marketplace and URL install were cut from scope entirely on 2026-08-07, which removed the trust-root work this wave originally carried.

Original description follows.

### Wave 3 — Plugin trust surface (2–3 days — DECIDED: delete the subprocess hatch)

Delete `subprocess.rs`, the `RuntimeSubprocess` capability variant, the `runtime.requires_subprocess` manifest flag, and the `entry_points.subprocess` handling; drop the escape hatch from `plugin-system.md`, ADR 0003, and `capability-model.md` so the canonical "no process capability ever" statement becomes true again.

Then: signing needs a trust root (today any attacker-generated key reports "Signature verified"); sandbox limits must be host-clamped rather than manifest-chosen; grants must be rejected when they exceed what the manifest requested; `.plx` extraction needs decompressed-size limits.

### Wave 4 — Plugin runtime, full scope including interceptors (4–6 weeks — DECIDED: full runtime)

Q2 was decided as **full runtime including interceptor chains**, larger than the minimum I recommended. Re-scoped in dependency order:

1. **Persistent instances.** Keep the `Store` alive in `InstanceRegistry` instead of dropping it after `activate()`. Load-bearing — everything below depends on it. The hard part is wasmtime `Store` lifetime and `Send`/`Sync` across Tauri managed state and the NAPI boundary; `instance.rs` and `concurrency.rs` were written for exactly this and have never been exercised in production.
2. **Epoch ticker** spawned by both shells, so the 100ms/5s preemption guarantee actually fires.
3. **Event dispatch** — call `handle-event` on live instances, and reconcile the shipped bus with the topic grammar, dot-globs, and `schemaVersion` that `plugin-events.md` documents but no bus implements.
4. **Supervisor on the crash path** — restart policy and the 3/60s crash budget reaching DISABLED, driven by real faults rather than test fixtures.
5. **In-flight cap** enforced through the real call path.
6. **Interceptor chains** — narrower than first estimated. `plamenix-ui/src/interceptors/` already ships a tested TypeScript framework (`chain.ts` plus eight chains: connection-opening, query-executing, cell-committing, row-inserting, row-deleting, editor-saving, export-starting, schema-action-applying), so first-party code can already intercept. The gap is the same shape as the event gap: **no WIT exports, so WASM plugins cannot participate.** Scope is defining the interceptor exports in the WIT contract and bridging them to the existing TS chain, not designing the chain semantics from scratch. Roughly a week rather than two.
7. **WIT world enforcement** — recognize declared worlds, refuse unknown ones, link per-world imports, cross-check grants against the world surface. Today only `plugin-minimal` is bound and `validate_world_identifier` is pure syntax, so a `db-reader` plugin fails with a raw linker error instead of the documented clean refusal.

Items 1–5 integrate existing tested code. Items 6–7 are new design work.

**Items 1–5 are done, and items 2, 4, and 5 are now demonstrated rather than asserted.** They had been landing with their guarantees proven by construction — an epoch deadline set by hand, `on_exit` called directly, arithmetic checked — which is the same module-local definition of done that §6 exists to retire. A fixture that misbehaves on purpose (`examples/misbehaving-plugin`, driven by `tests/misbehaving_plugin.rs`) now spins, traps, and allocates until refused, through the real dispatch path.

Two things came out of firing them:

- **Failures were indistinguishable to the host.** `DispatchOutcome::Failed` carried `err.to_string()`, which on a wasmtime error is only the outermost layer; the reason lives in the error's source. A runaway loop, a panicking plugin, and a refused allocation all reached the supervisor as the same opaque string, so the assertion "this plugin was *preempted*" could not be written. `Failed` now carries a classified `CallFailure`. Note that the deadline-to-`Trap::Interrupt` mapping is undocumented by wasmtime and rests on that test.
- **Preemption depends on the host embedding, not on this crate.** The epoch ticker is a Tokio task and a spinning plugin holds its thread without yielding, so on a current-thread runtime the ticker never runs and the call never ends. Both shells happen to use multi-threaded runtimes; nothing required them to. Recorded in `plugin-architecture.md` §9.

**Items 6 and 7 are now done too, so Wave 4 is complete.**

Item 6 shipped `intercept: func(point, context-json) -> interception` in the WIT, manifest validation for `[[contributions.interceptors]]`, a host-side chain with the same semantics as the TypeScript one, and a bridge that registers plugins into the existing chains from both shells. The design deviates from the sketch in `plugin-interceptors.md` — one dispatching export rather than eight named ones, a JSON context rather than a host-owned resource — and that doc now records both the reasons and what it costs.

Item 7 turned the WIT header's three promises into enforcement. Two consequences worth carrying forward:

- **No wasm plugin can currently hold any capability.** Only `plugin-minimal` is linkable, because the imports the higher tiers expose have no host implementation, and minimal exposes none of the imports a capability would exercise. Capability grants are reachable today only for UI-only plugins. The permissions dialog has correspondingly little to show for wasm plugins, which is honest rather than new — it was previously showing grants that could never be exercised.
- **This is a breaking change for existing manifests.** A manifest that requests a capability without declaring a world that exposes it is now refused. Six test fixtures and the shipped `hello` plugin were all in that state; `hello` was asking users to approve db, notify, and clipboard access for a plugin whose code logs one line.

Two divergences found along the way and not yet fixed, both Wave 7 material: the capability grammar the parser implements is dot-separated (`db.write.any`), while `plugin-interceptors.md` and `capability-model.md` use a mixed dotted/colon form (`db.write:execute`) that nothing parses; and `plamenix-web/packages/client` has no test files at all, so `pnpm -r test` fails there on an empty run.

### Wave 5 — Web edition (1 week for localhost-only, per Q1)

Localhost binding with explicit refusal to bind externally, Origin/CSRF checks, remove the request-controlled `dlopen`, session reaping with idle timeout, bounded exports, and an actual deployment path (the server serves no static assets today, and production CORS is off, so the SPA is reachable neither same-origin nor cross-origin).

### Wave 6 — Architecture improvements (1 week)

The genuine design wins, as opposed to defect repair:

- **~1,560 lines of shell orchestration are duplicated verbatim between the two `App.tsx` files and have already drifted.** That belongs in `plamenix-ui` as a headless orchestrator hook. This is the single highest-leverage refactor in the codebase and it prevents the drift from compounding.
- **Transport contract v2**: add cancellation, a host→client push channel, and a typed error shape. Long queries currently lock the tab with no way out, and the missing push channel is part of why plugin events have nowhere to go.
- Delete `ResultTable`'s second live copy of all five export formats, now that the builtins exist.
- Make feature availability independent of unrelated component mounts (the SQL Format button never appears in the desktop query workflow because registration is mount-scoped).

### Wave 7 — Docs reconciliation, human-eyes pass, re-review (3–4 days)

- Rewrite the capability grammar, event catalogue, WIT world tiering, and manifest `[contributions.ui]` sections to match shipped reality — most of this is mechanical once Q2/Q3 are decided.
- **Hand-read `plamenix-ui/src/db/inline-edit.ts`.** It builds the UPDATE/DELETE statements — the one place the product destroys user data. The NUL half of this item is done: `e54cd77` replaced the literal NUL sentinels with `\u0000` escapes, and a sweep of all six repos now finds no source file with a NUL byte in it. What remains is coverage. `inline-edit.test.ts` has eleven tests and not one of them touches `buildBulkUpdateSql` or `buildBulkDeleteSql`, which are the multi-row destructive paths.
- Final adversarial re-review before tagging (worth running as a multi-agent pass again — independent skeptics are the point).
- Then I9.13: tag `1.0.0-beta`.

---

## 5. Sequencing rationale

Waves 1 and 2 come before the plugin work even though plugins are the differentiator, because data corruption and an editor that cannot run a stored procedure undermine the product's core claim, and because they are bounded, high-confidence fixes that need no decisions. Wave 3 precedes Wave 4 so the subprocess deletion lands before anything is built on top of it.

**Rough total with the decisions taken: 8–11 weeks**, putting 1.0.0-beta in October 2026. Wave 4 dominates at 4–5 weeks. The schedule risk concentrates in Wave 4 item 1 (persistent instances — wasmtime `Store` lifetime across the Tauri and NAPI boundaries, never yet exercised) rather than in interceptors, which turned out to be mostly bridging work over an existing tested TypeScript framework.

If the date needs to come down, the honest levers are deferring Wave 4 items 6–7 to 1.1, or dropping the web edition to desktop-only. Cutting Waves 1–2 is not a lever — they are what makes the tool trustworthy.

## 6. Process change — otherwise this regrows

Adopt as the tracker's definition of done: **an item is done when a production call path reaches it and a test exercises it through the shell.** The current codebase passes 915 tests while 36% of the plugin host is unreachable; that is precisely what a module-local definition of done produces. Two supporting rules:

- A failing test is never left red as documentation of a known gap. Either fix it or delete the claim.
- Any comment saying `REMOVE before deploy` is a release blocker by definition, and something should fail the build while one exists.
