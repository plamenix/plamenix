# Building the desktop edition

The Tauri 2 application: a Rust binary with a React front end, shipped
as a `.dmg`, `.exe`, `.deb`, `.rpm` or `.AppImage`.

Install everything in [Build prerequisites](./build-prerequisites.md)
first, including the sibling repository layout. The desktop build cannot
resolve its dependencies without it.

---

## Quick version

```sh
cd plamenix-ui       && pnpm install && pnpm build
cd ../plamenix-desktop && just setup && just dev
```

The rest of this page explains why the first line is not optional and
what to do when something fails.

---

## 1. Build the shared UI library first

```sh
cd plamenix-ui
pnpm install
pnpm build
```

`plamenix-desktop` depends on `@plamenix/ui` as `link:../plamenix-ui`
and imports its **built output**, not its source. A fresh clone has no
`dist/`, so skipping this step produces module-not-found errors that
point at the desktop repo while the cause is here.

While changing shared components, leave a watcher running instead of
rebuilding by hand:

```sh
pnpm dev        # vite build --watch
```

With that running, edits to `plamenix-ui` reach a running desktop app
through hot reload — no restart, no rebuild of the Rust side.

## 2. Fetch dependencies

```sh
cd ../plamenix-desktop
just setup      # pnpm install + cargo fetch
```

## 3. Run it

```sh
just dev        # pnpm tauri dev
```

First run compiles the whole Rust dependency tree and takes several
minutes. Later runs are incremental and fast. Front-end changes hot
reload; Rust changes trigger a rebuild and restart.

---

## Producing installers

```sh
just build      # pnpm tauri build
```

Output lands in `src-tauri/target/release/bundle/`.

### The bundled Firebird client

The build bundles a native `fbclient` so the application can use the
native driver without a system-wide Firebird install. That directory is
**gitignored**, so a fresh clone does not have it and `tauri build`
fails with:

```
resource path `../resources/fbclient` doesn't exist
```

Populate it once per platform:

```sh
./scripts/fetch-fbclient.sh          # latest pinned release (5.0.3)
./scripts/fetch-fbclient.sh 4.0.5    # a specific major
```

The script picks its download from the machine's architecture. When
cross-compiling — an Intel macOS build on Apple Silicon, say — tell it
the target instead, or you will bundle a client for the wrong
architecture into an application that builds cleanly and then cannot
attach to anything:

```sh
FB_ARCH=x86_64 ./scripts/fetch-fbclient.sh
```

`just dev` does not need this. Only bundling does.

### Cross-compiling

```sh
rustup target add x86_64-apple-darwin
FB_ARCH=x86_64 ./scripts/fetch-fbclient.sh
pnpm tauri build --target x86_64-apple-darwin
```

### Choosing bundle formats

```sh
pnpm tauri build --bundles deb,rpm
```

Useful on Linux, where `tauri build` bundles every configured format in
one pass and **aborts the whole command on the first failure** — so a
failing AppImage discards a `.deb` and `.rpm` that already built. The
release workflow builds the packages first and attempts the AppImage
separately for this reason.

### Signing

Releases are currently **unsigned**. macOS reports an unverified
developer and Windows shows a SmartScreen warning. To sign locally, set
the `APPLE_*` or Windows certificate environment variables Tauri
documents.

One caveat worth knowing if you touch CI: an unset GitHub Actions secret
expands to an **empty string, not nothing**, and `tauri-action` reads an
empty `APPLE_CERTIFICATE` as "sign this build" and then fails importing
a certificate that was never there. Omit the variables entirely rather
than passing empty ones.

---

## Checks

```sh
just typecheck
just lint
just test
just fmt
```

Verify by **exit code**, not by grepping output. `tsc` colourises even
when piped, placing ANSI escapes between `error` and the code, so
`| grep "error TS"` silently matches nothing on a real failure:

```sh
pnpm typecheck; echo "exit=$?"
```

> The desktop shell currently has **no test suite** — `just test` runs
> vitest, finds nothing, and exits 0. Its checks are a typecheck and a
> lint. Treat a green result here as "nothing obviously broken", not as
> "the application works". Run it.

---

## Troubleshooting

**`resource path '../resources/fbclient' doesn't exist`**
Run `./scripts/fetch-fbclient.sh`. See above.

**`Cannot find module '@plamenix/ui'`**
`plamenix-ui` has not been built, or is not a sibling directory. Run
`pnpm build` there.

**`error: package 'plamenix-types' not found`**
`plamenix-core` is missing from the sibling layout.

**`could not locate firebird/ inside tarball`**
The fetch script could not find what it expected inside the Firebird
release archive, usually because the upstream layout changed. The
archive unpacks to a versioned directory containing `buildroot.tar.gz`.

**`failed to run linuxdeploy`, with no further detail**
Tauri discards linuxdeploy's stderr. Re-run with `--verbose` to see the
real error. The usual cause here is dependency resolution: linuxdeploy
walks every shared object in the AppDir and resolves through the system
linker, which does not search Firebird's private `lib/`, so it cannot
find `libtomcrypt.so.1` even though the bundle carries it. Point it
there:

```sh
LD_LIBRARY_PATH=$PWD/resources/fbclient/v50/lib pnpm tauri build
```

**A build succeeds but the app cannot connect using the native driver**
Likely the wrong-architecture `fbclient` from a cross-compile. Delete
`resources/fbclient/` and re-fetch with `FB_ARCH` set.
