#!/bin/bash
# myles.network: emit every stored NetworkManager Wi-Fi and Ethernet profile,
# plus the Wi-Fi blocklist, as `key<TAB>value` records separated by a `--` line.
#
# First-party `omarchy-network-status` only reports the interface on the default
# route, so anything about *stored* profiles has to be read from nmcli here.
# This script is the plugin's own read-only probe; it never writes.

set -uo pipefail

# A pathological profile list should not turn into an unbounded burst of
# subprocess calls on a poll timer.
MAX_PROFILES=60

# Read one `key: value` line out of `nmcli con show <uuid>` output. awk rather
# than a shell loop because the property block is a few dozen lines and this
# runs once per profile.
con_field() {
  awk -v want="$2" '
    {
      idx = index($0, ":")
      if (idx == 0) next
      key = substr($0, 1, idx - 1)
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      if (key != want) next
      v = substr($0, idx + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      # Drop nmcli provenance annotations -- they are not part of the value.
      sub(/[ \t]+\((default|externally)\)$/, "", v)
      print v
      exit
    }
  ' <<<"$1"
}

# A `802-1x.*` block with a real eap method means the profile authenticates
# with 802.1X. Any other read of that block is a wifi/wired profile using a
# pre-shared key.
has_eap() {
  local eap
  eap=$(nmcli -g 802-1x.eap con show "$1" 2>/dev/null | head -n 1)
  [ -n "$eap" ] && [ "$eap" != "--" ]
}

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

emit "kind" "profiles"
printf -- '--\n'

# Which interfaces currently carry an activated profile, so the panel can mark
# a stored profile live without trusting a stale poll.
declare -A active_iface=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  # uuid:device, and both halves are colon-free.
  uuid=${line%%:*}
  dev=${line#*:}
  [ "$uuid" = "$line" ] && continue
  [ "$dev" = "--" ] || active_iface["$uuid"]="$dev"
done < <(nmcli -t -f UUID,DEVICE con show 2>/dev/null)

count=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  uuid=${line%%:*}
  rest=${line#*:}
  type=${rest%%:*}
  [ -n "$uuid" ] && [ -n "$type" ] || continue

  case "$type" in
    802-11-wireless | 802-3-ethernet) ;;
    *) continue ;;
  esac

  count=$((count + 1))
  [ "$count" -gt "$MAX_PROFILES" ] && break

  detail=$(nmcli con show "$uuid" 2>/dev/null) || continue
  [ -n "$detail" ] || continue

  emit "uuid" "$uuid"
  emit "name" "$(con_field "$detail" connection.id)"
  emit "type" "$type"
  emit "iface" "$(con_field "$detail" connection.interface-name)"
  emit "autoconnect" "$(con_field "$detail" connection.autoconnect)"
  emit "priority" "$(con_field "$detail" connection.autoconnect-priority)"
  # nmcli reads the addressing group back under lower-case `ipv4.*` names, not
  # the `IP4.*` names accepted by `nmcli -g` writes.
  emit "method" "$(con_field "$detail" ipv4.method)"
  emit "addresses" "$(con_field "$detail" ipv4.addresses)"
  emit "gateway" "$(con_field "$detail" ipv4.gateway)"
  emit "dns" "$(con_field "$detail" ipv4.dns)"

  if [ "$type" = "802-11-wireless" ]; then
    emit "ssid" "$(con_field "$detail" 802-11-wireless.ssid)"
    emit "clonedMac" "$(con_field "$detail" 802-11-wireless.mac-address)"
  else
    emit "clonedMac" "$(con_field "$detail" 802-3-ethernet.cloned-mac-address)"
    emit "wol" "$(con_field "$detail" 802-3-ethernet.wake-on-lan)"
    # 0 means "leave it to autonegotiation"; any other value is a profile that
    # pins the link, which is what makes a negotiated shortfall a real fault.
    emit "pinnedSpeed" "$(con_field "$detail" 802-3-ethernet.speed)"
    emit "pinnedDuplex" "$(con_field "$detail" 802-3-ethernet.duplex)"
  fi

  if has_eap "$uuid"; then emit "eap" "yes"; else emit "eap" "no"; fi
  emit "active" "${active_iface[$uuid]-}"
  printf -- '--\n'
done < <(nmcli -t -f UUID,TYPE,DEVICE con show 2>/dev/null)

# Wi-Fi blocklist. nmcli reports it as a column on the scan list; only the
# entries that are actually blocked are interesting.
emit "kind" "blocklist"
printf -- '--\n'

while IFS= read -r line; do
  [ -n "$line" ] || continue
  bssid=${line%%:*}
  [ -n "$bssid" ] || continue
  [ "$bssid" = "--" ] && continue
  emit "bssid" "$bssid"
done < <(nmcli -t -f WIFI-BLOCKLIST dev wifi list --rescan no 2>/dev/null | sort -u)
