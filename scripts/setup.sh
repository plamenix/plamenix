#!/usr/bin/env bash
#
# Plamenix local workspace bootstrap.
#
# Run from the meta-workspace repo:
#
#   cd plamenix
#   just setup
#
# This script ensures the four sibling repositories exist next to this one
# and configures local path overrides so that cross-repo changes are picked
# up without republishing artifacts.
#
# Until the public release infrastructure is live, sibling repos must be
# created locally. This script only verifies the layout and reports what is
# missing; it does not yet clone from a remote.

set -euo pipefail

# Resolve the parent workspace directory (the dir holding plamenix/ and the
# sibling repos), regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_DIR="$(cd "${META_DIR}/.." && pwd)"

SIBLINGS=(
    "plamenix-core"
    "plamenix-ui"
    "plamenix-desktop"
    "plamenix-web"
)

REQUIRED_TOOLS=(
    "git"
    "rustc"
    "cargo"
    "node"
    "pnpm"
    "just"
)

# ── Helpers ───────────────────────────────────────────────────────────────

info() { printf '\033[0;36m[plamenix]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[plamenix]\033[0m %s\n' "$*"; }
fail() { printf '\033[0;31m[plamenix]\033[0m %s\n' "$*" >&2; exit 1; }

# ── Tool check ────────────────────────────────────────────────────────────

info "Checking required tools..."
missing_tools=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        missing_tools+=("${tool}")
    fi
done

if [ "${#missing_tools[@]}" -gt 0 ]; then
    warn "Missing tools: ${missing_tools[*]}"
    warn "Install them before continuing. See plamenix/CONTRIBUTING.md."
    exit 1
fi
info "All required tools found."

# ── Sibling repo check ────────────────────────────────────────────────────

info "Workspace directory: ${WORKSPACE_DIR}"
missing_repos=()
for sibling in "${SIBLINGS[@]}"; do
    if [ ! -d "${WORKSPACE_DIR}/${sibling}" ]; then
        missing_repos+=("${sibling}")
    fi
done

if [ "${#missing_repos[@]}" -gt 0 ]; then
    warn "Missing sibling repositories:"
    for repo in "${missing_repos[@]}"; do
        warn "  - ${WORKSPACE_DIR}/${repo}"
    done
    warn ""
    warn "Public release infrastructure is not live yet. Create the missing"
    warn "sibling repositories locally and re-run 'just setup'."
    exit 1
fi

info "All sibling repositories present."

# ── Path-override wiring placeholder ──────────────────────────────────────

# When sibling repos exist, this is where we wire local Cargo [patch] entries
# and pnpm link:* references so that working copies of plamenix-core and
# plamenix-ui are picked up by plamenix-desktop and plamenix-web without
# publishing to crates.io or npm. Implementation lands once the sibling
# repos have their own Cargo.toml / package.json files.

info "Local path-override wiring is not yet implemented. Skipping."
info "Setup complete."
