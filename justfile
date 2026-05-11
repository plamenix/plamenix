# Plamenix meta-workspace command runner.
#
# This justfile orchestrates the four sibling repositories that live next to
# this one. Recipes here are intentionally thin wrappers; per-repo recipes
# live inside each sibling repo.

# Show the list of available recipes when `just` is run with no arguments.
default:
    @just --list

# Bootstrap the local development workspace.
# Clones the sibling repos if missing and wires path overrides.
setup:
    @bash scripts/setup.sh

# Run the desktop edition against local sibling repos.
dev:
    @echo "Not yet implemented. Will run plamenix-desktop in dev mode."
    @echo "See plamenix-desktop/CONTRIBUTING.md for now."

# Run the web edition against local sibling repos.
web:
    @echo "Not yet implemented. Will run plamenix-web in dev mode."
    @echo "See plamenix-web/CONTRIBUTING.md for now."

# Run every sibling repo's test suite.
test:
    @echo "Not yet implemented. Will run cargo test / pnpm test across all repos."

# Format every sibling repo (rustfmt + prettier).
fmt:
    @echo "Not yet implemented. Will run rustfmt + prettier across all repos."

# Lint every sibling repo (clippy + eslint).
lint:
    @echo "Not yet implemented. Will run clippy + eslint across all repos."

# Build every sibling repo for release.
build:
    @echo "Not yet implemented. Will build every sibling repo."

# Print the current Plamenix version (single source of truth: this repo).
version:
    @echo "1.0.0-beta"
