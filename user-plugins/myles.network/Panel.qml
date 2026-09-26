import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Ui
import qs.Commons
import "Model.js" as Model

// The inline components below (SavedNetworkRow, WiredProfileRow, SettingRow,
// ActionChip, ...) all read `root.<something>`: the probe Processes, the shared
// action state, the bar colours. An inline component's lexical scope does not
// include the enclosing object's ids, so those lookups are only defined because
// the component was created inside `root`. `Bound` is the pragma that makes that
// guaranteed rather than incidental, and it has to sit above the import of the
// base type it applies to.
pragma ComponentBehavior: Bound

Panel {
  id: root
  moduleName: "omarchy.network"
  ipcTarget: "omarchy.network"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the toggleNetwork method below.
  manageIpc: false

  // Centralized close so callers can't forget to drop the passphrase prompt.
  function close() {
    root.controller.hide()
    cancelPasswordPrompt()
  }

  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
    identityText = ""
  }

  // Live connection details from `ip` / /sys / iw.
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate, rx_bytes, tx_bytes, router_ping_ms, internet_ping_ms }

  // Throughput tracking. Rates are computed as deltas between successive
  // `omarchy-network-status --verbose` samples (~1.5s apart via detailsPoll).
  // We hold "prev" alongside a timestamp so the first sample after open or
  // after an interface switch doesn't manufacture a spike.
  property real prevRxBytes: 0
  property real prevTxBytes: 0
  property real prevSampleTime: 0
  property string prevIface: ""
  property real downloadRate: 0  // bytes/sec
  property real uploadRate: 0    // bytes/sec
  property string pingIface: ""
  property var routerPingSamples: []
  property var internetPingSamples: []
  property var signalHistory: []
  property real routerPingLatency: -1
  property real internetPingLatency: -1
  property int internetPingPacketLoss: 0
  readonly property int pingHistoryWindow: 24
  readonly property int pingAverageWindow: 5
  readonly property int signalHistoryWindow: 32
  readonly property bool hasInternetPing: internetPingSamples.length > 0
  // Every stat row stays mounted whether or not there is data behind it, so a
  // sample arriving late never reflows the grid. This says whether the numbers
  // are real yet or the row should read "--".
  readonly property bool hasTransferStats: info.rx_bytes !== undefined
  property int connectionPhraseIndex: 0
  readonly property var connectionPhrases: [
    "Wiring bits",
    "Handling packets",
    "Sorting frames",
    "Hauling bytes",
    "Routing crumbs",
    "Counting collisions",
    "Bending light",
  ]
  readonly property string connectionPhrase: connectionPhrases[connectionPhraseIndex % connectionPhrases.length]
  readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  readonly property var connectedWifiNetwork: findConnectedWifiNetwork()
  property var wifiNetworks: []
  property bool scanning: false
  property bool wifiStationAvailable: false
  property string dnsProvider: ""
  property string pendingDnsProvider: ""
  // Wi-Fi band state from `omarchy-network-band`. `bandCurrent` is the band
  // the radio is actually on; `bandSelected` is the pinned choice ("auto" when
  // nothing is pinned), and the two differ whenever Auto is in effect.
  property string bandCurrent: ""
  property string bandSelected: "auto"
  property var bandAvailable: []
  property string pendingBand: ""

  // Per-row in-flight state. `actionSsid` flips on for the row whose action
  // is currently running so it can render "Connecting…" / "Disconnecting…" /
  // "Forgetting…". `passwordSsid` is the row currently expanded into
  // password-entry mode; we keep it open across refresh cycles so a slow scan
  // doesn't collapse the input the user is typing into. Rows must gate
  // comparisons on the matching `*Kind`/`*Reason` being non-empty so a
  // hidden-SSID row (ssid == "") doesn't collide with the "" defaults.
  property string actionSsid: ""
  property string actionKind: ""  // "connect" | "disconnect" | "forget"
  property string failureSsid: ""
  property string failureReason: ""
  property string passwordSsid: ""
  property string passwordText: ""
  property string identityText: ""

  // ConnectionFailReason values as a plain object, so Model.js helpers stay
  // pure JS and Node-testable.
  readonly property var connectionFailReasons: ({
    NoSecrets: ConnectionFailReason.NoSecrets,
    WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
    WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
    WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
    WifiClientFailed: ConnectionFailReason.WifiClientFailed
  })

  // True while any wifi action is mid-flight. Rows
  // disable themselves on this so clicks on the other rows don't silently
  // no-op against runNetworkAction's serialized guard.
  readonly property bool busy: actionKind !== ""

  // Index into `wifiNetworks` for keyboard navigation. -1 = no selection.
  property int selectedIndex: -1
  property bool wifiActionFocused: false
  property bool cursorActive: false

  // Keyboard focus zone for the panel. j/k crosses row boundaries:
  // header actions ⇄ portal ⇄ band ⇄ DNS row ⇄ Wi-Fi networks. h/l move
  // within header actions, band pills, or DNS providers.
  property string focusSection: "dns"  // "header" | "portal" | "band" | "dns" | "wifi"
  property int headerIndex: 0
  readonly property bool canDisconnect: !!connectedWifiNetwork
  readonly property bool headerHasDisconnect: false
  readonly property bool canShareWifi: !!connectedWifiNetwork && canShareNetwork(connectedWifiNetwork)
  // The hero switch is the Wi-Fi radio, so it only exists when there is a
  // radio to switch. On a wired box it would otherwise sit there reading
  // "off" beside a perfectly live Ethernet connection.
  readonly property bool canToggleWifi: networkManagerAvailable && wifiStationAvailable
  // Proton VPN (official CLI). Separate from Tailscale.
  property bool protonInstalled: false
  property bool protonSignedIn: false
  property string protonAccount: ""
  property bool vpnActive: false
  property string vpnActiveName: ""
  property string vpnAction: "" // "connect" | "disconnect"
  property string vpnStatusText: ""
  property string vpnError: ""
  property string vpnProbeWarning: ""
  readonly property bool vpnReady: protonInstalled && protonSignedIn
  readonly property bool vpnBusy: vpnAction !== ""
  readonly property string vpnToggleHint: {
    if (!protonInstalled) return "Install Proton VPN first"
    if (!protonSignedIn) return "Sign in to Proton VPN first"
    if (vpnBusy) return vpnAction === "disconnect" ? "Disconnecting…" : "Connecting…"
    if (vpnActive) return "Turn Proton VPN off"
    return "Turn Proton VPN on (fastest free server)"
  }
  readonly property string vpnSectionMeta: {
    if (!protonInstalled) return "Not installed — press Install"
    if (vpnBusy) return vpnStatusText !== "" ? vpnStatusText : (vpnAction === "disconnect" ? "Disconnecting…" : "Connecting…")
    if (!protonSignedIn) return "Sign in with a free Proton account"
    if (vpnError !== "") return vpnError
    if (vpnProbeWarning !== "") return vpnActive ? "Connected · last status check failed" : "Status check failed · " + vpnProbeWarning
    if (preferredVpnForActiveSetup && !vpnActive) return "VPN is preferred for this setup · currently disconnected"
    if (vpnActive) return "Connected · " + (vpnActiveName || "Proton VPN")
    return "Off · fastest free server"
  }
  readonly property bool preferredVpnForActiveSetup: {
    if (!activeProfile) return false
    for (var i = 0; i < savedSetups.length; i++)
      if (savedSetups[i] && !savedSetups[i].deletedAt && savedSetups[i].uuid === activeProfile.uuid) return !!savedSetups[i].vpn
    return false
  }
  readonly property int qrHeaderIndex: canShareWifi ? 0 : -1
  readonly property int speedHeaderIndex: canRunSpeedTest ? (canShareWifi ? 1 : 0) : -1
  readonly property int toggleHeaderIndex: canToggleWifi
    ? (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0)
    : -1
  readonly property int headerActionCount: (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) + (canToggleWifi ? 1 : 0)
  readonly property bool qrHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === qrHeaderIndex
  readonly property bool speedHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === speedHeaderIndex
  readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex
  readonly property string toggleHint: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
  readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]
  property int dnsIndex: 0
  // ["2.4", "5", ...], or empty when there is nothing to choose between.
  // Wi-Fi only: on Ethernet the band of a secondary radio is not what the
  // panel is describing.
  // `bandBusy` keeps the section mounted across the reconnect a band change
  // causes: `kind` stops being "wifi" for a second or two in the middle of it,
  // and without this the whole segment would vanish and rebuild itself.
  // Worth showing when there is a real choice, or when a pin is in force even
  // though only one band answers right now -- otherwise the Automatic switch
  // vanishes and the pin becomes unclearable from the panel.
  readonly property bool canSelectBand: (kind === "wifi" || bandBusy)
    && (bandAvailable.length > 1 || bandPinned)
  // While a change is in flight, show the state that was asked for rather than
  // the one still in force, so the row answers the click immediately instead of
  // after the reconnect. actionProc puts it back if the change failed.
  readonly property string bandEffective: pendingBand !== "" ? pendingBand : bandSelected
  readonly property bool bandPinned: bandEffective !== "auto"
  // Under Automatic there is nothing to pick, so the pills collapse away and
  // the header states the live band instead.
  readonly property bool bandPillsVisible: canSelectBand && bandPinned
  readonly property string bandSectionTitle: Model.bandSectionTitle(bandEffective, bandCurrent)
  readonly property bool bandBusy: pendingBand !== ""
  // The speed test needs an interface to test, so its hero action only
  // appears once there is one.
  readonly property bool canRunSpeedTest: !!info.iface
  property int bandIndex: 0
  // The band section has up to two cursor rows: the Automatic switch on the
  // header line, then the pills. Same shape as wifiActionFocused.
  property bool bandAutoFocused: true

  // ---- stored profiles, link facts, host extras -------------------------
  // Read by the plugin's own probes (net-*.sh) rather than by the first-party
  // `omarchy-network-status`, which only ever describes the interface on the
  // default route. A saved profile for a network that is not in range, a stored
  // Ethernet profile on a machine currently on Wi-Fi, and the blocklist are all
  // invisible to that command and are the reason these exist.
  property var profiles: []
  property var wifiProfiles: []
  property var wiredProfiles: []
  property var blocklist: []
  property var link: ({ exists: false })
  property var extras: ({})
  property var scanDetail: []

  // The profile that is actually up, matched by the interface it is bound to.
  // A profile bound to a specific interface is only live on that interface, so
  // matching on name alone would report the wrong one as active.
  readonly property var activeProfile: {
    var iface = info.iface || ""
    for (var i = 0; i < profiles.length; i++) {
      var p = profiles[i]
      if (!p.active) continue
      if (!iface || !p.iface || p.iface === iface) return p
    }
    return null
  }

  // ---- public address ---------------------------------------------------
  // The only value here that needs the network to answer, so it is fetched on a
  // slow timer, only while the panel is open, and never allowed to hold up
  // anything else.
  property string publicIp: ""
  property bool publicIpOk: false
  property string publicIpError: ""


  // ---- Wi-Fi actions ----------------------------------------------------
  property string confirmForgetSsid: ""
  property string confirmForgetUuid: ""
  property string detailSsid: ""
  property bool addHiddenOpen: false
  property string hiddenSsid: ""
  property string hiddenIdentity: ""
  property string hiddenSecret: ""
  property bool hiddenEnterprise: false

  // ---- Ethernet actions -------------------------------------------------
  property string wiredBusyUuid: ""
  property string wiredStatus: ""
  property string staticEditUuid: ""
  property string staticAddress: ""
  property string staticPrefix: "24"
  property string staticGateway: ""
  property string staticDns: ""
  property var staticOriginal: null
  property bool staticCanRestore: false
  // A temporary CPE management profile is isolated from the user's normal
  // wired profile. Its restore deadline and prior profile UUID survive a
  // shell reload through pluginStateFile.
  property string cpeInterface: ""
  property string cpeSelectedInterface: ""
  property string cpeReachability: ""
  property string cpeProfileName: ""
  property string cpePreviousUuid: ""
  property double cpeRestoreAt: 0
  property int cpeClock: 0
  property string cpeDeviceIp: "192.168.0.254"
  property string cpeHostIp: "192.168.0.10"
  property string cpePrefix: "24"
  property var savedIpv4Profiles: []
  property string defaultIpv4ProfileId: ""
  property string primaryWiredUuid: ""
  property string primaryWiredName: ""
  property string ipv4ProfileEditId: ""
  property string ipv4ProfileNameDraft: ""
  property string ipv4ExpandedProfileId: ""
  property string ipv4HoveredProfileId: ""
  property var ipv4PinnedProfiles: ({})
  property bool ipv4FormOpen: false
  property bool primaryEditOpen: false
  property string primaryNameDraft: ""
  property double primaryDeletedAt: 0
  property bool showIpv4Trash: false
  property string setupNameDraft: ""
  property bool setupVpnDraft: false
  property var savedSetups: []
  property bool showSetupTrash: false
  property string setupSearch: ""
  property string ipv4Search: ""
  property bool ipv4SortByName: false
  property string setupImportError: ""
  property string cpeRecoveryStatus: ""
  property bool cpeTemporaryRemoved: false
  property bool cpeRestoreInProgress: false
  property bool cpeConflictConfirmed: false
  property var dailyUsage: ({ day: "", rx: 0, tx: 0 })
  property double usageBaseRx: -1
  property double usageBaseTx: -1
  property string usageBaseIface: ""
  property string usageDay: ""
  property double usageLastWrite: 0
  property double sessionDownloaded: 0
  property double sessionUploaded: 0
  property bool pluginStateLoaded: false
  property bool pluginStateDirReady: false
  property string wiredEapUuid: ""
  property string wiredEapIdentity: ""
  property string wiredEapSecret: ""

  // ---- generic nmcli action runner --------------------------------------
  // One serialized runner for every write the panel performs, so two clicks can
  // never race, and so each call can report a single human-readable failure
  // instead of a raw CLI string.
  property string nmLabel: ""
  property string nmError: ""
  property string nmSuccess: ""
  property string profileImportError: ""
  property int nmToken: 0

  // ---- throughput history for the sparkline -----------------------------
  property var rateHistory: []
  readonly property int rateHistoryWindow: 48
  readonly property string pluginStateDir: Quickshell.env("HOME") + "/.local/state/omarchy/myles-network"
  readonly property string pluginStatePath: pluginStateDir + "/state.json"
  readonly property int cpeSetupDurationMs: 15 * 60 * 1000
  readonly property bool narrowLayout: panel.contentWidth < Style.space(420)

  // ---- section collapse -------------------------------------------------
  // Keyed by section id so a setting and a runtime toggle share one store.
  property var pinnedSections: ({})
  property string hoveredSectionId: ""
  // Inline row components cannot reach the root's Process id directly.
  readonly property bool nmBusy: nmProc.running

  // ---- settings ---------------------------------------------------------
  // Read through the manifest schema, with a fallback so the panel behaves
  // sensibly before shell.json has ever been written for this widget.
  function opt(key, fallback) {
    var value = setting(key, fallback)
    if (value === undefined || value === null || value === "") return fallback
    return value
  }

  function boolOpt(key, fallback) {
    var value = setting(key, fallback)
    if (typeof value === "boolean") return value
    var text = String(value).toLowerCase()
    if (text === "true" || text === "1" || text === "yes") return true
    if (text === "false" || text === "0" || text === "no") return false
    return fallback
  }

  readonly property bool showSavedNetworks: boolOpt("showSavedNetworks", true)
  readonly property bool showLinkDetails: boolOpt("showLinkDetails", true)
  readonly property bool showHostDetails: boolOpt("showHostDetails", true)
  readonly property bool showSparkline: boolOpt("showSparkline", true)
  readonly property bool confirmForget: boolOpt("confirmForget", true)
  readonly property bool autoScanOnOpen: boolOpt("autoScanOnOpen", true)
  readonly property bool showPublicIp: boolOpt("showPublicIp", true)

  onHeaderActionCountChanged: clampHeaderIndex()

  // Availability shifts as scans land, so the option list can shrink out from
  // under the cursor. Clamp the index and evacuate the section before it
  // disappears, or the panel is left highlighting nothing.
  onBandAvailableChanged: {
    if (bandIndex > bandAvailable.length - 1) bandIndex = Math.max(0, bandAvailable.length - 1)
  }

  onCanSelectBandChanged: {
    if (!canSelectBand && focusSection === "band") {
      focusSection = "dns"
      bandAutoFocused = true
    }
  }

  // Collapsing the pills out from under the cursor would leave it pointing at
  // nothing, so send it up to the switch that is still on screen.
  onBandPillsVisibleChanged: {
    if (!bandPillsVisible) bandAutoFocused = true
  }

  function clampHeaderIndex() {
    var max = Math.max(0, headerActionCount - 1)
    if (headerIndex > max) headerIndex = max
    if (headerIndex < 0) headerIndex = 0
  }

  function selectHeaderByDelta(delta) {
    headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
  }

  function toggleNetwork() {
    if (!networkManagerAvailable) return
    Networking.wifiEnabled = !Networking.wifiEnabled
    Qt.callLater(function() { root.refresh(true) })
  }

  function updateVpn(raw, errRaw) {
    var combined = String(raw || "") + "\n" + String(errRaw || "")
    if (Model.protonAuthRequired(combined)) {
      protonSignedIn = false
      protonAccount = ""
      vpnActive = false
      vpnActiveName = ""
      // Don't surface raw CLI auth text — Sign in is the fix.
      if (vpnError !== "" && Model.protonAuthRequired(vpnError))
        vpnError = ""
      return
    }
    var st = Model.parseProtonStatus(raw)
    vpnActive = !!st.connected
    vpnActiveName = st.label || (st.connected ? "Proton VPN" : "")
    // Status alone does not mean signed in — unsigned installs still print
    // "Status: Disconnected". Account probe owns signed-in state.
  }

  function updateProtonAccount(raw, errRaw, exitCode) {
    var account = Model.parseProtonAccount(raw)
    var combined = String(raw || "") + "\n" + String(errRaw || "")
    // A transient CLI/D-Bus failure is not proof that the user signed out.
    // Keep the last known authentication state and make the stale check clear.
    if (exitCode !== 0 && !Model.protonAuthRequired(combined)) {
      vpnProbeWarning = "last known state shown"
      return
    }
    vpnProbeWarning = ""
    if (account) {
      protonSignedIn = true
      protonAccount = account
      if (vpnError !== "" && Model.protonAuthRequired(vpnError))
        vpnError = ""
      return
    }
    // Account: 'None' or auth failure → signed out.
    protonSignedIn = false
    protonAccount = ""
    if (!vpnActive) vpnActiveName = ""
    if (vpnError !== "" && Model.protonAuthRequired(vpnError))
      vpnError = ""
    void exitCode
    void combined
  }

  function refreshVpn() {
    if (!protonInstalled) {
      if (!protonProbeProc.running) {
        protonProbeProc.command = ["bash", "-lc", "command -v protonvpn >/dev/null"]
        protonProbeProc.running = true
      }
      return
    }
    if (!vpnStatusProc.running) {
      vpnStatusProc.command = ["protonvpn", "status"]
      vpnStatusProc.running = true
    }
    // Always refresh account — CLI reports Account: 'None' while signed out.
    if (!protonAccountProc.running) {
      protonAccountProc.command = ["protonvpn", "info"]
      protonAccountProc.running = true
    }
  }

  function toggleVpn() {
    if (!protonInstalled) {
      vpnError = "Proton VPN is not installed — press Install"
      return
    }
    if (!protonSignedIn) {
      vpnError = ""
      openProtonSignIn()
      return
    }
    if (vpnBusy) return
    var goingDown = vpnActive
    vpnAction = goingDown ? "disconnect" : "connect"
    vpnStatusText = goingDown ? "Disconnecting…" : "Connecting to fastest server…"
    vpnError = ""
    if (goingDown)
      vpnActionProc.command = ["protonvpn", "disconnect"]
    else {
      var country = String(setting("protonCountry", "") || "").trim()
      if (country)
        vpnActionProc.command = ["protonvpn", "connect", "--country", country]
      else
        vpnActionProc.command = ["protonvpn", "connect"]
    }
    vpnActionProc.running = true
  }

  function openProtonSignIn() {
    vpnStatusText = ""
    vpnError = ""
    if (!protonInstalled) {
      vpnError = "Proton VPN is not installed — press Install"
      return
    }
    var script = Qt.resolvedUrl("proton-signin.sh").toString().replace(/^file:\/\//, "")
    if (root.bar)
      root.bar.run("omarchy-launch-tui --app-id=org.omarchy.protonvpn-signin " + Util.shellQuote(script))
  }

  function installProtonVpn() {
    vpnStatusText = "Installing Proton VPN…"
    vpnError = ""
    var script = Qt.resolvedUrl("proton-install.sh").toString().replace(/^file:\/\//, "")
    if (root.bar)
      root.bar.run("omarchy-launch-tui --app-id=org.omarchy.protonvpn-install " + Util.shellQuote(script))
  }

  IpcHandler {
    target: "omarchy.network"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function toggleNetwork() { root.toggleNetwork() }
    function toggleVpn() { root.toggleVpn(); return "ok" }
    // Compat routes for configs that summon the centered cards through the
    // network target; both cards are their own plugins now.
    function showQr() { root.summonWifiQr(true) }
    function speedTest() { root.summonSpeedTest() }
    function openCaptivePortal() { root.openCaptivePortal() }
    function checkConnectivity() { root.checkConnectivity() }
  }

  function activateHeader() {
    if (headerIndex === qrHeaderIndex) summonWifiQr()
    else if (headerIndex === speedHeaderIndex) summonSpeedTest()
    else if (headerIndex === toggleHeaderIndex) toggleNetwork()
  }

  function setHeaderCursor(index) {
    cursorActive = true
    focusSection = "header"
    headerIndex = index
  }

  function selectDnsByDelta(delta) {
    dnsIndex = Math.max(0, Math.min(dnsProviders.length - 1, dnsIndex + delta))
  }

  function activateDns() {
    if (dnsIndex < 0 || dnsIndex >= dnsProviders.length) return
    setDns(dnsProviders[dnsIndex])
  }

  function selectBandByDelta(delta) {
    bandIndex = Math.max(0, Math.min(bandAvailable.length - 1, bandIndex + delta))
  }

  function activateBand() {
    if (bandAutoFocused) {
      toggleBandAuto()
      return
    }
    if (bandIndex < 0 || bandIndex >= bandAvailable.length) return
    setBand(bandAvailable[bandIndex])
  }

  // Switching Automatic off has to commit to something, so it pins whatever
  // band the radio already landed on -- the reading the pills are showing.
  function toggleBandAuto() {
    if (bandSelected !== "auto") {
      setBand("auto")
      return
    }
    if (bandCurrent === "") return
    setBand(bandCurrent)
  }

  // Park the cursor on the pinned band, so opening the panel highlights the
  // pill the user would expect. Under Automatic there are no pills, so the
  // cursor belongs on the switch.
  function syncBandIndex() {
    var idx = bandAvailable.indexOf(bandSelected)
    bandIndex = idx >= 0 ? idx : 0
    bandAutoFocused = !bandPillsVisible
  }

  function bandLabel(band) {
    return Model.bandLabel(band)
  }

  function bandTooltip(band) {
    return Model.bandTooltip(band)
  }

  // Single cursor model: exactly one highlighted spot across the whole
  // panel, located via `focusSection` + (`headerIndex` | `dnsIndex` |
  // `selectedIndex`). Mouse hover and keyboard nav both mutate this state
  // at the root; items never read containsMouse for visuals. See
  // CursorSurface for the shared chrome shared by rows and pills.
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // scannerEnabled lives on the shared WifiDevice, which has no reference
  // counting, and a bar widget is instantiated once per monitor. Tracking the
  // device this instance turned scanning on for keeps the release correct when
  // the panel closes, the device is replaced, or the widget is destroyed —
  // without a closed instance ever claiming the scanner.
  property var scannerDevice: null

  function setScannerEnabled(enabled) {
    var nextDevice = opened ? wifiDevice : null

    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false

    scannerDevice = nextDevice

    if (scannerDevice)
      scannerDevice.scannerEnabled = enabled
  }

  Component.onDestruction: {
    if (scannerDevice) scannerDevice.scannerEnabled = false
  }

  // KeyboardPanel primes layer-shell focus whenever the panel opens. That's
  // what makes the SUPER+CTRL+W keybind land here with navigation ready.
  onOpenedChanged: {
    if (opened) {
      refresh(autoScanOnOpen)
      // Re-check Proton sign-in each open (user may have signed in via terminal).
      if (protonInstalled && !protonAccountProc.running) {
        protonAccountProc.command = ["protonvpn", "info"]
        protonAccountProc.running = true
      }
      // Stored profiles, link facts and host extras have no cached copy to
      // fall back on, so they are fetched on every open rather than left to
      // their poll timers' first tick.
      refreshProfiles()
      refreshScanDetail()
      selectedIndex = wifiNetworks.length > 0 ? 0 : -1
      wifiActionFocused = false
      focusSection = hasCaptivePortal ? "portal" : (wifiNetworks.length > 0 ? "wifi" : "dns")
      var idx = dnsProviders.indexOf(dnsProvider)
      dnsIndex = idx >= 0 ? idx : 0
      syncBandIndex()
      cursorActive = hasCaptivePortal
    } else {
      // Drop a restart armed by this open: without it a close/reopen inside
      // the 100ms window reuses the running timer and re-enables the scanner
      // almost immediately, undoing the deferral #6605 restored.
      scanRestart.stop()
      // Reset throughput tracking so the next open doesn't compute a fake
      // rate from a sample taken minutes ago.
      prevSampleTime = 0
      downloadRate = 0
      uploadRate = 0
      pingIface = ""
      routerPingSamples = []
      internetPingSamples = []
      routerPingLatency = -1
      internetPingLatency = -1
      internetPingPacketLoss = 0
      // The sparkline is derived from those counters, so it goes with them.
      rateHistory = []
      signalHistory = []
      // Any half-finished destructive action is abandoned rather than left
      // armed: a confirm dialog that survives a close would forget a network on
      // the next open, with nothing on screen to explain it.
      cancelForget()
      cancelStaticEdit()
      cancelWiredEap()
      addHiddenOpen = false
      hiddenSsid = ""
      hiddenSecret = ""
      hiddenIdentity = ""
      detailSsid = ""
      nmError = ""
      nmSuccess = ""
      wiredStatus = ""
      setScannerEnabled(false)
      pinnedSections = ({})
      hoveredSectionId = ""
      ipv4PinnedProfiles = ({})
      ipv4HoveredProfileId = ""
      ipv4FormOpen = false
      primaryEditOpen = false
      showIpv4Trash = false
      showSetupTrash = false
      root.vpnStatusText = ""
      root.vpnError = ""
    }
  }

  // When the passphrase prompt closes (Esc / Cancel / success) restore
  // focus to the keyCatcher so j/k/Enter resume working without a click.
  // The KeyboardPanel's focusTarget covers initial popup-open; this handles
  // the inline-editor case where focus was handed off to a child.
  onPasswordSsidChanged: {
    if (passwordSsid === "" && opened) {
      passwordText = ""
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  // Keep selectedIndex valid as scans refresh the network list.
  // If the list empties (station gone, e.g. wifi off), bounce the cursor
  // back to the DNS row so the panel doesn't end up with no cursor at all.
  onWifiNetworksChanged: {
    if (wifiNetworks.length === 0) {
      selectedIndex = -1
      wifiActionFocused = false
      if (focusSection === "wifi") focusSection = "dns"
    } else if (passwordSsid !== "") {
      var passwordIndex = wifiIndexForSsid(passwordSsid)
      if (passwordIndex >= 0) {
        selectedIndex = passwordIndex
        focusSection = "wifi"
      }
    } else if (selectedIndex >= wifiNetworks.length) {
      selectedIndex = wifiNetworks.length - 1
    } else if (selectedIndex < 0 && opened) {
      selectedIndex = 0
    }

    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length || !canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
    }
  }

  onWifiDeviceChanged: {
    setScannerEnabled(true)
    syncWifiNetworks()
  }

  onWifiNetworkObjectsChanged: syncWifiNetworks()

  function selectByDelta(delta) {
    if (wifiNetworks.length === 0) { selectedIndex = -1; return }
    if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : wifiNetworks.length - 1
    else selectedIndex = Math.max(0, Math.min(wifiNetworks.length - 1, selectedIndex + delta))
    wifiActionFocused = false
  }

  function canForgetNetwork(net) {
    return Model.canForgetNetwork(net)
  }

  function canShareNetwork(net) {
    if (!net || !net.connected) return false
    return net.security !== WifiSecurityType.Wpa2Eap && net.security !== WifiSecurityType.WpaEap
  }

  function selectWifiActionByDelta(delta) {
    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    if (!canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
      return
    }
    if (delta > 0) wifiActionFocused = true
    else if (delta < 0) wifiActionFocused = false
  }

  // Enter/Space on the highlighted row. Mirrors row-click semantics:
  // connected → disconnect, credentials-required/unknown → prompt,
  // passwordless/known → connect.
  function activateSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    var net = wifiNetworks[selectedIndex]
    if (!net) return
    if (wifiActionFocused && canForgetNetwork(net)) { forget(net); return }
    // Only act on a row that still resolves. disconnect() falls back to
    // connectedWifiNetwork when handed null, so a row left stale by scan churn
    // would otherwise tear down whatever is connected now instead.
    if (net.connected) { disconnectRow(net.ssid); return }
    if (requiresCredentials(net.security) && !net.known) { openPasswordPrompt(net.ssid); return }
    connectDirectly(net.ssid)
  }

  // Bar pill state, derived from the native NetworkManager service so the
  // icon reflects connection changes without polling. Wired is preferred
  // when both are up, matching the default-route device.
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property var wiredDevices: (networkDevices || []).filter(function(device) { return device && device.type === DeviceType.Wired })
  readonly property var selectedCpeDevice: {
    var wanted = cpeSelectedInterface || (wiredDevice ? wiredDevice.name : "")
    for (var i = 0; i < wiredDevices.length; i++) if (wiredDevices[i].name === wanted) return wiredDevices[i]
    return null
  }
  readonly property string kind: {
    if (wiredDevice && wiredDevice.connected) return "ethernet"
    if (connectedWifiNetwork) return "wifi"
    return "disconnected"
  }
  readonly property int signalStrength: connectedWifiNetwork
    ? Math.round((connectedWifiNetwork.signalStrength || 0) * 100)
    : -1

  function copyToClipboard(value) {
    if (!value) return
    if (clipboardCopyProc.running) { nmError = "Clipboard copy is already in progress"; return }
    clipboardCopyProc.payload = String(value)
    clipboardCopyProc.running = true
  }

  function copyConnectionSummary() {
    var lines = [
      "Connection: " + (root.info.ssid || (root.info.type === "ethernet" ? "Ethernet" : root.info.iface || "Disconnected")),
      "Interface: " + (root.info.iface || "--"),
      "IPv4: " + (root.info.ip || "--"),
      "Gateway: " + (root.info.gateway || "--"),
      "DNS: " + (root.dnsSummary || "--"),
      "Ping: " + root.formatPingLatency(root.internetPingLatency),
      "VPN: " + (root.vpnActive ? "Connected · " + (root.vpnActiveName || "Proton VPN") : "Disconnected")
    ]
    root.copyToClipboard(lines.join("\n"))
  }

  function todayKey() {
    return Qt.formatDate(new Date(), "yyyy-MM-dd")
  }

  function trackDailyUsage(next) {
    if (!next || !next.iface || next.rx_bytes === undefined || next.tx_bytes === undefined) return
    var rx = Number(next.rx_bytes), tx = Number(next.tx_bytes)
    if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0) return
    var day = todayKey()
    if (dailyUsage.day !== day) dailyUsage = ({ day: day, rx: 0, tx: 0 })
    if (usageBaseIface !== next.iface || usageBaseRx < 0 || rx < usageBaseRx || tx < usageBaseTx) {
      usageBaseIface = next.iface
      usageBaseRx = rx
      usageBaseTx = tx
      return
    }
    var down = Math.max(0, rx - usageBaseRx), up = Math.max(0, tx - usageBaseTx)
    if (down || up) {
      dailyUsage = ({ day: day, rx: Number(dailyUsage.rx || 0) + down, tx: Number(dailyUsage.tx || 0) + up })
      sessionDownloaded += down
      sessionUploaded += up
    }
    usageBaseRx = rx
    usageBaseTx = tx
    usageBaseIface = next.iface
    if (Date.now() - usageLastWrite > 60000) writePluginState()
  }

  function resetUsage() {
    dailyUsage = ({ day: todayKey(), rx: 0, tx: 0 })
    sessionDownloaded = 0
    sessionUploaded = 0
    usageBaseRx = Number(info.rx_bytes || -1)
    usageBaseTx = Number(info.tx_bytes || -1)
    usageBaseIface = info.iface || ""
    writePluginState()
  }

  function loadPluginState(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      if (data && typeof data === "object") {
        savedSetups = Array.isArray(data.setups) ? data.setups.map(function(item) { return item && Object.assign({ deletedAt: 0 }, item) }) : []
        savedIpv4Profiles = Array.isArray(data.ipv4Profiles) ? data.ipv4Profiles : []
        defaultIpv4ProfileId = String(data.defaultIpv4ProfileId || "")
        if (data.primaryWired && data.primaryWired.uuid) {
          primaryWiredUuid = String(data.primaryWired.uuid)
          primaryWiredName = String(data.primaryWired.name || "Primary wired profile")
          primaryDeletedAt = Number(data.primaryWired.deletedAt || 0)
        }
        root.ensureCpe220Preset()
        if (data.usage && data.usage.day === todayKey()) dailyUsage = data.usage
        if (data.cpe && data.cpe.profileName) {
          cpeProfileName = String(data.cpe.profileName)
          cpePreviousUuid = String(data.cpe.previousUuid || "")
          cpeInterface = String(data.cpe.iface || "")
          cpeTemporaryRemoved = !!data.cpe.temporaryRemoved
          cpeRestoreAt = Number(data.cpe.restoreAt || 0)
          var remaining = cpeRestoreAt - Date.now()
          if (remaining <= 0) Qt.callLater(root.restoreCpeSetup)
          else {
            cpeRestoreTimer.interval = Math.min(remaining, root.cpeSetupDurationMs)
            Qt.callLater(function() { cpeRestoreTimer.start() })
          }
        }
      }
    } catch (e) {
      console.warn("myles.network: ignoring invalid saved plugin state", e)
    }
    pluginStateLoaded = true
    root.ensureCpe220Preset()
    root.writePluginState()
  }

  function writePluginState() {
    if (!pluginStateLoaded || !pluginStateDirReady) return
    var data = { version: 5, setups: savedSetups, usage: dailyUsage,
      ipv4Profiles: savedIpv4Profiles, defaultIpv4ProfileId: defaultIpv4ProfileId }
    if (primaryWiredUuid !== "" || primaryDeletedAt !== 0)
      data.primaryWired = { uuid: primaryWiredUuid, name: primaryWiredName, deletedAt: primaryDeletedAt }
    if (cpeProfileName !== "") data.cpe = {
      profileName: cpeProfileName,
      previousUuid: cpePreviousUuid,
      iface: cpeInterface,
      restoreAt: cpeRestoreAt,
      temporaryRemoved: cpeTemporaryRemoved
    }
    pluginStateFile.setText(JSON.stringify(data, null, 2) + "\n")
    usageLastWrite = Date.now()
  }

  function addCurrentSetup() {
    var profile = activeProfile
    var label = setupNameDraft.trim()
    if (!profile || !profile.uuid || !label) return
    var next = savedSetups.slice()
    for (var i = 0; i < next.length; i++) if (next[i].uuid === profile.uuid) next.splice(i--, 1)
    next.push({ uuid: profile.uuid, label: label, vpn: setupVpnDraft, type: profile.isWifi ? "Wi-Fi" : "Ethernet" })
    savedSetups = next
    setupNameDraft = ""
    writePluginState()
  }

  function removeSetup(uuid) {
    savedSetups = savedSetups.map(function(item) { return item && item.uuid === uuid
      ? Object.assign({}, item, { deletedAt: Date.now() }) : item })
    writePluginState()
  }

  function restoreSetup(uuid) {
    savedSetups = savedSetups.map(function(item) { return item && item.uuid === uuid
      ? Object.assign({}, item, { deletedAt: 0 }) : item })
    writePluginState()
  }

  function activeSetups() {
    var q = setupSearch.trim().toLowerCase()
    return savedSetups.filter(function(item) { return item && !item.deletedAt && (!q || (item.label + " " + item.type).toLowerCase().indexOf(q) >= 0) })
  }
  function cpeSubnetConflict(deviceIp, hostIp, prefix) {
    var targetIface = cpeSelectedInterface || (wiredDevice ? wiredDevice.name : "")
    for (var i = 0; i < profiles.length; i++) {
      var p = profiles[i]
      if (!p || !p.active || !p.addresses) continue
      if (targetIface && (p.iface === targetIface || p.active === targetIface)) continue
      var addresses = String(p.addresses).split(/[,;\s]+/)
      for (var j = 0; j < addresses.length; j++) {
        var bits = String(addresses[j]).split("/")
        if (bits.length === 2 && Model.isIPv4(bits[0]) && /^([1-9]|[12][0-9]|3[0-2])$/.test(bits[1])) {
          if (Model.ipv4InSubnet(hostIp, bits[0], bits[1]) || Model.ipv4InSubnet(bits[0], hostIp, prefix))
            return "Possible subnet overlap with active connection " + (p.name || "") + " (" + bits[0] + "/" + bits[1] + "). Confirm before applying."
        }
      }
    }
    return ""
  }

  function validIpv4Pair(deviceIp, hostIp, prefix) {
    var bits = String(prefix)
    return /^([1-9]|[12][0-9]|3[0-2])$/.test(bits)
      && Model.ipv4UsableHost(deviceIp, bits) && Model.ipv4UsableHost(hostIp, bits)
      && deviceIp !== hostIp && Model.ipv4InSubnet(hostIp, deviceIp, bits)
  }
  function deletedSetups() { return savedSetups.filter(function(item) { return item && item.deletedAt }) }

  function activateSetup(setup) {
    if (!setup || !setup.uuid || nmProc.running) return
    var exists = false
    for (var i = 0; i < profiles.length; i++) if (profiles[i].uuid === setup.uuid) exists = true
    if (!exists) { nmError = "That saved connection no longer exists"; return }
    runNm("Connecting " + setup.label, ["nmcli", "connection", "up", "uuid", setup.uuid], function(ok) {
      if (ok && setup.vpn && !root.vpnActive) root.toggleVpn()
    })
  }

  function startCpeSetupFor(deviceIp, hostIp, prefix) {
    if (cpeProfileName !== "" || cpeSetupProc.running || nmProc.running) return
    var conflict = cpeSubnetConflict(deviceIp, hostIp, prefix)
    if (conflict && !cpeConflictConfirmed) { nmError = conflict; return }
    var iface = cpeSelectedInterface || (wiredDevice ? wiredDevice.name : "")
    var selectedDevice = null
    for (var d = 0; d < wiredDevices.length; d++) if (wiredDevices[d].name === iface) selectedDevice = wiredDevices[d]
    if (!selectedDevice || !selectedDevice.connected) { nmError = "Select a connected Ethernet adapter"; return }
    if (!validIpv4Pair(deviceIp, hostIp, prefix)) {
      nmError = "Enter two valid IPv4 addresses in the same subnet"; return
    }
    var previous = ""
    for (var p = 0; p < wiredProfiles.length; p++) {
      if (wiredProfiles[p].active === iface) { previous = wiredProfiles[p].uuid; break }
    }
    if (previous !== "" && primaryWiredUuid === "") {
      primaryWiredUuid = previous
      primaryWiredName = activeWiredProfile && activeWiredProfile.uuid === previous
        ? String(activeWiredProfile.name || "Primary wired profile") : "Primary wired profile"
      writePluginState()
    }
    var name = "Myles CPE Setup " + Date.now()
    cpeSetupProc.profileName = name
    cpeSetupProc.previousUuid = previous
    cpeSetupProc.iface = iface
    cpeTemporaryRemoved = false
    cpeSetupProc.command = ["nmcli", "connection", "add", "type", "ethernet", "ifname", iface,
      "con-name", name, "connection.autoconnect", "no", "ipv4.method", "manual",
      "ipv4.addresses", hostIp + "/" + prefix,
      "ipv4.never-default", "yes", "ipv6.method", "disabled"]
    cpeSetupProc.running = true
    wiredStatus = "Preparing temporary CPE link…"
  }

  function startCpeSetup() { startCpeSetupFor(cpeDeviceIp, cpeHostIp, cpePrefix) }

  function ensureCpe220Preset() {
    for (var i = 0; i < savedIpv4Profiles.length; i++)
      if (savedIpv4Profiles[i] && savedIpv4Profiles[i].id === "builtin-cpe220") return
    var next = savedIpv4Profiles.slice()
    next.push({ id: "builtin-cpe220", name: "TP-Link CPE220", deviceIp: "192.168.0.254",
      hostIp: "192.168.0.10", prefix: "24", order: 0, builtin: true,
      createdAt: Date.now(), updatedAt: Date.now(), deletedAt: 0 })
    savedIpv4Profiles = next
    if (pluginStateLoaded) writePluginState()
  }

  function activeIpv4Profiles() {
    var q = ipv4Search.trim().toLowerCase()
    return savedIpv4Profiles.filter(function(profile) { return profile && !profile.deletedAt && (!q || (profile.name + " " + profile.deviceIp + " " + profile.hostIp).toLowerCase().indexOf(q) >= 0) })
      .sort(function(a, b) {
        if (ipv4SortByName) return String(a.name).localeCompare(String(b.name))
        var orderA = a.id === "builtin-cpe220" ? 0 : Number(a.order || 10)
        var orderB = b.id === "builtin-cpe220" ? 0 : Number(b.order || 10)
        return orderA - orderB || Number(a.createdAt || 0) - Number(b.createdAt || 0)
      })
  }

  function deletedIpv4Profiles() {
    return savedIpv4Profiles.filter(function(profile) { return profile && profile.deletedAt })
  }

  function isIpv4ProfileExpanded(id) {
    if (Object.prototype.hasOwnProperty.call(ipv4PinnedProfiles, id)) return !!ipv4PinnedProfiles[id]
    return ipv4HoveredProfileId === id
  }

  function setIpv4ProfileHovered(id, hovered) {
    if (hovered) ipv4HoveredProfileId = id
    else if (ipv4HoveredProfileId === id) ipv4HoveredProfileId = ""
  }

  function toggleIpv4Profile(id) {
    var next = {}
    for (var key in ipv4PinnedProfiles)
      if (Object.prototype.hasOwnProperty.call(ipv4PinnedProfiles, key)) next[key] = ipv4PinnedProfiles[key]
    next[id] = Object.prototype.hasOwnProperty.call(next, id) ? !next[id] : true
    ipv4PinnedProfiles = next
  }

  function beginNewIpv4Profile() {
    ensureCpe220Preset()
    ipv4ProfileEditId = ""
    ipv4ProfileNameDraft = ""
    cpeDeviceIp = "192.168.0.254"
    cpeHostIp = "192.168.0.10"
    cpePrefix = "24"
    ipv4FormOpen = true
  }

  function saveIpv4Profile() {
    var label = ipv4ProfileNameDraft.trim()
    if (!label) { nmError = "Enter a name for this IPv4 setup"; return }
    if (!validIpv4Pair(cpeDeviceIp, cpeHostIp, cpePrefix)) {
      nmError = "Enter two valid IPv4 addresses in the same subnet before saving"; return
    }
    var next = savedIpv4Profiles.slice()
    var found = false
    for (var i = 0; i < next.length; i++) {
      if (next[i] && next[i].id === ipv4ProfileEditId) {
        next[i] = Object.assign({}, next[i], { name: label, deviceIp: cpeDeviceIp,
          hostIp: cpeHostIp, prefix: cpePrefix, updatedAt: Date.now(), deletedAt: 0 })
        found = true
      }
    }
    if (!found) next.push({ id: "ipv4-" + Date.now() + "-" + Math.floor(Math.random() * 100000),
      name: label, deviceIp: cpeDeviceIp, hostIp: cpeHostIp, prefix: cpePrefix,
      createdAt: Date.now(), updatedAt: Date.now(), deletedAt: 0 })
    savedIpv4Profiles = next
    ipv4ProfileEditId = ""
    ipv4ProfileNameDraft = ""
    ipv4FormOpen = false
    writePluginState()
    nmSuccess = found ? "IPv4 setup updated" : "IPv4 setup saved"
  }

  function editIpv4Profile(profile) {
    if (!profile || profile.deletedAt) return
    ipv4ProfileEditId = profile.id
    ipv4ProfileNameDraft = profile.name
    cpeDeviceIp = profile.deviceIp
    cpeHostIp = profile.hostIp
    cpePrefix = String(profile.prefix)
    ipv4FormOpen = true
  }

  function duplicateIpv4Profile(profile) {
    if (!profile || profile.deletedAt) return
    ipv4ProfileEditId = ""
    ipv4ProfileNameDraft = profile.name + " copy"
    cpeDeviceIp = profile.deviceIp
    cpeHostIp = profile.hostIp
    cpePrefix = String(profile.prefix)
    ipv4FormOpen = true
  }

  function resetCpe220Preset() {
    var next = savedIpv4Profiles.slice()
    for (var i = 0; i < next.length; i++) if (next[i].id === "builtin-cpe220")
      next[i] = Object.assign({}, next[i], { name: "TP-Link CPE220", deviceIp: "192.168.0.254",
        hostIp: "192.168.0.10", prefix: "24", deletedAt: 0, updatedAt: Date.now() })
    savedIpv4Profiles = next
    writePluginState()
    nmSuccess = "CPE220 factory preset restored"
  }

  function exportIpv4Profiles() {
    copyToClipboard(JSON.stringify({ format: "myles.network.ipv4", version: 1, profiles: savedIpv4Profiles }, null, 2))
  }

  function exportSavedSetups() {
    var exported = []
    var active = savedSetups.filter(function(item) { return item && !item.deletedAt })
    for (var i = 0; i < active.length; i++) {
      var setup = active[i], profile = null
      for (var j = 0; j < profiles.length; j++) if (profiles[j].uuid === setup.uuid) { profile = profiles[j]; break }
      exported.push({ uuid: setup.uuid, label: setup.label, vpn: !!setup.vpn, type: setup.type,
        connectionType: profile ? profile.type : "", connectionName: profile ? profile.name : "",
        ssid: profile ? profile.ssid : "" })
    }
    copyToClipboard(JSON.stringify({ format: "myles.network.setups", version: 2, setups: exported }, null, 2))
  }

  function importSavedSetups(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (!data || data.format !== "myles.network.setups" || !Array.isArray(data.setups)) throw new Error("Unrecognized Saved Setups backup")
      var known = {}
      for (var i = 0; i < savedSetups.length; i++) if (savedSetups[i]) known[savedSetups[i].uuid] = true
      var incoming = [], unmatched = 0
      for (var j = 0; j < data.setups.length; j++) {
        var s = data.setups[j]
        if (!s || !s.label) { unmatched++; continue }
        var match = null
        if (s.uuid) for (var p = 0; p < profiles.length; p++) if (profiles[p].uuid === s.uuid) { match = profiles[p]; break }
        if (!match && s.connectionType) {
          var candidates = []
          for (var q = 0; q < profiles.length; q++) {
            var candidate = profiles[q]
            if (candidate.type !== s.connectionType) continue
            if (s.connectionType === "802-11-wireless") {
              if (s.ssid && candidate.ssid === s.ssid) candidates.push(candidate)
            } else if (s.connectionType === "802-3-ethernet" && s.connectionName && candidate.name === s.connectionName) candidates.push(candidate)
          }
          if (candidates.length === 1) match = candidates[0]
        }
        if (!match || known[match.uuid]) { unmatched++; continue }
        known[match.uuid] = true
        incoming.push({ uuid: String(match.uuid), label: String(s.label), type: String(s.type || (match.isWifi ? "Wi-Fi" : "Ethernet")), vpn: !!s.vpn, deletedAt: 0 })
      }
      if (!incoming.length) throw new Error("No backups matched. Save the relevant NetworkManager profiles on this PC first; passwords are never included in this backup.")
      savedSetups = savedSetups.concat(incoming); writePluginState(); setupImportError = ""
      nmSuccess = "Imported " + incoming.length + " Saved Setup(s)"
      if (unmatched) setupImportError = unmatched + " setup(s) skipped: no unique local profile match. Network passwords are not included."
    } catch (e) { setupImportError = String(e.message || e) }
  }

  function importClipboard() {
    setupImportError = ""; profileImportError = ""
    savedSetupImportProc.running = true
  }

  function importIpv4Profiles(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (!data || data.format !== "myles.network.ipv4" || !Array.isArray(data.profiles)) throw new Error("Unrecognized backup format")
      var incoming = []
      for (var i = 0; i < data.profiles.length; i++) {
        var p = data.profiles[i]
        if (!p || !p.name || !validIpv4Pair(p.deviceIp, p.hostIp, p.prefix) || p.id === "builtin-cpe220") continue
        incoming.push(Object.assign({}, p, { id: "ipv4-import-" + Date.now() + "-" + i, builtin: false, deletedAt: 0 }))
      }
      if (!incoming.length) throw new Error("No valid profiles found in backup")
      savedIpv4Profiles = savedIpv4Profiles.concat(incoming)
      writePluginState()
      nmSuccess = "Imported " + incoming.length + " IPv4 profile(s)"
      profileImportError = ""
    } catch (e) { profileImportError = String(e.message || e) }
  }

  function useIpv4Profile(profile) {
    if (!profile || profile.deletedAt) return
    startCpeSetupFor(String(profile.deviceIp), String(profile.hostIp), String(profile.prefix))
  }

  function setDefaultIpv4Profile(profile) {
    if (!profile || profile.deletedAt) return
    defaultIpv4ProfileId = profile.id
    writePluginState()
  }

  function softDeleteIpv4Profile(profile) {
    if (!profile || profile.deletedAt) return
    var next = savedIpv4Profiles.slice()
    for (var i = 0; i < next.length; i++) if (next[i].id === profile.id)
      next[i] = Object.assign({}, next[i], { deletedAt: Date.now(), updatedAt: Date.now() })
    savedIpv4Profiles = next
    if (defaultIpv4ProfileId === profile.id) defaultIpv4ProfileId = ""
    if (ipv4ProfileEditId === profile.id) { ipv4ProfileEditId = ""; ipv4ProfileNameDraft = "" }
    writePluginState()
  }

  function savePrimaryDisplayName() {
    var label = primaryNameDraft.trim()
    if (!label) { nmError = "Enter a name for the primary shortcut"; return }
    primaryWiredName = label
    primaryEditOpen = false
    writePluginState()
  }

  function softDeletePrimary() {
    if (!primaryWiredUuid) return
    primaryDeletedAt = Date.now()
    writePluginState()
  }

  function restorePrimary() {
    if (!primaryDeletedAt) return
    primaryDeletedAt = 0
    writePluginState()
  }

  function restoreIpv4Profile(profile) {
    if (!profile || !profile.deletedAt) return
    var next = savedIpv4Profiles.slice()
    for (var i = 0; i < next.length; i++) if (next[i].id === profile.id)
      next[i] = Object.assign({}, next[i], { deletedAt: 0, updatedAt: Date.now() })
    savedIpv4Profiles = next
    writePluginState()
  }

  function returnToPrimaryWired() {
    if (!primaryWiredUuid || nmProc.running) return
    var exists = false
    for (var i = 0; i < profiles.length; i++) if (profiles[i].uuid === primaryWiredUuid) exists = true
    if (!exists) { nmError = "The saved primary wired profile is no longer available"; return }
    runNm("Returning to " + (primaryWiredName || "primary wired profile"),
      ["nmcli", "connection", "up", "uuid", primaryWiredUuid])
  }

  function saveCurrentAsPrimaryWired() {
    var profile = activeWiredProfile
    if (!profile || !profile.uuid || cpeProfileName !== "") {
      nmError = "Connect the primary Ethernet profile before saving it"; return
    }
    primaryWiredUuid = String(profile.uuid)
    primaryWiredName = String(profile.name || "Primary wired profile")
    writePluginState()
    nmSuccess = "Primary wired profile saved: " + primaryWiredName
  }

  function primaryConnectionSummary() {
    if (!primaryWiredUuid) return "No wired profile has been saved yet."
    for (var i = 0; i < wiredProfiles.length; i++) {
      var profile = wiredProfiles[i]
      if (profile && profile.uuid === primaryWiredUuid) {
        var addresses = Array.isArray(profile.addresses) ? profile.addresses.join(", ") : String(profile.addresses || "")
        return Model.profileMethodLabel(profile.method, profile.addresses)
          + (addresses ? " · " + addresses : "")
      }
    }
    return "Saved NetworkManager connection · " + primaryWiredUuid.slice(0, 8)
  }

  function restoreCpeSetup() {
    if (cpeProfileName === "" || cpeRestoreProc.running) return
    cpeRestoreTimer.stop()
    cpeRestoreProc.profileName = cpeProfileName
    cpeRestoreProc.previousUuid = cpePreviousUuid
    cpeRestoreProc.iface = cpeInterface
    cpeRestoreInProgress = true
    cpeRestoreProc.command = ["bash", "-c",
      'set -u; LC_ALL=C nmcli -t -f RUNNING general | grep -qx running || { echo "NetworkManager is not running" >&2; exit 10; }; tmp_uuid=$(nmcli -g UUID connection show id "$1" 2>/dev/null) || tmp_uuid=""; if [[ -n "$tmp_uuid" ]]; then nmcli connection delete uuid "$tmp_uuid" >/dev/null 2>&1 || { echo "Could not remove the temporary connection" >&2; exit 11; }; fi; if [[ -n "$2" ]]; then if [[ -n "$3" ]]; then nmcli connection up uuid "$2" ifname "$3" || { echo "The previous connection could not be activated on its original adapter" >&2; exit 12; }; else nmcli connection up uuid "$2" || { echo "The previous connection could not be activated" >&2; exit 12; }; fi; fi',
      "restore-cpe", cpeProfileName, cpePreviousUuid, cpeInterface]
    cpeRestoreProc.running = true
    wiredStatus = "Restoring the previous wired profile…"
  }

  // NetworkManager performs the HTTP probe (including unexpected page bodies,
  // not just redirects). Consume its native notifications rather than running
  // a second curl loop or mistaking an ordinary timeout for a captive portal.
  readonly property bool connectivityChecksEnabled: networkManagerAvailable
    && Networking.canCheckConnectivity && Networking.connectivityCheckEnabled
  readonly property string connectivity: Model.connectivityState(kind, Networking.connectivity, {
    Portal: NetworkConnectivity.Portal, Limited: NetworkConnectivity.Limited,
    Full: NetworkConnectivity.Full, None: NetworkConnectivity.None
  }, connectivityChecksEnabled)
  readonly property bool hasCaptivePortal: connectivity === "portal"
  readonly property bool restricted: hasCaptivePortal || connectivity === "limited"
  readonly property string icon: Model.connectionIcon(kind, signalStrength, connectivity)
  readonly property string connectionKey: kind === "wifi" && wifiDevice && connectedWifiNetwork
    ? kind + ":" + wifiDevice.name + ":" + connectedWifiNetwork.name
    : (kind === "ethernet" && wiredDevice ? kind + ":" + wiredDevice.name : "")

  onConnectionKeyChanged: Qt.callLater(checkConnectivity)
  onConnectivityChecksEnabledChanged: Qt.callLater(checkConnectivity)
  onHasCaptivePortalChanged: {
    if (hasCaptivePortal && opened && passwordSsid === "") {
      focusSection = "portal"
      cursorActive = true
    } else if (!hasCaptivePortal && focusSection === "portal") {
      focusSection = headerActionCount > 0 ? "header" : "dns"
      headerIndex = 0
    }
  }
  onRestrictedChanged: {
    connectionPhraseSwap.stop()
    heroMeta.opacity = 1.0
  }

  function checkConnectivity() {
    if (connectivityChecksEnabled && kind !== "disconnected") Networking.checkConnectivity()
  }

  function openCaptivePortal() {
    if (!hasCaptivePortal) return
    // Explicit user action only. argv (not a shell string), and a fixed HTTP
    // URL: let the browser handle the redirect without trusting portal input.
    Quickshell.execDetached(["omarchy-launch-browser", Model.captivePortalUrl])
    close()
  }

  // Keep checking while login is needed, even with the panel closed in favour
  // of the browser. Normal connected operation relies on NM's own schedule.
  Timer {
    id: connectivityPoll
    interval: 10000
    repeat: true
    running: root.restricted && root.connectivityChecksEnabled
    onTriggered: root.checkConnectivity()
  }

  // The share card is its own panel plugin (omarchy.wifiqr) so a replacement
  // design can take it over; summon() routes to whichever implementation is
  // enabled. The panel's own button pins the interface it is showing. The
  // IPC route forces self-detection instead: details polling stops while the
  // panel is closed, so its cached interface can be stale.
  function summonWifiQr(forceDetect) {
    controller.hide()
    cancelPasswordPrompt()
    var payload = {}
    if (!forceDetect && info.type === "wifi" && info.iface) {
      payload.iface = info.iface
      if (info.ssid) payload.ssid = info.ssid
    }
    bar.shell.summon("omarchy.wifiqr", JSON.stringify(payload))
  }

  function refresh(scanWifi) {
    checkConnectivity()
    if (scanWifi === undefined) scanWifi = false
    if (!detailsProc.running) detailsProc.running = true
    if (!dnsProc.running) {
      dnsProc.command = ["bash", "-c", root.dnsCommand("")]
      dnsProc.running = true
    }
    if (!bandProc.running) {
      bandProc.command = ["omarchy-network-band"]
      bandProc.running = true
    }
    refreshVpn()
    // A closed panel has no nearby-network list to fill, and bare refresh()
    // reaches here from action completion, timeouts and construction.
    if (opened && wifiDevice) {
      if (scanWifi) {
        scanning = true
        setScannerEnabled(false)
        scanRestart.start()
      } else {
        setScannerEnabled(true)
      }
    }
    syncWifiNetworks()
  }

  function formatHeaderSpeed(mbps) {
    return Model.formatHeaderSpeed(mbps)
  }

  function formatHeaderFreq(mhz) {
    return Model.formatHeaderFreq(mhz)
  }

  function headerDetail() {
    return Model.headerDetail(info)
  }

  function updateDetails(raw) {
    var next = Model.parseKeyValue(raw)

    // A band change tears the link down and brings it back, and the status
    // command reports nothing at all while there is no route. Publishing that
    // would blank every stat and unmount the whole section mid-toggle, so the
    // last good sample stands until the reconnect settles. A real disconnect is
    // still reported, because nothing is in flight then.
    if (bandBusy && !next.iface) return

    // The link and host probes are keyed on the routed interface, so they have
    // to be re-issued whenever the route moves. Doing it here rather than
    // waiting for the next poll is what keeps a Wi-Fi to Ethernet switch from
    // showing the old interface's carrier and counters for several seconds.
    var ifaceChanged = next.iface !== info.iface

    info = next
    updateThroughput(next)
    updatePingLatency(next)
    trackDailyUsage(next)

    if (ifaceChanged && opened) {
      refreshLink()
      refreshExtras()
      // The counters these read are per-interface, so the rate calculation has
      // to start over or the first sample after a switch is a phantom spike.
      prevIface = ""
      prevSampleTime = 0
      rateHistory = []
    }
  }

  function updateThroughput(next) {
    var state = Model.throughputState({
      prevIface: prevIface,
      prevRxBytes: prevRxBytes,
      prevTxBytes: prevTxBytes,
      prevSampleTime: prevSampleTime,
      downloadRate: downloadRate,
      uploadRate: uploadRate
    }, next, Date.now() / 1000)

    prevIface = state.prevIface
    prevRxBytes = state.prevRxBytes
    prevTxBytes = state.prevTxBytes
    prevSampleTime = state.prevSampleTime
    downloadRate = state.downloadRate
    uploadRate = state.uploadRate
  }

  function updatePingLatency(next) {
    var state = Model.pingLatencyState({
      pingIface: pingIface,
      routerPingSamples: routerPingSamples,
      internetPingSamples: internetPingSamples
    }, next, pingHistoryWindow, pingAverageWindow)

    pingIface = state.pingIface
    routerPingSamples = state.routerPingSamples
    internetPingSamples = state.internetPingSamples
    routerPingLatency = state.routerPingLatency
    internetPingLatency = state.internetPingLatency
    internetPingPacketLoss = state.internetPingPacketLoss
  }

  function formatBytes(bytes) {
    return Model.formatBytes(bytes)
  }

  function formatRate(bytesPerSec) {
    return Model.formatRate(bytesPerSec)
  }

  function formatPingLatency(ms) {
    return Model.formatPingLatency(ms, hasInternetPing)
  }

  function formatPacketLoss(percent) {
    return Model.formatPacketLoss(percent, hasInternetPing)
  }

  // Prefer a connected device: a machine can expose several NICs of the
  // same type (e.g. an idle onboard port alongside the active adapter),
  // and the first-enumerated one may be carrierless.
  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  function findConnectedWifiNetwork() {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }

  function syncWifiNetworks() {
    var nets = []
    var networks = wifiNetworkObjects || []

    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network) continue
      checkActionCompletion(network)
      var row = Model.wifiRow(network)
      if (row) nets.push(row)
    }
    wifiNetworks = Model.sortWifiRows(nets)
    wifiStationAvailable = !!wifiDevice
    scanning = false
  }

  function wifiSectionTitle(index) {
    return Model.wifiSectionTitle(wifiNetworks, index)
  }

  function wifiIconFor(strength) {
    return Model.wifiIconFor(strength)
  }

  function updateDns(raw) {
    var value = String(raw || "").trim()
    dnsProvider = value || "DHCP"
  }

  function updateBand(raw) {
    var status = Model.parseBandStatus(raw)

    // Mid-reconnect there is no connected station, so the command reports
    // nothing. Publishing that would empty the option list and unmount the
    // section on every toggle -- same guard as updateDetails.
    if (bandBusy && status.available.length === 0) return

    bandCurrent = status.band
    bandSelected = status.selected
    bandAvailable = status.available
  }

  // Pinning a band reassociates, but the panel deliberately stays open: the
  // reconnect is the thing you want to watch, and the details rows above
  // report it as it happens.
  function setBand(band) {
    if (!band || actionProc.running) return

    root.pendingBand = band
    actionProc.command = ["omarchy-network-band", band]
    actionProc.running = true
  }

  // The speed test is its own panel plugin (omarchy.speedtest) so a
  // replacement design can take it over; summon() routes to whichever
  // implementation is enabled. The payload names the connection when this
  // panel knows it; the plugin looks it up itself otherwise.
  function summonSpeedTest() {
    controller.hide()
    cancelPasswordPrompt()
    var connection = ""
    if (info.type === "wifi") connection = info.ssid || "Wi-Fi"
    else if (info.type === "ethernet") connection = "Ethernet"
    bar.shell.summon("omarchy.speedtest", connection ? JSON.stringify({ connection: connection }) : "{}")
  }

  function dnsCommand(provider) {
    var command = "omarchy-dns"
    if (provider) command += " " + Util.shellQuote(provider)
    return command
  }

  function setDns(provider) {
    if (!root.bar || !provider || actionProc.running) return

    if (provider === "Custom") {
      var launcher = "omarchy-launch-floating-terminal-with-presentation"
      root.bar.run(launcher + " " + Util.shellQuote(root.dnsCommand(provider)))
      root.close()
      return
    }

    root.pendingDnsProvider = provider
    actionProc.command = ["bash", "-c", root.dnsCommand(provider)]
    actionProc.running = true
    root.close()
  }

  function requiresCredentials(security) {
    return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe)
  }

  function openPasswordPrompt(ssid) {
    if (passwordSsid !== ssid) {
      passwordText = ""
      identityText = ""
    }
    passwordSsid = ssid
  }

  function networkForSsid(ssid) {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid) return networks[i]
    }
    return null
  }

  function wifiIndexForSsid(ssid) {
    for (var i = 0; i < wifiNetworks.length; i++) {
      if (wifiNetworks[i] && wifiNetworks[i].ssid === ssid) return i
    }
    return -1
  }

  function runNetworkAction(kind, network, callback) {
    if (actionKind !== "" || !network) return
    var ssid = network.name || ""
    actionSsid = ssid
    actionKind = kind
    failureSsid = ""
    failureReason = ""
    callback(network)
    // Safety net: if onExited never fires (process death, signal handler
    // throws, etc.), clear the busy state so the row doesn't get stuck on
    // "Connecting…" / "Disconnecting…" forever.
    actionTimeout.restart()
  }

  function clearNetworkAction() {
    actionTimeout.stop()
    if (actionKind === "connect") passwordSsid = ""
    failureSsid = ""
    failureReason = ""
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function failNetworkAction(network, reason) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    actionTimeout.stop()
    failureSsid = actionSsid
    failureReason = networkFailureReason(reason, requiresCredentials(network.security))
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function networkFailureReason(reason, needsCredentials) {
    return Model.networkFailureReason(reason, needsCredentials, connectionFailReasons)
  }

  function shouldRepromptPassphrase(reason, needsCredentials) {
    return Model.shouldRepromptPassphrase(reason, needsCredentials, connectionFailReasons)
  }

  function checkActionCompletion(network) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    if (actionKind === "connect" && network.connected) clearNetworkAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) clearNetworkAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging) clearNetworkAction()
  }

  function connectDirectly(ssid) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connect() })
  }

  function connectWithPassphrase(ssid, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connectWithPsk(passphrase) })
  }

  function connectEnterprise(ssid, identity, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) {
      enterpriseConnect.secret = passphrase
      enterpriseConnect.command = ["bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity]
      enterpriseConnect.running = true
    })
  }

  // Creates and activates the 802.1X profile (see Model.enterpriseConnectScript).
  // The password goes over stdin, never argv.
  Process {
    id: enterpriseConnect
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
  }

  function disconnect(network) {
    runNetworkAction("disconnect", network || connectedWifiNetwork, function(net) { net.disconnect() })
  }

  // Disconnect from a row's SSID. Rows are primitive snapshots that can outlive
  // their WifiNetwork, and disconnect()'s null fallback targets whatever is
  // connected now, so a stale row must do nothing rather than hit an unrelated
  // network. Callers that mean "drop the current connection" call disconnect().
  function disconnectRow(ssid) {
    var network = networkForSsid(ssid)
    if (network) disconnect(network)
  }

  function forget(net) {
    runNetworkAction("forget", net ? networkForSsid(net.ssid) : null, function(network) { network.forget() })
  }

  // =========================================================================
  // Stored profiles, link facts and host extras
  //
  // Everything below drives the plugin's own probes. The panel keeps one
  // serialized writer so two clicks cannot race, and so every failure surfaces
  // as a single sentence rather than a raw CLI string.
  // =========================================================================

  readonly property string scriptsPath: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  function probe(name) {
    return ["bash", scriptsPath + "/" + name]
  }

  // ---- serialized nmcli writer -------------------------------------------

  function runNm(label, argv, onDone) {
    // A click while an action is in flight is dropped rather than queued: the
    // probes all re-read from NetworkManager afterwards, so a queued second
    // write would act on a state the user can no longer see.
    if (nmProc.running) return
    nmLabel = label
    nmError = ""
    nmSuccess = ""
    pendingNmDone = onDone || null
    nmProc.command = argv
    nmProc.running = true
  }

  property var pendingNmDone: null

  // nmcli reports most failures on stderr with a useful sentence, but the
  // useful part is a trailing explanation after the generic prefix. Trim that
  // rather than showing the user a four-line nmcli diagnostic.
  function nmErrorText(raw) {
    var text = String(raw || "").trim()
    if (text === "") return ""
    var lines = text.split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line === "") continue
      if (line.indexOf("Error: failed to") === 0 && lines.length > 1) continue
      if (line.indexOf("** (") === 0) continue
      return line
    }
    return lines[lines.length - 1].trim()
  }

  function finishNm(exitCode, stdout, stderr) {
    var label = nmLabel
    var done = pendingNmDone
    nmLabel = ""
    pendingNmDone = null

    if (exitCode === 0) {
      nmSuccess = label
      // Re-read from NetworkManager: nothing is inferred from the write's own
      // output, because nmcli's echo is not the state a panel should render.
      refreshProfiles()
      refresh()
      if (done) done(true, stdout)
    } else {
      nmError = (label ? label + ": " : "") + nmErrorText(stderr || stdout)
      if (done) done(false, stderr)
    }
  }

  // ---- probes -------------------------------------------------------------

  function refreshProfiles() {
    profilesProc.running = true
  }

  function refreshLink() {
    var iface = info.iface || ""
    if (iface === "") {
      link = ({ exists: false })
      return
    }
    linkProc.iface = iface
    linkProc.running = true
  }

  function refreshExtras() {
    extrasProc.iface = info.iface || ""
    extrasProc.running = true
  }

  function refreshScanDetail() {
    scanProc.running = true
  }

  function applyProfiles(text) {
    var parsed = Model.parseProfiles(text)
    profiles = parsed.profiles
    blocklist = parsed.blocklist

    var wifi = []
    var wired = []
    for (var i = 0; i < parsed.profiles.length; i++) {
      if (parsed.profiles[i].isWifi) wifi.push(parsed.profiles[i])
      else if (parsed.profiles[i].isWired) wired.push(parsed.profiles[i])
    }
    wifiProfiles = wifi
    wiredProfiles = wired
  }

  // ---- Wi-Fi --------------------------------------------------------------

  // A manual rescan has to restart the scanner rather than just re-read the
  // cached list, and the list is only repopulated once the scan settles, so the
  // completion is driven by the same settle path the automatic scan uses.
  function rescan() {
    if (!wifiDevice || scanning) return
    scanning = true
    setScannerEnabled(false)
    scanRestart.start()
  }

  // Forget is destructive in a way the other row actions are not: a forgotten
  // profile takes its stored passphrase with it, and the user cannot get it back
  // without re-entering it. The hover trash icon is one click from that, so it
  // asks first.
  function requestForgetByUuid(profile) {
    if (!profile || !profile.uuid) return
    if (!confirmForget) {
      commitForget(profile)
      return
    }
    confirmForgetUuid = profile.uuid
    confirmForgetSsid = profile.ssid || profile.name
  }

  function requestForgetRow(net) {
    if (!net) return
    var profile = profileForSsid(net.ssid)
    if (profile) {
      requestForgetByUuid(profile)
      return
    }
    // A network seen in the scan but never saved is still a Quickshell
    // WifiNetwork with its own forget(), and there is nothing stored to lose.
    forget(net)
  }

  function cancelForget() {
    confirmForgetUuid = ""
    confirmForgetSsid = ""
  }

  function commitForget(profile) {
    var target = profile || profileByUuid(confirmForgetUuid)
    cancelForget()
    if (!target) return
    runNm("Removed " + (target.ssid || target.name), ["nmcli", "connection", "delete", "uuid", target.uuid])
  }

  function profileByUuid(uuid) {
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i].uuid === uuid) return profiles[i]
    }
    return null
  }

  // The profile a scan row corresponds to. A row can carry an SSID that differs
  // from the profile name (an enterprise AP is the usual case), so this is
  // matched on the stored SSID first and only then on the name.
  function profileForSsid(ssid) {
    if (!ssid) return null
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i].isWifi && profiles[i].ssid === ssid) return profiles[i]
    }
    for (var j = 0; j < profiles.length; j++) {
      if (profiles[j].isWifi && profiles[j].name === ssid) return profiles[j]
    }
    return null
  }

  function toggleAutoconnect(profile) {
    if (!profile || !profile.uuid) return
    runNm(
      (profile.autoconnect ? "Autoconnect off for " : "Autoconnect on for ") + (profile.ssid || profile.name),
      ["nmcli", "connection", "modify", "uuid", profile.uuid, "connection.autoconnect", profile.autoconnect ? "no" : "yes"])
  }

  // NetworkManager's autoconnect priority is unbounded and only relative, so a
  // move is a fixed step rather than a swap: it has to keep working when three
  // profiles are dragged past each other.
  property int priorityStep: 10

  function moveProfilePriority(profile, delta) {
    if (!profile || !profile.uuid) return
    var next = Math.max(0, profile.priority + delta)
    if (next === profile.priority) return
    runNm(
      "Priority " + next + " for " + (profile.ssid || profile.name),
      ["nmcli", "connection", "modify", "uuid", profile.uuid, "connection.autoconnect-priority", String(next)])
  }

  function isBlockedBssid(bssid) {
    return Model.isBlocked(blocklist, bssid)
  }

  function toggleBlocklist(bssid) {
    if (!bssid) return
    var blocked = isBlockedBssid(bssid)
    runNm(
      blocked ? "Unblocked " + bssid : "Blocked " + bssid,
      ["nmcli", "device", "wifi", blocked ? "remove-blacklist" : "add-blacklist", bssid])
  }

  // A hidden AP broadcasts no SSID, so it can never appear in a scan and the
  // passphrase prompt on a row is unreachable for it. The profile is created
  // explicitly instead.
  function addHiddenNetwork() {
    var ssid = hiddenSsid.trim()
    if (ssid === "" || hiddenSecret === "" || nmProc.running) return

    var eap = hiddenEnterprise
    if (eap && hiddenIdentity.trim() === "") {
      nmError = "An enterprise network needs an identity as well as a password"
      return
    }

    // Secrets go over stdin, never argv: `ps` is world-readable and the panel's
    // own Process is no more private than any other.
    hiddenAdd.secret = hiddenSecret
    hiddenAdd.ssid = ssid
    hiddenAdd.identity = hiddenIdentity.trim()
    hiddenAdd.enterprise = eap
    hiddenAdd.running = true

    hiddenSsid = ""
    hiddenSecret = ""
    hiddenIdentity = ""
    addHiddenOpen = false
  }

  Process {
    id: hiddenAdd
    property string secret: ""
    property string ssid: ""
    property string identity: ""
    property bool enterprise: false
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    onExited: function(exitCode) {
      root.nmError = exitCode === 0 ? "" : root.nmErrorText("Error: could not add the hidden network")
      if (exitCode === 0) {
        root.nmSuccess = "Added " + ssid
        root.refreshProfiles()
        root.refresh()
      }
    }
  }

  function toggleRowDetail(ssid) {
    detailSsid = detailSsid === ssid ? "" : ssid
  }

  // ---- Ethernet -----------------------------------------------------------

  function activateWired(profile) {
    if (!profile || !profile.uuid) return
    wiredBusyUuid = profile.uuid
    wiredStatus = ""
    runNm("Connecting " + profile.name, ["nmcli", "connection", "up", "uuid", profile.uuid], function(ok) {
      root.wiredBusyUuid = ""
      if (!ok) root.wiredStatus = "Could not bring up " + profile.name
    })
  }

  function disconnectWired(profile) {
    if (!profile || !profile.iface) return
    wiredBusyUuid = profile.uuid
    wiredStatus = ""
    // Target the saved profile UUID. `device disconnect <iface>` can drop a
    // different connection if this row became stale during a rescan.
    runNm("Disconnecting " + profile.name, ["nmcli", "connection", "down", "uuid", profile.uuid], function(ok) {
      root.wiredBusyUuid = ""
      if (!ok) root.wiredStatus = "Could not disconnect " + profile.iface
    })
  }

  function forgetWired(profile) {
    if (!profile || !profile.uuid) return
    wiredStatus = ""
    runNm("Removed " + profile.name, ["nmcli", "connection", "delete", "uuid", profile.uuid])
  }

  function toggleWiredWake(profile) {
    if (!profile || !profile.uuid) return
    var on = !!profile.wol
    runNm(
      (on ? "Wake-on-LAN off for " : "Wake-on-LAN on for ") + profile.name,
      ["nmcli", "connection", "modify", "uuid", profile.uuid, "802-3-ethernet.wake-on-lan", on ? "0" : "magic"])
  }

  function toggleWiredClonedMac(profile) {
    if (!profile || !profile.uuid) return
    // "preserve" is NetworkManager's instruction to present the permanent
    // hardware address; toggling off of it means asking for a stable random
    // one, which survives reconnects but is not a chosen address.
    var on = !!profile.clonedMac
    runNm(
      (on ? "Permanent MAC on " : "Random MAC on ") + profile.name,
      ["nmcli", "connection", "modify", "uuid", profile.uuid, "802-3-ethernet.cloned-mac-address", on ? "preserve" : "random"])
  }

  // Bouncing the interface is the only way to force the driver to renegotiate
  // speed and re-run DHCP, and it is the first thing to try when a link has
  // silently settled on the wrong rate.
  function relink() {
    var iface = info.iface || ""
    if (iface === "" || relinkProc.running) return
    wiredStatus = "Re-negotiating " + iface + "…"
    relinkProc.iface = iface
    relinkProc.running = true
  }

  Process {
    id: relinkProc
    property string iface: ""
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.wiredStatus = ""
        root.refresh()
        root.refreshLink()
      } else {
        root.wiredStatus = "Could not re-negotiate " + iface
      }
    }
  }

  // ---- static addressing --------------------------------------------------

  function beginStaticEdit(profile) {
    if (!profile) return
    staticEditUuid = profile.uuid
    // An existing manual profile already holds the answer; prefill from it so
    // editing one field does not silently blank the other three.
    var parts = String(profile.addresses || "").split(",")
    var first = (parts[0] || "").trim()
    var slash = first.indexOf("/")
    staticAddress = slash === -1 ? first : first.slice(0, slash)
    staticPrefix = slash === -1 ? "24" : first.slice(slash + 1)
    staticGateway = profile.gateway || ""
    staticDns = profile.dns || ""
    staticOriginal = {
      method: profile.method || "auto",
      addresses: profile.addresses || "",
      gateway: profile.gateway || "",
      dns: profile.dns || ""
    }
    staticCanRestore = false
  }

  function cancelStaticEdit() {
    staticEditUuid = ""
    staticAddress = ""
    staticPrefix = "24"
    staticGateway = ""
    staticDns = ""
    staticOriginal = null
    staticCanRestore = false
  }

  function applyStatic() {
    var profile = profileByUuid(staticEditUuid)
    if (!profile) return

    var address = staticAddress.trim()
    var prefix = staticPrefix.trim()
    if (address === "" || prefix === "") {
      nmError = "An address and a prefix length are both required"
      return
    }
    if (!Model.isIPv4(address)) {
      nmError = "\"" + address + "\" is not an IPv4 address"
      return
    }
    if (!/^[0-9]{1,2}$/.test(prefix) || parseInt(prefix, 10) < 1 || parseInt(prefix, 10) > 32) {
      nmError = "A prefix length is 1 to 32"
      return
    }

    var gateway = staticGateway.trim()
    var dns = staticDns.trim()
    if (gateway && (!Model.isIPv4(gateway) || !Model.ipv4InSubnet(address, gateway, prefix))) {
      nmError = "Gateway must be a valid IPv4 address in the same subnet"
      return
    }
    if (!Model.ipv4UsableHost(address, prefix)) {
      nmError = "That address is the subnet or broadcast address"
      return
    }
    var dnsServers = dns === "" ? [] : dns.split(/[\s,]+/).filter(function(value) { return value !== "" })
    for (var d = 0; d < dnsServers.length; d++) {
      if (!Model.isIPv4(dnsServers[d])) { nmError = "DNS servers must be valid IPv4 addresses"; return }
    }

    var argv = [
      "nmcli", "connection", "modify", "uuid", profile.uuid,
      "ipv4.method", "manual",
      "ipv4.addresses", address + "/" + prefix,
      // Explicit empty values clear old optional settings. Omitting an empty
      // gateway or DNS field used to leave its previous value in the profile.
      "ipv4.gateway", gateway,
      "ipv4.dns", dnsServers.join(",")
    ]

    var uuid = profile.uuid
    var name = profile.name
    runNm("Saved static address for " + name, argv, function(ok) {
      if (ok) root.staticCanRestore = true
    })
  }

  function useDhcp(profile) {
    if (!profile || !profile.uuid) return
    runNm(
      profile.name + " back on DHCP",
      ["nmcli", "connection", "modify", "uuid", profile.uuid, "ipv4.method", "auto",
        "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", ""],
      function(ok) { if (ok) root.staticCanRestore = true })
  }

  function restoreStaticOriginal() {
    var profile = profileByUuid(staticEditUuid)
    if (!profile || !staticOriginal) return
    var original = staticOriginal
    runNm("Restored previous IPv4 settings for " + profile.name, [
      "nmcli", "connection", "modify", "uuid", profile.uuid,
      "ipv4.method", original.method,
      "ipv4.addresses", original.addresses,
      "ipv4.gateway", original.gateway,
      "ipv4.dns", original.dns
    ], function(ok) { if (ok) root.cancelStaticEdit() })
  }

  // ---- wired 802.1X -------------------------------------------------------

  function openWiredEap(profile) {
    if (!profile) return
    wiredEapUuid = profile.uuid
    wiredEapIdentity = ""
    wiredEapSecret = ""
  }

  function cancelWiredEap() {
    wiredEapUuid = ""
    wiredEapIdentity = ""
    wiredEapSecret = ""
  }

  function submitWiredEap() {
    var profile = profileByUuid(wiredEapUuid)
    if (!profile) return
    var identity = wiredEapIdentity.trim()
    if (identity === "" || wiredEapSecret === "") {
      nmError = "Wired 802.1X needs both an identity and a password"
      return
    }
    var uuid = profile.uuid
    var name = profile.name
    var secret = wiredEapSecret
    cancelWiredEap()
    runNm(
      "802.1X set on " + name,
      ["nmcli", "connection", "modify", "uuid", uuid, "802-1x.identity", identity, "802-1x.eap", "peap"],
      function(ok) {
        if (!ok) return
        // The password cannot go on the same argv as the identity, so it is a
        // second write once the first has been accepted.
        root.runNm("802.1X password saved for " + name, ["nmcli", "connection", "modify", "uuid", uuid, "802-1x.password", secret])
      })
  }

  // ---- derived display state ---------------------------------------------

  readonly property var activeWiredProfile: {
    for (var i = 0; i < wiredProfiles.length; i++) {
      if (wiredProfiles[i].active === (info.iface || "")) return wiredProfiles[i]
    }
    return null
  }

  onActiveWiredProfileChanged: {
    if (pluginStateLoaded && !cpeProfileName && !primaryWiredUuid && activeWiredProfile)
      Qt.callLater(root.saveCurrentAsPrimaryWired)
  }

  readonly property string linkSpeedWarningText: {
    var warning = Model.linkSpeedWarning(link, activeWiredProfile)
    if (warning !== "") return warning
    return Model.linkDuplexWarning(link)
  }

  readonly property bool hasWiredDevice: !!wiredDevice

  // Reference information about the machine rather than the current link, so it
  // is opt-out and hidden entirely until there is something in it.
  readonly property bool hostSectionVisible: showHostDetails && !!info.iface

  // A resolver list can be long; the first two are what a person is looking
  // for, and the count tells them whether they are seeing all of it.
  readonly property string dnsSummary: {
    var servers = (extras && extras.dns) ? extras.dns : []
    if (servers.length === 0) {
      if (extras && extras.dnsUnavailable) return "Unavailable"
      return "--"
    }
    if (servers.length <= 2) return servers.join(", ")
    return servers[0] + ", " + servers[1] + " +" + (servers.length - 2)
  }

  readonly property string publicIpText: {
    if (!showPublicIp) return "Off"
    if (publicIpOk) return publicIp
    // While the first lookup is still in flight, "--" is the honest reading;
    // only a finished-but-failed lookup is reported as a failure.
    if (publicIpError === "" && !publicIpProc.running) return "--"
    return "Looking up…"
  }

  // Shown for a wired port that exists, or for stored wired profiles, but not
  // on a machine with neither -- a permanently empty Ethernet section is worse
  // than no section. The route being on Ethernet is deliberately not required:
  // choosing a profile is something you do from Wi-Fi.
  readonly property bool ethernetSectionVisible: showLinkDetails

  // Quickshell's WiredDevice.linkSpeed is authoritative while the port is up;
  // sysfs covers a port that is present but down, where linkSpeed reports
  // nothing. Neither is presented unless it is a real number -- a link that is
  // down has no negotiated speed, and printing "0mbit" would read as a fault
  // rather than as the absence of one.
  readonly property string wiredLinkSpeedLabel: {
    if (!hasWiredDevice) return "No port"

    var fromApi = 0
    if (wiredDevice && wiredDevice.connected && wiredDevice.linkSpeed > 0) {
      fromApi = wiredDevice.linkSpeed
    }
    if (fromApi > 0) return Model.formatLinkSpeed(fromApi)

    var fromSysfs = Model.formatLinkSpeed(link.speed)
    if (fromSysfs !== "") return fromSysfs

    if (link.exists && link.operstate !== "up") return "Link down"
    return "Unknown"
  }

  readonly property string wiredDuplexLabel: {
    if (!hasWiredDevice) return "--"
    if (link.operstate !== "up") return "Link down"
    var value = String(link.duplex || "").toLowerCase()
    if (value === "full") return "Full"
    if (value === "half") return "Half"
    return "Unknown"
  }

  function isSectionCollapsed(id) {
    if (Object.prototype.hasOwnProperty.call(pinnedSections, id)) return !pinnedSections[id]
    if (hoveredSectionId === id) return false
    return true
  }

  function setSectionHovered(id, hovered) {
    if (hovered) hoveredSectionId = id
    else if (hoveredSectionId === id) hoveredSectionId = ""
  }

  function toggleSection(id) {
    var next = {}
    for (var key in pinnedSections) {
      if (Object.prototype.hasOwnProperty.call(pinnedSections, key)) next[key] = pinnedSections[key]
    }
    if (Object.prototype.hasOwnProperty.call(next, id)) next[id] = !next[id]
    else next[id] = true
    pinnedSections = next
  }

  function pushRateSample() {
    rateHistory = Model.rateSeries(rateHistory, downloadRate, uploadRate, rateHistoryWindow)
  }

  function pushSignalSample() {
    var next = signalHistory.slice()
    next.push(kind === "wifi" && signalStrength >= 0 ? signalStrength : null)
    while (next.length > signalHistoryWindow) next.shift()
    signalHistory = next
  }

  // ---- public address -----------------------------------------------------

  function refreshPublicIp() {
    if (!showPublicIp || !opened) return
    if (publicIpProc.running) return
    publicIpProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    refresh()
    pluginStateDirProc.running = true
  }

  Process {
    id: pluginStateDirProc
    command: ["mkdir", "-p", root.pluginStateDir]
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.pluginStateDirReady = true
      pluginStateFile.reload()
    }
  }

  FileView {
    id: pluginStateFile
    path: root.pluginStatePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadPluginState(text())
    onLoadFailed: root.loadPluginState("{}")
  }

  Process {
    id: ipv4ImportProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.importIpv4Profiles(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.profileImportError = "Could not read clipboard. Copy the exported JSON first."
    }
  }

  Process {
    id: savedSetupImportProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.importSavedSetups(text) }
    onExited: function(exitCode) { if (exitCode !== 0) root.setupImportError = "Could not read clipboard. Copy the Saved Setups JSON first." }
  }

  Process {
    id: clipboardCopyProc
    property string payload: ""
    command: ["bash", "-c", "printf %s \"$1\" | wl-copy", "myles-network-copy", payload]
    onExited: function(exitCode) {
      if (exitCode === 0) root.nmSuccess = "Copied to clipboard"
      else root.nmError = "Could not copy to clipboard. Check that wl-clipboard is installed and a Wayland session is active."
    }
  }

  Process {
    id: cpeProbeProc
    property string address: ""
    command: ["ping", "-c", "1", "-W", "2", address]
    onExited: function(exitCode) {
      root.cpeReachability = exitCode === 0 ? "CPE responded at " + address : "No ICMP reply from " + address + " · the device may block ping"
    }
  }

  Process {
    id: cpeSetupProc
    property string profileName: ""
    property string previousUuid: ""
    property string iface: ""
    stderr: StdioCollector { id: cpeSetupStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.wiredStatus = "Could not create temporary CPE profile"
        root.nmError = String(cpeSetupStderr.text || "NetworkManager refused the temporary profile").trim()
        return
      }
      root.cpeProfileName = profileName
      root.cpePreviousUuid = previousUuid
      root.cpeInterface = iface
      // Persist the temporary profile before activation completes. If the
      // shell reloads while NetworkManager is bringing it up, the next panel
      // instance still knows what to remove and which connection to restore.
      root.cpeRestoreAt = Date.now() + root.cpeSetupDurationMs
      root.writePluginState()
      cpeActivateProc.profileName = profileName
      cpeActivateProc.command = ["nmcli", "connection", "up", "id", profileName]
      cpeActivateProc.running = true
    }
  }

  Process {
    id: cpeActivateProc
    property string profileName: ""
    stderr: StdioCollector { id: cpeActivateStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.nmError = String(cpeActivateStderr.text || "Could not activate the temporary CPE profile").trim()
        root.restoreCpeSetup()
        return
      }
      root.cpeRestoreAt = Date.now() + root.cpeSetupDurationMs
      cpeRestoreTimer.interval = root.cpeSetupDurationMs
      cpeRestoreTimer.start()
      root.wiredStatus = "Temporary CPE link active · restores in 15 minutes"
      root.nmSuccess = "Use " + root.cpeDeviceIp + " in your browser; temporary PC IP is " + root.cpeHostIp + "/" + root.cpePrefix
      cpeProbeProc.address = root.cpeDeviceIp
      cpeProbeProc.running = true
      root.writePluginState()
      root.refresh()
    }
  }

  Process {
    id: cpeRestoreProc
    property string profileName: ""
    property string previousUuid: ""
    property string iface: ""
    stderr: StdioCollector { id: cpeRestoreStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.cpeRestoreInProgress = false
      if (exitCode !== 0) {
        if (exitCode === 12) root.cpeTemporaryRemoved = true
        if (exitCode === 10)
          root.cpeRecoveryStatus = "NetworkManager is unavailable. The temporary profile may still be active; recovery will retry."
        else if (exitCode === 11)
          root.cpeRecoveryStatus = "Could not remove the temporary profile on " + root.cpeInterface + "; it may still be active. Recovery will retry."
        else if (exitCode === 12)
          root.cpeRecoveryStatus = "Temporary profile removed, but the previous connection could not be activated on " + root.cpeInterface + ". Recovery will retry."
        else root.cpeRecoveryStatus = "Connection recovery failed. Check adapter " + root.cpeInterface + " and retry."
        root.nmError = String(cpeRestoreStderr.text || "Could not complete wired connection recovery").trim()
        root.cpeRestoreAt = Date.now() + 30000
        root.writePluginState()
        cpeRestoreTimer.interval = 30000
        cpeRestoreTimer.start()
        return
      }
      var recoveryHadFailed = root.cpeRecoveryStatus !== ""
      root.cpeRecoveryStatus = ""
      root.cpeTemporaryRemoved = false
      root.cpeProfileName = ""
      root.cpePreviousUuid = ""
      root.cpeInterface = ""
      root.cpeRestoreAt = 0
      root.writePluginState()
      root.wiredStatus = "Temporary profile removed; previous wired profile restored"
      if (recoveryHadFailed) {
        root.nmError = ""
        root.nmSuccess = "Previous wired connection restored"
      }
      root.refresh()
    }
  }

  Timer {
    id: cpeRestoreTimer
    interval: root.cpeSetupDurationMs
    repeat: false
    onTriggered: root.restoreCpeSetup()
  }

  Timer {
    id: cpeCountdownTick
    interval: 60000
    repeat: true
    running: root.cpeProfileName !== ""
    onTriggered: root.cpeClock++
  }

  // Pulls everything we want about the active route's interface in one shot.
  Process {
    id: detailsProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDetails(text)
    }
  }

  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.opened && root.wifiDevice) {
        root.setScannerEnabled(true)
        scanDone.start()
      }
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    repeat: false
    onTriggered: root.syncWifiNetworks()
  }

  Process {
    id: dnsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDns(text)
    }
  }

  Process {
    id: bandProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBand(text)
    }
  }

  Process {
    id: protonProbeProc
    onExited: function(exitCode) {
      root.protonInstalled = exitCode === 0
      if (root.protonInstalled) root.refreshVpn()
    }
  }

  Process {
    id: vpnStatusProc
    stdout: StdioCollector { id: vpnStatusStdout; waitForEnd: true }
    stderr: StdioCollector { id: vpnStatusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.updateVpn(vpnStatusStdout.text, vpnStatusStderr.text)
    }
  }

  Process {
    id: protonAccountProc
    stdout: StdioCollector { id: protonAccountStdout; waitForEnd: true }
    stderr: StdioCollector { id: protonAccountStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.updateProtonAccount(protonAccountStdout.text, protonAccountStderr.text, exitCode)
    }
  }

  Process {
    id: vpnActionProc
    stdout: StdioCollector { id: vpnActionStdout; waitForEnd: true }
    stderr: StdioCollector { id: vpnActionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var action = root.vpnAction
      root.vpnAction = ""
      if (exitCode === 0) {
        root.vpnStatusText = action === "disconnect" ? "Disconnected" : "Connected"
        root.vpnError = ""
      } else {
        var err = String(vpnActionStderr.text || vpnActionStdout.text || "").trim()
        err = err.split(/\r?\n/).filter(function(l) { return !!l }).slice(-2).join(" · ")
        root.vpnStatusText = ""
        if (Model.protonAuthRequired(err)) {
          root.protonSignedIn = false
          root.protonAccount = ""
          root.vpnError = ""
        } else {
          root.vpnError = err !== "" ? err : ("Failed to " + (action === "disconnect" ? "disconnect" : "connect") + " Proton VPN")
        }
      }
      root.refreshVpn()
    }
  }

  // Slower than detailsPoll on purpose: this shells out to nmcli several times,
  // and band availability only moves when a scan turns up a new BSSID.
  Timer {
    id: bandPoll
    interval: 4000
    repeat: true
    running: root.opened
    onTriggered: {
      if (bandProc.running) return
      bandProc.command = ["omarchy-network-band"]
      bandProc.running = true
    }
  }

  Timer {
    id: vpnPoll
    interval: root.opened ? 3000 : 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshVpn()
  }

  // Action runner for DNS provider changes. Wi-Fi actions use the
  // Quickshell.Networking NetworkManager backend directly.
  Process {
    id: actionProc
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.pendingDnsProvider !== "") {
        if (exitCode === 0) root.dnsProvider = root.pendingDnsProvider
        root.pendingDnsProvider = ""
      }
      if (root.pendingBand !== "") {
        // A refused or reverted pin leaves bandSelected alone, so the pills
        // keep showing what is actually in force rather than what was asked.
        if (exitCode === 0) root.bandSelected = root.pendingBand
        root.pendingBand = ""
        // The panel stayed open through the reconnect, so pull fresh state now
        // instead of leaving stale readings until the next poll tick.
        root.refresh()
      }
    }
  }

  // Poll details while the panel is open so the IP/route header catches up
  // as soon as NetworkManager finishes activating a connection.
  Timer {
    id: detailsPoll
    interval: 1500
    repeat: true
    running: root.opened
    onTriggered: {
      if (!detailsProc.running) detailsProc.running = true
      // A sparkline sample is one per details tick, so the series and the
      // numbers above it are always the same length.
      if (root.showSparkline) {
        root.pushRateSample()
        root.pushSignalSample()
      }
    }
  }

  // Daily byte totals are sampled in the background while the bar widget is
  // alive, even when its popup is closed. The detailed UI keeps its faster
  // cadence only while visible.
  Timer {
    id: usagePoll
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!detailsProc.running) detailsProc.running = true
  }

  // ---- probe processes ----------------------------------------------------

  // Result plumbing: every probe reads its result in `onExited` rather than in
  // the collector's own onStreamFinished. onExited is the only one of the two
  // that is ordered after `waitForEnd` has drained the collector, so the text
  // here is guaranteed complete. A nonzero exit is treated as "no new data" and
  // leaves the previous result in place, so a probe that breaks on one poll
  // cannot blank a section that was populated a second earlier.
  //
  // Every probe script must also finish: the panel runs them with stdin open, so
  // any stage in them that defaults to stdin blocks forever and the panel is
  // left waiting on a process that will never exit.
  Process {
    id: profilesProc
    command: root.probe("net-profiles.sh")
    stdout: StdioCollector { id: profilesStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyProfiles(profilesStdout.text)
    }
  }

  Process {
    id: linkProc
    property string iface: ""
    // Rebuilt from `iface` rather than reassigned, so a poll that fires between
    // an interface change and its refresh still probes the current interface.
    command: ["bash", root.scriptsPath + "/net-link.sh", iface]
    stdout: StdioCollector { id: linkStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.link = Model.parseLink(linkStdout.text)
    }
  }

  Process {
    id: scanProc
    command: root.probe("net-scan.sh")
    stdout: StdioCollector { id: scanStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.scanDetail = Model.parseScan(scanStdout.text)
    }
  }

  Process {
    id: extrasProc
    property string iface: ""
    command: ["bash", root.scriptsPath + "/net-extras.sh", iface]
    stdout: StdioCollector { id: extrasStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.extras = Model.parseExtras(extrasStdout.text)
    }
  }

  // The one serialized writer. Every nmcli call the panel makes goes through
  // this so two clicks cannot interleave and a failure has one place to be
  // reported from.
  Process {
    id: nmProc
    stdout: StdioCollector { id: nmStdout; waitForEnd: true }
    stderr: StdioCollector { id: nmStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishNm(exitCode, nmStdout.text, nmStderr.text)
    }
  }

  // A public address is a round trip to a third party, so it is the slowest
  // thing the panel does and is fetched on its own long timer, only while open.
  Process {
    id: publicIpProc
    command: ["curl", "-s", "--max-time", "6", "-4", "https://api.ipify.org"]
    stdout: StdioCollector { id: publicIpStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var state = Model.publicIpState(publicIpStdout.text, exitCode)
      root.publicIp = state.address
      root.publicIpOk = state.ok
      // A failed lookup is reported once and then left alone; retrying it on
      // every tick of a timer the user cannot see is not a useful signal.
      root.publicIpError = state.ok ? "" : (exitCode === 0 ? "Unexpected response" : "Could not reach the lookup service")
    }
  }

  Timer {
    id: publicIpPoll
    interval: 300000
    repeat: true
    running: root.opened && root.showPublicIp
    triggeredOnStart: true
    onTriggered: root.refreshPublicIp()
  }

  // Link and host facts move far more slowly than the byte counters the
  // details poll already reads, and each is a handful of subprocesses, so they
  // get their own slower cadence rather than joining the 1.5s tick.
  Timer {
    id: linkPoll
    interval: 4000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: if (!linkProc.running) root.refreshLink()
  }

  Timer {
    id: extrasPoll
    interval: 8000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: if (!extrasProc.running) root.refreshExtras()
  }

  // Profiles only change when something the user does changes them, and a
  // refresh shells out once per stored profile, so this is the slowest poll in
  // the panel and exists mainly to notice a change made elsewhere.
  Timer {
    id: profilesPoll
    interval: 15000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: if (!profilesProc.running) root.refreshProfiles()
  }

  Timer {
    id: connectionPhraseTimer
    interval: 2800
    running: root.opened && !root.restricted && (root.info.type === "ethernet" || (root.info.type === "wifi" && root.canDisconnect))
    repeat: true
    onTriggered: connectionPhraseSwap.restart()
  }

  SequentialAnimation {
    id: connectionPhraseSwap
    PropertyAnimation {
      target: heroMeta; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.connectionPhraseIndex = (root.connectionPhraseIndex + 1) % root.connectionPhrases.length
    }
    PropertyAnimation {
      target: heroMeta; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onInfoChanged() {
      if (!(root.info.type === "ethernet" || (root.info.type === "wifi" && root.canDisconnect))) {
        connectionPhraseSwap.stop()
        heroMeta.opacity = 1.0
      }
    }
  }

  Timer {
    id: actionTimeout
    // Must outlast NetworkManager's 25s supplicant timeout: a wrong saved
    // PSK fails with WifiAuthTimeout at ~25s, and that failure has to land
    // while the action is still tracked to show "Wrong password" and reopen
    // the passphrase prompt.
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.actionKind) return
      var reason
      if (root.actionKind === "connect") reason = "Timed out connecting"
      else if (root.actionKind === "disconnect") reason = "Timed out disconnecting"
      else reason = "Timed out forgetting"
      root.failureSsid = root.actionSsid
      root.failureReason = reason
      root.actionSsid = ""
      root.actionKind = ""
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.restricted
    tooltipText: {
      if (root.hasCaptivePortal) return "Sign in to this network"
      if (root.restricted) return "Limited internet access"
      if (root.vpnActive) return "Proton VPN · " + root.vpnActiveName
      return ""
    }

    onPressed: function(b) {
      if (root.opened) root.close()
      // open() is enough: onOpenedChanged runs refresh(true), which defers the
      // PHY scan past the first frame. The bare refresh() that used to follow
      // took the no-scan branch and set scannerEnabled synchronously, undoing
      // that deferral and stalling the open on NetworkManager's AP flood.
      else root.open()
    }
  }

  // Keyboard-driven popup anchored to the bar widget icon. The shared
  // KeyboardPanel handles the layer-shell PanelWindow scaffolding
  // (focus priming on open, screen binding, anchored-to-icon positioning,
  // outside-click via an overlay MouseArea + Region mask that lets the bar
  // remain clickable, fade animation, popout coordination). What stays
  // here is the wifi-specific UI inside.
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Wide enough for the 4-up stats/DNS grids and the saved-row action chips
    // without the label/value cells colliding. 380 left "DNS servers" overlapping
    // its addresses and forced the wired action Flow onto two cramped lines.
    contentWidth: panel.fittedContentWidth(Style.space(480))
    // Measured from the Flickable, not the Column, so the card is sized to the
    // content when the content fits and to the screen when it does not.
    contentHeight: panel.fittedContentHeight(flick.contentHeight)

    // Catches all unhandled keys for keyboard navigation. AfterItem priority
    // lets the passphrase TextField (a child via focus chain) get its keys
    // first; only events the focused subtree ignores bubble back here.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Freeze the cursor model while the inline password prompt is open;
      // the TextField inside owns input until Esc/Enter/Cancel.
      blocked: root.passwordSsid !== ""

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          if (dy >= 0) return
        }
        if (dy !== 0) {
          // Hidden sections drop out of the keyboard chain entirely.
          if (root.focusSection === "header") {
            if (dy > 0) {
              if (root.hasCaptivePortal) {
                root.focusSection = "portal"
              } else if (root.canSelectBand) {
                root.focusSection = "band"
                root.bandAutoFocused = true
              } else {
                root.focusSection = "dns"
              }
            }
          } else if (root.focusSection === "portal") {
            if (dy < 0 && root.headerActionCount > 0) {
              root.focusSection = "header"
              root.headerIndex = 0
            } else if (dy > 0) {
              root.focusSection = root.canSelectBand ? "band" : "dns"
              root.bandAutoFocused = true
            }
          } else if (root.focusSection === "band") {
            // Automatic on the header line, then the pills -- which collapse
            // away under Automatic, leaving a single row to walk.
            if (dy < 0) {
              if (!root.bandAutoFocused) {
                root.bandAutoFocused = true
              } else if (root.hasCaptivePortal) {
                root.focusSection = "portal"
              } else if (root.headerActionCount > 0) {
                root.focusSection = "header"
                root.headerIndex = 0
              }
            } else if (root.bandAutoFocused && root.bandPillsVisible) {
              root.bandAutoFocused = false
            } else {
              root.focusSection = "dns"
            }
          } else if (root.focusSection === "dns") {
            // k from DNS moves up into the band section when it's on screen,
            // then the disconnect button; otherwise stays put. j drops into the
            // wifi list if there's anywhere to land.
            if (dy < 0) {
              if (root.canSelectBand) {
                root.focusSection = "band"
                root.bandAutoFocused = !root.bandPillsVisible
              } else if (root.hasCaptivePortal) {
                root.focusSection = "portal"
              } else if (root.headerActionCount > 0) {
                root.focusSection = "header"
                root.headerIndex = 0
              }
            } else if (root.wifiNetworks.length > 0) {
              root.focusSection = "wifi"
              if (root.selectedIndex < 0) root.selectedIndex = 0
            }
          } else {  // wifi
            // k from the top row escapes back up to the DNS row rather than
            // wrapping around to the bottom of the list.
            if (dy < 0 && root.selectedIndex <= 0) {
              root.focusSection = "dns"
              root.wifiActionFocused = false
            }
            else root.selectByDelta(dy)
          }
        }
        if (dx !== 0) {
          if (root.focusSection === "header") root.selectHeaderByDelta(dx)
          else if (root.focusSection === "band") { if (!root.bandAutoFocused) root.selectBandByDelta(dx) }
          else if (root.focusSection === "dns") root.selectDnsByDelta(dx)
          else if (root.focusSection === "wifi") root.selectWifiActionByDelta(dx)
        }
      }
      onActivateRequested: {
        if (root.cursorActive) {
          if (root.focusSection === "header") root.activateHeader()
          else if (root.focusSection === "portal") root.openCaptivePortal()
          else if (root.focusSection === "band") root.activateBand()
          else if (root.focusSection === "dns") root.activateDns()
          else root.activateSelected()
        }
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "w" || t === "W") root.toggleNetwork()
        else if (t === "v" || t === "V") root.toggleVpn()
      }

    // The card is clamped to the space between the bar and the bottom of the
    // screen, and KeyboardPanel puts no scroll container of its own around
    // panel content. Everything below the fold would simply be unreachable, and
    // the fold moves as rows come and go, so the content scrolls here instead.
    //
    // The Flickable is what `contentHeight` below is measured from, so the card
    // still shrinks to fit short content and there is nothing to scroll until
    // the content genuinely outgrows the screen. A wheel over a nested scrolling
    // list goes to that list, since the innermost flickable gets the event
    // first.
    Flickable {
      id: flick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      interactive: true
      flickableDirection: Flickable.VerticalFlick
      boundsBehavior: Flickable.StopAtBounds

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: flick.width
        spacing: Style.space(12)


        // ---------- Hero: network icon · SSID + state · actions ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)

          // Status only — the switch owns toggling, mouse and keyboard alike.
          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.icon
            color: root.restricted ? root.bar.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.networkManagerAvailable ? 1.0 : 0.5
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          // Sharing belongs to the connected-network hero rather than the scan
          // result row. The radio switch remains beside it as the other hero action.
          RowLayout {
            id: heroActions
            spacing: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Button {
              id: qrAction
              visible: root.canShareWifi
              iconText: "󰐲"
              tooltipText: "Show QR code"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              hasCursor: root.qrHeaderHasCursor
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setHeaderCursor(root.qrHeaderIndex) }
              onClicked: root.summonWifiQr()
            }

            Button {
              id: speedAction
              visible: root.canRunSpeedTest
              iconText: "󰓅"
              tooltipText: "Run a speed test"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              hasCursor: root.speedHeaderHasCursor
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setHeaderCursor(root.speedHeaderIndex) }
              onClicked: root.summonSpeedTest()
            }

            ToggleSwitch {
              id: powerSwitch
              Accessible.name: "Wi-Fi radio"
              Accessible.description: root.toggleHint
              visible: root.canToggleWifi
              checked: Networking.wifiEnabled
              hasCursor: root.toggleHeaderHasCursor
              foreground: root.bar.foreground
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setHeaderCursor(root.toggleHeaderIndex) }
              onToggled: root.toggleNetwork()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: root.bar.fontFamily
              }
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: heroActions.width > 0 ? heroActions.width + Style.space(12) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            // Link detail rides inline after the name — "Ethernet (2.5gbit)" —
            // rather than in a pill, which crowded the on/off switch.
            Text {
              id: heroSsid
              textFormat: Text.PlainText
              width: parent.width

              readonly property string title: {
                // The HTTP restriction does not undo association. Show the live
                // SSID even before route/details polling has returned anything.
                if (root.kind === "wifi" && root.connectedWifiNetwork) return root.connectedWifiNetwork.name || "Wi-Fi"
                if (root.info.type === "wifi") return root.info.ssid || "Wi-Fi"
                if (root.info.type === "ethernet") return "Ethernet"
                return root.info.iface || (root.kind === "disconnected" ? "Disconnected" : "No connection")
              }
              readonly property string detail: root.headerDetail()

              text: heroSsid.detail !== "" ? heroSsid.title + " (" + heroSsid.detail + ")" : heroSsid.title
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              id: heroMeta
              textFormat: Text.PlainText
              width: parent.width
              text: {
                if (root.hasCaptivePortal) return "SIGN-IN REQUIRED"
                if (root.restricted) return "LIMITED INTERNET ACCESS"
                if (root.info.type === "wifi") {
                  if (root.canDisconnect) return root.connectionPhrase.toUpperCase()
                  if (root.kind === "disconnected") return "NOT CONNECTED"
                  return ""
                }
                if (root.info.type === "ethernet") return root.connectionPhrase.toUpperCase()
                if (root.kind === "disconnected") return "NOT CONNECTED"
                return ""
              }
              visible: text !== ""
              color: root.restricted ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // Proton VPN: simple on/off after a one-time sign-in.
        Column {
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            spacing: Style.space(10)

            Column {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: "Proton VPN"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.vpnSectionMeta
                color: (root.vpnError !== "" && root.protonSignedIn) ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Button {
              visible: !root.protonInstalled
              text: "Install"
              iconText: "󰏖"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.installProtonVpn()
            }

            Button {
              visible: root.protonInstalled && !root.protonSignedIn
              text: "Sign in"
              iconText: "󰌾"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.openProtonSignIn()
            }

            Button {
              visible: root.protonInstalled && root.protonSignedIn && !root.vpnActive
              text: root.vpnError !== "" ? "Retry" : "Connect"
              iconText: "󰖂"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              Layout.alignment: Qt.AlignVCenter
              enabled: !root.vpnBusy
              onClicked: root.toggleVpn()
            }

            ToggleSwitch {
              id: vpnSectionSwitch
              Accessible.name: "Proton VPN connection"
              checked: root.vpnActive
              enabled: root.protonInstalled && !root.vpnBusy
              foreground: root.bar.foreground
              Layout.alignment: Qt.AlignVCenter
              onToggled: root.toggleVpn()

              PanelToolTip {
                visible: vpnSectionSwitch.containsMouse
                text: root.vpnToggleHint
                fontFamily: root.bar.fontFamily
              }
            }
          }
        }

        // DNS provider selection.
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "DNS PROVIDER"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: dnsRow
            width: parent.width
            spacing: Style.space(6)

            readonly property int count: 4
            readonly property real cellWidth: (width - spacing * (count - 1)) / count

            DnsProviderPill {
              provider: "DHCP"
              index: 0
              tooltipText: "Use DNS from DHCP"
              width: dnsRow.cellWidth
              onClicked: root.setDns(provider)
            }

            DnsProviderPill {
              provider: "Cloudflare"
              index: 1
              tooltipText: "Set DNS to Cloudflare"
              width: dnsRow.cellWidth
              onClicked: root.setDns(provider)
            }

            DnsProviderPill {
              provider: "Google"
              index: 2
              tooltipText: "Set DNS to Google"
              width: dnsRow.cellWidth
              onClicked: root.setDns(provider)
            }

            DnsProviderPill {
              provider: "Custom"
              index: 3
              tooltipText: "Set custom DNS servers"
              width: dnsRow.cellWidth
              onClicked: root.setDns(provider)
            }
          }
        }


        // Wi-Fi networks (only if a Wi-Fi station is available).
        PanelSeparator {
          visible: root.wifiStationAvailable
          foreground: root.bar.foreground
        }

        Column {
          id: availableWifiSection
          visible: root.wifiStationAvailable
          width: parent.width
          spacing: Style.space(4)

          HoverHandler {
            onHoveredChanged: root.setSectionHovered("wifiAvailable", hovered)
          }

          Item {
            visible: root.wifiStationAvailable
            width: parent.width
            implicitHeight: wifiHeaderRow.implicitHeight

          PanelSectionHeader {
            id: wifiHeaderRow
            // The scan state lives here rather than in its own header, so the
            // "scan again" control is reachable without waiting for a scan to
            // finish -- the automatic scan on open is the only one that blocks.
            text: root.scanning ? "SCANNING WI-FI…" : "AVAILABLE WI-FI"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            id: wifiHeaderActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: root.isSectionCollapsed("wifiAvailable") ? "›" : "⌄"
              color: root.bar.foreground
              opacity: 0.65
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              Accessible.role: Accessible.Button
              Accessible.name: root.isSectionCollapsed("wifiAvailable") ? "Expand available Wi-Fi" : "Collapse available Wi-Fi"
              Accessible.onPressAction: root.toggleSection("wifiAvailable")

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleSection("wifiAvailable")
              }
            }

            ActionChip {
              actionText: "Scan again"
              // A rescan while one is in flight would restart the radio for
              // nothing, so the button reflects the state rather than the intent.
              enabled: !root.scanning
              onClicked: root.rescan()
            }

            ActionChip {
              actionText: root.addHiddenOpen ? "Cancel" : "Add hidden"
              armed: root.addHiddenOpen
              onClicked: {
                root.addHiddenOpen = !root.addHiddenOpen
                if (!root.addHiddenOpen) {
                  root.hiddenSsid = ""
                  root.hiddenSecret = ""
                  root.hiddenIdentity = ""
                  root.hiddenEnterprise = false
                }
              }
            }
          }
        }

        // Scrollable network list — cap the height so a busy neighbourhood
        // doesn't push the popup off-screen. ListView (vs Repeater+Column)
        // gives us positionViewAtIndex for free, which is what keeps the
        // keyboard-selected row scrolled into view as j/k walk past the
        // visible window.
        ListView {
          id: networkList
          visible: root.wifiStationAvailable && !root.isSectionCollapsed("wifiAvailable")
          width: parent.width
          height: Math.min(contentHeight, Style.space(240))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          model: root.wifiStationAvailable ? root.wifiNetworks : []
          currentIndex: root.selectedIndex
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          // Wrapper takes the required props from ListView's delegate context
          // (which doesn't bind into nested `component` declarations like
          // NetworkRow) and passes them down explicitly.
          delegate: Item {
            required property var modelData
            required property int index
            readonly property string sectionTitle: root.wifiSectionTitle(index)
            width: ListView.view.width
            height: delegateColumn.implicitHeight

            Column {
              id: delegateColumn
              width: parent.width
              spacing: Style.space(4)
              // `index` is a required property of the delegate, which is in scope
              // here but is not reachable as `parent.parent.index`: an Item has no
              // `index` member, so that lookup silently yields undefined.
              readonly property int rowIndex: index

              PanelSectionHeader {
                visible: sectionTitle !== ""
                text: sectionTitle
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              // No id on this delegate instance: `row` is the root id inside the
              // NetworkRow component, and giving the instance the same name
              // duplicates it in the scope the component is declared in.
              NetworkRow {
                width: parent.width
                net: modelData
                index: delegateColumn.rowIndex
              }
            }
          }
          }
        }
        // ---- hidden network form -------------------------------------------
        // A non-broadcasting AP never appears in a scan, so the per-row passphrase
        // prompt is unreachable for it. This is the only way in.
        Column {
          id: hiddenForm
          visible: root.addHiddenOpen
          width: parent.width
          spacing: Style.space(8)
          topPadding: Style.space(8)

          InlineField {
            label: "Network name (SSID)"
            placeholder: "Hidden network"
            value: root.hiddenSsid
            onCommitted: function(text) { root.hiddenSsid = text }
            onCancelled: root.addHiddenOpen = false
          }

          SettingRow {
            text: "Enterprise (802.1X)"
            checked: root.hiddenEnterprise
            onToggled: function() { root.hiddenEnterprise = !root.hiddenEnterprise }
          }

          InlineField {
            visible: root.hiddenEnterprise
            label: "Identity"
            placeholder: "user@domain"
            value: root.hiddenIdentity
            onCommitted: function(text) { root.hiddenIdentity = text }
          }

          InlineField {
            label: root.hiddenEnterprise ? "Password" : "Passphrase"
            placeholder: "Required"
            secret: true
            value: root.hiddenSecret
            onCommitted: function(text) { root.hiddenSecret = text }
          }

          Row {
            spacing: Style.space(6)

            ActionChip {
              actionText: "Connect"
              armed: root.hiddenSsid.trim() !== "" && root.hiddenSecret !== ""
                && (!root.hiddenEnterprise || root.hiddenIdentity.trim() !== "")
              enabled: root.hiddenSsid.trim() !== "" && root.hiddenSecret !== ""
              onClicked: root.addHiddenNetwork()
            }

            ActionChip {
              actionText: "Cancel"
              onClicked: {
                root.addHiddenOpen = false
                root.hiddenSsid = ""
                root.hiddenSecret = ""
                root.hiddenIdentity = ""
                root.hiddenEnterprise = false
              }
            }
          }
        }

        // ---- forget confirmation -------------------------------------------
        // Shown in place of the list rather than as a modal: the panel is a popup
        // already, and a dialog on top of a popup obscures the row it is about.
        Column {
          visible: root.confirmForgetUuid !== ""
          width: parent.width
          topPadding: Style.space(8)
          spacing: Style.space(6)

          Column {
            id: forgetConfirm
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              // Stated explicitly, because the consequence is not obvious: the
              // stored passphrase goes with the profile and cannot be recovered.
              text: "Remove the saved profile for " + root.confirmForgetSsid + "? The saved password is deleted."
              color: root.bar.foreground
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              spacing: Style.space(6)

              ActionChip {
                actionText: "Remove"
                destructive: true
                armed: true
                onClicked: root.commitForget(null)
              }

              ActionChip {
                actionText: "Keep"
                onClicked: root.cancelForget()
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          id: setupSection
          width: parent.width
          spacing: Style.space(8)

          HoverHandler {
            onHoveredChanged: root.setSectionHovered("setups", hovered)
          }

          RowLayout {
            width: parent.width
            CollapsibleHeader { Layout.fillWidth: true; text: "SAVED SETUPS"; sectionId: "setups" }
            ActionChip { actionText: root.showSetupTrash ? "Hide recovery" : "Recovery"; armed: root.showSetupTrash; onClicked: root.showSetupTrash = !root.showSetupTrash }
          }

          Column {
            visible: !root.isSectionCollapsed("setups")
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Pin a saved Wi-Fi or Ethernet profile for one-click switching. Backups transfer shortcuts only; the matching local profile and its credentials must already exist."
              color: root.bar.foreground
              opacity: 0.65
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              TextField {
                width: root.narrowLayout ? parent.width : parent.width * 0.45
                placeholderText: "Search saved setups"
                Accessible.name: "Search Saved Setups"
                text: root.setupSearch
                onTextChanged: root.setupSearch = text
              }
              ActionChip { actionText: "Export JSON"; Accessible.name: "Export Saved Setups as JSON"; onClicked: root.exportSavedSetups() }
              ActionChip { actionText: "Import"; Accessible.name: "Import Saved Setups JSON from clipboard"; enabled: !savedSetupImportProc.running; onClicked: root.importClipboard() }
            }
            Text { visible: root.setupImportError !== ""; width: parent.width; text: root.setupImportError; color: root.bar.urgent; wrapMode: Text.WordWrap; Accessible.role: Accessible.Alert }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              TextField {
                id: setupNameField
                Layout.fillWidth: true
                placeholderText: "Setup name"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                foreground: root.bar.foreground
                horizontalPadding: Style.spacing.controlGap
                verticalPadding: Style.spacing.controlPaddingY
                text: root.setupNameDraft
                onTextChanged: if (text !== root.setupNameDraft) root.setupNameDraft = text
                selectByMouse: true
              }
              Button {
                text: "Save current"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(4)
                enabled: root.pluginStateLoaded && !!root.activeProfile && root.setupNameDraft.trim() !== ""
                onClicked: root.addCurrentSetup()
              }
            }

            RowLayout {
              width: parent.width
              Text {
                Layout.fillWidth: true
                text: "Connect Proton VPN with this setup"
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              ToggleSwitch {
                Accessible.name: "Connect Proton VPN with this setup"
                checked: root.setupVpnDraft
                foreground: root.bar.foreground
                onToggled: root.setupVpnDraft = checked
              }
            }

            Repeater {
              model: root.activeSetups()
              delegate: RowLayout {
                required property var modelData
                width: parent.width
                spacing: Style.space(6)
                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: modelData.label + " · " + modelData.type + (modelData.vpn ? " · VPN" : "")
                  color: root.bar.foreground
                  elide: Text.ElideRight
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Button {
                  text: "Use"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  enabled: root.pluginStateLoaded && !root.nmBusy
                  onClicked: root.activateSetup(modelData)
                }
                Button {
                  text: "Remove"
                  foreground: root.bar.urgent
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  onClicked: root.removeSetup(modelData.uuid)
                }
              }
            }

            Text {
              visible: root.activeSetups().length === 0
              width: parent.width
              text: "No setups saved yet. Connect to a profile, name it above, and save it."
              textFormat: Text.PlainText
              color: root.bar.foreground
              opacity: 0.55
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              visible: root.showSetupTrash
              width: parent.width
              spacing: Style.space(4)
              Text { text: "RECOVERY"; color: root.bar.foreground; opacity: 0.6; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
              Repeater {
                model: root.deletedSetups()
                delegate: RowLayout {
                  required property var modelData
                  width: parent.width
                  Text { Layout.fillWidth: true; text: modelData.label + " · deleted"; color: root.bar.foreground; opacity: 0.65; elide: Text.ElideRight; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                  ActionChip { actionText: "Restore"; Accessible.name: "Restore saved setup " + modelData.label; onClicked: root.restoreSetup(modelData.uuid) }
                }
              }
              Text { visible: root.deletedSetups().length === 0; text: "Recovery is empty."; color: root.bar.foreground; opacity: 0.5; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          id: cpeSection
          width: parent.width
          spacing: Style.space(8)

          HoverHandler {
            onHoveredChanged: root.setSectionHovered("cpe", hovered)
          }

          CollapsibleHeader {
            text: "CPE IPv4 SETUP"
            sectionId: "cpe"
          }

          Column {
            visible: !root.isSectionCollapsed("cpe")
            width: parent.width
            spacing: Style.space(6)

        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            visible: !root.wiredDevice && root.cpeProfileName === ""
            text: "Connect the PC to the CPE through its PoE adapter Ethernet port to enable setup."
            textFormat: Text.PlainText
            color: root.bar.foreground
            opacity: 0.68
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            text: "TEMPORARY CPE SETUP"
            textFormat: Text.PlainText
            color: root.bar.foreground
            opacity: 0.65
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.0
          }
          Text {
            width: parent.width
            text: root.cpeProfileName !== ""
              ? root.cpeRestoreInProgress ? "Restoring the temporary CPE connection on " + root.cpeInterface + "…"
                : root.cpeTemporaryRemoved ? "Temporary profile removed · restoring the previous connection on " + root.cpeInterface
                : "Temporary profile active on " + root.cpeInterface + ". It restores the previous wired profile automatically."
              : "For a factory-default TP-Link CPE220: PC 192.168.0.10/24, device 192.168.0.254. Wi-Fi stays available."
            textFormat: Text.PlainText
            color: root.bar.foreground
            opacity: 0.68
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(4)
            Text {
              text: "Ethernet adapter"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            Repeater {
              model: root.wiredDevices
              delegate: ActionChip {
                required property var modelData
                actionText: modelData.name + (modelData.connected ? " · connected" : "")
                armed: root.cpeSelectedInterface === modelData.name || (!root.cpeSelectedInterface && root.wiredDevice === modelData)
                enabled: modelData.connected && root.cpeProfileName === ""
                Accessible.name: "Use Ethernet adapter " + modelData.name
                onClicked: { root.cpeSelectedInterface = modelData.name; root.cpeConflictConfirmed = false }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: root.cpeProfileName !== ""
                ? "Temporary link active on " + root.cpeInterface + " · restores automatically"
                : "Use a saved setup to reach the device. The PC address is temporary and has no gateway or DNS."
              textFormat: Text.PlainText
              color: root.bar.foreground
              opacity: 0.68
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: root.cpeProfileName === "" && root.cpeSubnetConflict(root.cpeDeviceIp, root.cpeHostIp, root.cpePrefix) !== ""
              text: root.cpeSubnetConflict(root.cpeDeviceIp, root.cpeHostIp, root.cpePrefix)
              color: root.bar.urgent
              wrapMode: Text.WordWrap
              Accessible.role: Accessible.Alert
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            CheckBox {
              visible: root.cpeSubnetConflict(root.cpeDeviceIp, root.cpeHostIp, root.cpePrefix) !== ""
              text: "I understand; continue anyway"
              Accessible.name: "Confirm possible subnet overlap"
              checked: root.cpeConflictConfirmed
              onToggled: root.cpeConflictConfirmed = checked
            }

            Flow {
              spacing: Style.space(6)
              width: parent.width
              ActionChip {
                actionText: root.cpeProfileName !== "" ? "Restore connection now" : "Start with current addresses"
                armed: root.cpeProfileName !== ""
                Accessible.name: root.cpeProfileName !== "" ? "Restore previous Ethernet connection now" : "Start temporary CPE IPv4 setup"
                enabled: root.pluginStateLoaded && ((root.cpeProfileName !== "" && !cpeActivateProc.running && !cpeRestoreProc.running) || (!!root.selectedCpeDevice && root.selectedCpeDevice.connected && root.cpeProfileName === "" && !cpeSetupProc.running && !cpeActivateProc.running && !cpeRestoreProc.running))
                onClicked: root.cpeProfileName === "" ? root.startCpeSetup() : root.restoreCpeSetup()
              }
              ActionChip {
                visible: root.cpeProfileName !== ""
                actionText: "Test CPE"
                enabled: visible && !cpeProbeProc.running
                Accessible.name: "Test if CPE responds at " + root.cpeDeviceIp
                onClicked: { root.cpeReachability = "Checking CPE…"; cpeProbeProc.address = root.cpeDeviceIp; cpeProbeProc.running = true }
              }
              Text {
                text: root.cpeProfileName !== ""
                  ? Math.max(0, Math.ceil((root.cpeRestoreAt - Date.now() + root.cpeClock * 0) / 60000)) + " min left"
                  : root.selectedCpeDevice && root.selectedCpeDevice.connected ? "Temporary · no default route" : "Waiting for selected Ethernet adapter"
                textFormat: Text.PlainText
                color: root.bar.foreground
                opacity: 0.58
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: root.cpeReachability !== ""
                text: root.cpeReachability
                color: root.bar.foreground
                opacity: 0.7
                wrapMode: Text.WordWrap
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: root.cpeRecoveryStatus !== ""
                text: root.cpeRecoveryStatus
                color: root.bar.urgent
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.Alert
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              Text {
                Layout.fillWidth: true
                text: "SAVED IPv4 PROFILES"
                textFormat: Text.PlainText
                color: root.bar.foreground
                opacity: 0.68
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }
              ActionChip {
                actionText: "Add new"
                enabled: root.cpeProfileName === ""
                onClicked: root.beginNewIpv4Profile()
              }
              ActionChip {
                actionText: root.showIpv4Trash ? "Hide recovery" : "Recovery"
                armed: root.showIpv4Trash
                onClicked: root.showIpv4Trash = !root.showIpv4Trash
              }
            }

            Text {
              width: parent.width
                text: "Primary is your normal wired connection. The CPE220 preset and saved profiles are temporary PC addresses for reaching a device."
              textFormat: Text.PlainText
              color: root.bar.foreground
              opacity: 0.55
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

          Flow {
            width: parent.width
            spacing: Style.space(4)
            TextField {
              width: root.narrowLayout ? parent.width : parent.width * 0.45
              placeholderText: "Search profiles"
              Accessible.name: "Search IPv4 profiles by name or address"
              text: root.ipv4Search
              onTextChanged: root.ipv4Search = text
            }
            ActionChip { actionText: root.ipv4SortByName ? "Sort: custom" : "Sort: name"; Accessible.name: "Sort IPv4 profiles"; onClicked: root.ipv4SortByName = !root.ipv4SortByName }
            ActionChip { actionText: "Export JSON"; onClicked: root.exportIpv4Profiles() }
              ActionChip { actionText: "Import clipboard"; enabled: !ipv4ImportProc.running; onClicked: { root.profileImportError = ""; ipv4ImportProc.running = true } }
              Text {
                visible: root.profileImportError !== ""
                text: root.profileImportError
                color: root.bar.urgent
                wrapMode: Text.WordWrap
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                Accessible.role: Accessible.Alert
              }
            }

            Column {
              id: ipv4ProfileForm
              visible: root.ipv4FormOpen
              width: parent.width
              spacing: Style.space(5)

              Text {
                text: root.ipv4ProfileEditId === "" ? "NEW IPv4 SETUP" : "EDIT IPv4 SETUP"
                textFormat: Text.PlainText
                color: root.bar.foreground
                opacity: 0.68
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }
              TextField {
                width: parent.width
                Accessible.name: "Saved IPv4 setup name"
                text: root.ipv4ProfileNameDraft
                placeholderText: "Name, e.g. CPE 220 or office router"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                foreground: root.bar.foreground
                horizontalPadding: Style.spacing.controlGap
                verticalPadding: Style.spacing.controlPaddingY
                onTextChanged: if (text !== root.ipv4ProfileNameDraft) root.ipv4ProfileNameDraft = text
              }
              GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: Style.space(10)
                rowSpacing: Style.space(4)
                InfoLabel { text: "Device IPv4" }
                TextField {
                  Layout.fillWidth: true
                  Accessible.name: "CPE device IPv4 address"
                  enabled: root.cpeProfileName === "" && !cpeSetupProc.running
                  text: root.cpeDeviceIp
                  placeholderText: "192.168.0.254"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  foreground: root.bar.foreground
                  horizontalPadding: Style.spacing.controlGap
                  verticalPadding: Style.spacing.controlPaddingY
                    onTextChanged: if (text !== root.cpeDeviceIp) { root.cpeDeviceIp = text; root.cpeConflictConfirmed = false }
                }
                InfoLabel { text: "PC IPv4 / prefix" }
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(4)
                  TextField {
                    Layout.fillWidth: true
                    Accessible.name: "Temporary PC IPv4 address"
                    enabled: root.cpeProfileName === "" && !cpeSetupProc.running
                    text: root.cpeHostIp
                    placeholderText: "192.168.0.10"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    foreground: root.bar.foreground
                    horizontalPadding: Style.spacing.controlGap
                    verticalPadding: Style.spacing.controlPaddingY
                    onTextChanged: if (text !== root.cpeHostIp) { root.cpeHostIp = text; root.cpeConflictConfirmed = false }
                  }
                  TextField {
                    Layout.preferredWidth: Style.space(54)
                    Accessible.name: "Temporary PC IPv4 prefix length"
                    enabled: root.cpeProfileName === "" && !cpeSetupProc.running
                    text: root.cpePrefix
                    placeholderText: "24"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    foreground: root.bar.foreground
                    horizontalPadding: Style.spacing.controlGap
                    verticalPadding: Style.spacing.controlPaddingY
                    onTextChanged: if (text !== root.cpePrefix) { root.cpePrefix = text; root.cpeConflictConfirmed = false }
                  }
                }
              }
              Flow {
                width: parent.width
                spacing: Style.space(5)
                ActionChip {
                  actionText: root.ipv4ProfileEditId === "" ? "Save setup" : "Save changes"
                  enabled: root.cpeProfileName === "" && !cpeSetupProc.running
                  onClicked: root.saveIpv4Profile()
                }
                ActionChip {
                  actionText: "Start now"
                  enabled: !!root.selectedCpeDevice && root.selectedCpeDevice.connected && root.cpeProfileName === "" && !cpeSetupProc.running && (!root.cpeSubnetConflict(root.cpeDeviceIp, root.cpeHostIp, root.cpePrefix) || root.cpeConflictConfirmed)
                  onClicked: root.startCpeSetup()
                }
                ActionChip {
                  actionText: "Cancel"
                  onClicked: {
                    root.ipv4FormOpen = false
                    root.ipv4ProfileEditId = ""
                    root.ipv4ProfileNameDraft = ""
                  }
                }
              }
            }

            Column {
              id: primaryIpv4Card
              width: parent.width
              spacing: Style.space(4)
              HoverHandler { onHoveredChanged: root.setIpv4ProfileHovered("primary", hovered) }
              RowLayout {
                width: parent.width
                Text {
                  Layout.fillWidth: true
                  text: "1 · " + (root.primaryWiredUuid ? (root.primaryWiredName || "Primary") : "Primary · not saved")
                  textFormat: Text.PlainText
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
                ActionChip {
                  actionText: root.isIpv4ProfileExpanded("primary") ? "Hide" : "View"
                  Accessible.name: root.isIpv4ProfileExpanded("primary") ? "Hide Primary connection actions" : "View Primary connection details and actions"
                  armed: root.isIpv4ProfileExpanded("primary")
                  enabled: !root.primaryDeletedAt
                  onClicked: root.toggleIpv4Profile("primary")
                }
              }
              Column {
                visible: !root.primaryDeletedAt && root.isIpv4ProfileExpanded("primary")
                width: parent.width
                spacing: Style.space(4)
                Text {
                  width: parent.width
                  text: root.primaryConnectionSummary()
                  textFormat: Text.PlainText
                  color: root.bar.foreground
                  opacity: 0.58
                  wrapMode: Text.WordWrap
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  visible: root.primaryEditOpen
                  width: parent.width
                  text: root.primaryNameDraft
                  placeholderText: "Primary shortcut name"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  foreground: root.bar.foreground
                  onTextChanged: if (text !== root.primaryNameDraft) root.primaryNameDraft = text
                }
                Flow {
                  width: parent.width
                  spacing: Style.space(4)
                  ActionChip {
                    actionText: root.primaryEditOpen ? "Save name" : "Edit name"
                    visible: root.primaryWiredUuid !== ""
                    enabled: root.primaryWiredUuid !== ""
                    onClicked: {
                      if (root.primaryEditOpen) root.savePrimaryDisplayName()
                      else {
                        root.primaryNameDraft = root.primaryWiredName || "Primary"
                        root.primaryEditOpen = true
                      }
                    }
                  }
                  ActionChip {
                    visible: root.primaryEditOpen
                    actionText: "Cancel edit"
                    onClicked: root.primaryEditOpen = false
                  }
                  ActionChip {
                    actionText: "Save current as primary"
                    visible: root.primaryWiredUuid === ""
                    enabled: !!root.activeWiredProfile
                    onClicked: root.saveCurrentAsPrimaryWired()
                  }
                  ActionChip {
                    actionText: "Return"
                    visible: root.primaryWiredUuid !== ""
                    enabled: root.primaryWiredUuid !== "" && !root.nmProc.running
                    onClicked: root.returnToPrimaryWired()
                  }
                  ActionChip {
                    actionText: "Remove"
                    destructive: true
                    visible: root.primaryWiredUuid !== ""
                    enabled: root.primaryWiredUuid !== ""
                    onClicked: root.softDeletePrimary()
                  }
                }
              }
              Rectangle { width: parent.width; height: 1; color: root.bar.foreground; opacity: 0.1 }
            }

            Repeater {
              model: root.activeIpv4Profiles()
              delegate: Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(4)
                HoverHandler { onHoveredChanged: root.setIpv4ProfileHovered(modelData.id, hovered) }
                RowLayout {
                  width: parent.width
                  Text {
                    Layout.fillWidth: true
                    text: (index + 2) + " · " + modelData.name
                      + (modelData.id === root.defaultIpv4ProfileId ? " · DEFAULT" : "")
                    textFormat: Text.PlainText
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  ActionChip {
                    actionText: root.isIpv4ProfileExpanded(modelData.id) ? "Hide" : "View"
                    Accessible.name: root.isIpv4ProfileExpanded(modelData.id) ? "Hide " + modelData.name + " actions" : "View " + modelData.name + " details and actions"
                    armed: root.isIpv4ProfileExpanded(modelData.id)
                    onClicked: root.toggleIpv4Profile(modelData.id)
                  }
                }
                Column {
                  visible: root.isIpv4ProfileExpanded(modelData.id)
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    width: parent.width
                    text: "Device " + modelData.deviceIp + " · PC " + modelData.hostIp + "/" + modelData.prefix
                    textFormat: Text.PlainText
                    color: root.bar.foreground
                    opacity: 0.6
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Flow {
                    width: parent.width
                    spacing: Style.space(4)
                    ActionChip {
                      actionText: "Use"
                      Accessible.name: "Apply temporary IPv4 setup " + modelData.name
                      enabled: root.cpeProfileName === "" && !!root.selectedCpeDevice && root.selectedCpeDevice.connected && !cpeSetupProc.running
                      onClicked: root.useIpv4Profile(modelData)
                    }
                    ActionChip {
                      actionText: "Edit"
                      Accessible.name: "Edit IPv4 setup " + modelData.name
                      enabled: root.cpeProfileName === ""
                      onClicked: root.editIpv4Profile(modelData)
                    }
                    ActionChip {
                      actionText: modelData.id === root.defaultIpv4ProfileId ? "Default" : "Make default"
                      enabled: modelData.id !== root.defaultIpv4ProfileId
                      armed: modelData.id === root.defaultIpv4ProfileId
                      onClicked: root.setDefaultIpv4Profile(modelData)
                    }
                    ActionChip {
                      actionText: "Remove"
                      Accessible.name: "Move IPv4 setup " + modelData.name + " to recovery"
                      destructive: true
                      onClicked: root.softDeleteIpv4Profile(modelData)
                    }
                    ActionChip {
                      actionText: modelData.id === "builtin-cpe220" ? "Factory defaults" : "Duplicate"
                      Accessible.name: modelData.id === "builtin-cpe220" ? "Restore TP-Link CPE220 factory preset" : "Duplicate IPv4 profile " + modelData.name
                      onClicked: modelData.id === "builtin-cpe220" ? root.resetCpe220Preset() : root.duplicateIpv4Profile(modelData)
                    }
                  }
                }
                Rectangle { width: parent.width; height: 1; color: root.bar.foreground; opacity: 0.1 }
              }
            }

            Column {
              visible: root.showIpv4Trash
              width: parent.width
              spacing: Style.space(5)
              Text {
                text: "RECOVERY"
                textFormat: Text.PlainText
                color: root.bar.foreground
                opacity: 0.65
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }
              RowLayout {
                visible: !!root.primaryDeletedAt
                width: parent.width
                Text {
                  Layout.fillWidth: true
                  text: (root.primaryWiredName || "Primary") + " · deleted"
                  textFormat: Text.PlainText
                  color: root.bar.foreground
                  opacity: 0.65
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                ActionChip { actionText: "Restore"; onClicked: root.restorePrimary() }
              }
              Repeater {
                model: root.deletedIpv4Profiles()
                delegate: RowLayout {
                  required property var modelData
                  width: parent.width
                  Text {
                    Layout.fillWidth: true
                    text: modelData.name + " · deleted"
                    textFormat: Text.PlainText
                    color: root.bar.foreground
                    opacity: 0.65
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  ActionChip {
                    actionText: "Restore"
                    onClicked: root.restoreIpv4Profile(modelData)
                  }
                }
              }
              Text {
                visible: !root.primaryDeletedAt && root.deletedIpv4Profiles().length === 0
                width: parent.width
                text: "Recovery is empty."
                textFormat: Text.PlainText
                color: root.bar.foreground
                opacity: 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

        }
          }
        }

        Column {
          visible: root.hasCaptivePortal
          width: parent.width
          spacing: Style.space(6)

          Button {
            id: portalAction
            width: parent.width
            text: "Open Captive Portal"
            iconText: "󰏌"
            foreground: root.bar.urgent
            accent: root.bar.urgent
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.space(10)
            bordered: true
            active: true
            hasCursor: root.cursorActive && root.focusSection === "portal"
            onHovered: function(on) {
              if (!on) return
              root.cursorActive = true
              root.focusSection = "portal"
            }
            onClicked: root.openCaptivePortal()
          }

          Text {
            width: parent.width
            text: "Sign in or accept this network’s terms to access the internet."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.bar.foreground
            opacity: 0.7
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- management action feedback -----------------------------------
        // Every write the new sections perform goes through one runner, so every
        // failure has exactly one place to surface. Without this the sections
        // would fail silently -- a refused nmcli modify looks identical to a
        // click that did nothing.
        Item {
          visible: root.nmError !== "" || root.nmSuccess !== ""
          width: parent.width
          implicitHeight: nmFeedback.implicitHeight + Style.space(10)

          Item {
            id: nmFeedback
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Style.space(10)
            width: parent.width
            implicitHeight: nmFeedbackRow.implicitHeight + Style.space(6)

            // RowLayout so the message absorbs the leftover width. A Row would
            // have to be told the message's width by hand, against a parent
            // whose own width came from the message.
            RowLayout {
              id: nmFeedbackRow
              width: parent.width
              spacing: Style.space(8)

              Text {
                id: nmFeedbackText
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.nmError !== "" ? root.nmError : root.nmSuccess
                // A failure and a success are different states, not two shades
                // of the same one: the colour is the only thing that survives
                // being glanced at.
                color: root.nmError !== "" ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.3)
                wrapMode: Text.WordWrap
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                textFormat: Text.PlainText
                text: "󰅜"
                color: root.bar.foreground
                opacity: 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body

                MouseArea {
                  id: nmDismiss
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.nmError = ""
                    root.nmSuccess = ""
                  }
                }
              }
            }

            // Success is informational and self-expiring; an error is not,
            // because the user has to be able to read what went wrong.
            Timer {
              id: nmSuccessTimer
              interval: 4000
              running: root.nmSuccess !== "" && root.nmError === ""
              onTriggered: root.nmSuccess = ""
            }
          }
        }

        // Connection details: transfer metrics first, then IP/Gateway. The
        // header remains visible while the metrics and graphs are folded away.
        Column {
          visible: !!root.info.iface
          width: parent.width
          spacing: Style.space(6)

          CollapsibleHeader {
            text: "CONNECTION DETAILS"
            sectionId: "connection"
          }

          Column {
            visible: !root.isSectionCollapsed("connection")
            width: parent.width
            spacing: Style.spacing.labelGap

          GridLayout {
            width: parent.width
            columns: root.narrowLayout ? 2 : 4
            columnSpacing: Style.space(12)
            rowSpacing: Style.spacing.labelGap

            // Always mounted: these two used to appear a beat after the panel
            // opened, once the first probe returned, shoving everything below
            // them down. They now hold their place and read "--" until there is
            // a sample.
            InfoLabel { text: "Ping" }
            DetailValue {
              text: root.formatPingLatency(root.internetPingLatency)
              color: root.internetPingPacketLoss > 0 ? root.bar.urgent : root.bar.foreground
            }
            InfoLabel { text: "Packet Loss" }
            DetailValue {
              text: root.formatPacketLoss(root.internetPingPacketLoss)
              color: root.internetPingPacketLoss > 0 ? root.bar.urgent : root.bar.foreground
            }

            InfoLabel { text: "Receiving" }
            DetailValue { text: root.hasTransferStats ? root.formatRate(root.downloadRate) : "--" }
            InfoLabel { text: "Sending" }
            DetailValue { text: root.hasTransferStats ? root.formatRate(root.uploadRate) : "--" }

            InfoLabel { text: "Downloaded" }
            DetailValue { text: root.hasTransferStats ? root.formatBytes(parseFloat(root.info.rx_bytes || "0")) : "--" }
            InfoLabel { text: "Uploaded" }
            DetailValue { text: root.hasTransferStats ? root.formatBytes(parseFloat(root.info.tx_bytes || "0")) : "--" }

            InfoLabel { text: "IP Address" }
            DetailValue {
              text: root.info.ip || "--"
              copyable: !!root.info.ip
              tooltipText: "Copy IP"
            }
            InfoLabel { text: "Gateway" }
            DetailValue {
              text: root.info.gateway || "--"
              copyable: !!root.info.gateway
              tooltipText: "Copy gateway"
            }
          }

          GridLayout {
            width: parent.width
            columns: root.narrowLayout ? 2 : 4
            columnSpacing: Style.space(12)
            rowSpacing: Style.spacing.labelGap
            InfoLabel { text: "Today ↓" }
            DetailValue { text: root.formatBytes(root.dailyUsage.rx || 0) }
            InfoLabel { text: "Today ↑" }
            DetailValue { text: root.formatBytes(root.dailyUsage.tx || 0) }
            InfoLabel { text: "Session ↓" }
            DetailValue { text: root.formatBytes(root.sessionDownloaded) }
            InfoLabel { text: "Session ↑" }
            DetailValue { text: root.formatBytes(root.sessionUploaded) }
          }

          Text {
            width: parent.width
            text: "Usage totals are sampled by this shell while it is running; interface changes can leave a small gap."
            textFormat: Text.PlainText
            color: root.bar.foreground
            opacity: 0.5
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.space(6)
            ActionChip {
              actionText: "Copy connection details"
              tooltipText: "Copy interface, local address, gateway, DNS, ping, and VPN state"
              onClicked: root.copyConnectionSummary()
            }
            ActionChip {
              actionText: "Reset usage totals"
              tooltipText: "Reset today's observed totals and this shell session's totals"
              onClicked: root.resetUsage()
            }
          }

          // The sparkline is the same rate the two figures above are computed
          // from, sampled on the same tick, so the shape and the numbers cannot
          // disagree. Scaled to its own window, not to a fixed ceiling: a
          // gigabit link's idle baseline would otherwise be a flat line with
          // nothing to compare a burst against.
          Item {
            visible: root.showSparkline && root.hasTransferStats
            width: parent.width
            implicitHeight: sparkLabel.implicitHeight + Style.space(4) + throughputSpark.implicitHeight + Style.space(6) + pingGraph.implicitHeight + (root.kind === "wifi" ? Style.space(6) + signalGraph.implicitHeight : 0) + Style.space(4)
            height: implicitHeight

            Text {
              id: sparkLabel
              textFormat: Text.PlainText
              text: "Recent throughput"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              anchors.left: parent.left
              anchors.top: parent.top
            }

            Text {
              id: sparkPeak
              textFormat: Text.PlainText
              text: {
                var peak = Model.rateSeriesPeak(root.rateHistory)
                return peak > 0 ? Model.formatRate(peak) + " peak" : ""
              }
              color: root.bar.foreground
              opacity: 0.5
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.verticalCenter: sparkLabel.verticalCenter
            }

            ThroughputSpark {
              id: throughputSpark
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: sparkLabel.bottom
              anchors.topMargin: Style.space(4)
              series: root.rateHistory
              windowSize: root.rateHistoryWindow
            }

            PingHistory {
              id: pingGraph
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: throughputSpark.bottom
              anchors.topMargin: Style.space(6)
              samples: root.internetPingSamples
              windowSize: root.pingHistoryWindow
            }

            SignalHistory {
              id: signalGraph
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: pingGraph.bottom
              anchors.topMargin: Style.space(6)
              visible: root.kind === "wifi"
              samples: root.signalHistory
              windowSize: root.signalHistoryWindow
            }
          }
          }

          HoverHandler {
            onHoveredChanged: root.setSectionHovered("connection", hovered)
          }
        }

        // ---- host-level network state -------------------------------------
        // Everything here is about the machine's network as a whole rather than
        // the link it happens to be on: what the resolver is actually using,
        // whether a v6 address exists, what the outside world sees, and what the
        // firewall and tailnet are doing. Hover to peek or click to keep open.
        PanelSeparator {
          visible: root.hostSectionVisible
          foreground: root.bar.foreground
        }

        // A Column rather than an Item: the layout engine flows the header and
        // body and sizes the section for us, and it drops the body from the flow
        // entirely when collapsed. Doing this by hand meant both children sat at
        // (0,0) on top of each other.
        Column {
          id: hostSection
          visible: root.hostSectionVisible
          width: parent.width
          topPadding: Style.space(8)
          spacing: Style.space(8)

          CollapsibleHeader {
            id: hostHeader
            text: "NETWORK DETAILS"
            sectionId: "host"
          }

          Column {
            id: hostBody
            visible: !root.isSectionCollapsed("host")
            width: parent.width
            spacing: Style.space(8)

            GridLayout {
              width: parent.width
              // Two columns (label | value) so long fields like DNS servers and
              // the public address never collide with the next pair the way a
              // cramped 4-up grid did at panel width.
              columns: 2
              columnSpacing: Style.space(16)
              rowSpacing: Style.spacing.labelGap

              // Which interface the rest of this panel is describing. Shown
              // because everything above and below is scoped to it, and a machine
              // with a dock, a VPN and Wi-Fi has more than one.
              InfoLabel { text: "Primary interface" }
              DetailValue {
                text: root.info.iface || "None"
                copyable: !!root.info.iface
                tooltipText: "Copy interface name"
              }
              InfoLabel { text: "Link type" }
              DetailValue {
                text: root.info.type === "wifi" ? "Wi-Fi" : root.info.type === "ethernet" ? "Ethernet" : root.info.type || "None"
              }

              InfoLabel { text: "IPv6" }
              DetailValue {
                text: root.extras.v6 && root.extras.v6.length > 0 ? root.extras.v6[0] : "None"
                copyable: !!(root.extras.v6 && root.extras.v6.length > 0)
                tooltipText: "Copy IPv6 address"
              }
              InfoLabel { text: "DNS servers" }
              DetailValue {
                text: root.dnsSummary
                copyable: root.dnsSummary !== "--"
                tooltipText: "Copy DNS server list"
              }

              InfoLabel { text: "Public address" }
              DetailValue {
                text: root.publicIpText
                copyable: root.publicIpOk
                tooltipText: "Copy public address"
              }
              InfoLabel { text: "Firewall" }
              DetailValue { text: Model.firewallLabel(root.extras) }

              InfoLabel { text: "Tailscale" }
              DetailValue {
                text: Model.tailscaleLabel(root.extras.tailscale) || "--"
              }
              InfoLabel { text: "Tailnet peers" }
              DetailValue {
                text: root.extras.tailscale && root.extras.tailscale.installed
                  ? root.extras.tailscale.activePeers + " of " + root.extras.tailscale.tailnetPeers + " online"
                  : "--"
              }
            }

            Text {
              width: parent.width
              visible: root.publicIpError !== ""
              textFormat: Text.PlainText
              text: root.publicIpError
              color: root.bar.foreground
              opacity: 0.6
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          HoverHandler {
            onHoveredChanged: root.setSectionHovered("host", hovered)
          }
        }

        // ---- Ethernet ----------------------------------------------------
        // Shown when a wired port exists or a wired profile is stored, not only
        // when the route is currently on Ethernet: the point of managing a
        // profile is to choose it, which means looking at it while still on
        // Wi-Fi. Every field degrades to "--" when its probe could not read it,
        // so an absent fact is never shown as a zero.
        PanelSeparator {
          visible: root.ethernetSectionVisible
          foreground: root.bar.foreground
        }

        // Column, not Item: see the note on hostSection. It flows the children,
        // sizes itself, and collapses when the section is closed.
        Column {
          id: ethernetSection
          visible: root.ethernetSectionVisible
          width: parent.width
          topPadding: Style.space(8)
          spacing: Style.space(8)

          CollapsibleHeader {
            id: ethernetHeader
            text: "ETHERNET"
            sectionId: "ethernet"
          }

          Column {
            id: ethernetBody
            visible: !root.isSectionCollapsed("ethernet")
            width: parent.width
            spacing: Style.space(8)

            // No wired port at all is a different situation from a wired port
            // that is down, and the second is worth acting on.
            Text {
              width: parent.width
              visible: !root.hasWiredDevice
              textFormat: Text.PlainText
              text: "No wired network interface on this machine."
              color: root.bar.foreground
              opacity: 0.5
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            GridLayout {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(16)
              rowSpacing: Style.spacing.labelGap
              visible: root.hasWiredDevice

              InfoLabel { text: "Interface" }
              DetailValue {
                text: root.info.iface || "--"
                copyable: !!root.info.iface
                tooltipText: "Copy interface name"
              }
              InfoLabel { text: "State" }
              DetailValue {
                text: root.link.exists
                  ? (root.link.operstate === "up" ? "Up" : root.link.operstate || "Unknown")
                  : "Not found"
                color: root.link.exists && root.link.operstate === "up" ? root.bar.foreground : root.bar.urgent
              }

              InfoLabel { text: "Speed" }
              DetailValue {
                // The Quickshell API's linkSpeed is authoritative when the port is
                // up; the sysfs probe covers a port that is present but down,
                // where linkSpeed reports nothing.
                text: root.wiredLinkSpeedLabel
              }
              InfoLabel { text: "Duplex" }
              DetailValue { text: root.wiredDuplexLabel }

              InfoLabel { text: "MAC" }
              DetailValue {
                text: root.link.mac || "--"
                copyable: !!root.link.mac
                tooltipText: "Copy MAC address"
              }
              InfoLabel { text: "MTU" }
              DetailValue { text: Model.formatMtu(root.link.mtu) || "--" }

              InfoLabel { text: "Driver" }
              DetailValue { text: root.link.driver || "Unknown" }
              InfoLabel { text: "Addressing" }
              DetailValue {
                text: root.activeWiredProfile
                  ? Model.profileMethodLabel(root.activeWiredProfile.method, root.activeWiredProfile.addresses)
                  : "No profile"
              }
            }

            // The one actionable thing a link probe can tell you. Only rendered
            // when a fact actually supports the claim -- the formatter returns
            // nothing rather than guessing.
            Item {
              visible: root.linkSpeedWarningText !== ""
              width: parent.width
              implicitHeight: linkWarning.implicitHeight

              Text {
                id: linkWarning
                width: parent.width
                textFormat: Text.PlainText
                text: root.linkSpeedWarningText
                color: root.bar.urgent
                wrapMode: Text.WordWrap
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Counters. Absent counters render "--" rather than 0, because a
            // kernel that does not account an interface is not one with a clean
            // record.
            GridLayout {
              width: parent.width
              columns: root.narrowLayout ? 2 : 4
              columnSpacing: Style.space(12)
              rowSpacing: Style.spacing.labelGap
              visible: root.hasWiredDevice

              InfoLabel { text: "RX errors" }
              DetailValue {
                text: Model.formatCounter(root.link.rxErrors)
                color: root.link.rxErrors > 0 ? root.bar.urgent : root.bar.foreground
              }
              InfoLabel { text: "TX errors" }
              DetailValue {
                text: Model.formatCounter(root.link.txErrors)
                color: root.link.txErrors > 0 ? root.bar.urgent : root.bar.foreground
              }

              InfoLabel { text: "RX dropped" }
              DetailValue { text: Model.formatCounter(root.link.rxDropped) }
              InfoLabel { text: "TX dropped" }
              DetailValue { text: Model.formatCounter(root.link.txDropped) }

              InfoLabel { text: "CRC errors" }
              DetailValue {
                text: Model.formatCounter(root.link.rxCrcErrors)
                color: root.link.rxCrcErrors > 0 ? root.bar.urgent : root.bar.foreground
              }
              InfoLabel { text: "Collisions" }
              DetailValue {
                text: Model.formatCounter(root.link.collisions)
                color: root.link.collisions > 0 ? root.bar.urgent : root.bar.foreground
              }
            }

            // RowLayout, not Row: the status text has to absorb whatever width the
            // chip does not. A Row sizes itself from its children's implicit widths,
            // so asking the text to be "the rest" of it is a binding loop.
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              ActionChip {
                actionText: "Re-link"
                tooltipText: "Bounce the interface to renegotiate speed and re-run DHCP"
                enabled: root.hasWiredDevice && !relinkProc.running && !root.nmBusy
                onClicked: root.relink()
              }

              Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                textFormat: Text.PlainText
                text: root.wiredStatus
                visible: text !== ""
                elide: Text.ElideRight
                color: root.bar.foreground
                opacity: 0.7
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              width: parent.width
              visible: root.wiredProfiles.length > 0
              textFormat: Text.PlainText
              text: "WIRED PROFILES"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.wiredProfiles

              delegate: WiredProfileRow {
                required property var modelData
                width: ethernetBody.width
                profile: modelData
              }
            }



            Text {
              width: parent.width
              visible: root.hasWiredDevice && root.wiredProfiles.length === 0
              textFormat: Text.PlainText
              text: "No stored Ethernet profiles. NetworkManager will create one when a cable is connected and a network is chosen."
              color: root.bar.foreground
              opacity: 0.5
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          HoverHandler {
            onHoveredChanged: root.setSectionHovered("ethernet", hovered)
          }
        }

        // Wi-Fi band selection. Only on Wi-Fi, and only when the network answers
        // on more than one band -- a single-band AP has nothing to toggle.
        PanelSeparator {
          visible: root.canSelectBand
          foreground: root.bar.foreground
        }

        Column {
          visible: root.canSelectBand
          width: parent.width
          spacing: Style.space(10)

          // "Automatic" rides on the header line rather than under the pills: it
          // qualifies the whole row, and at header scale it reads as a modifier
          // instead of competing with the band choices for attention.
          Item {
            width: parent.width
            implicitHeight: Math.max(bandHeader.implicitHeight, bandAutoRow.implicitHeight)

            PanelSectionHeader {
              id: bandHeader
              text: root.bandSectionTitle
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              id: bandAutoRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              PanelSectionHeader {
                id: bandAutoLabel
                text: "AUTOMATIC"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              // Sized off the label rather than the theme's control height so it
              // reads as part of the header, and centred on the label's *glyphs*:
              // PanelSectionHeader carries topPadding to protect Nerd Font
              // overshoot, which pushes its text below its own box centre, so a
              // plain verticalCenter would sit the switch visibly high.
              ToggleSwitch {
                id: bandAutoSwitch
                trackHeight: Math.round(bandAutoLabel.font.pixelSize * 1.2)
                cursorPad: Style.space(3)
                anchors.verticalCenter: bandAutoLabel.verticalCenter
                anchors.verticalCenterOffset: Math.round(bandAutoLabel.topPadding / 2)
                checked: !root.bandPinned
                busy: root.bandBusy
                hasCursor: root.cursorActive && root.focusSection === "band" && root.bandAutoFocused
                foreground: root.bar.foreground
                onToggled: root.toggleBandAuto()

                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "band"
                  root.bandAutoFocused = true
                }

                PanelToolTip {
                  visible: bandAutoSwitch.containsMouse
                  text: root.bandPinned
                    ? "Let Wi-Fi pick the band"
                    : "Stay on " + root.bandLabel(root.bandCurrent)
                  fontFamily: root.bar.fontFamily
                }
              }
            }
          }

          // Collapsing container: the pills animate their height so toggling
          // Automatic slides the sections below into place instead of snapping.
          // `visible` only drops at a real zero, which keeps the row rendered for
          // the whole animation and takes it out of the Column's spacing once
          // it's actually gone.
          Item {
            id: bandPillsClip
            width: parent.width
            clip: true
            visible: height > 0
            height: root.bandPillsVisible ? bandRow.implicitHeight : 0
            opacity: root.bandPillsVisible ? 1 : 0

            Behavior on height {
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Row {
              id: bandRow
              width: parent.width
              spacing: Style.space(6)

              readonly property int count: Math.max(1, root.bandAvailable.length)
              readonly property real cellWidth: (width - spacing * (count - 1)) / count

              // Wrapper takes modelData/index from the Repeater's delegate
              // context, which doesn't bind into nested `component` declarations,
              // and passes them down explicitly -- same shape as the network
              // list delegate.
              Repeater {
                model: root.bandAvailable

                delegate: Item {
                  required property var modelData
                  required property int index
                  width: bandRow.cellWidth
                  height: bandPill.implicitHeight

                  BandPill {
                    id: bandPill
                    band: modelData
                    slot: index
                    width: parent.width
                  }
                }
              }
            }
          }

        }

        // ---- saved networks -------------------------------------------------
        // Separate from the scan list on purpose: the scan only shows what is in
        // range, so a profile for a network you are nowhere near cannot be managed
        // at all from the list above. This is the only place a stored profile can
        // be forgotten while out of range, or reordered.
        // Column, not Item: see the note on hostSection. This is also the reason the
        // section can close -- an invisible child is dropped from a layout's flow,
        // so `savedList.visible` alone collapses it without any height arithmetic.
        Column {
          id: savedSection
          visible: root.showSavedNetworks && root.wifiStationAvailable
          width: parent.width
          topPadding: Style.space(10)
          spacing: Style.space(8)

          CollapsibleHeader {
            id: savedHeader
            text: "SAVED NETWORKS · " + root.wifiProfiles.length
            sectionId: "saved"
          }

          Column {
            id: savedList
            visible: !root.isSectionCollapsed("saved")
            width: parent.width
            // More air than the scan list: each saved row carries a caption and
            // an auto-connect switch, and a tight 4px gap made adjacent rows
            // read as one block even after their heights were correct.
            spacing: Style.space(10)

            Repeater {
              model: root.wifiProfiles

              delegate: SavedNetworkRow {
                required property var modelData
                required property int index
                width: savedList.width
                profile: modelData
              }
            }

            Text {
              visible: root.wifiProfiles.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: "No saved Wi-Fi profiles."
              color: root.bar.foreground
              opacity: 0.5
              wrapMode: Text.WordWrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          HoverHandler {
            onHoveredChanged: root.setSectionHovered("saved", hovered)
          }
        }
      }
    }

    }

    }

  // One Wi-Fi band pill. `active` (fill) is the band actually in use and
  // `selected` (bold) is the pinned choice; with Automatic on nothing is
  // pinned, so only the live band lights up and the two can no longer read as
  // a contradiction. They land on the same pill once a band is pinned.
  component BandPill: Button {
    id: pill
    required property string band
    required property int slot

    text: root.bandLabel(band)
    tooltipText: root.bandTooltip(band)
    fontSize: Style.font.bodySmall
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true

    active: root.bandCurrent === band
    selected: root.bandEffective === band
    hasCursor: root.cursorActive && root.focusSection === "band"
      && !root.bandAutoFocused && root.bandIndex === slot

    onClicked: root.setBand(band)

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "band"
      root.bandIndex = pill.slot
    }
  }

  // One DNS provider pill. The cursor + current visuals come entirely from
  // CursorSurface; this component just binds them to the panel's cursor
  // state and renders the label/tooltip/click target.
  component DnsProviderPill: Button {
    id: pill
    required property string provider
    required property int index

    text: provider
    fontSize: Style.font.bodySmall
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true

    // Map the panel's domain semantics onto Button's structural props:
    // `current DNS` is the pill's `active` fill; the keyboard cursor lights
    // up `hasCursor`.
    active: root.dnsProvider === provider
    hasCursor: root.cursorActive && root.focusSection === "dns" && root.dnsIndex === index

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "dns"
      root.dnsIndex = pill.index
    }
  }

  // A single Wi-Fi network entry. Collapses to a one-line pill normally;
  // expands inline to a passphrase prompt when the user picks a network that
  // requires credentials we do not have. Clicking a connected row
  // disconnects.
  component NetworkRow: CursorSurface {
    id: row
    required property var net
    required property int index

    readonly property bool isConnected: net && net.connected
    readonly property bool isKnown: !!(net && net.known)
    readonly property bool requiresCredentials: net ? root.requiresCredentials(net.security) : false
    readonly property bool isEnterprise: net
      ? (net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap)
      : false
    readonly property bool canForget: root.canForgetNetwork(net)
    readonly property bool isSelected: root.focusSection === "wifi" && root.selectedIndex === index
    readonly property bool forgetFocused: isSelected && root.wifiActionFocused && canForget
    readonly property bool forgetVisible: canForget && (!requiresCredentials || forgetFocused || rightMouse.containsMouse)

    // Per-BSSID detail from the nmcli probe. Quickshell's WifiNetwork carries
    // only a name, a signal fraction and a security enum, so channel, width and
    // dBm are not reachable from the object the row already holds.
    readonly property var scan: Model.scanRecordForSsid(root.scanDetail, net ? net.ssid : "")
    // The detail panel reads `detail`, not `scan`. QML keeps evaluating the
    // bindings inside an invisible item -- `visible` gates painting, not
    // binding -- so a panel that hides itself on `scan === null` still throws
    // "Cannot read property 'dbm' of null" for every closed row, on every
    // re-evaluation. An empty object has the same falsy-field behaviour and
    // none of the exceptions.
    readonly property var detail: scan || ({})
    readonly property string securityText: net ? Model.securityLabel(net.security, WifiSecurityType) : ""
    readonly property bool detailOpen: !!net && root.detailSsid === net.ssid
    readonly property bool blocked: scan ? root.isBlockedBssid(scan.bssid) : false
    readonly property bool confirming: root.confirmForgetUuid !== "" && root.confirmForgetSsid === (net ? net.ssid : "")

    hasCursor: root.cursorActive && isSelected && !root.wifiActionFocused
    current: isConnected
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    // Gate on the matching *Kind/*Reason being non-empty so a hidden-SSID
    // row (ssid == "") doesn't match the "" defaults of actionSsid etc.
    readonly property bool isBusy: root.actionKind !== "" && root.actionSsid === (net ? net.ssid : "")
    readonly property bool isFailed: root.failureReason !== "" && root.failureSsid === (net ? net.ssid : "")
    readonly property bool isPasswordOpen: root.passwordSsid !== "" && root.passwordSsid === (net ? net.ssid : "")

    function submitCredentials() {
      if (!net || root.busy || root.passwordText.length === 0) return
      if (!isEnterprise) return root.connectWithPassphrase(net.ssid, root.passwordText)
      if (root.identityText.length > 0) root.connectEnterprise(net.ssid, root.identityText, root.passwordText)
    }

    function toggleDetail() {
      if (!net || !row.scan) return
      root.toggleRowDetail(net.ssid)
    }

    Connections {
      target: row.net ? root.networkForSsid(row.net.ssid) : null
      function onConnectionFailed(reason) {
        // Background auto-connect retries fire this too; only reprompt for
        // the connect started from this panel. Checked before
        // failNetworkAction, which clears the action state.
        var ours = root.actionKind === "connect" && root.actionSsid === (row.net.ssid || "")
        root.failNetworkAction(root.networkForSsid(row.net.ssid), reason)
        if (ours && root.shouldRepromptPassphrase(reason, row.requiresCredentials)) root.openPasswordPrompt(row.net.ssid)
      }
      function onConnectedChanged() {
        if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
      }
      function onKnownChanged() {
        if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
      }
      function onStateChangingChanged() {
        if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
      }
    }

    readonly property string statusText: {
      if (!net) return ""
      if (isPasswordOpen) return ""
      if (isBusy && root.actionKind === "connect") return "Connecting…"
      if (isBusy && root.actionKind === "disconnect") return "Disconnecting…"
      if (isBusy && root.actionKind === "forget") return "Forgetting…"
      if (isFailed) return root.failureReason || "Failed"
      if (isConnected && root.kind === "wifi" && root.hasCaptivePortal) return "Sign-in required"
      if (isConnected) return "Connected"
      return ""
    }

    readonly property color statusColor: {
      if (isFailed) return root.bar.urgent
      if (isBusy) return root.bar.foreground
      if (isConnected && root.kind === "wifi" && root.hasCaptivePortal) return root.bar.urgent
      if (isConnected) return root.bar.foreground
      return Qt.darker(root.bar.foreground, 1.5)
    }

    implicitHeight: rowBody.implicitHeight
      + (isPasswordOpen ? passwordPanel.implicitHeight + Style.spacing.md : 0)
      + (detailOpen ? detailPanel.implicitHeight + Style.spacing.md : 0)
      + (confirming ? forgetPanel.implicitHeight + Style.spacing.md : 0)

    MouseArea {
      id: rowMouse
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: rowBody.implicitHeight
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      enabled: !root.busy

      // Move the cursor here when the mouse enters; mouse leaving doesn't
      // clear it (so the cursor stays where the mouse last was and
      // subsequent j/k pick up from this row).
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.focusSection = "wifi"; root.selectedIndex = row.index; root.wifiActionFocused = false }

      onClicked: {
        if (!row.net) return
        // Resync cursor in case keyboard nav moved it away while the mouse
        // stayed parked on this row — the click target is unambiguously here.
        root.cursorActive = true
        root.focusSection = "wifi"
        root.selectedIndex = row.index
        root.wifiActionFocused = false
        if (row.isConnected) {
          root.disconnectRow(row.net.ssid)
          return
        }
        if (row.requiresCredentials && !row.isKnown) {
          root.openPasswordPrompt(row.net.ssid)
          return
        }
        root.connectDirectly(row.net.ssid)
      }
    }

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, rightAction.implicitHeight) + Style.spacing.rowPaddingX

      Text {
        id: networkIcon
        textFormat: Text.PlainText
        text: row.net ? Model.connectionIcon("wifi", row.net.signal,
          row.isConnected && root.kind === "wifi" ? root.connectivity : "") : ""
        color: row.statusColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      // The right edge shows a lock for networks that require credentials and
      // reveals Forget on hover. Known passwordless networks show Forget
      // directly rather than reserving an invisible or misleading target.
      Item {
        id: rightAction
        visible: row.requiresCredentials || row.canForget
        width: Style.space(22)
        implicitHeight: lockIndicator.implicitHeight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: lockIndicator
          textFormat: Text.PlainText
          visible: row.requiresCredentials || row.forgetVisible
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: row.forgetVisible ? "󰅙" : "󰌾"
          color: row.forgetVisible ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        BorderSurface {
          anchors.fill: parent
          visible: row.forgetFocused
          color: Style.hoverFillFor(root.bar.urgent, root.bar.urgent)
          borderSpec: Border.controlSpec("hover-cursor", root.bar.urgent, root.bar.urgent)
          radius: Style.cornerRadius
          z: -1
        }

        MouseArea {
          id: rightMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          enabled: row.canForget && !root.busy
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.focusSection = "wifi"; root.selectedIndex = row.index; root.wifiActionFocused = true }
          onClicked: if (row.net) root.requestForgetRow(row.net)
        }

        PanelToolTip {
          visible: rightMouse.containsMouse || row.forgetFocused
          text: "Forget network"
          fontFamily: root.bar.fontFamily
        }
      }

      Column {
        id: networkInfo
        spacing: Style.space(1)
        anchors.left: networkIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: rightAction.visible ? rightAction.left : parent.right
        anchors.rightMargin: rightAction.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: row.net ? (row.net.ssid || "Hidden") : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          textFormat: Text.PlainText
          // Signal strength is conveyed by the wifi-bars icon, so the second
          // line carries action status (Connecting…, Connected, Failed) and
          // then the protection the network actually uses. The old lock glyph
          // said only "needs a password"; WPA3, WPA2 Enterprise and OWE are
          // all different things and a user has no other way to tell them
          // apart from here. Collapses to zero height when there is nothing to
          // say, so quiet rows keep a tight one-line look.
          text: {
            var parts = []
            if (row.statusText !== "") parts.push(row.statusText)
            if (row.securityText !== "") parts.push(row.securityText)
            if (row.blocked) parts.push("Blocked")
            return parts.join(" · ")
          }
          visible: text !== ""
          color: row.statusText !== "" ? row.statusColor : Qt.darker(root.bar.foreground, 1.35)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          // Stop short of the chevron, which is the click target. `row` is the
          // network record, not a parent item, so the toggle is reached by its
          // own id -- it is a sibling of this Text inside NetworkRow.
          width: parent.width - (rowDetailToggle.visible ? rowDetailToggle.width : 0)
          elide: Text.ElideRight

          // An explicit affordance rather than making the whole status line
          // clickable: an invisible full-width target gives no hint that it
          // exists, and it would put a pointing-hand cursor over every network
          // in range.
          Text {
            id: rowDetailChevron
            // The detail panel is built from the nmcli probe, so with no scan
            // record there is nothing to expand and no chevron to offer.
            visible: row.scan !== null
            textFormat: Text.PlainText
            text: row.detailOpen ? "󰅖" : "󰅗"
            color: root.bar.foreground
            opacity: 0.55
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }

          MouseArea {
            id: rowDetailToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: rowDetailChevron.visible ? rowDetailChevron.width : 0
            height: parent.height
            visible: width > 0
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: row.toggleDetail()
          }

          PanelToolTip {
            visible: rowDetailToggle.containsMouse
            text: row.detailOpen ? "Hide network detail" : "Show channel, width and signal detail"
            fontFamily: root.bar.fontFamily
          }
        }
      }
    }

    Timer {
      id: failureTimer
      interval: 2000
      running: row.isFailed && row.isPasswordOpen
      onTriggered: {
        root.failureSsid = ""
        root.failureReason = ""
        pwField.forceActiveFocus()
      }
    }

    // Per-BSSID detail. Everything here comes from the nmcli probe, because the
    // WifiNetwork the row holds exposes none of it -- so when the probe has not
    // run yet this collapses rather than showing a panel of placeholders.
    Column {
      id: detailPanel
      visible: row.detailOpen && row.scan !== null
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowMouse.bottom
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(6)
      width: parent.width - Style.space(20)
      spacing: Style.spacing.labelGap

      GridLayout {
        width: parent.width
        columns: root.narrowLayout ? 2 : 4
        columnSpacing: Style.space(12)
        rowSpacing: Style.spacing.labelGap

        InfoLabel { text: "Signal" }
        DetailValue {
          text: row.detail.dbm
            ? row.detail.dbm + " dBm · " + Model.signalQualityLabel(row.detail.dbm)
            : (row.detail.signal >= 0 ? row.detail.signal + "%" : "--")
        }
        InfoLabel { text: "Band" }
        DetailValue { text: row.detail.band || "--" }

        InfoLabel { text: "Channel" }
        DetailValue { text: row.detail.chan || "--" }
        InfoLabel { text: "Frequency" }
        DetailValue { text: row.detail.freq || "--" }

        // Channel width is only reported by iw for 5/6 GHz links, and is
        // deliberately not inferred from the bitrate: 802.11ac puts 40 MHz and
        // 80 MHz at the same rate for one spatial stream.
        InfoLabel { text: "Width" }
        DetailValue {
          text: Model.channelWidthLabel(row.detail) || "--"
        }
        InfoLabel { text: "Link rate" }
        DetailValue {
          text: row.detail.rxBitrate
            ? Model.formatBitsPerSecond(parseFloat(row.detail.rxBitrate) * 1000000)
            : "--"
        }

        InfoLabel { text: "BSSID" }
        DetailValue {
          text: row.detail.bssid || "--"
          copyable: !!row.detail.bssid
          tooltipText: "Copy BSSID"
        }
        InfoLabel { text: "Security" }
        DetailValue { text: row.securityText || row.detail.security || "Unknown" }
      }

      Row {
        spacing: Style.space(6)

        ActionChip {
          actionText: row.blocked ? "Unblock" : "Block"
          destructive: !row.blocked
          enabled: !root.nmBusy
          tooltipText: row.blocked
            ? "Stop NetworkManager from choosing this access point"
            : "Stop NetworkManager from choosing this access point"
          onClicked: root.toggleBlocklist(row.scan ? row.scan.bssid : "")
        }

        ActionChip {
          actionText: row.detailOpen ? "Hide detail" : "Detail"
          armed: row.detailOpen
          onClicked: row.toggleDetail()
        }
      }
    }

    // Forget confirmation, in place of the row rather than over it. The
    // consequence -- the stored passphrase is deleted -- is the part that is not
    // obvious, so it is stated rather than implied by a button label.
    Column {
      id: forgetPanel
      visible: row.confirming
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: detailPanel.visible ? detailPanel.bottom : rowMouse.bottom
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(6)
      width: parent.width - Style.space(20)
      spacing: Style.space(6)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Forget " + (row.net ? row.net.ssid || "this network" : "this network") + "? The saved password is deleted."
        color: root.bar.foreground
        wrapMode: Text.WordWrap
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.space(6)

        ActionChip {
          actionText: "Forget"
          destructive: true
          armed: true
          onClicked: {
            var target = root.profileForSsid(row.net ? row.net.ssid : "")
            root.cancelForget()
            if (target) root.commitForget(target)
            else if (row.net) root.forget(row.net)
          }
        }

        ActionChip {
          actionText: "Keep"
          onClicked: root.cancelForget()
        }
      }
    }

    // Inline passphrase prompt — shown when we hit a protected network we
    // don't have saved credentials for, or when a connect fails because the
    // saved passphrase is wrong. Submitting (Enter or the check button) fires
    // connect; Esc cancels back to the row.
    Item {
      id: passwordPanel
      visible: row.isPasswordOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowMouse.bottom
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(4)
      implicitHeight: (idField.visible ? idField.implicitHeight + Style.space(4) : 0) + pwField.implicitHeight + Style.spacing.rowGap
      height: implicitHeight

      TextField {
        id: idField
        visible: row.isEnterprise && !row.isBusy && !row.isFailed
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.top: parent.top
        anchors.rightMargin: Style.space(6)
        placeholderText: "Identity (user@domain)"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !row.isBusy
        text: row.isPasswordOpen ? root.identityText : ""

        onAccepted: pwField.forceActiveFocus()
        onTextChanged: if (row.isPasswordOpen && text !== root.identityText) root.identityText = text
        Keys.onEscapePressed: root.cancelPasswordPrompt()

        onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
      }

      TextField {
        id: pwField
        visible: !row.isBusy && !row.isFailed
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.rowGap / 2
        anchors.rightMargin: Style.space(6)
        password: true
        placeholderText: "Passphrase"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !row.isBusy
        text: row.isPasswordOpen ? root.passwordText : ""

        onAccepted: row.submitCredentials()
        onTextChanged: if (row.isPasswordOpen && text !== root.passwordText) root.passwordText = text
        Keys.onEscapePressed: root.cancelPasswordPrompt()

        onVisibleChanged: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
      }

      BorderSurface {
        id: statusMsgWrapper
        visible: row.isBusy || row.isFailed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.spacing.controlHeight
        color: Style.normalFillFor(root.bar.foreground)
        borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
        radius: Style.cornerRadius

        Text {
          textFormat: Text.PlainText
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: row.isFailed ? "Wrong password" : "Connecting..."
          color: row.isFailed ? root.bar.urgent : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      // 22×22 right-anchored to line up with lockIndicator above. Esc closes
      // the prompt (handled by pwField.Keys.onEscapePressed)
      // so there's no separate cancel button.
      PanelActionButton {
        id: connectPwBtn
        visible: !row.isBusy && !row.isFailed
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: row.net && pwField.text.length > 0 && (!row.isEnterprise || idField.text.length > 0)
        iconText: "󰄬"
        tooltipText: "Connect"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: row.submitCredentials()
      }
    }
  }


  // =========================================================================
  // Components for the management sections
  //
  // These deliberately do NOT participate in the panel's j/k cursor chain. That
  // chain is a single ordered list of focusSection values with one index each,
  // and threading a dozen new row types through it would change navigation
  // behaviour that already works. These sections are mouse- and Tab-driven
  // instead, which is why none of them read cursorActive or focusSection.
  // =========================================================================

  // A full-width, keyboard-accessible section toggle. Hovering a section shows
  // it temporarily; clicking pins it open until the drawer closes.
  component CollapsibleHeader: Item {
    id: header
    required property string text
    required property string sectionId
    readonly property bool collapsed: root.isSectionCollapsed(sectionId)

    implicitHeight: Math.max(label.implicitHeight, chevron.implicitHeight) + Style.space(6)
    height: implicitHeight
    width: parent ? parent.width : implicitWidth

    PanelSectionHeader {
      id: label
      text: header.text
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: chevron
      textFormat: Text.PlainText
      text: header.collapsed ? "›" : "⌄"
      color: root.bar.foreground
      opacity: 0.55
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.right: parent.right
      anchors.rightMargin: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: headerMouse
      anchors.fill: parent
      anchors.rightMargin: Style.space(18)
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleSection(header.sectionId)
    }

    Accessible.role: Accessible.Button
    Accessible.name: (header.collapsed ? "Expand " : "Collapse ") + header.text
    Accessible.onPressAction: root.toggleSection(header.sectionId)
  }

  // A compact text button for the new management sections. Mirrors BandPill's
  // metrics so it lines up with the existing pills.
  component ActionChip: Button {
    id: chip
    required property string actionText
    property bool destructive: false
    property bool armed: false

    text: actionText
    fontSize: Style.font.bodySmall
    foreground: destructive ? root.bar.urgent : root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true
    active: armed
  }

  // A label on the left, a control on the right. Used for the per-profile
  // boolean settings (autoconnect, wake-on-LAN, cloned MAC) so a list of them
  // reads as a settings table rather than as a row of loose switches.
  //
  // Explicit `height: implicitHeight` is required: a plain Item inside a Column
  // keeps height 0 unless assigned, and without that the switch's
  // `anchors.verticalCenter` centres on a zero-tall parent while the switch
  // still paints at full size — spilling into the next saved-network row.
  // The root id is `setting`, not `row`: `NetworkRow` already owns `row`, and
  // with `pragma ComponentBehavior: Bound` the inline components below all
  // resolve their ids in the scope this file declares them in, so reusing the
  // name here collides.
  component SettingRow: Item {
    id: setting
    required property string text
    property bool checked: false
    property string busyText: ""
    // Named controlEnabled, not enabled: `Item` already has an `enabled`, and a
    // QML property of that name shadows the base one rather than driving it --
    // the C++ item machinery keeps reading the base value, so the switch would
    // stay clickable while the label dimmed.
    property bool controlEnabled: true

    // The row is stateless about the value: the caller binds `checked` to real
    // state and acts on `toggled`. That keeps the control composable with
    // profiles that get replaced wholesale by a probe refresh.
    signal toggled()

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(rowLabel.implicitHeight, rowSwitch.implicitHeight) + Style.space(6)
    height: implicitHeight

    Text {
      id: rowLabel
      textFormat: Text.PlainText
      text: setting.text
      color: root.bar.foreground
      opacity: setting.controlEnabled ? 1.0 : 0.4
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: rowSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    ToggleSwitch {
      id: rowSwitch
      Accessible.name: setting.text
      Accessible.description: setting.busyText !== "" ? setting.busyText : (checked ? "Enabled" : "Disabled")
      // Sized off the label's line height rather than the theme's control
      // height, so it reads as part of the row instead of a form field.
      trackHeight: Math.max(16, Math.round(rowLabel.font.pixelSize * 1.35))
      cursorPad: Style.space(3)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: setting.checked
      busy: setting.busyText !== ""
      enabled: setting.controlEnabled
      onToggled: setting.toggled()
    }
  }

  // A single labelled text input. `secret` masks the value, which is the only
  // difference from a plain field and the only thing a passphrase box needs
  // that a static address box does not.
  component InlineField: Item {
    id: field
    required property string label
    required property string placeholder
    property string value: ""
    property bool secret: false
    property bool wide: false
    signal committed(string text)
    signal cancelled()

    implicitHeight: caption.implicitHeight + Style.space(2) + input.implicitHeight
    width: parent ? parent.width : implicitWidth

    Text {
      id: caption
      textFormat: Text.PlainText
      text: field.label
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      anchors.left: parent.left
      anchors.top: parent.top
    }

    TextField {
      id: input
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: caption.bottom
      anchors.topMargin: Style.space(2)
      width: field.wide ? parent.width : Math.min(parent.width, Style.space(200))
      placeholderText: field.placeholder
      password: field.secret
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      foreground: root.bar.foreground
      horizontalPadding: Style.spacing.controlGap
      verticalPadding: Style.spacing.controlPaddingY
      text: field.value
      selectByMouse: true

      onTextChanged: if (text !== field.value) field.value = text
      onAccepted: field.committed(text)
      Keys.onEscapePressed: field.cancelled()
    }
  }

  // Throughput over time. The series is the same rate the numbers above it are
  // computed from, sampled once per details poll, so the shape and the figures
  // can never disagree.
  //
  // Bars are drawn as plain Rectangles rather than a Canvas: 48 of them is
  // nothing, it needs no graphics backend, and it keeps the widget legible at
  // any bar height instead of depending on a path being re-rasterised.
  component ThroughputSpark: Item {
    id: spark
    required property var series
    required property int windowSize
    readonly property real peak: Model.rateSeriesPeak(series)

    implicitHeight: Style.space(30)
    // implicitHeight alone is advisory -- it is what a layout reads to reserve
    // room, and it does not move `height`. Without this the item is 0 tall, and
    // everything below that scales against `height` (the bars, the peak line,
    // the peak label) collapses to nothing while the surrounding layout still
    // reserves the full 30px, which reads as a blank gap.
    height: implicitHeight
    width: parent ? parent.width : implicitWidth

    readonly property real slotWidth: windowSize > 0 ? width / windowSize : 0
    // A flat zero series would divide by zero; the guard also keeps a single
    // sample from rendering as a full-height bar.
    readonly property real valueScale: peak > 0 ? height / peak : 0

    // The grid line marks the series peak so a spiky history is readable
    // against its own scale rather than against an arbitrary one.
    Rectangle {
      visible: spark.peak > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: root.bar.foreground
      opacity: 0.15
    }

    Repeater {
      model: spark.series

      delegate: Item {
        id: bar
        required property var modelData
        required property int index

        // Right-anchored, so the newest sample sits at the right edge and the
        // series scrolls left as it fills -- the direction time runs.
        width: spark.slotWidth
        height: spark.height
        x: spark.width - (bar.index + 1) * spark.slotWidth

        // Download is the taller, more opaque band; upload stacks above it so
        // both are readable in the same column without a legend.
        Rectangle {
          id: downBar
          width: parent.width
          height: spark.valueScale > 0 ? Math.max(1, bar.modelData.down * spark.valueScale) : 0
          anchors.bottom: parent.bottom
          color: root.bar.foreground
          opacity: 0.75
        }

        Rectangle {
          width: parent.width
          height: spark.valueScale > 0 ? Math.max(1, bar.modelData.up * spark.valueScale) : 0
          anchors.bottom: downBar.top
          color: root.bar.foreground
          opacity: 0.35
        }
      }
    }

    // Peak label lives beside "Recent throughput" above this spark so it does
    // not paint over the bars.
  }

  // Latency history. A lost sample is a gap, not a zero: a zero would read as
  // "instant" when it means the opposite, so the sample is drawn as a full-
  // height marker in the urgent colour and the bar is omitted.
  component PingHistory: Item {
    id: graph
    required property var samples
    required property int windowSize
    readonly property real worst: {
      var max = 0
      for (var i = 0; i < samples.length; i++) {
        var value = samples[i]
        if (value === null || value === undefined) continue
        if (value > max) max = value
      }
      return max
    }

    implicitHeight: Style.space(22)
    // See ThroughputSpark: implicitHeight reserves the space, only `height`
    // gives the item any of it.
    height: implicitHeight
    width: parent ? parent.width : implicitWidth

    readonly property real slotWidth: windowSize > 0 ? width / windowSize : 0
    // 20ms floor keeps a fast link from rendering as a flat line of nothing.
    readonly property real valueScale: worst > 0 ? height / Math.max(worst, 20) : 0

    Repeater {
      model: graph.samples

      delegate: Item {
        id: slot
        required property var modelData
        required property int index

        width: graph.slotWidth
        height: graph.height
        x: graph.width - (slot.index + 1) * graph.slotWidth

        readonly property bool lost: modelData === null || modelData === undefined

        Rectangle {
          width: Math.max(1, parent.width - Style.space(1))
          height: slot.lost ? parent.height : Math.max(1, slot.modelData * graph.valueScale)
          anchors.bottom: parent.bottom
          color: slot.lost ? root.bar.urgent : root.bar.foreground
          opacity: slot.lost ? 0.45 : 0.6
        }
      }
    }
  }

  // Relative Wi-Fi signal history sampled alongside the throughput graph.
  // Null samples leave visible gaps when the link changes or signal data is
  // temporarily unavailable instead of drawing a misleading zero.
  component SignalHistory: Item {
    id: signalGraph
    required property var samples
    required property int windowSize
    implicitHeight: signalCaption.implicitHeight + Style.space(3) + Style.space(18)
    height: implicitHeight
    width: parent ? parent.width : implicitWidth
    readonly property real slotWidth: windowSize > 0 ? width / windowSize : 0
    readonly property string latestLabel: samples.length > 0 && samples[samples.length - 1] !== null
      ? Math.round(samples[samples.length - 1]) + "%" : "--"

    Text {
      id: signalCaption
      textFormat: Text.PlainText
      text: "Wi-Fi signal · " + signalGraph.latestLabel
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      anchors.left: parent.left
      anchors.top: parent.top
    }

    Item {
      id: signalBars
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(18)
      Repeater {
        model: signalGraph.samples
        delegate: Item {
          id: signalSlot
          required property var modelData
          required property int index
          width: signalGraph.slotWidth
          height: signalBars.height
          x: signalBars.width - (index + 1) * signalGraph.slotWidth
          Rectangle {
            width: Math.max(1, parent.width - Style.space(1))
            height: signalSlot.modelData === null ? 0 : Math.max(1, signalBars.height * Math.max(0, Number(signalSlot.modelData) || 0) / 100)
            anchors.bottom: parent.bottom
            color: root.bar.foreground
            opacity: signalSlot.modelData === null ? 0 : 0.65
          }
        }
      }
    }
  }

  // One stored Wi-Fi profile. Shows the settings that only exist on a profile
  // (autoconnect, priority) alongside the ones that decide whether the network
  // can be reached at all (blocked, enterprise), because a saved profile and a
  // scanned row are the same network seen from two different sides and the user
  // should not have to correlate them by eye.
  // A Column, not an Item, and that is the fix. This used to be an Item with a
  // hand-written `implicitHeight` summing its stacked sections, and the sum came
  // out smaller than what the row actually painted: it counted `savedBody` but
  // not the caption hanging off that body's bottom edge, and it ignored that the
  // action chips are taller than the body they are centred on and so overhang it.
  // `Repeater` in a `Column` stacks siblings at each one's `implicitHeight`, so a
  // row that reserved less than it painted made every row after the first overlap
  // the one above -- adjacent networks' name, caption and auto-connect switch all
  // landed in the same ~20px band and read as one line of garbage. Letting the
  // layout engine place the children and report the height it used means the
  // reserved height and the painted height cannot disagree.
  component SavedNetworkRow: Column {
    id: saved
    required property var profile

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(4)

    readonly property string label: profile.ssid || profile.name
    readonly property bool inRange: {
      // Only meaningful while a scan is available to compare against: a
      // network being out of range is the whole reason this section exists,
      // but claiming "out of range" from an empty scan would be a guess.
      for (var i = 0; i < root.scanDetail.length; i++) {
        if (root.scanDetail[i].ssid === label) return true
      }
      return false
    }
    readonly property bool isLive: profile.active !== ""
    readonly property bool confirming: root.confirmForgetUuid === profile.uuid

    // First line: name · auto-connect toggle · raise · lower · remove.
    // One horizontal row keeps the switch from claiming a second band under
    // every profile (which doubled the section height and looked like a
    // settings form rather than a list of networks).
    RowLayout {
      id: savedBody
      width: parent.width
      spacing: Style.space(6)

      Text {
        id: savedName
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        textFormat: Text.PlainText
        text: saved.label
        color: root.bar.foreground
        elide: Text.ElideRight
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }

      ToggleSwitch {
        id: savedAutoconnect
        Layout.alignment: Qt.AlignVCenter
        trackHeight: Math.max(16, Math.round(savedName.font.pixelSize * 1.35))
        cursorPad: Style.space(3)
        checked: saved.profile.autoconnect
        enabled: !root.nmBusy
        onToggled: root.toggleAutoconnect(saved.profile)

        PanelToolTip {
          visible: savedAutoconnect.containsMouse
          text: saved.profile.autoconnect ? "Auto-connect on" : "Auto-connect off"
          fontFamily: root.bar.fontFamily
        }
      }

      ActionChip {
        Layout.alignment: Qt.AlignVCenter
        actionText: "↑"
        tooltipText: "Raise auto-connect priority"
        enabled: !root.nmBusy
        onClicked: root.moveProfilePriority(saved.profile, root.priorityStep)
      }

      ActionChip {
        Layout.alignment: Qt.AlignVCenter
        actionText: "↓"
        tooltipText: "Lower auto-connect priority"
        enabled: !root.nmBusy
        onClicked: root.moveProfilePriority(saved.profile, -root.priorityStep)
      }

      ActionChip {
        Layout.alignment: Qt.AlignVCenter
        actionText: "Remove"
        destructive: true
        enabled: !root.nmBusy && !saved.isLive
        // Refuses to remove the profile that is currently up: deleting it
        // drops the connection as a side effect, which is almost never what
        // someone clicking "Remove" on the live row intends.
        tooltipText: saved.isLive ? "Disconnect before removing this profile" : "Forget this saved network"
        onClicked: root.requestForgetByUuid(saved.profile)
      }
    }

    // Second line: the facts that only a stored profile knows, and the reason a
    // network is or is not reachable.
    Text {
      id: savedMeta
      width: parent.width
      textFormat: Text.PlainText
      text: {
        var parts = []
        if (saved.isLive) parts.push("In use")
        if (saved.profile.eap) parts.push("802.1X")
        // Auto-connect is the switch on the name row — no need to repeat it.
        if (saved.profile.priority > 0) parts.push("Priority " + saved.profile.priority)
        parts.push(Model.profileMethodLabel(saved.profile.method, saved.profile.addresses))
        if (saved.profile.clonedMac) parts.push("MAC " + Model.clonedMacLabel(saved.profile.clonedMac))
        if (saved.profile.iface) parts.push("Bound to " + saved.profile.iface)
        else if (!saved.inRange && root.scanDetail.length > 0) parts.push("Out of range")
        return parts.join(" · ")
      }
      visible: text !== ""
      elide: Text.ElideRight
      color: saved.isLive ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Forget confirmation only — leaves the flow entirely when hidden so an
    // armed row grows and an unarmed one does not, with no height arithmetic.
    Column {
      id: confirm
      visible: saved.confirming
      width: parent.width
      topPadding: Style.space(4)
      spacing: Style.space(4)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: saved.inRange
          ? "This network is in range. Removing the profile deletes its saved password."
          : "Not in range. Removing the profile deletes its saved password."
        color: root.bar.foreground
        opacity: 0.7
        wrapMode: Text.WordWrap
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        spacing: Style.space(6)

        ActionChip {
          actionText: "Remove"
          destructive: true
          armed: true
          onClicked: root.commitForget(saved.profile)
        }

        ActionChip {
          actionText: "Keep"
          onClicked: root.cancelForget()
        }
      }
    }
  }

  // One stored Ethernet profile. Carries the settings a wired connection has and
  // Wi-Fi does not -- addressing method, wake-on-LAN, MAC policy, 802.1X --
  // plus the two actions that only make sense on a port: bringing it up and
  // bouncing it to force renegotiation.
  // A Column for the same reason `SavedNetworkRow` is one: the hand-written
  // `implicitHeight` this replaced never counted `wiredMeta`, the caption under
  // the name, so a wired row reserved less height than it painted and the rows
  // below it overlapped -- the same defect, on a machine with no wired port to
  // notice it on.
  component WiredProfileRow: Column {
    id: wired
    required property var profile

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(4)

    readonly property bool isLive: profile.active !== ""
    readonly property bool busy: root.wiredBusyUuid === profile.uuid
    readonly property bool editing: root.staticEditUuid === profile.uuid
    readonly property bool eapOpen: root.wiredEapUuid === profile.uuid

    Text {
      id: wiredName
      width: parent.width
      textFormat: Text.PlainText
      text: wired.profile.name
      color: root.bar.foreground
      elide: Text.ElideRight
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: wiredMeta
      width: parent.width
      textFormat: Text.PlainText
      text: {
        var parts = []
        if (wired.isLive) parts.push("In use on " + wired.profile.active)
        else if (wired.profile.iface) parts.push("Bound to " + wired.profile.iface)
        parts.push(Model.profileMethodLabel(wired.profile.method, wired.profile.addresses))
        if (wired.profile.pinnedSpeed > 0) parts.push("Pinned to " + Model.formatLinkSpeed(wired.profile.pinnedSpeed))
        // Auto-connect / WoL / MAC are the switches below — keep the caption to
        // facts the switches do not already state.
        if (wired.profile.eap) parts.push("802.1X")
        return parts.join(" · ")
      }
      visible: text !== ""
      elide: Text.ElideRight
      color: wired.isLive ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Five chips will not fit on one line of a 310px card, and a `Row` that runs
    // out of width just paints past the edge. `Flow` wraps them instead.
    Flow {
      id: wiredActions
      width: parent.width
      spacing: Style.space(6)

      ActionChip {
        actionText: wired.isLive ? "Up" : "Connect"
        armed: wired.isLive
        enabled: !wired.busy && !root.nmBusy && !wired.isLive
        onClicked: root.activateWired(wired.profile)
      }

      ActionChip {
        actionText: "Disconnect"
        enabled: wired.isLive && !wired.busy && !root.nmBusy
        onClicked: root.disconnectWired(wired.profile)
      }

      ActionChip {
        actionText: "Remove"
        destructive: true
        enabled: !wired.busy && !root.nmBusy && !wired.isLive
        onClicked: root.forgetWired(wired.profile)
      }

      ActionChip {
        actionText: wired.editing ? (root.staticCanRestore ? "Done" : "Cancel") : "Static IP"
        armed: wired.editing
        enabled: !wired.busy && !root.nmBusy
        onClicked: wired.editing ? root.cancelStaticEdit() : root.beginStaticEdit(wired.profile)
      }

      ActionChip {
        actionText: "802.1X"
        armed: wired.eapOpen
        enabled: !wired.busy && !root.nmBusy
        onClicked: wired.eapOpen ? root.cancelWiredEap() : root.openWiredEap(wired.profile)
      }
    }

    // Settings and the two editors sit below the chips with more air than the
    // caption above them gets, which a uniform `Column` spacing cannot express.
    Column {
      id: wiredTail
      width: parent.width
      topPadding: Style.space(4)
      spacing: Style.space(6)

      Column {
        id: wiredSettings
        width: parent.width
        spacing: Style.space(2)

        SettingRow {
          width: wiredSettings.width
          text: "Auto-connect"
          checked: wired.profile.autoconnect
          controlEnabled: !root.nmBusy
          onToggled: root.toggleAutoconnect(wired.profile)
        }

        SettingRow {
          width: wiredSettings.width
          text: "Wake-on-LAN"
          checked: !!wired.profile.wol
          controlEnabled: !root.nmBusy
          onToggled: root.toggleWiredWake(wired.profile)
        }

        SettingRow {
          width: wiredSettings.width
          text: "Random MAC"
          // "preserve" is NetworkManager's way of saying use the burned-in
          // address, so a preserved MAC is the off state of this switch.
          checked: !!wired.profile.clonedMac
          controlEnabled: !root.nmBusy
          onToggled: root.toggleWiredClonedMac(wired.profile)
        }
      }

      Column {
        id: staticForm
        visible: wired.editing
        width: parent.width
        spacing: Style.space(6)

        Text {
          width: parent.width
          text: "Edits the saved profile. Use Connect to apply it; Restore returns the profile to its original IPv4 settings."
          textFormat: Text.PlainText
          color: root.bar.foreground
          opacity: 0.6
          wrapMode: Text.WordWrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        GridLayout {
          width: parent.width
          columns: root.narrowLayout ? 2 : 4
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(4)

          InfoLabel { text: "Address" }
          TextField {
            Layout.fillWidth: true
            placeholderText: "192.168.1.50"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            text: root.staticAddress
            onTextChanged: if (text !== root.staticAddress) root.staticAddress = text
            selectByMouse: true
          }
          InfoLabel { text: "Prefix" }
          TextField {
            Layout.preferredWidth: Style.space(60)
            placeholderText: "24"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            text: root.staticPrefix
            onTextChanged: if (text !== root.staticPrefix) root.staticPrefix = text
            selectByMouse: true
          }

          InfoLabel { text: "Gateway" }
          TextField {
            Layout.fillWidth: true
            placeholderText: "Optional"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            text: root.staticGateway
            onTextChanged: if (text !== root.staticGateway) root.staticGateway = text
            selectByMouse: true
          }
          InfoLabel { text: "DNS" }
          TextField {
            Layout.fillWidth: true
            placeholderText: "Optional, comma separated"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            text: root.staticDns
            onTextChanged: if (text !== root.staticDns) root.staticDns = text
            selectByMouse: true
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          ActionChip {
            actionText: "Save profile"
            armed: root.staticAddress.trim() !== "" && root.staticPrefix.trim() !== ""
            enabled: root.staticAddress.trim() !== "" && root.staticPrefix.trim() !== ""
            onClicked: root.applyStatic()
          }

          // Static addressing that no longer matches the network is the single
          // most common way to strand a wired port, so returning to DHCP has to
          // be one click from the editor that caused it.
          ActionChip {
            actionText: "Use DHCP"
            visible: Model.profileIsManual(wired.profile)
            onClicked: root.useDhcp(wired.profile)
          }

          ActionChip {
            actionText: "Restore previous"
            visible: root.staticCanRestore
            enabled: !!root.staticOriginal && !root.nmBusy
            onClicked: root.restoreStaticOriginal()
          }
        }
      }
      Column {
        id: eapForm
        visible: wired.eapOpen
        width: parent.width
        spacing: Style.space(6)

        InlineField {
          width: parent.width
          label: "Identity (user@domain)"
          placeholder: "Required"
          value: root.wiredEapIdentity
          onCommitted: function(text) { root.wiredEapIdentity = text }
        }

        InlineField {
          width: parent.width
          label: "Password"
          placeholder: "Required"
          secret: true
          value: root.wiredEapSecret
          onCommitted: function(text) { root.wiredEapSecret = text }
        }

        Row {
          spacing: Style.space(6)

          ActionChip {
            actionText: "Set 802.1X"
            armed: root.wiredEapIdentity.trim() !== "" && root.wiredEapSecret !== ""
            enabled: root.wiredEapIdentity.trim() !== "" && root.wiredEapSecret !== ""
            onClicked: root.submitWiredEap()
          }

          ActionChip {
            actionText: "Cancel"
            onClicked: root.cancelWiredEap()
          }
        }
      }
    }
  }

  component DetailValue: InfoValue {
    id: value
    property bool copyable: false
    property string tooltipText: "Copy to clipboard"

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    wrapMode: Text.NoWrap

    MouseArea {
      id: valueMouse
      anchors.fill: parent
      enabled: copyable && value.text !== ""
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.copyToClipboard(value.text)
    }

    PanelToolTip {
      visible: valueMouse.enabled && valueMouse.containsMouse
      text: tooltipText
      fontFamily: root.bar.fontFamily
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: Style.space(120)
    elide: Text.ElideRight
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
