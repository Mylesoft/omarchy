#!/bin/bash
# myles.network: host-level network facts that are neither link nor profile --
# resolved DNS, IPv6 addresses, firewall posture, and Tailscale -- as
# `key<TAB>value` records separated by `--`.
#
# Everything here degrades to an explicit "unknown"/"absent" rather than to a
# silent empty, because the panel renders the difference between "no firewall"
# and "could not read the firewall rules" as two different statements.
#
# Usage: net-extras.sh [iface]

set -uo pipefail

iface=${1-}
if [ -n "$iface" ]; then
  case "$iface" in
    *[!a-zA-Z0-9._-]*) iface="" ;;
  esac
fi

# Values are tab-separated from their key, and neither an SSID nor a profile
# name is guaranteed to avoid a tab or a stray CR. Escape here, where the value
# is written, rather than filtering stdout afterwards: a post-filter would have
# to read this script's stdin, and the panel runs its probes with stdin open, so
# a stdin-reading stage blocks forever and the panel never gets a result at all.
# Backslash is escaped first so the substitutions cannot chain. The `--` record
# separators are printed with printf directly, never through here, so they stay
# exactly two characters and parseRecords keeps recognising them.
emit() {
  local v=${2-}
  v=${v//\\/\\\\}
  v=${v//$'\t'/\\t}
  v=${v//$'\r'/}
  printf '%s\t%s\n' "$1" "$v"
}

# Every record carries its own `kind`, so a section header is never a record
# that data can drift away from. A parser can then dispatch on `kind` alone,
# with no section state to fall out of sync with the probe's own framing.
emit "kind" "extras"

# ---- DNS -------------------------------------------------------------------
# resolvectl prints per-link scopes; prefer the routed interface's own servers
# and fall back to the global scope, which is what a static global override
# looks like.
dns_raw=""
if [ -n "$iface" ]; then
  dns_raw=$(resolvectl dns "$iface" 2>/dev/null)
fi
[ -n "$dns_raw" ] || dns_raw=$(resolvectl dns 2>/dev/null | awk '/^Global:/ { found = 1; next } /^Link/ { found = 0 } found')

if [ -n "$dns_raw" ]; then
  # "Link 2 (wlp1s0): 8.8.8.8 8.8.4.4" -> the server list only.
  servers=$(printf '%s\n' "$dns_raw" \
    | sed -n 's/^[^:]*: *//p' \
    | tr ' ' '\n' \
    | grep -E '^[0-9a-fA-F:.]+$' \
    | grep -v '^$' || true)
  if [ -n "$servers" ]; then
    count=0
    while IFS= read -r server; do
      [ -n "$server" ] || continue
      count=$((count + 1))
      emit "dns$count" "$server"
    done <<<"$servers"
    emit "dnsCount" "$count"
  else
    emit "dnsCount" "0"
  fi
else
  emit "dnsUnavailable" "yes"
fi

# ---- IPv6 ------------------------------------------------------------------
if [ -n "$iface" ] && [ -d "/sys/class/net/$iface" ]; then
  v6=$(ip -6 -o addr show dev "$iface" scope global 2>/dev/null \
    | awk '{ split($4, a, "/"); print a[1] }' || true)
  if [ -n "$v6" ]; then
    count=0
    while IFS= read -r addr; do
      [ -n "$addr" ] || continue
      count=$((count + 1))
      emit "v6$count" "$addr"
    done <<<"$v6"
    emit "v6Count" "$count"
  else
    emit "v6Count" "0"
  fi
fi

# ---- Firewall --------------------------------------------------------------
# Reading the ruleset needs root. `sudo -n` never prompts, so an unprivileged
# shell reports "unknown" instead of hanging on a password prompt the user
# cannot see.
fw_unit=$(systemctl is-active nftables 2>/dev/null || true)
if [ -n "$fw_unit" ]; then
  emit "firewallUnit" "$fw_unit"
fi

# Escalate only when there is a ruleset worth counting. sudo writes its
# "a password is required" line to the journal directly rather than to stderr,
# so no redirection hides it, and this probe runs on a poll -- attempting it
# unconditionally spams the journal on every machine without passwordless
# sudo. Gating on an active unit means the attempt happens exactly when the
# number would actually be informative.
if [ "$fw_unit" = "active" ] && sudo -n true </dev/null >/dev/null 2>&1; then
  rules=$(sudo -n nft list ruleset </dev/null 2>/dev/null | grep -c '^\s*\(table\|chain\|rule\)' || true)
  emit "firewallRules" "${rules:-0}"
  emit "firewallReadable" "yes"
else
  # Not attempted counts as not readable: either there is nothing running, or
  # the count was not obtainable without a password the panel must not ask for.
  emit "firewallReadable" "no"
fi

printf -- '--\n'
emit "kind" "tailscale"

# ---- Tailscale -------------------------------------------------------------
# Not installed on most machines, and omarchy ships it as an optional package,
# so absence is a first-class state rather than a failure.
if command -v tailscale >/dev/null 2>&1; then
  emit "installed" "yes"

  ts_json=$(tailscale status --json 2>/dev/null || true)
  if [ -n "$ts_json" ] && command -v jq >/dev/null 2>&1; then
    emit "backendState" "$(jq -r '.BackendState // "unknown"' <<<"$ts_json" 2>/dev/null)"
    emit "hostName" "$(jq -r '.Self.HostName // ""' <<<"$ts_json" 2>/dev/null)"
    emit "dnsName" "$(jq -r '.Self.DNSName // ""' <<<"$ts_json" 2>/dev/null)"
    emit "exitNode" "$(jq -r '.Self.ExitNodeOption // false | tostring' <<<"$ts_json" 2>/dev/null)"
    emit "tailnetPeers" "$(jq -r '(.Peer // {}) | length' <<<"$ts_json" 2>/dev/null)"

    peer_count=$(jq -r '(.Peer // {}) | to_entries | map(select(.value.Active == true)) | length' <<<"$ts_json" 2>/dev/null)
    emit "activePeers" "${peer_count:-0}"

    # The advertised address is the useful one: it is the only IPv4 the tailnet
    # can be reached on, and it is what a firewall exception needs.
    emit "ipv4" "$(jq -r '.Self.TailscaleIPs // [] | map(select(startswith("100.") or startswith("100.6"))) | .[0] // ""' <<<"$ts_json" 2>/dev/null)"

    if [ -n "$iface" ]; then
      if tailscale status --json 2>/dev/null | jq -e --arg i "$iface" \
        '.Self.TailscaleIPs // [] | length > 0' >/dev/null 2>&1; then
        emit "onIface" "yes"
      fi
    fi
  else
    emit "backendState" "unknown"
  fi
else
  emit "installed" "no"
fi

printf -- '--\n'
