# Build prerequisites

Everything you need installed before building either edition of
Plamenix, on macOS, Linux or Windows.

Do this once. Then go to
[Building the desktop edition](./build-desktop.md) or
[Building the web edition](./build-web.md).

> These versions are the ones the release pipeline builds with. Newer
> usually works; the pins are what is actually tested.

---

## 1. Toolchains

| Tool | Version | Why |
|---|---|---|
| Rust | **1.95** | The Tauri shell, the driver, the plugin host |
| Node | **24 LTS** | Both front ends and the web server |
| pnpm | **10** | The only supported package manager here — see below |
| just | any recent | Command runner used by every repo |
| Git | any recent | Five repositories |

### Rust

Install through [rustup](https://rustup.rs/) rather than a system
package, because the repositories pin a toolchain in
`rust-toolchain.toml` and rustup honours it automatically:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

On Windows, download and run
[`rustup-init.exe`](https://rustup.rs/) and choose the **MSVC**
toolchain when asked. The GNU toolchain will not build the Tauri shell.

Verify — the version comes from the pin, so being on 1.95 here means it
is working:

```sh
rustc --version
```

### Node and pnpm

Install Node 24 from [nodejs.org](https://nodejs.org/) or your version
manager of choice, then enable pnpm through Corepack, which ships with
Node:

```sh
corepack enable
corepack prepare pnpm@10 --activate
```

**pnpm is not interchangeable with npm or yarn here.** The desktop repo
consumes the shared UI library through a `link:` dependency to a sibling
directory, and the web repo is a pnpm workspace. Both rely on pnpm's
resolution. Using another package manager produces a lockfile that does
not match and a build that fails in a confusing place.

### just

```sh
# macOS
brew install just

# Linux (or anywhere with Rust already installed)
cargo install just

# Windows
winget install --id Casey.Just
```

---

## 2. Platform libraries

Only the desktop edition needs these; it builds a native application.

### macOS

Xcode Command Line Tools:

```sh
xcode-select --install
```

That is all. WebKit is part of the system.

### Linux

Tauri 2 links against **webkit2gtk 4.1**. The `4.0` packages are for
Tauri 1 and will not work.

```sh
# Debian / Ubuntu
sudo apt-get update
sudo apt-get install -y \
    libwebkit2gtk-4.1-dev \
    libappindicator3-dev \
    librsvg2-dev \
    patchelf \
    libssl-dev \
    build-essential \
    file \
    wget

# Fedora
sudo dnf install -y \
    webkit2gtk4.1-devel openssl-devel patchelf librsvg2-devel \
    gcc gcc-c++ make file wget

# Arch
sudo pacman -S --needed \
    webkit2gtk-4.1 openssl patchelf librsvg base-devel file wget
```

Add `libfuse2` if you intend to build the AppImage bundle.

### Windows

Install the **Microsoft C++ Build Tools** with the *Desktop development
with C++* workload, and **WebView2**, which is present on Windows 11 and
current Windows 10 but not on older installs:

```sh
winget install --id Microsoft.VisualStudio.2022.BuildTools
winget install --id Microsoft.EdgeWebView2Runtime
```

---

## 3. The repositories

Plamenix is a **polyrepo**, and this matters for the build rather than
being an organisational detail. `plamenix-desktop` reaches its
dependencies by relative path — a `link:../plamenix-ui` in
`package.json`, and Cargo `path` dependencies into
`../../plamenix-core`. They must be siblings, with these exact
directory names, or nothing resolves:

```
<any directory>/
├── plamenix/              meta-workspace: docs, milestones
├── plamenix-core/         shared Rust crates
├── plamenix-ui/           shared React library
├── plamenix-desktop/      Tauri desktop edition
└── plamenix-web/          Fastify + React web edition
```

```sh
mkdir plamenix-workspace && cd plamenix-workspace
for repo in plamenix plamenix-core plamenix-ui plamenix-desktop plamenix-web; do
    git clone https://github.com/plamenix/$repo.git
done
```

Check the layout and your toolchain versions:

```sh
cd plamenix && just setup
```

That recipe verifies; it does not install or clone. It tells you what is
missing.

> The other recipes in the meta-workspace `justfile` — `just dev`,
> `just build`, `just test` — are **placeholders that print a message
> and do nothing.** Real commands live in each repository's own
> `justfile`, and the two build guides use those.

---

## 4. A Firebird server

Not needed to build. Needed to do anything useful once built.

Plamenix speaks to Firebird **2.5 through 5.0**. Its default connection
mode is a pure-Rust implementation that needs no client library
installed. The bundled native `fbclient` is fetched at build time by
`scripts/fetch-fbclient.sh` in the desktop repo — you do not install it
yourself.

The quickest server to test against:

```sh
docker run -d --name firebird \
    -p 3050:3050 \
    -e FIREBIRD_ROOT_PASSWORD=masterkey \
    firebirdsql/firebird:5.0
```

Then connect to `localhost:3050`, user `SYSDBA`, password `masterkey`.

---

## Troubleshooting

**`error: failed to run custom build command for 'webkit2gtk-sys'`**
The 4.1 development package is missing, or 4.0 is installed instead.
Linux only.

**`linker 'link.exe' not found`**
Windows, and the C++ Build Tools are missing or the GNU Rust toolchain
was installed instead of MSVC. `rustup default stable-msvc`.

**`Cannot find module '@plamenix/ui'`**
The sibling layout is wrong. `plamenix-ui` must sit next to
`plamenix-desktop` under exactly that name.

**`error: package 'plamenix-types' not found`**
Same cause, on the Rust side. `plamenix-core` is missing or misnamed.
