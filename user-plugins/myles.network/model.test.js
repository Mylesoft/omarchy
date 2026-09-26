// Node test harness for the pure layer of myles.network's Model.js.
//
// The shell plugins are exercised against the real probes separately; this file
// covers the parsing and formatting that both the panel and those tests depend
// on. Run with: node model.test.js
//
// Deliberately dependency-free -- this lives inside a Quickshell plugin folder
// and must stay runnable with a bare node.

const M = require("./Model.js");

let passed = 0;
let failed = 0;

function eq(name, got, want) {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    passed++;
    return;
  }
  failed++;
  console.log("FAIL " + name + "\n  got:  " + g + "\n  want: " + w);
}

function ok(name, condition) {
  eq(name, !!condition, true);
}

// ---- escaping ---------------------------------------------------------------

// The probe escapes backslash first, then tab. Unescaping has to be a single
// pass or a literal "\t" inside an SSID round-trips into a real tab.
eq("unescape escaped tab", M.unescapeField("a\\tb"), "a\tb");
eq("unescape escaped backslash", M.unescapeField("a\\\\b"), "a\\b");
eq("unescape literal backslash-t", M.unescapeField("a\\\\tb"), "a\\tb");
eq("unescape plain", M.unescapeField("plain"), "plain");
eq("unescape empty", M.unescapeField(""), "");
eq("unescape undefined", M.unescapeField(undefined), "");

// The full round trip a real SSID takes through the probe and back.
(function () {
  const nasty = "My\\Net\tName";
  const escaped = nasty.replace(/\\/g, "\\\\").replace(/\t/g, "\\t");
  eq("ssid round trip", M.unescapeField(escaped), nasty);
})();

// ---- record framing ---------------------------------------------------------

eq("records split on separator", M.parseRecords("a\t1\n--\nb\t2\n"), [
  { a: "1" },
  { b: "2" },
]);
eq("records tolerate CRLF", M.parseRecords("a\t1\r\n--\r\n"), [{ a: "1" }]);
eq("records drop empty lines", M.parseRecords("\n\na\t1\n\n"), [{ a: "1" }]);
eq("records skip lines without a tab", M.parseRecords("garbage\na\t1\n"), [{ a: "1" }]);
eq("records ignore blank value", M.parseRecords("a\t\n"), [{ a: "" }]);
eq("records handle unterminated tail", M.parseRecords("--\na\t1"), [{ a: "1" }]);

// ---- profiles ---------------------------------------------------------------

const PROFILE_RAW = [
  "kind\tprofiles",
  "--",
  "uuid\tuuid-wired",
  "name\tDesk",
  "type\t802-3-ethernet",
  "iface\tenp3s0",
  "autoconnect\tyes",
  "priority\t10",
  "method\tmanual",
  "addresses\t192.168.1.50/24",
  "gateway\t192.168.1.1",
  "dns\t1.1.1.1",
  "clonedMac\tpreserve",
  "wol\tmls",
  "pinnedSpeed\t2500",
  "pinnedDuplex\tfull",
  "eap\tno",
  "active\tenp3s0",
  "--",
  "uuid\tuuid-wifi-b",
  "name\tCafe",
  "type\t802-11-wireless",
  "autoconnect\tyes",
  "priority\t50",
  "method\tauto",
  "ssid\tCafe",
  "eap\tno",
  "--",
  "uuid\tuuid-wifi-a",
  "name\tAttic",
  "type\t802-11-wireless",
  "autoconnect\tno",
  "priority\t0",
  "method\tauto",
  "ssid\tAttic",
  "eap\tyes",
  "--",
  "kind\tblocklist",
  "--",
  "bssid\tD0:EA:11:B7:57:38",
  "--",
].join("\n");

(function () {
  const parsed = M.parseProfiles(PROFILE_RAW);
  eq("profile count", parsed.profiles.length, 3);
  // Wi-Fi first, then priority descending.
  eq("profile order", parsed.profiles.map(p => p.name), ["Cafe", "Attic", "Desk"]);
  eq("blocklist lowercased", parsed.blocklist, ["d0:ea:11:b7:57:38"]);

  const cafe = parsed.profiles[0];
  eq("wifi autoconnect", cafe.autoconnect, true);
  eq("wifi isWifi", cafe.isWifi, true);
  eq("wifi isWired", cafe.isWired, false);
  eq("wifi ssid", cafe.ssid, "Cafe");
  eq("wifi eap", cafe.eap, false);

  const attic = parsed.profiles[1];
  eq("autoconnect no parses false", attic.autoconnect, false);
  eq("eap yes parses true", attic.eap, true);

  const desk = parsed.profiles[2];
  eq("wired iface", desk.iface, "enp3s0");
  eq("wired priority", desk.priority, 10);
  eq("wired manual", M.profileIsManual(desk), true);
  eq("wired dhcp", M.profileIsDhcp(desk), false);
  eq("wired addresses", desk.addresses, "192.168.1.50/24");
  eq("wired pinned speed", desk.pinnedSpeed, 2500);
  eq("wired active", desk.active, "enp3s0");
  eq("cloned mac preserve", M.clonedMacLabel(desk.clonedMac), "Preserve");
  eq("wol magic", M.wolLabel(desk.wol), "Magic packet");
})();

// The ordering rule is the whole point of sortProfiles, so pin it directly.
eq(
  "sort puts wifi first and priority desc",
  M.sortProfiles([
    { type: "802-3-ethernet", priority: 100, autoconnect: true, name: "E" },
    { type: "802-11-wireless", priority: 0, autoconnect: true, name: "Wlow" },
    { type: "802-11-wireless", priority: 9, autoconnect: true, name: "Whigh" },
  ]).map(p => p.name),
  ["Whigh", "Wlow", "E"]
);

// A profile with a name but no uuid is unusable -- every later nmcli call is
// keyed on it -- so it must not enter the list at all.
eq("profile without uuid dropped", M.parseProfiles("uuid\t\nname\tGhost\n").profiles.length, 0);
eq("empty profiles input", M.parseProfiles("").profiles, []);
eq("garbage profiles input", M.parseProfiles("not a record").profiles, []);

// ---- blocklist --------------------------------------------------------------

ok("blocked case-insensitive", M.isBlocked(["d0:ea:11"], "D0:EA:11"));
ok("not blocked", !M.isBlocked(["aa:bb"], "cc:dd"));
ok("no bssid not blocked", !M.isBlocked(["aa:bb"], ""));
ok("empty list not blocked", !M.isBlocked([], "aa:bb"));
ok("null list not blocked", !M.isBlocked(null, "aa:bb"));

// ---- link -------------------------------------------------------------------

const LINK_RAW = [
  "kind\tlink",
  "--",
  "exists\tyes",
  "operstate\tup",
  "carrier\t1",
  "mtu\t1500",
  "mac\tb4:b5:b6:85:fe:55",
  "speed\t1000",
  "duplex\tfull",
  "driver\tr8169",
  "autoNegotiated\t1",
  "ethtool\tyes",
  "autoneg\ton",
  "maxSpeed\t2500",
  "rxErrors\t0",
  "txErrors\t2",
  "rxDropped\t1358",
  "collisions\t0",
  "--",
].join("\n");

(function () {
  const link = M.parseLink(LINK_RAW);
  eq("link exists", link.exists, true);
  eq("link operstate", link.operstate, "up");
  eq("link mtu", M.formatMtu(link.mtu), "1500");
  eq("link speed warning", M.linkSpeedWarning(link, null), "Linked at 1gbit of 2.5gbit supported");
  eq("link duplex ok", M.linkDuplexWarning(link), "");
  eq("counter formatted", M.formatCounter(link.rxDropped), "1,358");
  eq("counter tx errors", M.formatCounter(link.txErrors), "2");
  // Counters the kernel does not account stay null so the panel can say
  // "unavailable" instead of claiming a clean zero.
  eq("absent counter null", link.txDropped, null);
  eq("absent counter renders --", M.formatCounter(link.txDropped), "--");
  eq("absent crc counter null", link.rxCrcErrors, null);
})();

eq("absent interface", M.parseLink("kind\tlink\n--\nexists\tno\n--").exists, false);
eq("empty link input", M.parseLink("").exists, false);
eq("formatMtu empty", M.formatMtu(""), "");
eq("formatMtu junk", M.formatMtu("--"), "");

eq("half duplex warning", M.linkDuplexWarning({ exists: true, operstate: "up", duplex: "half" }), "Half duplex");
eq("full duplex no warning", M.linkDuplexWarning({ exists: true, operstate: "up", duplex: "full" }), "");
eq("absent duplex no warning", M.linkDuplexWarning({ exists: true, operstate: "up", duplex: "" }), "");

// A down interface has no negotiated speed to be disappointed about.
eq("down link not warned", M.linkSpeedWarning({ exists: true, operstate: "down", speed: "1000", maxSpeed: 2500 }, null), "");
// An unknown speed is not evidence of a fault.
eq("unknown speed not warned", M.linkSpeedWarning({ exists: true, operstate: "up", speed: "-1", maxSpeed: 2500 }, null), "");
eq("missing link not warned", M.linkSpeedWarning(null, null), "");

// A profile that pins a speed and negotiated lower is the strongest signal
// available without ethtool, and it outranks the NIC-capability comparison.
eq(
  "pinned speed shortfall",
  M.linkSpeedWarning({ exists: true, operstate: "up", speed: "1000", maxSpeed: 0 }, { pinnedSpeed: 2500 }),
  "Linked at 1gbit, profile asks for 2.5gbit"
);
eq(
  "pinned speed met is silent",
  M.linkSpeedWarning({ exists: true, operstate: "up", speed: "2500", maxSpeed: 0 }, { pinnedSpeed: 2500 }),
  ""
);
eq("pinnedSpeed 0 means auto", M.linkSpeedWarning({ exists: true, operstate: "up", speed: "1000", maxSpeed: 0 }, { pinnedSpeed: 0 }), "");

eq("link speed 2500", M.formatLinkSpeed(2500), "2.5gbit");
eq("link speed 100", M.formatLinkSpeed(100), "100mbit");
eq("link speed junk", M.formatLinkSpeed("--"), "");

// ---- scan -------------------------------------------------------------------

const SCAN_RAW = [
  "kind\tscan",
  "--",
  "ssid\tCafe",
  "bssid\taa:bb:cc:dd:ee:01",
  "band\t2.4 GHz",
  "chan\t1",
  "freq\t2412 MHz",
  "signal\t40",
  "inUse\tno",
  "--",
  "ssid\tCafe",
  "bssid\taa:bb:cc:dd:ee:02",
  "band\t5 GHz",
  "chan\t36",
  "freq\t5180 MHz",
  "signal\t80",
  "inUse\tyes",
  "dbm\t-42",
  "width\t80",
  "rxBitrate\t866.7",
  "--",
  "ssid\t",
  "bssid\taa:bb:cc:dd:ee:03",
  "signal\t20",
  "inUse\tno",
  "--",
].join("\n");

(function () {
  const scan = M.parseScan(SCAN_RAW);
  eq("scan count", scan.length, 3);
  eq("scan bssid lowercased later", scan[0].bssid, "aa:bb:cc:dd:ee:01");
  eq("scan inUse", scan[1].inUse, true);
  eq("scan dbm", M.signalQualityLabel(scan[1].dbm), "Excellent");
  eq("scan width from iw", M.channelWidthLabel(scan[1]), "80 MHz");
  eq("scan width absent", M.channelWidthLabel(scan[0]), "");

  // A band-steered AP reports one BSSID per band; the row is keyed on SSID and
  // the associated BSSID is always the right answer for it.
  eq("scan picks in-use bssid", M.scanRecordForSsid(scan, "Cafe").bssid, "aa:bb:cc:dd:ee:02");
  // With no association, the strongest wins.
  eq("scan unknown ssid", M.scanRecordForSsid(scan, "Office"), null);
  eq("scan hidden ssid", M.scanRecordForSsid(scan, "").bssid, "aa:bb:cc:dd:ee:03");
})();

// Channel width must never be invented from a bitrate: ac 1SS reports the same
// 866.7 Mbit/s at both 40 and 80 MHz.
eq("width not guessed from 866", M.channelWidthLabel({ rxBitrate: "866.7" }), "");
eq("width not guessed from 1733", M.channelWidthLabel({ rxBitrate: "1733.3" }), "");

// Thresholds, and their exact boundaries, so a change to the bands is visible.
eq("signal quality excellent", M.signalQualityLabel(-45), "Excellent");
eq("signal quality boundary -50", M.signalQualityLabel(-50), "Excellent");
eq("signal quality good", M.signalQualityLabel(-60), "Good");
eq("signal quality fair", M.signalQualityLabel(-70), "Fair");
eq("signal quality weak", M.signalQualityLabel(-80), "Weak");
eq("signal quality very weak", M.signalQualityLabel(-85), "Very weak");
eq("signal quality junk", M.signalQualityLabel(""), "");

// ---- extras -----------------------------------------------------------------

// Each record carries its own `kind`, which is the framing the probes emit.
const EXTRAS_RAW = [
  "kind\textras",
  "dns1\t8.8.8.8",
  "dns2\t1.1.1.1",
  "v6Count\t0",
  "firewallUnit\tactive",
  "firewallReadable\tyes",
  "firewallRules\t42",
  "--",
  "kind\ttailscale",
  "installed\tyes",
  "backendState\tRunning",
  "hostName\tlaptop",
  "ipv4\t100.101.102.103",
  "activePeers\t2",
  "tailnetPeers\t5",
  "exitNode\ttrue",
  "--",
].join("\n");

(function () {
  const extras = M.parseExtras(EXTRAS_RAW);
  eq("extras dns", extras.dns, ["8.8.8.8", "1.1.1.1"]);
  eq("extras dns count", extras.dnsCount, 2);
  eq("extras v6 empty", extras.v6, []);
  eq("extras firewall", M.firewallLabel(extras), "Running · 42 rules");
  ok("extras tailscale installed", extras.tailscale.installed);
  eq("extras tailscale label", M.tailscaleLabel(extras.tailscale), "Connected · 100.101.102.103");
  eq("extras tailscale peers", extras.tailscale.activePeers, 2);
  eq("extras tailscale exit node", extras.tailscale.exitNode, true);
  ok("tailscale running is not busy", !M.tailscaleBusy(extras.tailscale));
})();

// The bug this parser shape exists to prevent: a probe appends a section header
// without terminating the record before it, and the two merge. Every field must
// still be found.
(function () {
  const merged = [
    "kind\textras",
    "dns1\t9.9.9.9",
    "v6Count\t1",
    "firewallReadable\tyes",
    "firewallRules\t7",
    "kind\ttailscale",
    "installed\tyes",
    "backendState\tStopped",
    "--",
  ].join("\n");
  const extras = M.parseExtras(merged);
  eq("merged record dns still found", extras.dns, ["9.9.9.9"]);
  eq("merged record firewall still found", extras.firewallRules, 7);
  eq("merged record tailscale still found", extras.tailscale.state, "Stopped");
})();

// The sudo result is incidental and must not become the headline. An unreadable
// ruleset on a stopped service is "not running", not "needs root" -- the old
// wording implied rules were waiting to be counted.
eq("firewall active but unreadable", M.firewallLabel({ firewallUnit: "active", firewallReadable: false }), "Running · count needs root");
eq("firewall no rules", M.firewallLabel({ firewallUnit: "active", firewallReadable: true, firewallRules: 0 }), "Running · no rules");
eq("firewall one rule", M.firewallLabel({ firewallUnit: "active", firewallReadable: true, firewallRules: 1 }), "Running · 1 rule");
eq("firewall many rules", M.firewallLabel({ firewallUnit: "active", firewallReadable: true, firewallRules: 9 }), "Running · 9 rules");
eq("firewall inactive wins over unreadable", M.firewallLabel({ firewallUnit: "inactive", firewallReadable: false }), "Not running");
eq("firewall unit absent", M.firewallLabel({ firewallUnit: "", firewallReadable: "no" }), "Not running");
// The panel starts with extras = {} before the first probe returns. That is
// "not probed yet" and must never be rendered as a firewall fact.
eq("firewall unprobed", M.firewallLabel({}), "Unknown");
eq("firewall no data at all", M.firewallLabel(undefined), "Unknown");
eq("firewall active with null rules", M.firewallLabel({ firewallUnit: "active", firewallReadable: true, firewallRules: null }), "Running · no rules");
eq("tailscale absent", M.tailscaleLabel({ installed: false }), "Not installed");
eq("tailscale needs login", M.tailscaleLabel({ installed: true, state: "NeedsLogin" }), "Needs sign-in");
eq("tailscale NoState silent", M.tailscaleLabel({ installed: true, state: "NoState" }), "");
ok("tailscale starting is busy", M.tailscaleBusy({ installed: true, state: "Starting" }));
ok("tailscale absent not busy", !M.tailscaleBusy({ installed: false }));

// ---- methods and labels -----------------------------------------------------

eq("method auto", M.profileMethodLabel("auto"), "DHCP");
eq("method dhcp", M.profileMethodLabel("dhcp"), "DHCP");
eq("method manual no address", M.profileMethodLabel("manual", ""), "Static · unset");
eq("method shared", M.profileMethodLabel("shared"), "Shared");
eq("method link-local", M.profileMethodLabel("link-local"), "Link-local");
eq("method disabled", M.profileMethodLabel("disabled"), "Disabled");
eq("method placeholder is unknown", M.profileMethodLabel("--"), "Unknown");
eq("method empty is unknown", M.profileMethodLabel(""), "Unknown");
ok("profileIsDhcp", M.profileIsDhcp({ method: "auto" }));
ok("not profileIsDhcp", !M.profileIsDhcp({ method: "manual" }));
ok("profileIsDhcp null safe", !M.profileIsDhcp(null));

eq("cloned mac permanent", M.clonedMacLabel("--"), "Permanent");
eq("cloned mac random", M.clonedMacLabel("random"), "Random");
eq("cloned mac explicit", M.clonedMacLabel("02:11:22:33:44:55"), "02:11:22:33:44:55");
eq("wol off", M.wolLabel("0"), "Off");
eq("wol unset", M.wolLabel("--"), "Off");

const SEC = {
  Wpa3SuiteB192: 0, Sae: 1, Wpa2Eap: 2, Wpa2Psk: 3, WpaEap: 4,
  WpaPsk: 5, StaticWep: 6, DynamicWep: 7, Leap: 8, Owe: 9, Open: 10, Unknown: 11,
};
eq("security wpa3", M.securityLabel(SEC.Sae, SEC), "WPA3");
eq("security wpa2", M.securityLabel(SEC.Wpa2Psk, SEC), "WPA2");
eq("security wpa2 enterprise", M.securityLabel(SEC.Wpa2Eap, SEC), "WPA2 Enterprise");
eq("security legacy enterprise", M.securityLabel(SEC.WpaEap, SEC), "Enterprise");
eq("security wep", M.securityLabel(SEC.StaticWep, SEC), "WEP");
eq("security owe", M.securityLabel(SEC.Owe, SEC), "OWE");
eq("security open", M.securityLabel(SEC.Open, SEC), "Open");
eq("security unknown blank", M.securityLabel(SEC.Unknown, SEC), "");
eq("security no types", M.securityLabel(SEC.Sae, null), "");

// ---- formatting -------------------------------------------------------------

eq("IPv4 valid", M.isIPv4("192.168.0.10"), true);
eq("IPv4 rejects octet overflow", M.isIPv4("192.168.0.256"), false);
eq("IPv4 rejects missing octet", M.isIPv4("192.168.0"), false);
eq("IPv4 rejects hostname", M.isIPv4("router.local"), false);
eq("IPv4 subnet match", M.ipv4InSubnet("192.168.0.10", "192.168.0.254", 24), true);
eq("IPv4 subnet mismatch", M.ipv4InSubnet("192.168.1.10", "192.168.0.254", 24), false);
eq("IPv4 host address valid", M.ipv4UsableHost("192.168.0.10", 24), true);
eq("IPv4 network address rejected", M.ipv4UsableHost("192.168.0.0", 24), false);
eq("IPv4 broadcast address rejected", M.ipv4UsableHost("192.168.0.255", 24), false);
eq("IPv4 point-to-point host accepted", M.ipv4UsableHost("192.0.2.1", 31), true);

eq("counter thousands", M.formatCounter(1234567), "1,234,567");
eq("counter negative", M.formatCounter(-42), "-42");
eq("counter zero", M.formatCounter(0), "0");
eq("bits gbit", M.formatBitsPerSecond(2500000000), "2.5 Gbit/s");
eq("bits mbit", M.formatBitsPerSecond(866700000), "866.7 Mbit/s");
eq("bits 54mbit", M.formatBitsPerSecond(54000000), "54 Mbit/s");
eq("bits kbit", M.formatBitsPerSecond(5400), "5.4 kbit/s");
eq("bits zero", M.formatBitsPerSecond(0), "");

eq("public ip ok", M.publicIpState("203.0.113.9", 0), { ok: true, address: "203.0.113.9" });
eq("public ip v6", M.publicIpState("2001:db8::1", 0).ok, true);
eq("public ip failed exit", M.publicIpState("203.0.113.9", 7).ok, false);
eq("public ip html body", M.publicIpState("<html>error</html>", 0).ok, false);
eq("public ip empty", M.publicIpState("", 0).ok, false);

// The window keeps the last N samples, so a full series shifts its oldest out
// and the newest stays at the end.
eq("rate series appends", M.rateSeries([], 1, 2, 4).length, 1);
eq("rate series caps", M.rateSeries([{ down: 1, up: 1 }, { down: 1, up: 1 }, { down: 1, up: 1 }], 5, 5, 3).length, 3);
eq("rate series drops oldest", M.rateSeries([{ down: 1, up: 1 }, { down: 1, up: 1 }], 7, 7, 2), [{ down: 1, up: 1 }, { down: 7, up: 7 }]);
eq("rate series clamps negative", M.rateSeries([], -5, -5, 4), [{ down: 0, up: 0 }]);
eq("rate peak", M.rateSeriesPeak([{ down: 3, up: 9 }, { down: 4, up: 2 }]), 9);
eq("rate peak empty", M.rateSeriesPeak([]), 0);
eq("rate peak null", M.rateSeriesPeak(null), 0);

// ---- regressions on the pre-existing surface --------------------------------

// These were already in the plugin; a rewrite of the file must not move them.
// 20% is the bottom of the scale, so it gets the lowest bar.
eq("regression wifiIconFor 20", M.wifiIconFor(20), "󰤯");
eq("regression wifiIconFor 40", M.wifiIconFor(40), "󰤟");
eq("regression wifiIconFor clamp low", M.wifiIconFor(-5), "󰤯");
eq("regression wifiIconFor clamp high", M.wifiIconFor(999), "󰤨");
eq("regression formatBytes", M.formatBytes(1536), "1.5 KB");
eq("regression formatRate", M.formatRate(2048), "2.0 KB/s");
eq("regression formatHeaderFreq 2412", M.formatHeaderFreq(2412), "2.4ghz");
eq("regression formatHeaderFreq 5180", M.formatHeaderFreq(5180), "5ghz");
eq("regression formatHeaderSpeed 2500", M.formatHeaderSpeed(2500), "2.5gbit");
eq("regression parseKeyValue", M.parseKeyValue("ssid\tMyNet\nsignal\t-42\n"), { ssid: "MyNet", signal: "-42" });
eq("regression requiresCredentials open", M.requiresCredentials(SEC.Open, SEC.Open, SEC.Owe), false);
eq("regression requiresCredentials owe", M.requiresCredentials(SEC.Owe, SEC.Open, SEC.Owe), false);
eq("regression requiresCredentials wpa2", M.requiresCredentials(SEC.Wpa2Psk, SEC.Open, SEC.Owe), true);
eq("regression canForgetNetwork", M.canForgetNetwork({ known: true, connected: false }), true);
eq("regression canForgetNetwork connected", M.canForgetNetwork({ known: true, connected: true }), false);
eq("regression proton connected", Model_isConnected(), true);
function Model_isConnected() {
  return M.parseProtonStatus("Status: Connected\nServer: IT#23 in Milan, Italy\n").connected;
}
eq("regression proton location", M.parseProtonStatus("Status: Connected\nServer: IT#23 in Milan, Italy\n").label, "IT#23 · Milan, Italy");
eq("regression proton account", M.parseProtonAccount("Account: 'me@example.com'"), "me@example.com");
eq("regression proton signed out", M.parseProtonAccount("Account: 'None'"), "");
eq("regression proton auth required", M.protonAuthRequired("Error: please sign in"), true);
eq("regression ping loss no samples", M.pingPacketLossPercent([]), 0);
eq("regression ping loss all lost", M.pingPacketLossPercent([null, null]), 100);
eq("regression ping latency unset", M.formatPingLatency(-1, false), "--");
eq("regression ping latency timeout", M.formatPingLatency(-1, true), "Timeout");

console.log("");
console.log((failed === 0 ? "PASS" : "FAIL") + "  " + passed + " passed, " + failed + " failed");
process.exit(failed === 0 ? 0 : 1);
