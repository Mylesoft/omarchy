function parseNetworkStatus(raw) {
  var parts = String(raw || "disconnected\t\t\t").replace(/\r?\n+$/, "").split("\t")
  return {
    kind: parts[0] || "disconnected",
    label: parts[1] || "",
    signalStrength: parts[2] ? parseInt(parts[2], 10) : -1,
    frequency: parts[3] || ""
  }
}

function wifiIconFor(strength) {
  var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
  var index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
  return icons[index]
}

// A known plain-HTTP endpoint lets the network redirect the browser to its
// login page. Never execute or automatically open an untrusted Location header.
var captivePortalUrl = "http://ping.archlinux.org/nm-check.txt"

function connectivityState(kind, connectivity, states, checksEnabled) {
  if (kind === "disconnected") return "none"
  // Ignore stale cached results when the operator has disabled probing.
  if (!checksEnabled) return "unknown"
  if (connectivity === states.Portal) return "portal"
  if (connectivity === states.Limited) return "limited"
  if (connectivity === states.Full) return "full"
  if (connectivity === states.None) return "none"
  return "unknown"
}

function connectionIcon(kind, signalStrength, connectivity) {
  var restricted = connectivity === "portal" || connectivity === "limited"
  if (kind === "wifi") return restricted ? "󰤩" : wifiIconFor(signalStrength)
  if (kind === "ethernet") return restricted ? "󰈂" : "󰈀"
  return "󰤮"
}

function formatHeaderSpeed(mbps) {
  var v = parseInt(mbps, 10)
  if (!v || v < 0) return ""
  if (v >= 1000) return (v / 1000).toFixed(v % 1000 === 0 ? 0 : 1) + "gbit"
  return v + "mbit"
}

function formatHeaderFreq(mhz) {
  var v = parseFloat(mhz)
  if (!v) return ""

  if (v >= 2400 && v < 2500) return "2.4ghz"
  if (v >= 4900 && v < 5925) return "5ghz"
  if (v >= 5925 && v < 7125) return "6ghz"
  if (v >= 57000 && v < 71000) return "60ghz"

  var ghz = v / 1000
  return ghz.toFixed(ghz % 1 === 0 ? 0 : 1) + "ghz"
}

// Wi-Fi band state belongs in the selector section, not beside the hero name.
// Ethernet has no equivalent selector, so keep its negotiated link speed here.
function headerDetail(info) {
  var value = info || {}
  if (value.type === "ethernet") return formatHeaderSpeed(value.speed || "")
  return ""
}

function bandLabel(band) {
  if (band === "auto") return "Auto"
  if (!band) return ""
  return band + "ghz"
}

// Under Automatic the pills are hidden, so the header carries the live band
// instead -- "WI-FI BAND: 2.4GHZ". Once a band is pinned the pills are on
// screen and say it themselves, so the header drops back to a plain label.
function bandSectionTitle(selected, current) {
  if (selected !== "auto") return "WI-FI BAND"

  var label = bandLabel(current)
  if (label === "") return "WI-FI BAND"

  return "WI-FI BAND: " + label.toUpperCase()
}

function bandTooltip(band) {
  if (band === "auto") return "Let Wi-Fi pick the band"
  if (!band) return ""
  return "Stay on " + bandLabel(band)
}

function parseBandStatus(raw) {
  var next = parseKeyValue(raw)
  var tokens = String(next.available || "").split(" ")
  var available = []

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "") available.push(tokens[i])
  }

  return {
    band: next.band || "",
    selected: next.selected || "auto",
    available: available
  }
}

function decodeIwSsid(value) {
  var raw = String(value || "")

  try {
    var encoded = ""

    for (var i = 0; i < raw.length; i++) {
      if (raw[i] === "\\" && raw[i + 1] === "x" && /^[0-9a-f]{2}$/i.test(raw.substring(i + 2, i + 4))) {
        var hex = raw.substring(i + 2, i + 4)
        var byte = parseInt(hex, 16)
        encoded += byte < 32 || byte === 127 ? encodeURIComponent(raw.substring(i, i + 4)) : "%" + hex
        i += 3
      } else {
        encoded += encodeURIComponent(raw[i])
      }
    }

    return decodeURIComponent(encoded)
  } catch (error) {
    return raw
  }
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var idx = line.indexOf("\t")
    if (idx === -1) continue
    var key = line.substring(0, idx)
    var value = line.substring(idx + 1)
    next[key] = key === "ssid" ? decodeIwSsid(value) : value.trim()
  }
  return next
}

function throughputState(previous, next, now) {
  var prev = previous || {}
  var sample = next || {}
  var iface = sample.iface || ""
  var rx = parseFloat(sample.rx_bytes || "0")
  var tx = parseFloat(sample.tx_bytes || "0")
  var previousTime = Number(prev.prevSampleTime || 0)

  if (iface !== (prev.prevIface || "") || previousTime === 0) {
    return {
      prevIface: iface,
      prevRxBytes: rx,
      prevTxBytes: tx,
      prevSampleTime: now,
      downloadRate: 0,
      uploadRate: 0
    }
  }

  var downloadRate = Number(prev.downloadRate || 0)
  var uploadRate = Number(prev.uploadRate || 0)
  var dt = now - previousTime
  if (dt > 0) {
    downloadRate = Math.max(0, (rx - Number(prev.prevRxBytes || 0)) / dt)
    uploadRate = Math.max(0, (tx - Number(prev.prevTxBytes || 0)) / dt)
  }

  return {
    prevIface: iface,
    prevRxBytes: rx,
    prevTxBytes: tx,
    prevSampleTime: now,
    downloadRate: downloadRate,
    uploadRate: uploadRate
  }
}

function pingSampleValue(raw) {
  var value = parseFloat(raw)
  if (!isFinite(value) || value < 0) return null
  return value
}

function appendPingSample(samples, raw, limit) {
  var values = Array.isArray(samples) ? samples.slice() : []

  values.push(pingSampleValue(raw))
  while (values.length > limit) values.shift()

  return values
}

function averagePingLatency(samples, limit) {
  var values = Array.isArray(samples) ? samples : []
  var sampleLimit = Math.max(1, parseInt(limit, 10) || values.length || 1)
  var total = 0
  var count = 0

  for (var i = Math.max(0, values.length - sampleLimit); i < values.length; i++) {
    var value = values[i]
    if (typeof value !== "number" || !isFinite(value) || value < 0) continue
    total += value
    count++
  }

  return count > 0 ? total / count : -1
}

function pingPacketLossPercent(samples) {
  var values = Array.isArray(samples) ? samples : []
  if (values.length === 0) return 0

  var lost = 0
  for (var i = 0; i < values.length; i++) {
    if (values[i] === null) lost++
  }

  return Math.round((lost / values.length) * 100)
}

function formatPacketLoss(percent, hasSamples) {
  if (hasSamples === false) return "--"

  var value = parseInt(percent, 10)
  if (!value || value < 0) return "0%"
  return value + "%"
}

function pingLatencyState(previous, next, limit, averageLimit) {
  var prev = previous || {}
  var sample = next || {}
  var iface = sample.iface || ""
  var window = Math.max(1, parseInt(limit, 10) || 5)
  var averageWindow = Math.max(1, parseInt(averageLimit, 10) || window)
  var reset = iface === "" || iface !== (prev.pingIface || "")
  var routerSamples = reset ? [] : prev.routerPingSamples
  var internetSamples = reset ? [] : prev.internetPingSamples

  routerSamples = sample.router_ping_ms === undefined ? [] : appendPingSample(routerSamples, sample.router_ping_ms, window)
  internetSamples = sample.internet_ping_ms === undefined ? [] : appendPingSample(internetSamples, sample.internet_ping_ms, window)

  return {
    pingIface: iface,
    routerPingSamples: routerSamples,
    internetPingSamples: internetSamples,
    routerPingLatency: averagePingLatency(routerSamples, averageWindow),
    internetPingLatency: averagePingLatency(internetSamples, averageWindow),
    internetPingPacketLoss: pingPacketLossPercent(internetSamples)
  }
}

function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
  if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
  return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
}

function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}

// `hasSamples` false means no probe has come back yet, which is different from
// a probe that timed out. The rows stay mounted through that gap and read "--"
// so the grid doesn't reflow a second after the panel opens.
function formatPingLatency(ms, hasSamples) {
  if (hasSamples === false) return "--"

  var value = parseFloat(ms)
  if (!isFinite(value) || value < 0) return "Timeout"
  return value.toFixed(value > 0 && value < 10 ? 1 : 0) + " ms"
}

function wifiRow(network) {
  if (!network) return null
  // Primitives only: rows become list-model data, so a WifiNetwork here puts a
  // live QObject wrapper in every delegate's var property. NetworkManager churn
  // (scans, AP removals) can destroy the object while a delegate is still
  // incubating, which segfaults quickshell in wrap_slowPath on the dangling
  // wrapper. Callers that need the object resolve it via networkForSsid().
  return {
    connected: !!network.connected,
    known: !!network.known,
    ssid: network.name || "",
    signal: Math.round((network.signalStrength || 0) * 100),
    security: network.security
  }
}

function sortWifiRows(rows) {
  var nets = Array.isArray(rows) ? rows.slice() : []
  nets.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    if (a.known !== b.known) return a.known ? -1 : 1
    return b.signal - a.signal
  })
  return nets
}

function wifiSectionTitle(wifiNetworks, index) {
  var networks = Array.isArray(wifiNetworks) ? wifiNetworks : []
  if (index < 0 || index >= networks.length) return ""

  var net = networks[index]
  if (!net) return ""

  if (net.known && index === 0) return "KNOWN NETWORKS"
  if (!net.known && (index === 0 || (networks[index - 1] && networks[index - 1].known))) return "OTHER NETWORKS"
  return ""
}

// OWE (Enhanced Open) encrypts traffic without authenticating the user, so it
// has no credentials to collect. The panel's lock is a credentials-required
// affordance, so OWE should neither show it nor open its attached prompt.
function requiresCredentials(security, openSecurity, oweSecurity) {
  // Only explicit passwordless types bypass the prompt. Unknown security
  // stays credentialed as the conservative fallback.
  return security !== openSecurity && security !== oweSecurity
}

function canForgetNetwork(network) {
  return !!(network && network.known && !network.connected)
}

// The password arrives on stdin and reaches nmcli through the scriptable
// `connection edit` editor -- argv is world-readable in /proc, so the secret
// must never be an argument (printf is a bash builtin, so no process spawns
// with it either).
var enterpriseConnectScript =
  "u=$(uuidgen); IFS= read -r pw;" +
  " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" +
  " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
  " 802-1x.identity \"$2\" 802-1x.auth-timeout 8 >/dev/null" +
  " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" +
  " && nmcli connection up uuid \"$u\"" +
  " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

function networkFailureReason(reason, needsCredentials, reasons) {
  var r = reasons || {}
  if (needsCredentials && reason === r.NoSecrets) return "Passphrase required"
  if (needsCredentials && reason === r.WifiAuthTimeout) return "Wrong password"
  if (reason === r.WifiNetworkLost) return "Network lost"
  if (reason === r.WifiClientDisconnected) return "Disconnected"
  if (reason === r.WifiClientFailed) return "Connection failed"
  return "Failed to connect"
}

// Whether a failed connect should reopen the passphrase prompt. NoSecrets
// means credentials are missing only for a network that actually uses them.
// An auth timeout on such a network means the saved passphrase is wrong (the
// same profile a first failed attempt leaves behind as "known"), so the user
// needs a chance to re-enter it -- connectWithPsk overwrites the stored PSK on
// submit.
function shouldRepromptPassphrase(reason, needsCredentials, reasons) {
  var r = reasons || {}
  if (!needsCredentials) return false
  return reason === r.NoSecrets || reason === r.WifiAuthTimeout
}

// Parse `protonvpn status` output into a simple state object.
// Connected example:
//   Status: Connected
//   Server: IT#23 in Milan, Italy
//   Load: 42%
//   Protocol: wireguard
// Disconnected example:
//   Status: Disconnected
function parseProtonStatus(raw) {
  var text = String(raw || "")
  var connected = /^Status:\s*Connected\b/im.test(text)
  var server = ""
  var location = ""
  var m = text.match(/^Server:\s*(.+)$/im)
  if (m) {
    var serverLine = String(m[1] || "").trim()
    var inIdx = serverLine.indexOf(" in ")
    if (inIdx >= 0) {
      server = serverLine.slice(0, inIdx).trim()
      location = serverLine.slice(inIdx + 4).trim()
    } else {
      server = serverLine
    }
  }
  return {
    connected: connected,
    server: server,
    location: location,
    label: connected
      ? (location ? (server ? server + " · " + location : location) : (server || "Connected"))
      : ""
  }
}

// `protonvpn info` prints: Account: 'name'
// When signed out it still exits 0 with Account: 'None'.
function parseProtonAccount(raw) {
  var m = String(raw || "").match(/Account:\s*'([^']*)'/i)
  if (!m) return ""
  var name = String(m[1] || "").trim()
  if (!name || name.toLowerCase() === "none") return ""
  return name
}

function protonAuthRequired(raw) {
  var text = String(raw || "").toLowerCase()
  return text.indexOf("authentication") >= 0
    || text.indexOf("sign in") >= 0
    || text.indexOf("not signed") >= 0
    || text.indexOf("please sig") >= 0
}

// ---------------------------------------------------------------------------
// Stored profiles, link facts and host extras
//
// The plugin's own probes (net-profiles.sh, net-link.sh, net-extras.sh,
// net-scan.sh) all emit the same shape: `key<TAB>value` lines, records
// separated by a line holding only `--`. Backslash, tab and carriage return are
// escaped by the probe because an SSID or a profile name is an arbitrary byte
// string and none of them are guaranteed to avoid any of those.
//
// Everything below is pure so it stays testable outside the shell.
// ---------------------------------------------------------------------------

// Reverse of the probe-side escaping. Unescaping has to run as a single pass:
// a literal `\t` in an SSID is indistinguishable from an escape sequence once
// the substitutions start rewriting backslashes.
function unescapeField(value) {
  var raw = String(value === undefined || value === null ? "" : value)
  var out = ""
  for (var i = 0; i < raw.length; i++) {
    var ch = raw.charAt(i)
    if (ch !== "\\") {
      out += ch
      continue
    }
    var next = raw.charAt(i + 1)
    if (next === "t") out += "\t"
    else if (next === "\\") out += "\\"
    else out += "\\"
    i++
  }
  return out
}

// `key<TAB>value` lines grouped into records on the `--` separator.
function parseRecords(raw) {
  var text = String(raw || "")
  var lines = text.split("\n")
  var records = []
  var current = null

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.charAt(line.length - 1) === "\r") line = line.slice(0, -1)
    if (line === "") continue

    if (line === "--") {
      if (current) records.push(current)
      current = null
      continue
    }

    var tab = line.indexOf("\t")
    if (tab === -1) continue
    if (!current) current = {}

    var key = unescapeField(line.slice(0, tab))
    var value = unescapeField(line.slice(tab + 1))

    // A probe that appends a second section header without terminating the
    // record puts two `kind` keys in one record. Keeping only the last would
    // orphan the first section's fields, so a repeated key collects into an
    // array and the section readers below iterate it.
    if (Object.prototype.hasOwnProperty.call(current, key)) {
      if (Array.isArray(current[key])) current[key].push(value)
      else current[key] = [current[key], value]
    } else {
      current[key] = value
    }
  }

  if (current) records.push(current)
  return records
}

// Every `kind` a record declares, in order. A record from a well-formed probe
// has exactly one; a merged one is still fully readable.
function kindList(record) {
  if (!record || !Object.prototype.hasOwnProperty.call(record, "kind")) return []
  var value = record.kind
  if (Array.isArray(value)) return value
  return [String(value)]
}

// nmcli reports these as the literal placeholder when a field is unset.
function isUnset(value) {
  var v = String(value === undefined || value === null ? "" : value).trim()
  return v === "" || v === "--"
}

function cleanField(record, key) {
  if (!record) return ""
  var value = record[key]
  // A repeated key arrives as an array; the last occurrence is the one the
  // probe wrote most recently, which is the one that applies.
  if (Array.isArray(value)) value = value.length ? value[value.length - 1] : ""
  return isUnset(value) ? "" : String(value).trim()
}

function intField(record, key, fallback) {
  var value = parseInt(cleanField(record, key), 10)
  return isFinite(value) ? value : fallback
}

// Profiles, ordered the way the panel shows them: Wi-Fi before Ethernet, then
// auto-connect priority (descending), then name. A saved profile that
// autoconnects outranks one that does not, because that is the order
// NetworkManager itself will consider them in.
function sortProfiles(profiles) {
  var list = Array.isArray(profiles) ? profiles.slice() : []
  list.sort(function(a, b) {
    var aWifi = a.type === "802-11-wireless" ? 0 : 1
    var bWifi = b.type === "802-11-wireless" ? 0 : 1
    if (aWifi !== bWifi) return aWifi - bWifi
    if (a.priority !== b.priority) return b.priority - a.priority
    if (a.autoconnect !== b.autoconnect) return a.autoconnect ? -1 : 1
    return String(a.name || "").localeCompare(String(b.name || ""))
  })
  return list
}

function parseProfileRecord(record) {
  if (!record) return null
  var uuid = cleanField(record, "uuid")
  if (!uuid) return null

  return {
    uuid: uuid,
    name: cleanField(record, "name") || uuid,
    type: cleanField(record, "type"),
    iface: cleanField(record, "iface"),
    autoconnect: cleanField(record, "autoconnect") === "yes",
    priority: intField(record, "priority", 0),
    method: cleanField(record, "method"),
    addresses: cleanField(record, "addresses"),
    gateway: cleanField(record, "gateway"),
    dns: cleanField(record, "dns"),
    ssid: cleanField(record, "ssid"),
    clonedMac: cleanField(record, "clonedMac"),
    wol: cleanField(record, "wol"),
    pinnedSpeed: intField(record, "pinnedSpeed", 0),
    pinnedDuplex: cleanField(record, "pinnedDuplex"),
    eap: cleanField(record, "eap") === "yes",
    active: cleanField(record, "active"),
    isWifi: cleanField(record, "type") === "802-11-wireless",
    isWired: cleanField(record, "type") === "802-3-ethernet"
  }
}

// net-profiles.sh output -> { profiles, blocklist }. Blocklist entries are
// BSSIDs; they are kept as a set-like array because the probe sorts and dedupes
// but the panel only ever asks "is this one present".
function parseProfiles(raw) {
  var records = parseRecords(raw)
  var profiles = []
  var blocklist = []
  var section = ""

  for (var i = 0; i < records.length; i++) {
    var kind = cleanField(records[i], "kind")
    if (kind === "profiles") { section = "profiles"; continue }
    if (kind === "blocklist") { section = "blocklist"; continue }
    if (section === "") continue

    if (section === "blocklist") {
      var bssid = cleanField(records[i], "bssid")
      if (bssid) blocklist.push(bssid.toLowerCase())
      continue
    }

    // A record that still carries data after a `kind` header belongs to that
    // section, so parse it rather than dropping it. The probes terminate every
    // header with `--`, but losing a profile silently is too expensive a
    // failure mode to rely on that alone.
    var profile = parseProfileRecord(records[i])
    if (profile) profiles.push(profile)
  }

  return { profiles: sortProfiles(profiles), blocklist: blocklist }
}

function isBlocked(blocklist, bssid) {
  if (!bssid) return false
  var list = Array.isArray(blocklist) ? blocklist : []
  var needle = String(bssid).toLowerCase()
  for (var i = 0; i < list.length; i++) {
    if (String(list[i]).toLowerCase() === needle) return true
  }
  return false
}

function parseLink(raw) {
  var records = parseRecords(raw)
  var link = {
    exists: false,
    operstate: "",
    carrier: "",
    mtu: "",
    mac: "",
    speed: "",
    duplex: "",
    phyType: "",
    driver: "",
    autoNegotiated: "",
    ethtool: false,
    ethtoolSpeed: "",
    ethtoolDuplex: "",
    autoneg: "",
    linkDetected: "",
    maxSpeed: 0,
    rxErrors: null,
    txErrors: null,
    rxDropped: null,
    txDropped: null,
    rxCrcErrors: null,
    collisions: null
  }

  for (var i = 0; i < records.length; i++) {
    var record = records[i]

    // Selected by the presence of `exists` rather than by a `kind` header:
    // the probe emits the header as its own record, and keying off the header
    // would silently skip the very record that carries the data.
    if (!Object.prototype.hasOwnProperty.call(record, "exists")) continue
    if (cleanField(record, "exists") !== "yes") return link

    link.exists = true
    link.operstate = cleanField(record, "operstate")
    link.carrier = cleanField(record, "carrier")
    link.mtu = cleanField(record, "mtu")
    link.mac = cleanField(record, "mac")
    link.speed = cleanField(record, "speed")
    link.duplex = cleanField(record, "duplex")
    link.phyType = cleanField(record, "phyType")
    link.driver = cleanField(record, "driver")
    link.autoNegotiated = cleanField(record, "autoNegotiated")
    link.ethtool = cleanField(record, "ethtool") === "yes"
    link.ethtoolSpeed = cleanField(record, "ethtoolSpeed")
    link.ethtoolDuplex = cleanField(record, "ethtoolDuplex")
    link.autoneg = cleanField(record, "autoneg")
    link.linkDetected = cleanField(record, "linkDetected")
    link.maxSpeed = intField(record, "maxSpeed", 0)

    // Counters are emitted only when the kernel accounts them, so a null here
    // means "not available for this interface", never "zero".
    var counters = {
      rxErrors: "rxErrors",
      txErrors: "txErrors",
      rxDropped: "rxDropped",
      txDropped: "txDropped",
      rxCrcErrors: "rxCrcErrors",
      collisions: "collisions"
    }
    for (var key in counters) {
      if (!Object.prototype.hasOwnProperty.call(counters, key)) continue
      var raw2 = record[counters[key]]
      if (!isUnset(raw2)) link[key] = intField(record, counters[key], 0)
    }
    break
  }

  return link
}

// The one actionable thing a link probe can tell you: the negotiated speed is
// below what the hardware or the profile asked for. Returns "" when there is
// nothing wrong, and a null when the facts are insufficient to judge -- the
// panel must not claim a fault it cannot evidence.
function linkSpeedWarning(link, profile) {
  if (!link || !link.exists) return ""
  if (link.operstate !== "up") return ""

  var negotiated = parseInt(link.speed, 10)
  if (!isFinite(negotiated) || negotiated <= 0) return ""

  // A profile that pins a speed and negotiated lower is unambiguously wrong:
  // the user asked for a rate the link did not deliver.
  var pinned = profile && profile.pinnedSpeed ? parseInt(profile.pinnedSpeed, 10) : 0
  if (isFinite(pinned) && pinned > 0 && negotiated < pinned) {
    return "Linked at " + formatLinkSpeed(negotiated) + ", profile asks for " + formatLinkSpeed(pinned)
  }

  // Otherwise the ceiling is the NIC's own fastest supported mode, which needs
  // ethtool. Without it there is nothing to compare against.
  if (link.maxSpeed > 0 && negotiated < link.maxSpeed) {
    return "Linked at " + formatLinkSpeed(negotiated) + " of " + formatLinkSpeed(link.maxSpeed) + " supported"
  }

  return ""
}

// Half duplex on a modern gigabit-capable port is almost always a cable or
// autoneg fault, and it is worth saying so rather than showing "500 Mbit/s".
function linkDuplexWarning(link) {
  if (!link || !link.exists) return ""
  if (link.operstate !== "up") return ""
  if (String(link.duplex).toLowerCase() !== "half") return ""
  return "Half duplex"
}

function formatLinkSpeed(mbps) {
  var value = parseInt(mbps, 10)
  if (!isFinite(value) || value <= 0) return ""
  if (value >= 1000) {
    var gbit = value / 1000
    return (Math.round(gbit * 10) / 10) + "gbit"
  }
  return value + "mbit"
}

function parseScan(raw) {
  var records = parseRecords(raw)
  var out = []
  for (var i = 0; i < records.length; i++) {
    var record = records[i]
    var kind = cleanField(record, "kind")
    if (kind === "scan" || cleanField(record, "bssid") === "") continue
    var bssid = cleanField(record, "bssid")
    if (!bssid) continue
    out.push({
      ssid: cleanField(record, "ssid"),
      bssid: bssid,
      mode: cleanField(record, "mode"),
      band: cleanField(record, "band"),
      chan: cleanField(record, "chan"),
      freq: cleanField(record, "freq"),
      rate: cleanField(record, "rate"),
      signal: intField(record, "signal", -1),
      security: cleanField(record, "security"),
      inUse: cleanField(record, "inUse") === "yes",
      dbm: cleanField(record, "dbm"),
      width: cleanField(record, "width"),
      rxBitrate: cleanField(record, "rxBitrate"),
      txBitrate: cleanField(record, "txBitrate")
    })
  }
  return out
}

// Best per-SSID view of the scan detail: a band-steered AP reports one BSSID
// per band, and the row is keyed on SSID, so prefer the in-use BSSID, then the
// strongest, then the 5/6 GHz one.
function scanRecordForSsid(scan, ssid) {
  var list = Array.isArray(scan) ? scan : []
  var needle = String(ssid === undefined || ssid === null ? "" : ssid)
  var best = null

  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || entry.ssid !== needle) continue
    if (entry.inUse) return entry
    if (!best) { best = entry; continue }
    if (entry.signal > best.signal) best = entry
  }
  return best
}

function parseExtras(raw) {
  var records = parseRecords(raw)
  var extras = {
    dns: [],
    dnsCount: 0,
    dnsUnavailable: false,
    v6: [],
    v6Count: 0,
    firewallUnit: "",
    firewallRules: null,
    firewallReadable: false,
    tailscale: { installed: false, state: "", hostName: "", dnsName: "", ipv4: "", activePeers: 0, tailnetPeers: 0, exitNode: false }
  }

  // One pass, no section state. Every record is mined for the keys it happens
  // to carry: a `kind` header names the section a record's named fields belong
  // to, while the positional dns1../v6.. families are recognised by shape and
  // are only ever emitted inside the extras section. Deriving sections from
  // record boundaries was the bug this replaces -- a probe that appends a
  // header without terminating the previous record silently orphaned a whole
  // field family, and no amount of parser strictness catches that.
  for (var i = 0; i < records.length; i++) {
    var record = records[i]

    // A record may declare more than one section when a probe appends a header
    // without terminating the previous record, so every declared kind is
    // applied rather than just the last.
    var kinds = kindList(record)
    for (var k = 0; k < kinds.length; k++) {
      var kind = String(kinds[k]).trim()

      if (kind === "extras") {
        if (cleanField(record, "dnsUnavailable") === "yes") extras.dnsUnavailable = true
        var unit = cleanField(record, "firewallUnit")
        if (unit) extras.firewallUnit = unit
        if (cleanField(record, "firewallReadable") === "yes") {
          extras.firewallReadable = true
          extras.firewallRules = intField(record, "firewallRules", 0)
        }
      } else if (kind === "tailscale") {
        if (cleanField(record, "installed") === "yes") extras.tailscale.installed = true
        var state = cleanField(record, "backendState")
        if (state) extras.tailscale.state = state
        extras.tailscale.hostName = cleanField(record, "hostName")
        extras.tailscale.dnsName = cleanField(record, "dnsName")
        extras.tailscale.ipv4 = cleanField(record, "ipv4")
        extras.tailscale.activePeers = intField(record, "activePeers", 0)
        extras.tailscale.tailnetPeers = intField(record, "tailnetPeers", 0)
        if (cleanField(record, "exitNode") === "true") extras.tailscale.exitNode = true
      }
    }

    for (var key in record) {
      if (!Object.prototype.hasOwnProperty.call(record, key)) continue
      if (/^dns[0-9]+$/.test(key)) extras.dns.push(record[key])
      else if (/^v6[0-9]+$/.test(key)) extras.v6.push(record[key])
    }
  }

  extras.dnsCount = extras.dns.length
  extras.v6Count = extras.v6.length

  return extras
}

// Firewall posture, from what the probe could actually establish.
//
// The sudo check is incidental and must not drive the headline: on a machine
// with no nftables service at all, the ruleset is unreadable for the same
// reason it is empty, and reporting "needs root" there would imply rules exist
// to be counted. `systemctl is-active` answers "inactive" for both a stopped
// unit and one that is not installed, so "Not running" is the most this can
// honestly claim.
function firewallLabel(extras) {
  if (!extras) return "Unknown"

  // The probe has not reported yet: this is "not probed", not "not running".
  var probed = extras.firewallUnit !== undefined || extras.firewallReadable !== undefined
  if (!probed) return "Unknown"

  if (extras.firewallUnit !== "active") return "Not running"
  if (!extras.firewallReadable) return "Running · count needs root"

  var rules = extras.firewallRules === null || extras.firewallRules === undefined ? 0 : extras.firewallRules
  if (rules === 0) return "Running · no rules"
  return "Running · " + rules + " rule" + (rules === 1 ? "" : "s")
}

// Tailscale's BackendState is a fixed vocabulary; only the states that mean
// something actionable to a person get a sentence.
function tailscaleLabel(tailscale) {
  if (!tailscale) return ""
  if (!tailscale.installed) return "Not installed"
  switch (tailscale.state) {
    case "Running":
      return "Connected" + (tailscale.ipv4 ? " · " + tailscale.ipv4 : "")
    case "Stopped":
      return "Stopped"
    case "NeedsLogin":
      return "Needs sign-in"
    case "NeedsMachineAuth":
      return "Needs machine authorisation"
    case "Starting":
      return "Starting"
    case "NoState":
      return ""
    default:
      return tailscale.state || "Unknown"
  }
}

function tailscaleBusy(tailscale) {
  if (!tailscale || !tailscale.installed) return false
  return tailscale.state === "Starting" || tailscale.state === "Stopping"
}

// nmcli's ipv4.method vocabulary, as something a person would say. "auto" and
// "dhcp" both mean the lease came from the network. An unset property arrives
// as the literal placeholder, which is not a method and must not be echoed
// back to the user as one.
function profileMethodLabel(method, addresses) {
  if (isUnset(method)) return "Unknown"
  var value = String(method).toLowerCase()
  switch (value) {
    case "auto":
    case "dhcp":
    case "auto6":
      return "DHCP"
    case "manual":
      return addresses ? "Static" : "Static · unset"
    case "shared":
      return "Shared"
    case "link-local":
      return "Link-local"
    case "disabled":
      return "Disabled"
    case "":
      return "Unknown"
    default:
      return value
  }
}

function profileIsManual(profile) {
  if (!profile) return false
  return String(profile.method || "").toLowerCase() === "manual"
}

function profileIsDhcp(profile) {
  if (!profile) return false
  var value = String(profile.method || "").toLowerCase()
  return value === "auto" || value === "dhcp" || value === "auto6"
}

// Strict IPv4 validation shared by the static profile editor and temporary
// device setup flow. A shape-only regexp accepted values such as 999.2.3.4.
function isIPv4(value) {
  var parts = String(value === undefined || value === null ? "" : value).trim().split(".")
  if (parts.length !== 4) return false
  for (var i = 0; i < parts.length; i++) {
    if (!/^\d{1,3}$/.test(parts[i])) return false
    var octet = Number(parts[i])
    if (octet < 0 || octet > 255) return false
  }
  return true
}

function ipv4InSubnet(address, networkAddress, prefix) {
  if (!isIPv4(address) || !isIPv4(networkAddress)) return false
  var bits = parseInt(prefix, 10)
  if (!isFinite(bits) || bits < 0 || bits > 32) return false
  function number(ip) {
    return String(ip).split(".").reduce(function(value, part) {
      return value * 256 + Number(part)
    }, 0)
  }
  var mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0
  return ((number(address) >>> 0) & mask) === ((number(networkAddress) >>> 0) & mask)
}

function ipv4UsableHost(address, prefix) {
  if (!isIPv4(address)) return false
  var bits = parseInt(prefix, 10)
  if (!isFinite(bits) || bits < 1 || bits > 32) return false
  if (bits >= 31) return true
  var value = String(address).split(".").reduce(function(total, octet) {
    return total * 256 + Number(octet)
  }, 0) >>> 0
  var hostBits = 32 - bits
  var hostMask = Math.pow(2, hostBits) - 1
  var host = value & hostMask
  return host !== 0 && host !== hostMask
}

// nmcli represents "use the permanent hardware address" as the placeholder.
function clonedMacLabel(value) {
  var raw = String(value === undefined || value === null ? "" : value).trim()
  if (raw === "" || raw === "--") return "Permanent"
  if (/^(preserve|permanent|random)$/i.test(raw)) return raw.charAt(0).toUpperCase() + raw.slice(1)
  return raw
}

function wolLabel(value) {
  var raw = String(value === undefined || value === null ? "" : value).trim()
  if (raw === "" || raw === "--" || raw === "0") return "Off"
  return "Magic packet"
}

// Human label for a network's protection, replacing the single lock glyph.
// The enum is passed in so this stays a pure function.
function securityLabel(security, types) {
  if (!types) return ""
  switch (security) {
    case types.Wpa3SuiteB192: return "WPA3 192-bit"
    case types.Sae: return "WPA3"
    case types.Wpa2Eap: return "WPA2 Enterprise"
    case types.Wpa2Psk: return "WPA2"
    case types.WpaEap: return "Enterprise"
    case types.WpaPsk: return "WPA"
    case types.StaticWep: return "WEP"
    case types.DynamicWep: return "WEP"
    case types.Leap: return "LEAP"
    case types.Owe: return "OWE"
    case types.Open: return "Open"
    default: return ""
  }
}

// Channel width comes from `iw link`, which reports it for 5/6 GHz links and
// omits it for 20 MHz 2.4 GHz ones.
//
// It is deliberately NOT inferred from the negotiated bitrate: for a single
// spatial stream 802.11ac puts both 40 MHz and 80 MHz at 866.7 Mbit/s, and
// 802.11ax puts 20 MHz and 80 MHz at the same rate too, so any threshold
// either invents a width the link does not have or hides one it does.
function channelWidthLabel(record) {
  var raw = String(record && record.width ? record.width : "").trim()
  if (raw === "" || raw === "--") return ""
  var value = parseInt(raw, 10)
  if (!isFinite(value) || value <= 0) return ""
  return value + " MHz"
}

function signalQualityLabel(dbm) {
  var value = parseFloat(dbm)
  if (!isFinite(value)) return ""
  if (value >= -50) return "Excellent"
  if (value >= -60) return "Good"
  if (value >= -70) return "Fair"
  if (value >= -80) return "Weak"
  return "Very weak"
}

function formatMtu(value) {
  var mtu = parseInt(value, 10)
  return isFinite(mtu) && mtu > 0 ? String(mtu) : ""
}

// Thousands separators without Intl/Qt, so this stays a pure function the
// Node test harness can call.
function formatCounter(value) {
  if (value === null || value === undefined) return "--"
  var n = parseInt(value, 10)
  if (!isFinite(n)) return "--"

  var negative = n < 0
  var digits = String(Math.abs(n))
  var grouped = ""
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) grouped += ","
    grouped += digits.charAt(i)
  }
  return (negative ? "-" : "") + grouped
}

function formatBitsPerSecond(bits) {
  var value = parseFloat(bits)
  if (!isFinite(value) || value <= 0) return ""
  if (value >= 1000000000) return trimZero(value / 1000000000) + " Gbit/s"
  if (value >= 1000000) return trimZero(value / 1000000) + " Mbit/s"
  if (value >= 1000) return trimZero(value / 1000) + " kbit/s"
  return value + " bit/s"
}

function trimZero(number) {
  var rounded = Math.round(number * 10) / 10
  return String(rounded)
}

// Public address lookup: the probe returns the address on stdout, and the exit
// code is what distinguishes "no route", "DNS failure" and "a page that is not
// the API" -- three states a user reads very differently.
function publicIpState(raw, exitCode) {
  var text = String(raw || "").trim()
  if (exitCode !== 0 || text === "") return { ok: false, address: "" }
  if (!/^[0-9a-fA-F:.]{3,45}$/.test(text)) return { ok: false, address: "" }
  return { ok: true, address: text }
}

// Rate history for the throughput sparkline. The panel already computes
// instantaneous rates from consecutive byte counters; this keeps the last N of
// them so the same numbers can be drawn as a shape.
function rateSeries(previous, download, upload, limit) {
  var list = Array.isArray(previous) ? previous.slice() : []
  var window = Math.max(1, parseInt(limit, 10) || 48)
  list.push({ down: Math.max(0, Number(download) || 0), up: Math.max(0, Number(upload) || 0) })
  while (list.length > window) list.shift()
  return list
}

function rateSeriesPeak(series) {
  var list = Array.isArray(series) ? series : []
  var peak = 0
  for (var i = 0; i < list.length; i++) {
    if (!list[i]) continue
    if (list[i].down > peak) peak = list[i].down
    if (list[i].up > peak) peak = list[i].up
  }
  return peak
}

if (typeof module !== "undefined") {
  module.exports = {
    parseNetworkStatus: parseNetworkStatus,
    wifiIconFor: wifiIconFor,
    connectionIcon: connectionIcon,
    connectivityState: connectivityState,
    captivePortalUrl: captivePortalUrl,
    formatHeaderSpeed: formatHeaderSpeed,
    formatHeaderFreq: formatHeaderFreq,
    headerDetail: headerDetail,
    bandLabel: bandLabel,
    bandSectionTitle: bandSectionTitle,
    bandTooltip: bandTooltip,
    parseBandStatus: parseBandStatus,
    decodeIwSsid: decodeIwSsid,
    parseKeyValue: parseKeyValue,
    throughputState: throughputState,
    pingLatencyState: pingLatencyState,
    pingPacketLossPercent: pingPacketLossPercent,
    formatPacketLoss: formatPacketLoss,
    formatBytes: formatBytes,
    formatRate: formatRate,
    formatPingLatency: formatPingLatency,
    wifiRow: wifiRow,
    sortWifiRows: sortWifiRows,
    wifiSectionTitle: wifiSectionTitle,
    requiresCredentials: requiresCredentials,
    canForgetNetwork: canForgetNetwork,
    enterpriseConnectScript: enterpriseConnectScript,
    networkFailureReason: networkFailureReason,
    shouldRepromptPassphrase: shouldRepromptPassphrase,
    parseProtonStatus: parseProtonStatus,
    parseProtonAccount: parseProtonAccount,
    protonAuthRequired: protonAuthRequired,
    unescapeField: unescapeField,
    parseRecords: parseRecords,
    parseProfiles: parseProfiles,
    sortProfiles: sortProfiles,
    isBlocked: isBlocked,
    parseLink: parseLink,
    parseScan: parseScan,
    scanRecordForSsid: scanRecordForSsid,
    parseExtras: parseExtras,
    linkSpeedWarning: linkSpeedWarning,
    linkDuplexWarning: linkDuplexWarning,
    formatLinkSpeed: formatLinkSpeed,
    firewallLabel: firewallLabel,
    tailscaleLabel: tailscaleLabel,
    tailscaleBusy: tailscaleBusy,
    profileMethodLabel: profileMethodLabel,
    profileIsManual: profileIsManual,
    profileIsDhcp: profileIsDhcp,
    isIPv4: isIPv4,
    ipv4InSubnet: ipv4InSubnet,
    ipv4UsableHost: ipv4UsableHost,
    clonedMacLabel: clonedMacLabel,
    wolLabel: wolLabel,
    securityLabel: securityLabel,
    channelWidthLabel: channelWidthLabel,
    signalQualityLabel: signalQualityLabel,
    formatMtu: formatMtu,
    formatCounter: formatCounter,
    formatBitsPerSecond: formatBitsPerSecond,
    publicIpState: publicIpState,
    rateSeries: rateSeries,
    rateSeriesPeak: rateSeriesPeak
  }
}
