# Transport abstraction

Plamenix's React shell (`@plamenix/ui`) does not know whether it is
running inside a Tauri webview or a browser tab. Host interaction goes
through a single `Transport` interface implemented by the consuming
edition.

## The interface

```ts
// plamenix-ui/src/transport/index.ts
export interface Transport {
  invoke<T>(command: string, args?: Record<string, unknown>): Promise<T>;
}

export class TransportError extends Error {
  constructor(message: string, public readonly cause?: unknown);
}
```

Components, hooks, and stores in `@plamenix/ui` take a `Transport`
instance via context provider at the root. Nothing in the library
imports from `@tauri-apps/*` or calls `fetch` directly.

## Desktop implementation (`plamenix-desktop`)

```ts
import { invoke } from '@tauri-apps/api/core';

export const tauriTransport: Transport = {
  async invoke<T>(command, args) {
    try {
      return await invoke<T>(command, args);
    } catch (cause) {
      throw new TransportError(`Tauri command "${command}" failed`, cause);
    }
  },
};
```

Tauri commands are registered in `plamenix-desktop/src-tauri/src/commands/*.rs`
files, one file per feature namespace. Each command is a thin wrapper
that translates the IPC payload into a call against the relevant
`plamenix-core` use case.

## Web implementation (`plamenix-web`)

```ts
export function httpTransport(opts: { baseUrl: string; sessionToken?: string }): Transport {
  return {
    async invoke<T>(command, args) {
      const res = await fetch(`${opts.baseUrl}/api/${command}`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(args ?? {}),
      });
      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        throw new TransportError(`HTTP ${res.status} on "${command}": ${detail}`);
      }
      return (await res.json()) as T;
    },
  };
}
```

The Fastify server in `plamenix-web/` exposes one JSON-RPC-ish endpoint
per command at `/api/<command>`. Endpoints translate request bodies
into calls against `plamenix-core` via NAPI (see [napi-rsfbclient.md](./napi-rsfbclient.md)).

## Type sharing across the boundary

Rust types defined in `plamenix-core` carry `#[derive(specta::Type)]`.
Specta generates TypeScript bindings published as `@plamenix/types` (or
re-exported from `@plamenix/ui`). Front-end code imports these types
directly:

```ts
import type { ConnectionConfig, QueryResult } from '@plamenix/types';
```

Renaming or changing a Rust type produces a compile error on the TS
side in the same PR. Drift impossible.

## Capability awareness

The transport carries a capability descriptor advertised by the host:

```ts
type HostCapabilities = {
  edition: 'desktop' | 'web';
  fs: boolean;
  keychain: boolean;
  systemTray: boolean;
  multiUser: boolean;
  // ...
};
```

Components use `useCapability('fs')`-style hooks to hide or disable
features that are not available in the current edition (see
[three-editions.md](./three-editions.md)).

## Lifecycle

- Bootstrap: edition constructs its `Transport` instance, wraps the
  React app in `<TransportProvider value={...}>`.
- App start: a `bootstrap` command returns `{ settings, plugins,
  capabilities, currentSession? }` in one round trip.
- Plugin UI loading: plugin contributions are streamed via events; the
  React shell listens and updates its registry.
- Disconnect: a `disconnect` command closes the active session; the
  edition tears down any host-side resources.

## Error model

- Channel-level failures (network down, IPC closed) throw
  `TransportError`.
- Application-level failures (wrong credentials, query syntax error)
  flow through the command's typed return shape — typically a `Result`
  discriminated union or a `Result<T, AppError>` shape generated from
  Rust.

This keeps the two error classes distinguishable in UI code.

## Why a single abstraction

A single seam eliminates per-component `if (window.__TAURI__)` branches,
keeps the React shell completely portable, and lets future editions
(CLI mode? remote daemon mode?) plug in without React changes.
