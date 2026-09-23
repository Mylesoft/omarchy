import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model
import qs.Commons
import qs.Ui

// Plugin id: omacom.usage
// Tracks time at the PC (session uptime, idle-excluded active time today,
// daily goal with ETA + streak, hourly activity chart, week comparison,
// top apps with time + share) with a countdown timer, stopwatch, and an
// in-drawer Settings tab that persists overrides to settings.json.
Panel {
  id: root

  moduleName: "omacom.usage"
  ipcTarget: "omacom.usage"

  // -------------------------------------------------------------------------
  // Settings (from shell.json: bar.widgets.<id>, overridable in the Settings tab)
  // -------------------------------------------------------------------------

  property var overrides: ({})
  readonly property string settingsPath: root.stateDir + "/settings.json"

  function effSetting(name, fallback) {
    if (root.overrides && root.overrides[name] !== undefined && root.overrides[name] !== null) return root.overrides[name]
    return root.setting(name, fallback)
  }

  function writeOverride(name, value) {
    var next = {}
    for (var k in root.overrides) next[k] = root.overrides[k]
    next[name] = value
    root.overrides = next
    root.saveSettings()
  }

  function clearOverrides() {
    root.overrides = {}
    root.saveSettings()
  }

  function saveSettings() {
    root.saveJson(root.settingsPath, JSON.stringify(root.overrides || {}))
  }

  readonly property int configuredGoalMinutes: Number(root.effSetting("goalMinutes", 240))
  readonly property int configuredCustomMinutes: Number(root.effSetting("customMinutes", 25))
  readonly property int idleThresholdSeconds: Number(root.effSetting("idleThresholdSeconds", 60))
  readonly property string configuredBarMode: String(root.effSetting("barMode", "today"))
  readonly property bool configuredTrackApps: root.effSetting("trackApps", true) !== false
  readonly property int configuredHistoryDays: Math.max(1, Math.min(30, Number(root.effSetting("historyDays", 7))))
  readonly property int configuredTopApps: Math.max(1, Math.min(15, Number(root.effSetting("topApps", 5))))

  // -------------------------------------------------------------------------
  // Session / active-time state
  // -------------------------------------------------------------------------

  property string bootId: ""
  property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/usage"
  readonly property string statsPath: root.stateDir + "/stats.json"
  readonly property string timersPath: root.stateDir + "/timers.json"

  property double sessionStart: 0
  property double pcBootEpochMs: 0
  property var daySeconds: ({})
  property string todayKey: ""
  property double todaySeconds: 0
  property double todayIdleSeconds: 0
  property int activeSessionsToday: 0
  property double longestActiveBlock: 0
  property double currentActiveBlock: 0
  property bool activeNow: true
  property double activeSinceMs: 0
  property double idleSinceMs: 0
  property double nowMs: 0
  property bool statsLoaded: false
  property bool timersLoaded: false

  property var appSeconds: ({})
  property var appDays: ({})
  property var hourSeconds: ({})
  property int lastHour: -1
  property double lastHourMs: 0
  property double hourFoldMs: 0
  property string activeAppId: ""
  property double appFoldSinceMs: 0
  property int openToplevels: 0

  readonly property double pcOnSeconds: root.pcBootEpochMs > 0
    ? Math.max(0, (root.nowMs - root.pcBootEpochMs) / 1000) : 0
  readonly property double currentIdleSeconds: root.idleSinceMs > 0
    ? Math.max(0, (root.nowMs - root.idleSinceMs) / 1000) : 0
  readonly property double idleSecondsToday: root.todayIdleSeconds
    + (root.activeNow ? 0 : root.currentIdleSeconds)
  readonly property double sessionSeconds: root.sessionStart > 0
    ? Math.max(0, (root.nowMs - root.sessionStart) / 1000) : 0
  readonly property double activeSecondsToday: root.todaySeconds
    + (root.activeNow && root.activeSinceMs > 0 ? Math.max(0, (root.nowMs - root.activeSinceMs) / 1000) : 0)
  readonly property double goalSeconds: root.configuredGoalMinutes * 60
  readonly property double goalFraction: root.goalSeconds > 0 ? Math.min(1, root.activeSecondsToday / root.goalSeconds) : 0
  readonly property var historyList: Model.history(root.daySeconds, root.todayKey, root.activeSecondsToday, root.configuredHistoryDays)
  readonly property double historyMax: {
    var m = 1
    for (var i = 0; i < root.historyList.length; i++) m = Math.max(m, root.historyList[i].seconds)
    return Math.max(1, m)
  }
  readonly property double weekSeconds: Model.weekTotal(root.historyList)
  readonly property var topAppsList: Model.topApps(root.appSeconds, root.configuredTopApps)
  readonly property double topAppsMax: Model.topAppsMax(root.topAppsList)
  readonly property double totalAppSeconds: {
    var t = 0
    for (var id in root.appSeconds) t += (Number(root.appSeconds[id]) || 0)
    return t
  }
  readonly property color statusColor: root.activeNow ? Color.accent : Qt.rgba(0.6, 0.6, 0.6, 1)
  readonly property string statusLabel: root.activeNow
    ? "ACTIVE NOW"
    : "IDLE · " + Model.longTime(root.currentIdleSeconds)

  // -------------------------------------------------------------------------
  // Analytics (derived)
  // -------------------------------------------------------------------------

  readonly property var hourList: Model.hourList(root.hourSeconds, root.nowMs)
  readonly property double hourMax: root.hourList.max
  readonly property string busiestHourLabel: {
    var h = Model.busiestHour(root.hourSeconds)
    return h >= 0 ? Model.hourLabel(h) : "--:--"
  }
  readonly property int streakCount: Model.streak(root.daySeconds, root.todayKey, root.activeSecondsToday, root.goalSeconds)
  readonly property double bestDaySeconds: Model.bestDay(root.daySeconds, root.todayKey, root.activeSecondsToday)
  readonly property double avgDaySeconds: Model.averageDay(root.daySeconds, root.todayKey, root.activeSecondsToday, root.configuredHistoryDays)
  readonly property var weekCompare: Model.weekCompare(root.daySeconds, root.todayKey, root.activeSecondsToday)
  readonly property string goalEtaText: Model.goalEta(root.activeSecondsToday, root.goalSeconds, root.nowMs)
  readonly property var topAppsWeekList: Model.topAppsAcross(root.appDays, root.appSeconds, root.todayKey, root.configuredTopApps)
  readonly property double topAppsWeekMax: Model.topAppsMax(root.topAppsWeekList)
  readonly property double totalWeekAppSeconds: {
    var t = 0
    for (var i = 0; i < root.topAppsWeekList.length; i++) t += root.topAppsWeekList[i].seconds
    return t
  }
  readonly property double focusRatio: (root.activeSecondsToday + root.todayIdleSeconds) > 0
    ? Math.round((root.activeSecondsToday / (root.activeSecondsToday + root.todayIdleSeconds)) * 100) : 0
  readonly property string goalPctText: Math.min(100, Math.round(root.goalFraction * 100)) + "%"

  // -------------------------------------------------------------------------
  // Timer state
  // -------------------------------------------------------------------------

  property string timerTab: "countdown"
  property bool countdownRunning: false
  property double countdownTotal: root.configuredCustomMinutes * 60
  property double countdownRemaining: root.countdownTotal
  property double countdownEnd: 0
  property bool swRunning: false
  property double swBase: 0
  property double swStartedAt: 0
  property var laps: []

  readonly property bool timerArmed: root.swRunning || root.swBase > 0
  readonly property double countdownSeconds: root.countdownRunning ? Math.max(0, (root.countdownEnd - root.nowMs) / 1000) : root.countdownRemaining
  readonly property double stopwatchSeconds: root.swBase + (root.swRunning && root.swStartedAt > 0 ? Math.max(0, (root.nowMs - root.swStartedAt) / 1000) : 0)
  readonly property bool timerInBar: root.countdownRunning || root.timerArmed
  readonly property color timerActiveColor: root.timerTab === "countdown"
    ? (root.countdownRunning ? Color.accent : (root.countdownRemaining > 0 ? root.barForeground : Qt.darker(root.barForeground, 1.4)))
    : (root.swRunning || root.swBase > 0 ? Color.accent : Qt.darker(root.barForeground, 1.4))
  readonly property string cdStatusText: {
    if (root.countdownRunning) return "Running · ends " + Model.clockTime(root.countdownEnd)
    if (root.countdownRemaining <= 0) return "Finished"
    if (root.countdownRemaining < root.countdownTotal) return "Paused · " + Model.timerText(root.countdownRemaining) + " of " + Model.timerText(root.countdownTotal)
    return "Set · " + Model.timerText(root.countdownTotal)
  }
  readonly property string swStatusText: root.swBase > 0
    ? (root.swRunning ? "Running" : "Paused · " + Model.longTime(root.swBase))
    : "Ready"

  // -------------------------------------------------------------------------
  // Bar button
  // -------------------------------------------------------------------------

  readonly property string barText: {
    if (root.timerInBar) {
      if (root.countdownRunning) return "󰔟 " + Model.timerText(root.countdownSeconds)
      return "󰔒 " + Model.stopwatchText(root.stopwatchSeconds)
    }
    var mode = root.configuredBarMode
    if (mode === "uptime") {
      var up = root.pcOnSeconds
      if (up >= 60) return "󰍹 " + Model.compactTime(up)
      return "󰍹 " + Math.round(up) + "s"
    }
    if (mode === "apps") {
      if (root.activeAppId) return Model.appIcon(root.activeAppId) + " " + Model.appLabel(root.activeAppId)
      return "󰂯 none"
    }
    if (mode === "open") return "󰰘 " + root.openToplevels
    if (mode === "idle") {
      var idleT = root.idleSecondsToday
      if (idleT >= 60) return "󰅶 " + Model.compactTime(idleT)
      return "󰅶 " + Math.round(idleT) + "s"
    }
    if (mode === "session") return "󰥔 " + Model.compactTime(root.sessionSeconds)
    if (mode === "timer") return "󰔟 " + Model.timerText(root.countdownTotal)
    return "󰥔 " + Model.compactTime(root.activeSecondsToday)
  }

  readonly property string barTooltip: {
    if (root.countdownRunning) return "Countdown · " + Model.longTime(root.countdownSeconds) + " left · click to open"
    if (root.timerArmed) return "Stopwatch · " + Model.longTime(root.stopwatchSeconds) + " · click to open"
    return "Usage · " + Model.longTime(root.activeSecondsToday) + " active today · " + Model.longTime(root.sessionSeconds) + " session · PC on " + Model.longTime(root.pcOnSeconds) + " · " + root.openToplevels + " app(s) open"
  }

  WidgetButton {
    id: widgetButton
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    tooltipText: root.barTooltip
    fontSize: Style.font.bodySmall
    verticalPadding: 4
    active: root.timerInBar
    activeColor: Color.accent
    onPressed: function(b) { root.toggle() }
  }

  implicitWidth: widgetButton.implicitWidth
  implicitHeight: widgetButton.implicitHeight

  // -------------------------------------------------------------------------
  // Clock ticking
  // -------------------------------------------------------------------------

  Timer {
    id: tickTimer
    interval: 250
    repeat: true
    running: true
    onTriggered: root.tick()
  }

  Timer {
    id: foldTimer
    interval: 10000
    repeat: true
    running: true
    onTriggered: {
      root.foldActive()
      root.foldIdle()
    }
  }

  Timer {
    id: appTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.trackActiveApp()
  }

  function tick() {
    var now = Date.now()
    root.nowMs = now
    if (!root.bootId || !root.statsLoaded) return
    var key = Model.dayKey(new Date())
    var hour = new Date(now).getHours()

    if (root.hourFoldMs > 0) {
      var el = Math.max(0, (now - root.hourFoldMs) / 1000)
      if (el > 0) {
        var next = {}
        for (var k in root.hourSeconds) next[k] = root.hourSeconds[k]
        next[hour] = (next[hour] || 0) + el
        root.hourSeconds = next
      }
    }
    root.lastHour = hour
    root.hourFoldMs = now

    if (key !== root.todayKey) {
      root.daySeconds = Model.pruneDays(Model.rollover(root.daySeconds, root.todayKey, Math.round(root.activeSecondsToday)), 60)
      root.appDays = Model.rolloverApps(root.appDays, root.todayKey, root.appSeconds)
      root.appSeconds = {}
      root.appDays = Model.pruneApps(root.appDays, 60)
      root.hourSeconds = {}
      root.todayKey = key
      root.todaySeconds = 0
      root.todayIdleSeconds = 0
      root.activeSessionsToday = 0
      root.longestActiveBlock = 0
      root.currentActiveBlock = 0
      root.activeSinceMs = now
      root.scheduleSave()
    }
if (root.countdownRunning && root.nowMs >= root.countdownEnd) root.finishCountdown()
  }

  // Fold the focused-app accumulation: while active, count time toward the
  // currently focused toplevel; persist per-day so top-apps survive reloads.
  function trackActiveApp() {
    if (!root.configuredTrackApps || !root.bootId || !root.statsLoaded) return
    var id = ""
    var count = 0
    try {
      var tl = ToplevelManager.activeToplevel
      if (tl) id = String(tl.appId || tl.title || "").trim()
      count = ToplevelManager.toplevels ? (Number(ToplevelManager.toplevels.count) || 0) : 0
    } catch (e) {}
    root.openToplevels = count
    var now = Date.now()
    if (root.activeAppId && root.activeAppId !== id && root.appFoldSinceMs > 0) {
      var el = Math.max(0, (now - root.appFoldSinceMs) / 1000)
      if (el > 0) {
        var next = {}
        for (var k in root.appSeconds) next[k] = root.appSeconds[k]
        next[root.activeAppId] = (next[root.activeAppId] || 0) + el
        root.appSeconds = next
      }
    }
    root.activeAppId = id
    root.appFoldSinceMs = root.activeNow ? now : 0
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  property Timer scheduler: Timer {
    interval: 250
    repeat: false
    onTriggered: root.saveEverything()
  }

  function scheduleSave() {
    root.scheduler.restart()
  }

  function saveJson(path, json) {
    var cmd = "mkdir -p " + Util.shellQuote(root.stateDir)
      + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(path) + ".tmp"
      + " && mv -f " + Util.shellQuote(path) + ".tmp " + Util.shellQuote(path)
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function saveEverything() {
    if (!root.bootId || !root.statsLoaded || !root.timersLoaded) return
    root.saveJson(root.statsPath, JSON.stringify({
      "bootId": root.bootId,
      "pcBootEpochMs": Math.round(root.pcBootEpochMs),
      "sessionStart": root.sessionStart,
      "todayKey": root.todayKey,
      "todaySeconds": root.todaySeconds,
      "days": root.daySeconds,
      "todayIdleSeconds": root.todayIdleSeconds,
      "activeSessionsToday": root.activeSessionsToday,
      "longestActiveBlock": root.longestActiveBlock,
      "appSeconds": root.appSeconds,
      "appDays": root.appDays,
      "hourSeconds": root.hourSeconds,
      "goalMinutes": root.configuredGoalMinutes,
      "customMinutes": root.configuredCustomMinutes
    }))
    root.saveJson(root.timersPath, JSON.stringify({
      "bootId": root.bootId,
      "countdown": {
        "total": root.countdownTotal,
        "remaining": root.countdownRunning ? root.countdownSeconds : root.countdownRemaining,
        "running": root.countdownRunning,
        "end": Math.round(root.countdownEnd)
      },
      "stopwatch": {
        "base": root.swBase,
        "running": root.swRunning,
        "startedAt": Math.round(root.swStartedAt || 0)
      },
      "laps": root.laps
    }))
  }

  function foldActive() {
    if (!root.bootId || !root.statsLoaded) return
    if (!root.activeNow || root.activeSinceMs <= 0) return
    var now = Date.now()
    var delta = Math.max(0, (now - root.activeSinceMs) / 1000)
    root.todaySeconds += delta
    root.currentActiveBlock += delta
    root.activeSinceMs = now
    if (delta > 0) root.scheduleSave()
  }

  // Accumulate idle time into todayIdleSeconds while idle, so it survives
  // a shell restart mid-idle.
  function foldIdle() {
    if (!root.bootId || !root.statsLoaded) return
    if (root.activeNow || root.idleSinceMs <= 0) return
    var now = Date.now()
    root.todayIdleSeconds += Math.max(0, (now - root.idleSinceMs) / 1000)
    root.idleSinceMs = now
    root.scheduleSave()
  }

  // -------------------------------------------------------------------------
  // Boot id + load
  // -------------------------------------------------------------------------

  Process {
    id: bootProcess
    command: ["bash", "-lc", "cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo none; awk '{print $1}' /proc/uptime 2>/dev/null || echo 0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).split("\n")
        var id = String(lines[0] || "").trim()
        root.bootId = (id && id.length > 0 && id !== "none") ? id : "unknown-" + Date.now()
        var up = Number(lines[1]) || 0
        root.pcBootEpochMs = up > 0 ? Date.now() - up * 1000 : 0
        root.loadStats()
        root.loadTimers()
      }
    }
  }

  Process {
    id: statsProcess
    command: ["bash", "-lc", "cat " + Util.shellQuote(root.statsPath) + " 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStats(String(text).trim())
    }
  }

  Process {
    id: timersProcess
    command: ["bash", "-lc", "cat " + Util.shellQuote(root.timersPath) + " 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyTimers(String(text).trim())
    }
  }

  Process {
    id: settingsProcess
    command: ["bash", "-lc", "cat " + Util.shellQuote(root.settingsPath) + " 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySettings(String(text).trim())
    }
  }

  function loadStats() { statsProcess.running = true }
  function loadTimers() { timersProcess.running = true }

  Component.onCompleted: {
    bootProcess.running = true
    settingsProcess.running = true
  }

  function applyStats(raw) {
    var data = {}
    try { data = raw && raw.length > 0 ? JSON.parse(raw) : {} } catch (e) {}
    var now = Date.now()
    var sameBoot = String(data.bootId || "") === root.bootId
    if (sameBoot && Number(data.sessionStart) > 0) root.sessionStart = Number(data.sessionStart)
    else root.sessionStart = now

    if (root.pcBootEpochMs <= 0 && sameBoot && Number(data.pcBootEpochMs) > 0) {
      root.pcBootEpochMs = Number(data.pcBootEpochMs)
    }

    var key = Model.dayKey(new Date())
    root.daySeconds = data.days && typeof data.days === "object" ? Model.pruneDays(data.days, 60) : {}
    root.appDays = data.appDays && typeof data.appDays === "object" ? Model.pruneApps(data.appDays, 60) : {}
    if (String(data.todayKey) === key) {
      root.todayKey = key
      root.todaySeconds = sameBoot ? (Number(data.todaySeconds) || 0) : 0
      root.todayIdleSeconds = sameBoot ? (Number(data.todayIdleSeconds) || 0) : 0
      root.activeSessionsToday = sameBoot ? (Number(data.activeSessionsToday) || 0) : 0
      root.longestActiveBlock = sameBoot ? (Number(data.longestActiveBlock) || 0) : 0
      root.appSeconds = sameBoot && data.appSeconds && typeof data.appSeconds === "object" ? data.appSeconds : {}
      root.hourSeconds = sameBoot && data.hourSeconds && typeof data.hourSeconds === "object" ? data.hourSeconds : {}
    } else {
      if (String(data.todayKey) && Number(data.todaySeconds) > 0) {
        root.daySeconds = Model.rollover(root.daySeconds, String(data.todayKey), Number(data.todaySeconds))
      }
      if (String(data.todayKey) && data.appSeconds && typeof data.appSeconds === "object") {
        root.appDays = Model.rolloverApps(root.appDays, String(data.todayKey), data.appSeconds)
      }
      root.todayKey = key
      root.todaySeconds = 0
      root.todayIdleSeconds = 0
      root.activeSessionsToday = 0
      root.longestActiveBlock = 0
      root.appSeconds = {}
      root.hourSeconds = {}
    }
    root.activeSinceMs = now
    root.activeNow = true
    root.currentActiveBlock = 0
    root.appFoldSinceMs = now
    root.statsLoaded = true
    root.scheduleSave()
  }

  function applySettings(raw) {
    var data = {}
    try { data = raw && raw.length > 0 ? JSON.parse(raw) : {} } catch (e) {}
    var o = data && typeof data === "object" ? data : {}
    root.overrides = {}
    for (var k in o) {
      if (o.hasOwnProperty(k)) root.overrides[k] = o[k]
    }
    root.saveSettings()
  }

  function applyTimers(raw) {
    var data = {}
    try { data = raw && raw.length > 0 ? JSON.parse(raw) : {} } catch (e) {}
    var now = Date.now()
    var sameBoot = String(data.bootId || "") === root.bootId
    var cd = data.countdown || {}
    var total = Number(cd.total) > 0 ? Number(cd.total) : root.configuredCustomMinutes * 60
    root.countdownTotal = total

    var expiredDown = cd.running && (Number(cd.end) <= now || !sameBoot)
    if (sameBoot && cd.running && Number(cd.end) > now) {
      root.countdownRunning = true
      root.countdownEnd = Number(cd.end)
      root.countdownRemaining = Math.max(0, (root.countdownEnd - now) / 1000)
    } else if (!cd.running && Number(cd.remaining) >= 0) {
      root.countdownRunning = false
      root.countdownRemaining = Math.min(total, Number(cd.remaining))
    } else {
      root.countdownRunning = false
      root.countdownRemaining = total
    }
    if (expiredDown) {
      if (sameBoot) root.notifyFinished("Countdown finished while the shell was away")
      root.countdownRunning = false
      root.countdownRemaining = total
    }

    var sw = data.stopwatch || {}
    root.swBase = Number(sw.base) || 0
    if (sameBoot && sw.running && Number(sw.startedAt) > 0) {
      root.swStartedAt = Number(sw.startedAt)
      root.swRunning = true
    } else {
      root.swRunning = false
    }
    root.laps = Array.isArray(data.laps) ? data.laps.slice(0, 9) : []
    root.timersLoaded = true
    root.scheduleSave()
  }

  // -------------------------------------------------------------------------
  // Idle tracking
  // -------------------------------------------------------------------------

  IdleMonitor {
    id: idleMonitor
    enabled: true
    timeout: root.idleThresholdSeconds
    respectInhibitors: true
    onIsIdleChanged: {
      var now = Date.now()
      if (idleMonitor.isIdle) {
        if (root.activeNow) {
          root.foldActive()
          if (root.currentActiveBlock > root.longestActiveBlock) root.longestActiveBlock = root.currentActiveBlock
          root.currentActiveBlock = 0
        }
        root.activeNow = false
        root.activeAppId = ""
        root.appFoldSinceMs = 0
        root.idleSinceMs = now
      } else {
        root.activeNow = true
        root.activeSessionsToday += 1
        root.activeSinceMs = now
        root.idleSinceMs = 0
        root.appFoldSinceMs = now
      }
      root.scheduleSave()
    }
  }

  // -------------------------------------------------------------------------
  // Timer logic
  // -------------------------------------------------------------------------

  function startCountdown() {
    if (root.countdownRemaining <= 0) root.countdownRemaining = root.countdownTotal
    root.countdownEnd = Date.now() + Math.max(0, root.countdownRemaining) * 1000
    root.countdownRunning = true
    root.scheduleSave()
  }

  function toggleCountdown() {
    if (root.countdownRunning) {
      root.countdownRemaining = Math.max(0, (root.countdownEnd - Date.now()) / 1000)
      root.countdownRunning = false
    } else {
      root.startCountdown()
    }
    root.scheduleSave()
  }

  function resetCountdown() {
    root.countdownRunning = false
    root.countdownRemaining = root.countdownTotal
    root.scheduleSave()
  }

  function selectPreset(minutes) {
    root.countdownTotal = Math.max(1, Math.round(minutes * 60))
    root.countdownRemaining = root.countdownTotal
    root.startCountdown()
  }

  function adjustCustom(deltaMin) {
    var custom = Math.max(1, Math.min(240, Math.round(root.configuredCustomMinutes) + deltaMin))
    root.writeOverride("customMinutes", custom)
    var total = custom * 60
    root.countdownTotal = total
    root.countdownRemaining = total
    if (root.countdownRunning) root.countdownEnd = Date.now() + total * 1000
  }

  function adjustGoal(deltaMin) {
    var goal = Math.max(15, Math.min(1440, Math.round(root.configuredGoalMinutes) + deltaMin))
    root.writeOverride("goalMinutes", goal)
  }

  function adjustIdle(deltaSec) {
    var idle = Math.max(10, Math.min(600, Math.round(root.idleThresholdSeconds) + deltaSec))
    root.writeOverride("idleThresholdSeconds", idle)
  }

  function adjustTopApps(delta) {
    var top = Math.max(1, Math.min(15, Math.round(root.configuredTopApps) + delta))
    root.writeOverride("topApps", top)
  }

  function adjustHistory(delta) {
    var days = Math.max(1, Math.min(30, Math.round(root.configuredHistoryDays) + delta))
    root.writeOverride("historyDays", days)
  }

  function cycleBarMode() {
    var modes = ["today", "session", "uptime", "apps", "open", "idle", "timer"]
    var i = modes.indexOf(root.configuredBarMode)
    var next = modes[(i + 1) % modes.length]
    root.writeOverride("barMode", next)
  }

  function finishCountdown() {
    root.countdownRunning = false
    root.countdownRemaining = 0
    root.scheduleSave()
    root.notifyFinished()
  }

  function notifyFinished(title) {
    var bin = Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-notification-send"
    Util.execArgv([bin, "--app-name", "Usage & Timer",
      "-g", "󰔟", "-u", "normal", "-t", "8000",
      title || "Time's up", Model.longTime(root.countdownTotal) + " countdown finished"])
    root.timerTab = "countdown"
  }

  function toggleStopwatch() {
    if (root.swRunning) {
      root.swBase = root.stopwatchSeconds
      root.swRunning = false
    } else {
      root.swStartedAt = Date.now()
      root.swRunning = true
    }
    root.scheduleSave()
  }

  function resetStopwatch() {
    root.swBase = 0
    root.swRunning = false
    root.laps = []
    root.scheduleSave()
  }

  function lapStopwatch() {
    var l = root.laps.slice()
    l.unshift(Math.round(root.stopwatchSeconds))
    if (l.length > 9) l.pop()
    root.laps = l
    root.scheduleSave()
  }

  // -------------------------------------------------------------------------
  // Cursor navigation (keyboard + mouse)
  // -------------------------------------------------------------------------

  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  property string focusSection: "tab"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var countdownSections: ["tab", "presets", "custom", "cdaction"]
  readonly property var stopwatchSections: ["tab", "swaction"]
  readonly property var settingsSections: ["tab", "setgoal", "setcustom", "setidle", "setbarmode", "setapps", "settop", "sethistory", "setreset"]
  readonly property var visibleSections: root.timerTab === "stopwatch" ? root.stopwatchSections
    : (root.timerTab === "settings" ? root.settingsSections : root.countdownSections)

  function sectionCount(section) {
    switch (section) {
      case "tab": return 3
      case "presets": return 5
      case "custom": return 2
      case "cdaction": return 2
      case "swaction": return 3
      case "setgoal": return 2
      case "setcustom": return 2
      case "setidle": return 2
      case "setbarmode": return 1
      case "setapps": return 1
      case "settop": return 2
      case "sethistory": return 2
      case "setreset": return 1
    }
    return 0
  }

  function sectionIsHorizontal(section) {
    return section === "tab" || section === "presets" || section === "custom"
      || section === "setgoal" || section === "setcustom" || section === "setidle"
      || section === "settop" || section === "sethistory"
  }

  function tabOfSection(section) {
    if (section === "swaction") return "stopwatch"
    if (section.indexOf("set") === 0) return "settings"
    return "countdown"
  }

  function setFocus(section, index) {
    if (section !== "tab") root.timerTab = root.tabOfSection(section)
    root.cursorActive = true
    root.focusSection = section
    root.selectedIndex = index
  }

  function revealCursor() {
    root.cursorActive = true
    if (root.visibleSections.indexOf(root.focusSection) < 0) {
      root.focusSection = "tab"
      root.selectedIndex = root.timerTab === "countdown" ? 0 : (root.timerTab === "stopwatch" ? 1 : 2)
    }
  }

  function moveCursor(dx, dy) {
    if (dx === 0 && dy === 0) return
    if (!root.cursorActive) { root.revealCursor(); return }
    var sections = root.visibleSections
    if (sections.length === 0) return

    if (dx !== 0) {
      if (!root.sectionIsHorizontal(root.focusSection)) return
      var n = root.sectionCount(root.focusSection)
      root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + (dx > 0 ? 1 : -1)))
      return
    }

    var sIdx = sections.indexOf(root.focusSection)
    if (sIdx < 0) { root.focusSection = sections[0]; root.selectedIndex = 0; return }
    var idx = root.selectedIndex
    var count = root.sectionCount(root.focusSection)

    if (dy > 0) {
      if (idx < count - 1) root.selectedIndex = idx + 1
      else if (sIdx < sections.length - 1) { root.focusSection = sections[sIdx + 1]; root.selectedIndex = 0 }
    } else {
      if (idx > 0) root.selectedIndex = idx - 1
      else if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        root.focusSection = prev
        root.selectedIndex = root.sectionCount(prev) - 1
      }
    }
  }

  function activateSection(section, index) {
    root.setFocus(section, index)
    switch (section) {
      case "tab":
        root.timerTab = index === 0 ? "countdown" : (index === 1 ? "stopwatch" : "settings")
        break
      case "presets":
        root.selectPreset([25, 15, 45, 60, 5][index])
        break
      case "custom":
        root.adjustCustom(index === 1 ? 5 : -5)
        break
      case "cdaction":
        if (index === 0) root.toggleCountdown()
        else root.resetCountdown()
        break
      case "swaction":
        if (index === 0) root.toggleStopwatch()
        else if (index === 1) root.lapStopwatch()
        else root.resetStopwatch()
        break
      case "setgoal":
        root.adjustGoal(index === 1 ? 15 : -15)
        break
      case "setcustom":
        root.adjustCustom(index === 1 ? 1 : -1)
        break
      case "setidle":
        root.adjustIdle(index === 1 ? 15 : -15)
        break
      case "setbarmode":
        root.cycleBarMode()
        break
      case "setapps":
        root.writeOverride("trackApps", !root.configuredTrackApps)
        break
      case "settop":
        root.adjustTopApps(index === 1 ? 1 : -1)
        break
      case "sethistory":
        root.adjustHistory(index === 1 ? 1 : -1)
        break
      case "setreset":
        root.clearOverrides()
        break
    }
  }

  function activateCursor() {
    if (!root.cursorActive) return
    root.activateSection(root.focusSection, root.selectedIndex)
  }

  function switchTimerTab() {
    if (root.timerTab === "settings") { root.timerTab = "countdown"; root.focusSection = "tab"; root.selectedIndex = 0; return }
    root.timerTab = root.timerTab === "countdown" ? "stopwatch" : "countdown"
    root.focusSection = "tab"
    root.selectedIndex = root.timerTab === "countdown" ? 0 : 1
  }

  onOpenedChanged: {
    if (opened) {
      root.timerTab = root.countdownRunning ? "countdown" : (root.timerArmed ? "stopwatch" : root.timerTab)
      root.focusSection = "tab"
      root.selectedIndex = root.timerTab === "countdown" ? 0 : (root.timerTab === "stopwatch" ? 1 : 2)
      root.cursorActive = false
      Qt.callLater(root.resetScroll)
    }
  }

  // -------------------------------------------------------------------------
  // Scroll safety
  // -------------------------------------------------------------------------

  function resetScroll() {
    if (!scrollArea) return
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
    if (flick && flick.contentY !== undefined && timerSection) {
      flick.contentY = Math.max(0, Math.min(
        Math.max(0, column.implicitHeight - flick.height),
        timerSection.y - Style.space(8)))
    }
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = 6
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24)) { flick.contentY = 0; return }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
  }

  // -------------------------------------------------------------------------
  // Drawer
  // -------------------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: widgetButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(dir) { root.switchPanel(dir) }
      onTextKey: function(t) {
        if (t === "t" || t === "T" || t === "s" || t === "S") root.switchTimerTab()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: column.implicitHeight > scrollArea.height
        }

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          // ---- Hero ----
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroGoalPill.implicitHeight)

            // Accent-tinted icon tile so the hero reads as the panel's anchor.
            Rectangle {
              id: heroIcon
              width: Style.space(44)
              height: Style.space(44)
              radius: Style.cornerRadius
              color: Util.alpha(Color.accent, 0.16)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Text {
                textFormat: Text.PlainText
                text: "󰥔"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
                anchors.centerIn: parent
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: root.goalFraction > 0 ? heroGoalPill.width + Style.space(12) : 0
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: "Usage"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                width: parent.width
                elide: Text.ElideRight
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Rectangle {
                  width: Style.space(7)
                  height: Style.space(7)
                  radius: width / 2
                  color: root.statusColor
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.statusLabel
                  color: root.statusColor
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  elide: Text.ElideRight
                  width: parent.width - Style.space(15)
                }
              }
            }

            // Goal percentage pill pinned to the trailing edge
            BorderSurface {
              id: heroGoalPill
              visible: root.goalSeconds > 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: heroGoalText.implicitWidth + Style.space(12)
              implicitHeight: heroGoalText.implicitHeight + Style.space(4)
              radius: Style.cornerRadius
              color: "transparent"
              borderSpec: Border.controlSpec("normal", root.barForeground, Color.accent)

              Text {
                id: heroGoalText
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.goalPctText
                color: root.goalFraction >= 1 ? Color.accent : Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }

          // ---- Stat tiles (2 rows of cards) ----
          Row {
            width: parent.width
            spacing: Style.space(10)

            StatCard {
              label: "TODAY ACTIVE"
              value: Model.longTime(root.activeSecondsToday)
              valueColor: Color.accent
              width: (parent.width - Style.space(30)) / 4
            }

            StatCard {
              label: "SESSION"
              value: Model.longTime(root.sessionSeconds)
              width: (parent.width - Style.space(30)) / 4
            }

            StatCard {
              label: "PC ON"
              value: Model.longTime(root.pcOnSeconds)
              width: (parent.width - Style.space(30)) / 4
            }

            StatCard {
              label: "IDLE TODAY"
              value: Model.longTime(root.idleSecondsToday)
              width: (parent.width - Style.space(30)) / 4
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            StatCard {
              label: "SESSIONS"
              value: String(root.activeSessionsToday)
              width: (parent.width - Style.space(30)) / 4
            }

            StatCard {
              label: "LONGEST"
              value: Model.longTime(root.longestActiveBlock)
              width: (parent.width - Style.space(30)) / 4
            }

            StatCard {
              label: "OPEN APPS"
              value: String(root.openToplevels)
              width: (parent.width - Style.space(30)) / 4
            }

            StatCard {
              label: "DISTINCT"
              value: String(Object.keys(root.appSeconds).length)
              width: (parent.width - Style.space(30)) / 4
            }
          }

          // ---- Goal progress ----
          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(goalHeaderLeft.implicitHeight, goalHeaderRight.implicitHeight)

              PanelSectionHeader {
                id: goalHeaderLeft
                text: "DAY GOAL"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: goalHeaderRight
                textFormat: Text.PlainText
                text: Math.round(root.activeSecondsToday / 60) + " / " + root.configuredGoalMinutes + " min"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Rectangle {
              width: parent.width
              height: Math.max(Style.space(5), Style.spacing.md)
              radius: Style.cornerRadius
              color: Util.alpha(root.barForeground, 0.12)

              Rectangle {
                width: parent.width * root.goalFraction
                height: parent.height
                radius: Style.cornerRadius
                color: root.goalFraction >= 1 ? Color.accent : Qt.darker(Color.accent, 1.2)
                Behavior on width { NumberAnimation { duration: 250 } }
              }
            }
          }

          // ---- 7-day history ----
          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(weekHeaderLeft.implicitHeight, weekHeaderRight.implicitHeight)

              PanelSectionHeader {
                id: weekHeaderLeft
                text: "WEEKLY ACTIVITY"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: weekHeaderRight
                textFormat: Text.PlainText
                text: Model.longTime(root.weekSeconds)
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.historyList

                DayBar {
                  required property var modelData
                  required property int index
                  width: (parent.width - Style.space((root.historyList.length - 1) * 6)) / root.historyList.length
                  seconds: modelData.seconds
                  maxSeconds: root.historyMax
                  label: modelData.label
                  isToday: index === root.historyList.length - 1
                }
              }
            }
          }

          // ---- Activity by hour ----
          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(hourHeaderLeft.implicitHeight, hourHeaderRight.implicitHeight)

              PanelSectionHeader {
                id: hourHeaderLeft
                text: "TODAY BY HOUR"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: hourHeaderRight
                textFormat: Text.PlainText
                text: "Busiest " + root.busiestHourLabel
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              width: parent.width
              spacing: Math.max(2, Style.space(2))

              Repeater {
                model: root.hourList.entries

                HourBar {
                  required property var modelData
                  required property int index
                  width: (parent.width - Style.space(Math.max(0, root.hourList.entries.length - 1) * 2)) / Math.max(1, root.hourList.entries.length)
                  seconds: modelData.seconds
                  maxSeconds: root.hourMax
                  label: modelData.label
                  isNow: modelData.isNow
                }
              }
            }
          }

          // ---- Insights ----
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(insightsHeader.implicitHeight, insightsSub.implicitHeight)

              PanelSectionHeader {
                id: insightsHeader
                text: "INSIGHTS"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: insightsSub
                textFormat: Text.PlainText
                text: {
                  var w = root.weekCompare
                  var pct = w.deltaPct
                  var dir = ""
                  if (w.thisWeek > 0 && w.lastWeek > 0) dir = (pct >= 0 ? "▲ +" : "▼ ") + Math.abs(pct) + "% vs last week"
                  else if (w.thisWeek > 0) dir = "new week"
                  return "This wk " + Model.compactTime(w.thisWeek) + "  ·  " + dir
                }
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              StatCard {
                label: "STREAK"
                value: root.streakCount > 0 ? root.streakCount + " days" : "—"
                valueColor: root.streakCount > 0 ? Color.accent : root.barForeground
                width: (parent.width - Style.space(30)) / 4
              }

              StatCard {
                label: "BEST DAY"
                value: Model.longTime(root.bestDaySeconds)
                width: (parent.width - Style.space(30)) / 4
              }

              StatCard {
                label: "AVERAGE"
                value: Model.longTime(root.avgDaySeconds)
                width: (parent.width - Style.space(30)) / 4
              }

              StatCard {
                label: "FOCUS"
                value: root.focusRatio + "%"
                width: (parent.width - Style.space(30)) / 4
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "Goal " + Math.min(100, Math.round(root.goalFraction * 100)) + "%"
                color: root.goalFraction >= 1 ? Color.accent : root.barForeground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: {
                  if (root.goalEtaText === "") return ""
                  if (root.goalEtaText === "done") return "·  Goal reached"
                  return "·  Next " + Math.max(0, Math.round((root.goalSeconds - root.activeSecondsToday) / 60)) + " min on pace · ETA " + root.goalEtaText
                }
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width - Style.space(120)
              }
            }
          }

          // ---- Top apps ----
          Column {
            visible: root.configuredTrackApps && root.topAppsList.length > 0
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(topAppsHeaderLeft.implicitHeight, topAppsHeaderRight.implicitHeight)

              PanelSectionHeader {
                id: topAppsHeaderLeft
                text: "TOP APPS TODAY"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: topAppsHeaderRight
                textFormat: Text.PlainText
                text: Model.longTime(root.totalAppSeconds)
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Repeater {
              model: root.topAppsList

              AppBar {
                required property var modelData
                required property int index
                width: parent.width
                icon: modelData.icon
                label: modelData.label
                seconds: modelData.seconds
                maxSeconds: root.topAppsMax
                totalSeconds: root.totalAppSeconds
                accent: index === 0
              }
            }
          }

          // ---- Top apps this week ----
          Column {
            visible: root.configuredTrackApps && root.topAppsWeekList.length > 0
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(weekAppsHeaderLeft.implicitHeight, weekAppsHeaderRight.implicitHeight)

              PanelSectionHeader {
                id: weekAppsHeaderLeft
                text: "TOP APPS THIS WEEK"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: weekAppsHeaderRight
                textFormat: Text.PlainText
                text: String(root.topAppsWeekList.length) + " apps"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Repeater {
              model: root.topAppsWeekList

              AppBar {
                required property var modelData
                required property int index
                width: parent.width
                icon: modelData.icon
                label: modelData.label
                seconds: modelData.seconds
                maxSeconds: root.topAppsWeekMax
                totalSeconds: root.totalWeekAppSeconds
                accent: false
              }
            }
          }

          // ---- Timer ----
          PanelSeparator {
            id: timerSection
            foreground: root.bar.foreground
          }

          Item {
            width: parent.width
            height: Style.space(26)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "FOCUS TIMER"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.4
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.timerTab === "countdown"
                ? (root.countdownRunning ? "IN PROGRESS" : "COUNTDOWN")
                : root.timerTab === "stopwatch" ? "STOPWATCH" : "PREFERENCES"
              color: root.timerInBar ? Color.accent : Qt.darker(root.barForeground, 1.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.8
            }
          }

          // ---- Timer tabs (segmented control) ----
          Item {
            width: parent.width
            implicitHeight: Style.space(38)

            Row {
              width: parent.width
              spacing: Style.space(8)
              height: parent.height

              TimerTab {
                width: (parent.width - Style.space(16)) / 3
                label: "Countdown"
                active: root.timerTab === "countdown"
                section: "tab"
                rowIndex: 0
                onActivated: root.timerTab = "countdown"
              }

              TimerTab {
                width: (parent.width - Style.space(16)) / 3
                label: "Stopwatch"
                active: root.timerTab === "stopwatch"
                section: "tab"
                rowIndex: 1
                onActivated: root.timerTab = "stopwatch"
              }

              TimerTab {
                width: (parent.width - Style.space(16)) / 3
                label: "Settings"
                active: root.timerTab === "settings"
                section: "tab"
                rowIndex: 2
                onActivated: root.timerTab = "settings"
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(132)

            BorderSurface {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: Util.alpha(Color.accent, root.timerInBar ? 0.075 : 0.035)
              borderSpec: Border.controlSpec("normal", root.barForeground, Color.accent)
            }

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(28)
              spacing: Style.space(5)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.timerTab === "countdown"
                  ? Model.timerText(root.countdownSeconds)
                  : root.timerTab === "stopwatch"
                    ? Model.stopwatchText(root.stopwatchSeconds)
                    : ""
                color: root.timerActiveColor
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }

              Rectangle {
                visible: root.timerTab !== "settings"
                width: parent.width
                height: Style.space(5)
                radius: height / 2
                color: Util.alpha(root.barForeground, 0.12)

                Rectangle {
                  width: root.timerTab === "countdown"
                    ? parent.width * (root.countdownTotal > 0
                      ? Math.min(1, root.countdownSeconds / root.countdownTotal) : 0)
                    : (root.swRunning ? parent.width : 0)
                  height: parent.height
                  radius: height / 2
                  color: root.timerActiveColor
                  Behavior on width { NumberAnimation { duration: 180 } }
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.timerTab === "countdown" ? root.cdStatusText
                  : (root.timerTab === "stopwatch" ? root.swStatusText : "")
                color: Qt.darker(root.barForeground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
                elide: Text.ElideRight
              }
            }
          }

          // ---- Countdown: presets ----
          Row {
            visible: root.timerTab === "countdown"
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: [5, 15, 25, 45, 60]

              PresetChip {
                required property int modelData
                required property int index
                width: (parent.width - Style.space(32)) / 5
                label: modelData
                section: "presets"
                rowIndex: index
                onActivated: root.selectPreset(modelData)
              }
            }
          }

          // ---- Countdown: custom duration ----
          Row {
            visible: root.timerTab === "countdown"
            width: parent.width
            spacing: Style.space(8)

            PresetChip {
              section: "custom"
              rowIndex: 0
              width: (parent.width - Style.space(16 + 80 + 16)) / 2
              label: "−"
              labelFontSize: Style.font.subtitle
              onActivated: root.adjustCustom(-5)
            }

            Text {
              width: Style.space(80)
              text: root.configuredCustomMinutes + " min"
              color: root.barForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
            }

            PresetChip {
              section: "custom"
              rowIndex: 1
              width: (parent.width - Style.space(16 + 80 + 16)) / 2
              label: "+"
              labelFontSize: Style.font.subtitle
              onActivated: root.adjustCustom(5)
            }
          }

          // ---- Countdown actions ----
          Row {
            visible: root.timerTab === "countdown"
            width: parent.width
            spacing: Style.space(8)

            ActionButton {
              section: "cdaction"
              rowIndex: 0
              width: (parent.width - Style.space(8)) * 0.68
              label: root.countdownRunning ? "Pause" : "Start countdown"
              primary: true
              onActivated: root.toggleCountdown()
            }

            ActionButton {
              section: "cdaction"
              rowIndex: 1
              width: (parent.width - Style.space(8)) * 0.32
              label: "Reset"
              onActivated: root.resetCountdown()
            }
          }

          // ---- Stopwatch actions ----
          Row {
            visible: root.timerTab === "stopwatch"
            width: parent.width
            spacing: Style.space(8)

            ActionButton {
              section: "swaction"
              rowIndex: 0
              width: (parent.width - Style.space(16)) / 3
              label: root.swRunning ? "Pause" : "Start"
              primary: true
              onActivated: root.toggleStopwatch()
            }

            ActionButton {
              section: "swaction"
              rowIndex: 1
              width: (parent.width - Style.space(16)) / 3
              label: "Lap"
              onActivated: root.lapStopwatch()
            }

            ActionButton {
              section: "swaction"
              rowIndex: 2
              width: (parent.width - Style.space(16)) / 3
              label: "Reset"
              onActivated: root.resetStopwatch()
            }
          }

          // ---- Stopwatch laps ----
          Column {
            visible: root.timerTab === "stopwatch" && root.laps.length > 0
            width: parent.width
            spacing: Style.space(3)

            Text {
              text: "LAPS"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }

            Repeater {
              model: root.laps.slice(0, 4)

              Row {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: (index + 1) + "."
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(24)
                }

                Text {
                  text: Model.stopwatchText(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // ---- Settings tab ----
          Column {
            visible: root.timerTab === "settings"
            width: parent.width
            spacing: Style.space(12)

            SettingStepper {
              section: "setgoal"
              label: "Daily goal"
              valueText: root.configuredGoalMinutes + " min"
              detailText: Math.round(root.activeSecondsToday / 60) + " min today"
              accent: true
              onStepDown: root.adjustGoal(-15)
              onStepUp: root.adjustGoal(15)
            }

            SettingStepper {
              section: "setcustom"
              label: "Countdown default"
              valueText: root.configuredCustomMinutes + " min"
              onStepDown: root.adjustCustom(-1)
              onStepUp: root.adjustCustom(1)
            }

            SettingStepper {
              section: "setidle"
              label: "Idle threshold"
              valueText: root.idleThresholdSeconds + "s"
              detailText: "count as idle after no input"
              onStepDown: root.adjustIdle(-15)
              onStepUp: root.adjustIdle(15)
            }

            SettingStepper {
              section: "settop"
              label: "Top apps shown"
              valueText: String(root.configuredTopApps)
              onStepDown: root.adjustTopApps(-1)
              onStepUp: root.adjustTopApps(1)
            }

            SettingStepper {
              section: "sethistory"
              label: "History length"
              valueText: root.configuredHistoryDays + " days"
              onStepDown: root.adjustHistory(-1)
              onStepUp: root.adjustHistory(1)
            }

            // Bar mode (cycle)
            SettingAction {
              section: "setbarmode"
              label: "Bar shows"
              valueText: root.configuredBarMode.toUpperCase()
              hint: "click to cycle"
              onActivated: root.cycleBarMode()
            }

            // Track apps toggle
            SettingAction {
              section: "setapps"
              label: "Track app usage"
              valueText: root.configuredTrackApps ? "ON" : "OFF"
              hint: root.configuredTrackApps ? "click to disable" : "click to enable"
              accent: root.configuredTrackApps
              onActivated: root.writeOverride("trackApps", !root.configuredTrackApps)
            }

            // Reset to shell.json defaults
            SettingAction {
              section: "setreset"
              label: "Reset to defaults"
              valueText: "restore shell.json values"
              hint: ""
              dangerous: true
              onActivated: root.clearOverrides()
            }
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Inline components
  // -------------------------------------------------------------------------

  component FocusSurface: CursorSurface {
    id: focusSurface
    required property string section
    required property int rowIndex
    signal activated()

    readonly property bool activeCursor: root.cursorActive && root.focusSection === section && root.selectedIndex === rowIndex
    hasCursor: activeCursor
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(focusSurface)
    foreground: root.bar.foreground
    accent: Color.accent
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitWidth: Style.space(64)
    implicitHeight: Style.space(28)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.setFocus(focusSurface.section, focusSurface.rowIndex)
      onClicked: focusSurface.activated()
    }
  }

  component StatCard: Item {
    id: statCard
    required property string label
    required property string value
    property color valueColor: root.barForeground
    implicitHeight: Math.max(Style.space(44), cardColumn.implicitHeight + Style.space(12))

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Style.normalFillFor(root.barForeground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.barForeground, Color.accent)
    }

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        text: statCard.label
        color: Qt.darker(root.barForeground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.0
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: statCard.value
        color: statCard.valueColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }

  component DayBar: Item {
    id: dayBar
    required property double seconds
    required property double maxSeconds
    required property string label
    required property bool isToday
    implicitHeight: dayColumn.implicitHeight

    Column {
      id: dayColumn
      anchors.fill: parent
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: dayBar.seconds >= 60 ? Model.compactTime(dayBar.seconds) : ""
        color: dayBar.isToday ? Color.accent : Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        width: parent.width
      }

      Rectangle {
        width: parent.width
        height: Style.space(52)
        radius: Style.cornerRadius
        color: Util.alpha(root.bar.foreground, 0.08)

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(Style.space(3), (parent.height - Style.space(3)) * (dayBar.seconds / dayBar.maxSeconds))
          color: dayBar.isToday ? Color.accent : Util.alpha(root.bar.foreground, 0.45)
          radius: Style.cornerRadius
          Behavior on height { NumberAnimation { duration: 200 } }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: dayBar.label
        color: dayBar.isToday ? Color.accent : Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: dayBar.isToday
        horizontalAlignment: Text.AlignHCenter
        width: parent.width
      }
    }
  }

  component HourBar: Item {
    id: hourBar
    required property double seconds
    required property double maxSeconds
    required property string label
    required property bool isNow
    implicitHeight: hourColumn.implicitHeight

    Column {
      id: hourColumn
      anchors.fill: parent
      spacing: Style.space(4)

      Rectangle {
        width: parent.width
        height: Style.space(44)
        radius: Style.cornerRadius
        color: Util.alpha(root.bar.foreground, 0.08)

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(Style.space(2), (parent.height - Style.space(2)) * (hourBar.seconds / hourBar.maxSeconds))
          color: hourBar.isNow ? Color.accent : Util.alpha(root.bar.foreground, 0.45)
          radius: Style.cornerRadius
          Behavior on height { NumberAnimation { duration: 200 } }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: hourBar.label
        color: hourBar.isNow ? Color.accent : Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        width: parent.width
      }
    }
  }

  component AppBar: Item {
    id: appBar
    required property string icon
    required property string label
    required property double seconds
    required property double maxSeconds
    required property bool accent
    property double totalSeconds: 0
    implicitHeight: appBarRow.implicitHeight + Style.space(4)

    Column {
      anchors.fill: parent
      spacing: Style.space(5)

      Row {
        id: appBarRow
        width: parent.width
        spacing: Style.space(8)

        Rectangle {
          width: Style.space(24)
          height: Style.space(24)
          radius: Style.cornerRadius
          color: appBar.accent ? Util.alpha(Color.accent, 0.16) : Util.alpha(root.bar.foreground, 0.08)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: appBar.icon
            color: appBar.accent ? Color.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          textFormat: Text.PlainText
          text: appBar.label
          color: appBar.accent ? Color.accent : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: appBar.accent
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(24 + 8 + 64 + 8 + 52)
        }

        Text {
          textFormat: Text.PlainText
          text: appBar.totalSeconds > 0
            ? Math.round((appBar.seconds / appBar.totalSeconds) * 100) + "%"
            : ""
          color: appBar.accent ? Color.accent : Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(64)
          horizontalAlignment: Text.AlignRight
        }

        Text {
          textFormat: Text.PlainText
          text: Model.longTime(appBar.seconds)
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(52)
          horizontalAlignment: Text.AlignRight
        }
      }

      Rectangle {
        width: parent.width
        height: Math.max(Style.space(3), Style.spacing.xs)
        radius: Style.cornerRadius
        color: Util.alpha(root.bar.foreground, 0.12)

        Rectangle {
          width: parent.width * Math.min(1, appBar.seconds / Math.max(1, appBar.maxSeconds))
          height: parent.height
          radius: Style.cornerRadius
          color: appBar.accent ? Color.accent : Util.alpha(root.bar.foreground, 0.5)
          Behavior on width { NumberAnimation { duration: 200 } }
        }
      }
    }
  }

  component TimerTab: FocusSurface {
    id: timerTab
    required property string label
    required property bool active
    implicitWidth: Style.space(64)
    implicitHeight: Style.space(32)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      visible: timerTab.active && !timerTab.hasCursor
      color: Util.alpha(Color.accent, 0.16)
      border.color: Util.alpha(Color.accent, 0.55)
      border.width: 1
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: timerTab.label
      color: timerTab.active ? Color.accent : Qt.darker(root.barForeground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: timerTab.active
    }
  }

  component PresetChip: FocusSurface {
    id: presetChip
    required property var label
    property real labelFontSize: Style.font.bodySmall
    implicitWidth: Style.space(48)
    implicitHeight: Style.space(32)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      visible: !presetChip.hasCursor
      color: "transparent"
      border.color: Util.alpha(root.barForeground, 0.25)
      border.width: 1
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: String(presetChip.label)
      color: Qt.darker(root.barForeground, 1.2)
      font.family: root.bar.fontFamily
      font.pixelSize: presetChip.labelFontSize
      font.bold: true
    }
  }

  component ActionButton: FocusSurface {
    id: actionButton
    required property string label
    property bool primary: false
    implicitWidth: Style.space(120)
    implicitHeight: Style.space(34)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      visible: !actionButton.hasCursor
      color: actionButton.primary ? Util.alpha(Color.accent, 0.18) : "transparent"
      border.color: actionButton.primary ? Color.accent : Util.alpha(root.barForeground, 0.25)
      border.width: 1
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: actionButton.label
      color: actionButton.primary ? Color.accent : Qt.darker(root.barForeground, 1.2)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  component SettingStepper: Item {
    id: settingStepper
    required property string section
    required property string label
    required property string valueText
    property string detailText: ""
    property bool accent: false
    signal stepDown()
    signal stepUp()
    width: parent ? parent.width : Style.space(200)
    implicitHeight: Style.space(46)

    Row {
      anchors.fill: parent
      spacing: Style.space(10)

      Column {
        width: parent.width - Style.space(34 * 2 + 20)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: settingStepper.label
          color: Qt.darker(root.barForeground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.0
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: settingStepper.detailText !== ""
            ? settingStepper.valueText + "  ·  " + settingStepper.detailText
            : settingStepper.valueText
          color: settingStepper.accent ? Color.accent : root.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: settingStepper.accent
          elide: Text.ElideRight
        }
      }

      FocusSurface {
        id: settingStepperDown
        section: settingStepper.section
        rowIndex: 0
        width: Style.space(34)
        implicitWidth: Style.space(34)
        implicitHeight: Style.space(32)
        anchors.verticalCenter: parent.verticalCenter
        onActivated: settingStepper.stepDown()
        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          visible: !settingStepperDown.hasCursor
          color: "transparent"
          border.color: Util.alpha(root.barForeground, 0.25)
          border.width: 1
        }
        Text {
          anchors.centerIn: parent
          text: "−"
          color: root.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
        }
      }

      FocusSurface {
        id: settingStepperUp
        section: settingStepper.section
        rowIndex: 1
        width: Style.space(34)
        implicitWidth: Style.space(34)
        implicitHeight: Style.space(32)
        anchors.verticalCenter: parent.verticalCenter
        onActivated: settingStepper.stepUp()
        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          visible: !settingStepperUp.hasCursor
          color: "transparent"
          border.color: Util.alpha(root.barForeground, 0.25)
          border.width: 1
        }
        Text {
          anchors.centerIn: parent
          text: "+"
          color: root.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
        }
      }
    }
  }

  component SettingAction: Item {
    id: settingAction
    required property string section
    required property string label
    required property string valueText
    property string hint: ""
    property bool accent: false
    property bool dangerous: false
    signal activated()
    width: parent ? parent.width : Style.space(200)
    implicitHeight: Style.space(38)

    FocusSurface {
      id: settingActionSurface
      anchors.fill: parent
      section: settingAction.section
      rowIndex: 0
      onActivated: settingAction.activated()

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)

        Text {
          width: Style.space(120)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: settingAction.label
          color: Qt.darker(root.barForeground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.0
          elide: Text.ElideRight
        }

        Column {
          width: parent.width - Style.space(120 + 8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: settingAction.valueText
            color: settingAction.dangerous
              ? Qt.darker(root.barForeground, 1.6)
              : (settingAction.accent ? Color.accent : root.barForeground)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: settingAction.hint !== ""
            textFormat: Text.PlainText
            text: settingAction.hint
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}