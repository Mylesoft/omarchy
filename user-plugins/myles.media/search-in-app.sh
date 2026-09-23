#!/usr/bin/env bash
# Deprecated: searches now stay in the drawer via search-drawer.sh.
# Kept as a thin redirect for any leftover callers.
exec "$(dirname "$0")/search-drawer.sh" "$@"
