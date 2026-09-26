#!/bin/bash
# myles.network: per-BSSID detail for every network currently in range, as
# `key<TAB>value` records separated by `--`.
#
# Quickshell's WifiNetwork exposes only a name, a signal fraction and a security
# enum -- no BSSID, channel, frequency or link width -- so the row detail the
# panel shows has to be read from nmcli. The in-use BSSID is enriched from
# `iw link`, which reports dBm and the negotiated channel width.

set -uo pipefail

# ---- associated-link detail -------------------------------------------------
# `iw link` is absent on drivers that do not implement the command, and absent
# entirely when the station is not associated. Every field is optional; the
# panel treats a missing key as "unknown" rather than as a zero.
#
# These are captured into shell variables rather than printed inline, because
# they have to land *inside* the in-use record and the record is assembled in
# awk.
active_iface=""
iw_dbm=""
iw_width=""
iw_rxbit=""
iw_txbit=""

for path in /sys/class/net/*/wireless; do
  [ -d "$path" ] || continue
  iface=$(basename "$(dirname "$path")")
  # sysfs exposes no notion of which AP a station joined, so this is only a
  # candidate: the `iw link` succeeding below is what confirms association.
  [ -n "$active_iface" ] && continue
  active_iface=$iface
  command -v iw >/dev/null 2>&1 || break
  link=$(iw dev "$iface" link 2>/dev/null) || continue
  [ -n "$link" ] || continue
  iw_dbm=$(awk '/^[[:space:]]*signal:/ { print $2; exit }' <<<"$link")
  iw_width=$(awk '/^[[:space:]]*width:/ { print $2; exit }' <<<"$link")
  iw_rxbit=$(awk '/^[[:space:]]*rx bitrate:/ { print $3; exit }' <<<"$link")
  iw_txbit=$(awk '/^[[:space:]]*tx bitrate:/ { print $3; exit }' <<<"$link")
  break
done

# ---- neighbourhood ----------------------------------------------------------
# Terse output is colon separated with embedded colons backslash-escaped, and a
# leading `*` marks the associated BSSID. Splitting on unescaped colons in awk
# is the only way to read it correctly: SSIDs and BSSIDs are arbitrary byte
# strings that may contain either character.
printf 'kind\tscan\n--\n'

nmcli -t -f IN-USE,SSID,BSSID,MODE,BAND,CHAN,FREQ,RATE,SIGNAL,SECURITY \
  dev wifi list --rescan no 2>/dev/null \
| awk -F'\t' -v OFS='\t' \
      -v dbm="$iw_dbm" -v width="$iw_width" \
      -v rxbit="$iw_rxbit" -v txbit="$iw_txbit" '
  function unescape(s) {
    gsub(/\\:/, ":", s)
    gsub(/\\\\/, "\\", s)
    return s
  }
  # Record-format escaping: the value is tab-separated from its key, and an SSID
  # or BSSID may contain a tab or a stray CR. Backslash first so the
  # substitutions cannot chain. This belongs here, where the value is written: a
  # post-filter over stdout would have to read the stdin of the probe, which the
  # panel leaves open, so it would block forever and the panel would get nothing.
  function esc(v) {
    gsub(/\\/, "\\\\", v)
    gsub(/\t/, "\\t", v)
    gsub(/\r/, "", v)
    return v
  }
  {
    line = $0
    sub(/\r$/, "", line)

    in_use = "no"
    if (substr(line, 1, 1) == "*") {
      in_use = "yes"
      line = substr(line, 2)
    }

    n = split(line, f, ":")
    # An escaped colon survives a naive split as two fields, the first of which
    # now ends in a backslash. Rejoin those before reading positions.
    for (i = 1; i < n; i++) {
      while (i < n && substr(f[i], length(f[i]), 1) == "\\" && length(f[i + 1]) > 0) {
        f[i] = f[i] ":" f[i + 1]
        for (j = i + 1; j < n; j++) f[j] = f[j + 1]
        n--
      }
    }

    # IN-USE,SSID,BSSID,MODE,BAND,CHAN,FREQ,RATE,SIGNAL,SECURITY
    if (f[3] == "") next

    print "ssid", esc(unescape(f[2]))
    print "bssid", esc(unescape(f[3]))
    print "mode", esc(f[4])
    print "band", esc(f[5])
    print "chan", esc(f[6])
    print "freq", esc(f[7])
    print "rate", esc(f[8])
    print "signal", esc(f[9])
    print "security", esc(f[10])
    print "inUse", esc(in_use)
    if (in_use == "yes") {
      if (dbm != "") print "dbm", esc(dbm)
      if (width != "") print "width", esc(width)
      if (rxbit != "") print "rxBitrate", esc(rxbit)
      if (txbit != "") print "txBitrate", esc(txbit)
    }
    print "--"
  }
'
