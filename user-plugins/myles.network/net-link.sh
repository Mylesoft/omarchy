#!/bin/bash
# myles.network: raw link-level facts for one interface, as `key<TAB>value`.
#
# Reads sysfs for the things the kernel always exposes and shells out to
# ethtool when it happens to be installed. ethtool is optional: every fact it
# provides has a documented "unknown" representation, and the panel treats
# absent keys as unknown rather than as zero.
#
# Usage: net-link.sh <iface>

set -uo pipefail

iface=${1-}
[ -n "$iface" ] || exit 0

# An interface name is a kernel-supplied token, but this script is reachable
# from a text field, so refuse anything that is not plainly an interface name
# rather than letting it reach a path.
case "$iface" in
  *[!a-zA-Z0-9._-]*) exit 0 ;;
esac

sys=/sys/class/net/$iface
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

# The `kind` marker shares the record with the data it labels, so a parser
# never has to correlate a header record with the record that follows it.
emit "kind" "link"

if [ ! -d "$sys" ]; then
  # Not an error the panel needs to surface: an interface can vanish between
  # the route lookup and this probe. Absence is a valid reading.
  emit "exists" "no"
  printf -- '--\n'
  exec awk -F'\t' 'BEGIN { OFS = "\t" }
    { v = $2; gsub(/\\/, "\\\\", v); gsub(/\t/, "\\t", v); gsub(/\r/, "", v); print $1, v }'
fi

emit "exists" "yes"

read_sys() {
  # $1 = path under sysfs, $2 = emit key. Emits nothing when unreadable, which
  # is how the panel tells "unknown" apart from a real zero.
  local path=$sys/$1
  [ -r "$path" ] || return 0
  local value
  read -r value <"$path" 2>/dev/null || return 0
  [ -n "$value" ] || return 0
  emit "$2" "$value"
}

read_sys operstate operstate
read_sys carrier carrier
read_sys mtu mtu
read_sys address mac
read_sys speed speed
read_sys duplex duplex
read_sys type phyType
read_sys auto-negotiate autoNegotiated

# Driver, via the device symlink's owning module. Wireless and most wired NICs
# expose it; virtual and USB-less devices legitimately do not.
driver=$(basename "$(readlink -f "$sys/device/driver" 2>/dev/null)" 2>/dev/null)
[ -n "$driver" ] && [ "$driver" != "." ] && emit "driver" "$driver"

# Counters. Absent for interfaces the kernel does not account (tun, bridges
# report per-member stats instead), so each is independently optional.
for pair in "rx_errors:rxErrors" "tx_errors:txErrors" \
            "rx_dropped:rxDropped" "tx_dropped:txDropped" \
            "rx_crc_errors:rxCrcErrors" "collisions:collisions"; do
  read_sys "statistics/${pair%%:*}" "${pair#*:}"
done

# ethtool adds link modes, autoneg state and the advertised side of the
# negotiation, which is what makes a speed shortfall explicable rather than
# just surprising.
if command -v ethtool >/dev/null 2>&1; then
  ethtool_out=$(ethtool "$iface" 2>/dev/null)

  if [ -n "$ethtool_out" ]; then
    emit "ethtool" "yes"

    speed_line=$(awk -F': ' '/^[[:space:]]*Speed:/ { print $2; exit }' <<<"$ethtool_out")
    emit "ethtoolSpeed" "${speed_line%%,*}"

    emit "ethtoolDuplex" "$(awk -F': ' '/^[[:space:]]*Duplex:/ { print $2; exit }' <<<"$ethtool_out")"
    emit "autoneg" "$(awk -F': ' '/^[[:space:]]*Auto-negotiation:/ { print $2; exit }' <<<"$ethtool_out")"
    emit "linkDetected" "$(awk -F': ' '/^[[:space:]]*Link detected:/ { print $2; exit }' <<<"$ethtool_out")"

    # Fastest mode the NIC itself supports, so the panel can say "your port
    # does 2.5G but you linked at 1G" instead of only noticing the number is
    # low. The last entry of "Supported link modes" is the fastest.
    emit "maxSpeed" "$(awk -F': ' '
      /^[[:space:]]*Supported link modes:/ {
        modes = $2
        sub(/^[[:space:]]*\([0-9]+ bases supported\)[[:space:]]*/, "", modes)
        n = split(modes, parts, /[[:space:]]+/)
        for (i = 1; i <= n; i++) {
          if (match(parts[i], /^[0-9]+base/)) {
            v = substr(parts[i], 1, RLENGTH - 4)
            if (v + 0 > max) max = v + 0
          }
        }
      }
      END { if (max > 0) print max }' <<<"$ethtool_out")"
  fi
fi

printf -- '--\n'
