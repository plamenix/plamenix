# Building the web edition

A self-hostable Fastify server plus a React single-page client, sharing
the same UI library and Firebird driver as the desktop application. You
run it; a browser connects to it.

Install everything in [Build prerequisites](./build-prerequisites.md)
first, including the sibling repository layout.

The platform libraries in that document are **not** needed here — there
is no webview. Rust still is: the server reaches Firebird through a
native Node addon compiled from `plamenix-core`.

---

## Layout

A pnpm workspace of three packages:

| Package | What it is |
|---|---|
| `packages/native` | NAPI addon wrapping the Rust driver — the only compiled piece |
| `packages/server` | Fastify backend: sessions, routes, plugin host |
| `packages/client` | React SPA, consuming `@plamenix/ui` over HTTP |

---

## Quick version

```sh
cd plamenix-ui      && pnpm install && pnpm build
cd ../plamenix-web  && just setup && just napi-build && just dev
```

---

## 1. Build the shared UI library first

```sh
cd plamenix-ui
pnpm install
pnpm build
```

The client imports `@plamenix/ui`'s **built output**. A fresh clone has
no `dist/`, and skipping this produces module-not-found errors in the
client that have nothing to do with the client.

## 2. Fetch dependencies

```sh
cd ../plamenix-web
just setup      # pnpm install + cargo fetch
```

## 3. Build the native addon

```sh
just napi-build
```

This compiles Rust into a platform-specific `.node` binary. It is the
slowest step and the one people forget: the server cannot start without
it, and the failure looks like a missing JavaScript module rather than
an unbuilt binary.

Rebuild it after any change under `plamenix-core`. Pure TypeScript
changes do not need it.

## 4. Run it

```sh
just dev
```

Server on `http://127.0.0.1:3000`, client dev server alongside it with
hot reload.

---

## Configuration

Every setting is read once through `loadEnv()`, validated with zod.
There is no `.env.example`; the schema in `packages/server/src/env.ts`
is the source of truth. The ones that matter:

| Variable | Default | Notes |
|---|---|---|
| `HOST` | `127.0.0.1` | Set to `0.0.0.0` to accept connections from other machines |
| `PORT` | `3000` | |
| `AUTH_TOKEN` | — | Bearer token. **Set this before exposing the server.** |
| `AUTH_TOKENS` | — | Several named tokens, when one is not enough |
| `ALLOWED_HOSTS` | — | Host allowlist. See the security note below |
| `LOG_LEVEL` | `info` | |
| `PROFILES_PATH` | `./profiles.json` | Connection profiles. No secrets are stored server-side |
| `METADATA_PATH` | `./plamenix-meta.fdb` | Query history and settings |
| `FBCLIENT_PATH` | — | Only for the native driver; the default pure-Rust mode needs nothing |
| `SESSION_IDLE_MS` | 30 min | Idle sessions are swept |
| `EXPORT_MAX_ROWS` | 1,000,000 | Cap on a single export |

### Before putting it on a network

**Set `AUTH_TOKEN`.** Without it there is no authentication.

**Set `ALLOWED_HOSTS`.** A WebSocket upgrade is not subject to the
same-origin policy: no preflight is sent and no CORS header is
consulted, so any page in any browser can open a socket to this server.
The `Host` check is what stops it, together with the token — CORS is
not doing that work.

**Serve it over HTTPS**, behind a reverse proxy. The token travels on
every request, and on the WebSocket it rides in the subprotocol header
because browsers cannot set `Authorization` on a `WebSocket`.

One consequence of plain HTTP worth knowing: `navigator.clipboard` does
not exist outside a secure context, so on an `http://<lan-ip>`
deployment every copy button falls back to a legacy path. It works, but
it is one more reason to terminate TLS.

---

## Production build

```sh
just build      # tsc + vite build for each package
```

Then run the server with `NODE_ENV=production` and your environment
configured. The built client is served by the server; there is no
separate static host to deploy.

---

## Checks

```sh
just typecheck
just lint
pnpm -r test
just fmt
```

Verify by **exit code** rather than by grepping output — `tsc`
colourises even when piped, putting ANSI escapes between `error` and the
code, so `| grep "error TS"` silently matches nothing on a real failure:

```sh
pnpm -r typecheck; echo "exit=$?"
```

---

## Troubleshooting

**`Cannot find module '@plamenix/fbclient-node'`**
The native addon has not been built. `just napi-build`.

**`Cannot find module '@plamenix/ui'`**
`plamenix-ui` has not been built, or is not a sibling directory.

**`error: package 'plamenix-types' not found`**
`plamenix-core` is missing from the sibling layout.

**Every request returns 401**
`AUTH_TOKEN` is set on the server but the client is not sending it, or
the two disagree.

**The WebSocket connects and immediately closes**
Close code 1008 is an authentication refusal. The token travels as a
subprotocol; a proxy that strips `Sec-WebSocket-Protocol` will cause
exactly this.

**A request from another machine is refused with 403**
`ALLOWED_HOSTS` does not include the host being used. This is the
DNS-rebinding guard doing its job.
