# Authoring a Plamenix plugin

This document is the **plugin author's reference manual**. For a
hands-on walkthrough that takes you from `plamenix new` to a signed
`.plx` installed on either edition, start with
[`tutorial-first-plugin.md`](./tutorial-first-plugin.md) instead.
Come back here when you outgrow the tutorial and need
manifest-field-by-field + capability-by-capability detail.

For the wider architecture see
[`plugin-architecture.md`](./plugin-architecture.md); for the runtime
contract see [`plugin-system.md`](./plugin-system.md),
[`plugin-events.md`](./plugin-events.md), and
[`plugin-interceptors.md`](./plugin-interceptors.md).

> The `plamenix-cli` scaffold (I7.11+) generates the same files this
> doc describes. The CLI is the recommended path; the manual recipe
> below remains useful for understanding what each file does and for
> hosts / tools that can't use the CLI (e.g. fully custom build
> pipelines).

## A plugin in one paragraph

A Plamenix plugin is a `.plx` archive (zip) containing a
`manifest.toml`, an optional `plugin.wasm` Rust half, and an optional
`ui.mjs` React half. The host loads the bundle, instantiates the WASM
half in wasmtime, then dynamic-imports the `ui.mjs` and calls its
exported `activate(api)` function. Static contributions declared in
the bundle's default export auto-register against well-known
extension points; the React `<PluginOutlet>` slots in the host UI
render those contributions.

## Minimal bundle layout

```
my-plugin/
├── manifest.toml
├── plugin.wasm                  # optional — Rust half
└── ui.mjs                       # optional — React half (this doc focuses on this)
```

## Authoring the React half

### 1. Project skeleton

```
my-plugin-ui/
├── package.json
├── tsconfig.json
├── vite.config.ts
└── src/
    └── index.tsx
```

### 2. `package.json`

```jsonc
{
  "name": "my-plamenix-plugin",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "vite build"
  },
  "devDependencies": {
    "@plamenix/ui": "workspace:*",         // for the plugin-react SDK
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "typescript": "^6",
    "vite": "^8"
  },
  "peerDependencies": {
    "react": "^19",
    "react-dom": "^19",
    "lucide-react": "^0.460"
  }
}
```

`react`, `react-dom`, and `lucide-react` are **peer** dependencies, not
runtime deps. The host edition supplies them at load time through an
import map (see [§4 below](#4-runtime-import-resolution)); shipping
your own copy would (a) blow up bundle size by ~140 kB for React
alone, and (b) break Hooks + Context because the host's React would
not be the same module identity as your plugin's React. **Both
breakages are silent and catastrophic — externalise.**

### 3. `vite.config.ts`

```ts
import { defineConfig } from 'vite';
import { resolve } from 'node:path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.tsx'),
      formats: ['es'],
      fileName: () => 'ui.mjs',
    },
    rollupOptions: {
      // Mandatory: every module listed here must come from the host
      // at runtime, not from the plugin bundle.
      external: ['react', 'react-dom', 'react/jsx-runtime', 'lucide-react'],
    },
    target: 'es2022',
    minify: true,
    sourcemap: true,
  },
});
```

The host's main `@plamenix/ui` bundle uses the same externals — see
`plamenix-ui/vite.config.ts`. Plugin authors mirror that list so
contributions and shell consumers agree on shared module identity.

> If a plugin needs a heavy library that the host does not provide
> (e.g. its own visualisation runtime), bundle it normally. Only the
> four listed names are guaranteed host-provided.

### 4. Runtime import resolution

At shell boot, the host injects an [import map][importmap-mdn] into
the document `<head>`:

```html
<script type="importmap">
{
  "imports": {
    "react":              "/host-modules/react.mjs",
    "react-dom":          "/host-modules/react-dom.mjs",
    "react/jsx-runtime":  "/host-modules/react-jsx-runtime.mjs",
    "lucide-react":       "/host-modules/lucide-react.mjs"
  }
}
</script>
```

Each URL serves a tiny re-export module that hands the plugin the
host's bundled instance. Plugin author writes `import React from 'react'`
as usual; the browser's resolver follows the map.

| Edition | Where the host modules are served |
|---|---|
| Desktop (Tauri) | Tauri custom-protocol — `tauri://localhost/host-modules/<name>.mjs` resolved through `convertFileSrc` |
| Web (Fastify) | `/host-modules/<name>.mjs` served by a built-in Fastify route |

Both wirings land in Section I4 alongside the first real React plugin
extraction; until then a plugin bundle that does not use React can be
authored + tested.

[importmap-mdn]: https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/importmap

### 5. Module shape — `src/index.tsx`

```tsx
import type { PluginUiModule } from '@plamenix/ui/plugin-react';

const module: PluginUiModule = {
  contributions: {
    cell_renderers: [
      {
        id: 'json-tree',
        priority: 50,
        payload: {
          mimeType: 'application/json',
          Component: function JsonTreeCell(props: { value: unknown }) {
            return <pre>{JSON.stringify(props.value, null, 2)}</pre>;
          },
        },
      },
    ],
  },
  async activate(api) {
    api.log('info', `JSON tree renderer ready (plugin ${api.pluginId})`);
  },
};

export default module;
```

The default export must satisfy `PluginUiModule`. Both `contributions`
and `activate`/`deactivate` are optional — a tip-pack plugin with only
static `tip_packs` contributions skips `activate`; a command-only
plugin may have only `activate` and no static contributions.

### 6. Manifest

```toml
[plugin]
id = "com.example.json-cell-renderer"
name = "JSON Cell Renderer"
version = "1.0.0"
plamenix_min_version = ">=1.0.0-beta"
plugin_api = "1.0"
world = "plamenix:plugin@1.0.0/plugin-minimal"
targets = ["desktop", "web"]
restart_policy = "transient"
description = "Renders JSON-shaped VARCHAR cells as collapsible trees."

[permissions]
required = []
optional = []

[entry_points]
ui = "ui.mjs"
```

A pure-UI plugin omits `[entry_points] wasm`. The host loads `ui.mjs`
through the dynamic-import path (Sections I2.4 + I2.5).

## Local development loop

1. `pnpm build` — emits `dist/ui.mjs`.
2. Place `manifest.toml` + the built `ui.mjs` in a directory under
   the host's `PLUGINS_PATH` (web) or `<app-data>/.plamenix/plugins/`
   (desktop).
3. Start the host (`pnpm tauri dev` or `pnpm dev` for web).
4. The bootstrap discovers your plugin, registers your contributions,
   `<PluginOutlet>` slots pick them up.

Hot-reload-on-edit lands in Section I2.7; until then, restart the
host after rebuilding the plugin.

## Verifying externalisation

After `vite build`, check the emitted `dist/ui.mjs`:

```bash
grep -E "^import .* from ['\"](react|react-dom|react/jsx-runtime|lucide-react)['\"]" dist/ui.mjs
```

Every line should be an `import` statement against one of the four
bare specifiers. If you see no matches, externalisation is broken and
your bundle contains its own React copy.

```bash
# Bundle size should be tiny — your code + nothing else.
wc -c dist/ui.mjs
```

A renderer-only plugin should land under 10 kB. If it is hundreds of
kilobytes, externalisation failed.

## Common mistakes

- **Importing `@plamenix/ui` instead of `@plamenix/ui/plugin-react`** —
  the full `@plamenix/ui` bundle is the host's shell library; plugin
  authors only need the SDK subpath.
- **Calling `usePluginAPI()` outside `activate()` or a rendered
  contribution** — the hook reads from the host's
  `<PluginAPIProvider>`; nothing renders contributions outside the
  shell's outlets, so calling it elsewhere throws.
- **Subscribing to events inside a component without disposing on
  unmount** — `subscribe(...)` returns a `Disposable`; React effects
  must call `.dispose()` in their cleanup or you leak handlers.
- **Forgetting `lucide-react` in externals** — easy miss; you get a
  duplicate icon-library bundled and silent React-instance mismatch
  errors when host icons share a Context with plugin icons.

## Related

- [`plugin-architecture.md`](./plugin-architecture.md) — overall design
- [`plugin-system.md`](./plugin-system.md) — WASM Component Model + ESM contributions
- [`plugin-manifest.md`](./plugin-manifest.md) — manifest schema reference
- [`plugin-events.md`](./plugin-events.md) — event-bus topics
- [`plugin-interceptors.md`](./plugin-interceptors.md) — synchronous middleware
- [`contribution-points.md`](./contribution-points.md) — enumeration of slots
- [`capability-model.md`](./capability-model.md) — permission grammar
