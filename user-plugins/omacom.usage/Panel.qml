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
  property string reviewPage: ""
  property int appListRefresh: 0
  property var manualRecords: []
  property var focusLog: []
  property string reviewSearch: ""
  property string aliasDraft: ""
  property var undoRecord: null
  property double focusStartedAt: 0
  property var focusAppSnapshot: ({})
  property string backupPathDraft: ""
  property bool restoreArmed: false
  property bool settingsEditorActive: false
  property string goalDraft: ""
  property string timelineDraftStart: ""
  property string timelineDraftEnd: ""
  property int timelineDraftIndex: -1
  property bool timelineDraftActive: true
  property bool timelineEditorActive: false
  property string recordEditorKind: ""
  property string recordEditingId: ""
  property string recordDraftName: ""
  property string recordDraftAlias: ""
  property string recordDraftStartTime: ""
  property string recordDraftDay: ""
  property string recordDraftMinutes: ""
  property string recordDraftActivity: "active"
  property bool recordEditorActive: false
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
    if (name === "breakReminderMinutes" && root.statsLoaded)
      root.lastBreakReminderBucket = Math.floor(root.todaySeconds / (root.breakReminderMinutes * 60))
  }

  function clearOverrides() {
    root.overrides = {}
    root.saveSettings()
  }

  function saveSettings() {
    root.saveJson(root.settingsPath, JSON.stringify(root.overrides || {}))
  }

  function selectHistoryRange(days) {
    var value = [7, 14, 30].indexOf(Number(days)) >= 0 ? Number(days) : 7
    root.writeOverride("historyRange", value)
  }

  function categoryForApp(appId) {
    return String(root.appCategoryOverrides[appId] || Model.appCategory(appId))
  }

  function appDisplayName(appId) {
    var aliases = root.effSetting("appAliases", ({})) || ({})
    return String(aliases[appId] || Model.appLabel(appId))
  }

  function filteredUniqueApplicationRows() {
    var query = root.reviewSearch.toLowerCase().trim()
    return root.uniqueApplicationRows().filter(function(row) {
      return !query || row.appId.toLowerCase().indexOf(query) >= 0
        || root.appDisplayName(row.appId).toLowerCase().indexOf(query) >= 0
        || row.category.toLowerCase().indexOf(query) >= 0
    })
  }

  function filteredManualRecords(kind) {
    var query = root.reviewSearch.toLowerCase().trim()
    return root.manualRecordsFor(kind).filter(function(row) {
      return !query || String(row.appId || row.note || "").toLowerCase().indexOf(query) >= 0
        || row.day.indexOf(query) >= 0 || row.kind.indexOf(query) >= 0
    })
  }

  function setGoalFromDraft() {
    var parts = String(root.goalDraft || "").split("=")
    var target = String(parts[0] || "").trim().toLowerCase()
    var minutes = Number(parts[1])
    if (!target || !isFinite(minutes) || minutes < 1 || minutes > 1440) {
      root.notifyMessage("Goal format", "Enter app:app-id=minutes or category:work=minutes.")
      return
    }
    var group = target.indexOf("app:") === 0 ? "appGoals" : (target.indexOf("category:") === 0 ? "categoryGoals" : "")
    var id = target.slice(target.indexOf(":") + 1)
    if (!group || !id) { root.notifyMessage("Goal format", "Use app: or category: before the goal name."); return }
    var map = {}
    var current = root.effSetting(group, ({})) || ({})
    for (var key in current) map[key] = current[key]
    map[id] = Math.round(minutes)
    root.writeOverride(group, map)
    root.notifyMessage("Usage goal saved", id + " · " + minutes + " min per day")
  }

  function goalRows() {
    var rows = []
    for (var appId in root.appGoals) rows.push({ group: "appGoals", id: appId, label: "App · " + root.appDisplayName(appId), minutes: Number(root.appGoals[appId]) })
    for (var category in root.categoryGoals) rows.push({ group: "categoryGoals", id: category, label: "Category · " + (root.categoryLabels[category] || category), minutes: Number(root.categoryGoals[category]) })
    return rows
  }

  function removeGoal(group, id) {
    var next = {}
    var current = root.effSetting(group, ({})) || ({})
    for (var key in current) if (key !== id) next[key] = current[key]
    root.writeOverride(group, next)
  }

  function checkUsageGoals() {
    var notices = root.effSetting("goalNotices", ({})) || ({})
    var nextNotices = {}
    for (var old in notices) if (old.indexOf(root.todayKey + ":") === 0) nextNotices[old] = notices[old]
    var categoryTotals = { work: 0, communication: 0, browsing: 0, other: 0 }
    var rows = root.uniqueApplicationRows()
    for (var i = 0; i < rows.length; i++) categoryTotals[rows[i].category] += rows[i].seconds
    var changed = false
    for (var appId in root.appGoals) {
      var appSeconds = 0
      for (var a = 0; a < rows.length; a++) if (rows[a].appId === appId) appSeconds = rows[a].seconds
      var appKey = root.todayKey + ":app:" + appId
      if (appSeconds >= Number(root.appGoals[appId]) * 60 && !nextNotices[appKey]) {
        nextNotices[appKey] = true
        changed = true
        root.notifyMessage("App goal reached", root.appDisplayName(appId) + " reached its daily limit.")
      }
    }
    for (var category in root.categoryGoals) {
      var categoryKey = root.todayKey + ":category:" + category
      if ((categoryTotals[category] || 0) >= Number(root.categoryGoals[category]) * 60 && !nextNotices[categoryKey]) {
        nextNotices[categoryKey] = true
        changed = true
        root.notifyMessage("Category goal reached", root.categoryLabels[category] + " reached its daily limit.")
      }
    }
    if (changed) root.writeOverride("goalNotices", nextNotices)
  }

  function beginTimelineEdit(index) {
    var entry = root.todayTimeline[index]
    if (!entry || Number(entry.end) <= 0) return
    root.timelineDraftIndex = index
    root.timelineDraftStart = Qt.formatDateTime(new Date(Number(entry.start)), "HH:mm")
    root.timelineDraftEnd = Qt.formatDateTime(new Date(Number(entry.end)), "HH:mm")
    root.timelineDraftActive = Boolean(entry.active)
    root.timelineEditorActive = true
  }

  function saveTimelineEdit() {
    var index = root.timelineDraftIndex
    var oldRows = root.todayTimeline.slice()
    if (index < 0 || index >= oldRows.length) return
    var old = oldRows[index]
    var day = Model.parseKey(root.todayKey)
    function stamp(clock) {
      var match = String(clock).match(/^(\d{1,2}):(\d{2})$/)
      if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return 0
      return new Date(day.getFullYear(), day.getMonth(), day.getDate(), Number(match[1]), Number(match[2])).getTime()
    }
    var start = stamp(root.timelineDraftStart), end = stamp(root.timelineDraftEnd)
    if (!start || end <= start) { root.notifyMessage("Invalid timeline time", "Use a valid same-day start and end time."); return }
    for (var i = 0; i < oldRows.length; i++) if (i !== index) {
      var otherStart = Number(oldRows[i].start), otherEnd = Number(oldRows[i].end) || root.nowMs
      if (start < otherEnd && end > otherStart) { root.notifyMessage("Timeline overlap", "This change overlaps another tracked period."); return }
    }
    var previousSeconds = (Number(old.end) - Number(old.start)) / 1000
    var updatedSeconds = (end - start) / 1000
    var delta = updatedSeconds - previousSeconds
    var dayMap = {}
    for (var key in root.timelineDays) dayMap[key] = root.timelineDays[key]
    var changed = oldRows.slice()
    changed[index] = { start: start, end: end, active: root.timelineDraftActive }
    dayMap[root.todayKey] = changed
    root.timelineDays = dayMap
    if (old.active === root.timelineDraftActive) {
      if (old.active) root.todaySeconds = Math.max(0, root.todaySeconds + delta)
      else root.todayIdleSeconds = Math.max(0, root.todayIdleSeconds + delta)
    } else if (old.active) {
      root.todaySeconds = Math.max(0, root.todaySeconds - previousSeconds)
      root.todayIdleSeconds += updatedSeconds
    } else {
      root.todayIdleSeconds = Math.max(0, root.todayIdleSeconds - previousSeconds)
      root.todaySeconds += updatedSeconds
    }
    root.timelineDraftIndex = -1
    root.timelineEditorActive = false
    root.scheduleSave()
  }

  function saveAppAlias(appId, label) {
    var aliases = {}
    var existing = root.effSetting("appAliases", ({})) || ({})
    for (var id in existing) aliases[id] = existing[id]
    var name = String(label || "").trim().slice(0, 40)
    if (name) aliases[appId] = name
    else delete aliases[appId]
    root.writeOverride("appAliases", aliases)
  }

  function deleteManualRecord(id) {
    var next = []
    for (var i = 0; i < root.manualRecords.length; i++) {
      if (String(root.manualRecords[i].id) === String(id)) root.undoRecord = root.manualRecords[i]
      else next.push(root.manualRecords[i])
    }
    root.manualRecords = next
    root.scheduleSave()
  }

  function undoDeleteRecord() {
    if (!root.undoRecord) return
    var next = root.manualRecords.slice()
    next.push(root.undoRecord)
    root.manualRecords = next
    root.undoRecord = null
    root.scheduleSave()
  }

  function exportBackup() {
    var payload = {
      version: 1,
      exportedAt: new Date().toISOString(),
      stats: { bootId: root.bootId, pcBootEpochMs: root.pcBootEpochMs, sessionStart: root.sessionStart,
        todayKey: root.todayKey, todaySeconds: root.todaySeconds, days: root.daySeconds, idleDays: root.idleDays,
        todayIdleSeconds: root.todayIdleSeconds, activeSessionsToday: root.activeSessionsToday,
        longestActiveBlock: root.longestActiveBlock, appSeconds: root.appSeconds, appDays: root.appDays,
        hourSeconds: root.hourSeconds, focusDays: root.focusDays, focusLog: root.focusLog,
        timelineDays: root.timelineDays, manualRecords: root.manualRecords },
      timers: { countdown: { total: root.countdownTotal, remaining: root.countdownRunning ? root.countdownSeconds : root.countdownRemaining,
        running: root.countdownRunning, end: root.countdownEnd }, stopwatch: { base: root.swBase, running: root.swRunning,
        startedAt: root.swStartedAt }, laps: root.laps, pomodoro: { enabled: root.pomodoroEnabled,
        phase: root.pomodoroPhase, cycles: root.pomodoroCycles } },
      settings: root.overrides
    }
    var path = Quickshell.env("HOME") + "/Downloads/usage-backup-" + root.todayKey + ".json"
    var json = JSON.stringify(payload, null, 2)
    var script = "import os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); open(p,'w',encoding='utf-8').write(sys.argv[2])"
    Quickshell.execDetached(["python3", "-c", script, path, json])
    root.notifyMessage("Backup saved", path)
  }

  function restoreBackup(path) {
    var safePath = String(path || "").trim()
    if (!safePath) { root.notifyMessage("Choose a backup", "Enter the path to a Usage backup JSON file."); return }
    restoreProcess.command = ["bash", "-lc", "cat " + Util.shellQuote(safePath) + " 2>/dev/null || true"]
    restoreProcess.running = true
  }

  function applyBackup(raw) {
    var data = {}
    try { data = JSON.parse(raw) } catch (e) { root.notifyMessage("Invalid backup", "The selected file is not valid JSON."); return }
    if (Number(data.version) !== 1 || !data.stats || !data.settings) {
      root.notifyMessage("Unsupported backup", "This file is not a Usage & Timer backup."); return
    }
    root.applySettings(JSON.stringify(data.settings))
    root.applyStats(JSON.stringify(data.stats))
    root.applyTimers(JSON.stringify(data.timers || {}))
    root.notifyMessage("Backup restored", "Usage history, timers, and settings were loaded.")
  }

  function recordFocusCompletion() {
    var elapsed = root.focusStartedAt > 0 ? Math.max(0, Math.round((Date.now() - root.focusStartedAt) / 1000)) : root.countdownTotal
    if (elapsed < 60) elapsed = root.countdownTotal
    var appTotals = {}
    for (var id in root.liveAppSeconds) {
      var amount = Math.max(0, (Number(root.liveAppSeconds[id]) || 0) - (Number(root.focusAppSnapshot[id]) || 0))
      if (amount > 0) appTotals[id] = amount
    }
    var log = root.focusLog.slice()
    log.push({ at: Date.now(), seconds: elapsed, apps: appTotals })
    root.focusLog = log.slice(-180)
    root.focusStartedAt = 0
    root.focusAppSnapshot = ({})
  }

  function openApplicationRows() {
    var rows = []
    try {
      var windows = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
      for (var i = 0; windows && i < windows.length; i++) {
        var window = windows[i]
        rows.push({
          title: String(window.title || window.appId || "Untitled window"),
          appId: String(window.appId || "Unknown app"),
          toplevel: window
        })
      }
    } catch (e) {}
    rows.sort(function(a, b) { return a.appId.localeCompare(b.appId) || a.title.localeCompare(b.title) })
    return rows
  }

  function activateOpenApplication(toplevel) {
    try {
      if (!toplevel || typeof toplevel.activate !== "function") return
      toplevel.activate()
      root.close()
    } catch (e) {
      root.notifyMessage("Could not activate window", "This window is no longer available.")
      root.appListRefresh++
    }
  }

  function closeOpenApplication(toplevel) {
    try {
      if (!toplevel || typeof toplevel.close !== "function") return
      toplevel.close()
      root.appListRefresh++
    } catch (e) {
      root.notifyMessage("Could not close window", "This window is no longer available.")
      root.appListRefresh++
    }
  }

  function uniqueApplicationRows() {
    var totals = {}
    var apps = root.liveAppSeconds
    for (var trackedId in apps) totals[trackedId] = Number(apps[trackedId]) || 0
    for (var i = 0; i < root.manualRecords.length; i++) {
      var entry = root.manualRecords[i]
      if (entry.kind === "app" && entry.day === root.todayKey)
        totals[entry.appId] = (totals[entry.appId] || 0) + (Number(entry.seconds) || 0)
    }
    var rows = []
    for (var appId in totals)
      rows.push({ appId: String(appId), label: root.appDisplayName(appId), seconds: totals[appId], category: root.categoryForApp(appId) })
    rows.sort(function(a, b) { return b.seconds - a.seconds || a.appId.localeCompare(b.appId) })
    return rows
  }

  function manualRecordsFor(kind) {
    var rows = []
    for (var i = 0; i < root.manualRecords.length; i++) {
      var row = root.manualRecords[i]
      if (row.kind === kind) rows.push(row)
    }
    rows.sort(function(a, b) { return String(b.day).localeCompare(String(a.day)) || String(a.id).localeCompare(String(b.id)) })
    return rows
  }

  function manualActivityRecords() {
    var rows = []
    for (var i = 0; i < root.manualRecords.length; i++) {
      var row = root.manualRecords[i]
      if (row.kind === "active" || row.kind === "idle") rows.push(row)
    }
    rows.sort(function(a, b) { return String(b.day).localeCompare(String(a.day)) || String(a.id).localeCompare(String(b.id)) })
    return rows
  }

  function manualSecondsToday(kind) {
    var seconds = 0
    for (var i = 0; i < root.manualRecords.length; i++)
      if (root.manualRecords[i].kind === kind && root.manualRecords[i].day === root.todayKey)
        seconds += Number(root.manualRecords[i].seconds) || 0
    return seconds
  }

  function manualActivityCountToday(kind) {
    var count = 0
    for (var i = 0; i < root.manualRecords.length; i++)
      if (root.manualRecords[i].kind === kind && root.manualRecords[i].day === root.todayKey) count++
    return count
  }

  function longestActivityToday() {
    var longest = root.longestActiveBlockSeconds
    for (var i = 0; i < root.manualRecords.length; i++)
      if (root.manualRecords[i].kind === "active" && root.manualRecords[i].day === root.todayKey)
        longest = Math.max(longest, Number(root.manualRecords[i].seconds) || 0)
    return longest
  }

  function beginRecord(kind, entry) {
    root.recordEditorKind = kind
    root.recordEditingId = entry ? String(entry.id) : ""
    root.recordDraftName = entry ? String(entry.appId || entry.note || "") : ""
    root.recordDraftAlias = entry ? String((root.effSetting("appAliases", ({})) || ({}))[entry.appId] || "") : ""
    root.recordDraftDay = entry ? String(entry.day || root.todayKey) : root.todayKey
    root.recordDraftMinutes = entry ? String(Math.max(1, Math.round((Number(entry.seconds) || 60) / 60))) : "60"
    root.recordDraftStartTime = entry ? String(entry.startTime || "") : ""
    root.recordDraftActivity = entry && (entry.kind === "idle" || entry.kind === "active") ? entry.kind : "active"
    Qt.callLater(function() {
      manualNameField.text = root.recordDraftName
      if (manualAliasField) manualAliasField.text = root.recordDraftAlias
      manualDayField.text = root.recordDraftDay
      manualMinutesField.text = root.recordDraftMinutes
      if (manualStartTimeField) manualStartTimeField.text = root.recordDraftStartTime
      root.ensureCursorVisible(recordEditor)
      if (kind === "app") manualNameField.forceActiveFocus()
      else manualMinutesField.forceActiveFocus()
    })
  }

  function beginAppRecord(appId) {
    root.beginRecord("app", null)
    root.recordDraftName = String(appId || "")
    Qt.callLater(function() { manualNameField.text = root.recordDraftName })
  }

  function cancelRecordEdit() {
    root.recordEditorKind = ""
    root.recordEditingId = ""
    root.recordEditorActive = false
  }

  function saveManualRecord() {
    var kind = root.recordEditorKind
    var day = String(root.recordDraftDay || "").trim()
    var minutes = Number(root.recordDraftMinutes)
    if ((kind !== "app" && kind !== "activity") || !/^\d{4}-\d{2}-\d{2}$/.test(day)
        || Model.dayKey(Model.parseKey(day)) !== day || !isFinite(minutes) || minutes < 1 || minutes > 10080) {
      root.notifyMessage("Check record details", "Use a valid date and a duration from 1 to 10080 minutes.")
      return
    }
    var appId = String(root.recordDraftName || "").trim()
    if (kind === "app" && appId.length === 0) {
      root.notifyMessage("App ID required", "Enter an application ID to save this record.")
      return
    }
    var activityStartTime = ""
    if (kind === "activity") {
      activityStartTime = String(root.recordDraftStartTime || "").trim()
      if (!/^([01]?\d|2[0-3]):[0-5]\d$/.test(activityStartTime)) {
        root.notifyMessage("Start time required", "Use a 24-hour HH:MM time to check activity overlaps.")
        return
      }
      var hm = activityStartTime.split(":")
      var date = Model.parseKey(day)
      var intervalStart = new Date(date.getFullYear(), date.getMonth(), date.getDate(), Number(hm[0]), Number(hm[1])).getTime()
      var intervalEnd = intervalStart + Math.round(minutes * 60) * 1000
      for (var r = 0; r < root.manualRecords.length; r++) {
        var other = root.manualRecords[r]
        if (String(other.id) === root.recordEditingId || other.day !== day || (other.kind !== "active" && other.kind !== "idle") || !other.startTime) continue
        var otherHm = String(other.startTime).split(":")
        var otherStart = new Date(date.getFullYear(), date.getMonth(), date.getDate(), Number(otherHm[0]), Number(otherHm[1])).getTime()
        var otherEnd = otherStart + (Number(other.seconds) || 0) * 1000
        if (intervalStart < otherEnd && intervalEnd > otherStart) {
          root.notifyMessage("Activity overlap", "This manual session overlaps another saved session.")
          return
        }
      }
      var tracked = root.timelineDays[day] || []
      for (var t = 0; t < tracked.length; t++) {
        var trackedStart = Number(tracked[t].start), trackedEnd = Number(tracked[t].end) || root.nowMs
        if (intervalStart < trackedEnd && intervalEnd > trackedStart) {
          root.notifyMessage("Tracked time overlap", "This manual session overlaps the tracked timeline.")
          return
        }
      }
    }
    for (var d = 0; d < root.manualRecords.length; d++) {
      var duplicate = root.manualRecords[d]
      if (String(duplicate.id) !== root.recordEditingId && duplicate.kind === (kind === "app" ? "app" : root.recordDraftActivity)
          && duplicate.day === day && duplicate.appId === (kind === "app" ? appId : "")
          && String(duplicate.note || "") === (kind === "activity" ? String(root.recordDraftName || "Activity") : "")
          && String(duplicate.startTime || "") === activityStartTime
          && Number(duplicate.seconds) === Math.round(minutes * 60)) {
        root.notifyMessage("Duplicate record", "An identical record already exists for this date.")
        return
      }
    }
    var entry = {
      id: root.recordEditingId || String(Date.now()) + "-" + Math.floor(Math.random() * 100000),
      kind: kind === "app" ? "app" : root.recordDraftActivity,
      appId: kind === "app" ? appId : "",
      note: kind === "activity" ? String(root.recordDraftName || "Activity") : "",
      day: day,
      seconds: Math.round(minutes * 60)
    }
    if (kind === "activity") entry.startTime = activityStartTime
    if (kind === "app") root.saveAppAlias(appId, root.recordDraftAlias)
    var next = []
    var replaced = false
    for (var i = 0; i < root.manualRecords.length; i++) {
      if (String(root.manualRecords[i].id) === entry.id) { next.push(entry); replaced = true }
      else next.push(root.manualRecords[i])
    }
    if (!replaced) next.push(entry)
    root.manualRecords = next
    root.scheduleSave()
    root.cancelRecordEdit()
  }

  function reviewTitle() {
    if (root.reviewPage === "open") return "OPEN APPS"
    if (root.reviewPage === "unique") return "UNIQUE APPS TODAY"
    return "SHELL SESSION"
  }

  function openReviewPage(page) {
    root.reviewPage = page
    root.cursorActive = false
    Qt.callLater(root.resetScroll)
  }

  function cycleAppCategory(appId) {
    var order = ["work", "communication", "browsing", "other"]
    var current = root.categoryForApp(appId)
    var next = order[(order.indexOf(current) + 1) % order.length]
    var map = {}
    for (var id in root.appCategoryOverrides) map[id] = root.appCategoryOverrides[id]
    map[appId] = next
    root.writeOverride("appCategories", map)
  }

  function setCategoryLabel(key, value) {
    var labels = { work: "Work", communication: "Communication", browsing: "Browsing", other: "Other" }
    var name = String(value || "").trim().slice(0, 20)
    root.writeOverride("categoryName" + key.charAt(0).toUpperCase() + key.slice(1), name || labels[key])
  }

  function timelineStateChanged(active, at) {
    var key = Model.dayKey(new Date(at))
    var days = {}
    for (var day in root.timelineDays) days[day] = root.timelineDays[day]
    var rows = (days[key] || []).slice()
    var last = rows.length > 0 ? rows[rows.length - 1] : null
    if (last && Number(last.end) === 0) {
      if (Boolean(last.active) === Boolean(active)) return
      var closed = {}
      for (var field in last) closed[field] = last[field]
      closed.end = at
      rows[rows.length - 1] = closed
    }
    rows.push({ start: at, end: 0, active: Boolean(active) })
    if (rows.length > 160) rows = rows.slice(rows.length - 160)
    days[key] = rows
    var keys = Object.keys(days).sort()
    while (keys.length > 60) delete days[keys.shift()]
    root.timelineDays = days
    root.scheduleSave()
  }

  function rolloverTimeline(previousKey, nextKey, at, nextStart) {
    var days = {}
    for (var day in root.timelineDays) days[day] = root.timelineDays[day]
    var previous = (days[previousKey] || []).slice()
    if (previous.length > 0) {
      var last = previous[previous.length - 1]
      if (Number(last.end) === 0) {
        var closed = {}
        for (var field in last) closed[field] = last[field]
        closed.end = at
        previous[previous.length - 1] = closed
      }
      days[previousKey] = previous
    }
    days[nextKey] = [{ start: Number(nextStart) > 0 ? Number(nextStart) : at, end: 0, active: root.activeNow }]
    var keys = Object.keys(days).sort()
    while (keys.length > 60) delete days[keys.shift()]
    root.timelineDays = days
  }

  function maybeBreakReminder() {
    if (!root.breakRemindersEnabled) return
    var interval = root.breakReminderMinutes * 60
    var bucket = Math.floor(root.todaySeconds / interval)
    if (bucket <= root.lastBreakReminderBucket || bucket < 1) return
    root.lastBreakReminderBucket = bucket
    root.notifyMessage("Time for a break", "You have been active for " + bucket * root.breakReminderMinutes + " minutes. Take a short stretch break.")
  }

  function exportCsv() {
    var lines = ["date,active_seconds,idle_seconds,focus_sessions,app_id,app_seconds,record_kind,record_id,note"]
    var keys = Object.keys(root.daySeconds).sort()
    for (var focusKey in root.focusDays) if (keys.indexOf(focusKey) < 0) keys.push(focusKey)
    for (var appKey in root.appDays) if (keys.indexOf(appKey) < 0) keys.push(appKey)
    for (var idleKey in root.idleDays) if (keys.indexOf(idleKey) < 0) keys.push(idleKey)
    if (keys.indexOf(root.todayKey) < 0) keys.push(root.todayKey)
    keys.sort()
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      var active = key === root.todayKey ? Math.round(root.activeSecondsToday) : Math.round(Number(root.daySeconds[key]) || 0)
      var idle = key === root.todayKey ? Math.round(root.idleSecondsToday) : Math.round(Number(root.idleDays[key]) || 0)
      var focus = Number(root.focusDays[key]) || 0
      var apps = key === root.todayKey ? root.liveAppSeconds : ((root.appDays[key] && typeof root.appDays[key] === "object") ? root.appDays[key] : {})
      var ids = Object.keys(apps || {})
      if (ids.length === 0) lines.push([key, active, idle, focus, "", 0, "", "", ""].join(","))
      for (var j = 0; j < ids.length; j++) {
        var appId = String(ids[j]).replace(/"/g, '""')
        lines.push([key, active, idle, focus, '"' + appId + '"', Math.round(Number(apps[ids[j]]) || 0), "", "", ""].join(","))
      }
    }
    for (var r = 0; r < root.manualRecords.length; r++) {
      var entry = root.manualRecords[r]
      var note = String(entry.note || "").replace(/"/g, '""')
      var app = String(entry.appId || "").replace(/"/g, '""')
      lines.push([
        entry.day,
        entry.kind === "active" ? Number(entry.seconds) || 0 : 0,
        entry.kind === "idle" ? Number(entry.seconds) || 0 : 0,
        0,
        app ? '"' + app + '"' : "",
        entry.kind === "app" ? Number(entry.seconds) || 0 : 0,
        "manual-" + entry.kind,
        String(entry.id || ""),
        note ? '"' + note + '"' : ""
      ].join(","))
    }
    var path = Quickshell.env("HOME") + "/Downloads/usage-history-" + root.todayKey + "-" + Date.now() + ".csv"
    var script = "import os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); open(p,'w',encoding='utf-8').write(sys.argv[2])"
    Quickshell.execDetached(["python3", "-c", script, path, lines.join("\n") + "\n"])
    root.notifyMessage("Usage exported", path)
  }

  function clearUsageHistory() {
    var now = Date.now()
    root.daySeconds = {}
    root.idleDays = {}
    root.appSeconds = {}
    root.appDays = {}
    root.hourSeconds = {}
    root.focusDays = {}
    root.focusLog = []
    root.timelineDays = {}
    root.manualRecords = []
    root.undoRecord = null
    root.todaySeconds = 0
    root.todayIdleSeconds = 0
    root.activeSessionsToday = root.activeNow ? 1 : 0
    root.longestActiveBlock = 0
    root.currentActiveBlock = 0
    root.activeSinceMs = root.activeNow ? now : 0
    root.idleSinceMs = root.activeNow ? 0 : now
    root.appFoldSinceMs = root.activeNow ? now : 0
    root.lastBreakReminderBucket = 0
    root.timelineStateChanged(root.activeNow, now)
    root.clearHistoryArmed = false
    root.scheduleSave()
  }

  readonly property int configuredGoalMinutes: Number(root.effSetting("goalMinutes", 240))
  readonly property int configuredCustomMinutes: Number(root.effSetting("customMinutes", 25))
  readonly property int idleThresholdSeconds: Number(root.effSetting("idleThresholdSeconds", 60))
  readonly property string configuredBarMode: String(root.effSetting("barMode", "today"))
  readonly property bool configuredTrackApps: root.effSetting("trackApps", true) !== false
  readonly property int configuredHistoryDays: Math.max(1, Math.min(30, Number(root.effSetting("historyDays", 7))))
  readonly property int configuredTopApps: Math.max(1, Math.min(15, Number(root.effSetting("topApps", 5))))
  readonly property bool breakRemindersEnabled: root.effSetting("breakReminders", false) === true
  readonly property int breakReminderMinutes: Math.max(20, Math.min(240, Number(root.effSetting("breakReminderMinutes", 60))))
  readonly property var appCategoryOverrides: root.effSetting("appCategories", ({})) || ({})
  readonly property var appGoals: root.effSetting("appGoals", ({})) || ({})
  readonly property var categoryGoals: root.effSetting("categoryGoals", ({})) || ({})
  readonly property var categoryLabels: ({
    work: String(root.effSetting("categoryNameWork", "Work")),
    communication: String(root.effSetting("categoryNameCommunication", "Communication")),
    browsing: String(root.effSetting("categoryNameBrowsing", "Browsing")),
    other: String(root.effSetting("categoryNameOther", "Other"))
  })

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
  property var idleDays: ({})
  property string todayKey: ""
  property double todaySeconds: 0
  property double todayIdleSeconds: 0
  property var focusDays: ({})
  property int pendingFocusCompletions: 0
  property var timelineDays: ({})
  property int lastBreakReminderBucket: 0
  property bool clearHistoryArmed: false
  property bool categoryEditorActive: false
  readonly property int historyRangeDays: [7, 14, 30].indexOf(Number(root.effSetting("historyRange", 7))) >= 0
    ? Number(root.effSetting("historyRange", 7)) : 7
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
  readonly property double currentActiveBlockSeconds: root.currentActiveBlock
    + (root.activeNow && root.activeSinceMs > 0 ? Math.max(0, (root.nowMs - root.activeSinceMs) / 1000) : 0)
  readonly property double longestActiveBlockSeconds: Math.max(root.longestActiveBlock, root.currentActiveBlockSeconds)
  readonly property double activeSecondsToday: root.todaySeconds
    + (root.activeNow && root.activeSinceMs > 0 ? Math.max(0, (root.nowMs - root.activeSinceMs) / 1000) : 0)
  readonly property double goalSeconds: root.configuredGoalMinutes * 60
  readonly property double goalFraction: root.goalSeconds > 0 ? Math.min(1, root.activeSecondsToday / root.goalSeconds) : 0
  readonly property var historyList: Model.history(root.daySeconds, root.todayKey, root.activeSecondsToday, root.historyRangeDays)
  readonly property int focusSessionsToday: Number(root.focusDays[root.todayKey]) || 0
  readonly property var focusHistoryList: Model.history(root.focusDays, root.todayKey, root.focusSessionsToday, root.historyRangeDays)
  readonly property int focusHistoryTotal: Model.weekTotal(root.focusHistoryList)
  readonly property double focusHistoryMax: {
    var m = 1
    for (var i = 0; i < root.focusHistoryList.length; i++) m = Math.max(m, root.focusHistoryList[i].seconds)
    return m
  }
  readonly property var todayTimeline: root.timelineDays[root.todayKey] || []
  readonly property var rangeAllAppsList: Model.topAppsAcross(root.appDays, root.liveAppSeconds, root.todayKey, 1000, root.historyRangeDays)
  readonly property var rangeAppsList: Model.topAppsAcross(root.appDays, root.liveAppSeconds, root.todayKey, root.configuredTopApps, root.historyRangeDays)
  readonly property double rangeAppsMax: Model.topAppsMax(root.rangeAppsList)
  readonly property double totalRangeAppSeconds: {
    var t = 0
    for (var i = 0; i < root.rangeAppsList.length; i++) t += root.rangeAppsList[i].seconds
    return t
  }
  readonly property var categorySummary: {
    var totals = { work: 0, communication: 0, browsing: 0, other: 0 }
    for (var i = 0; i < root.rangeAllAppsList.length; i++) {
      var app = root.rangeAllAppsList[i]
      var category = root.appCategoryOverrides[app.id] || Model.appCategory(app.id)
      totals[category] = (totals[category] || 0) + app.seconds
    }
    return totals
  }
  readonly property double historyMax: {
    var m = 1
    for (var i = 0; i < root.historyList.length; i++) m = Math.max(m, root.historyList[i].seconds)
    return Math.max(1, m)
  }
  readonly property double weekSeconds: Model.weekTotal(root.historyList)
  readonly property var liveAppSeconds: {
    var live = {}
    for (var id in root.appSeconds) live[id] = Number(root.appSeconds[id]) || 0
    if (root.configuredTrackApps && root.activeNow && root.activeAppId && root.appFoldSinceMs > 0)
      live[root.activeAppId] = (live[root.activeAppId] || 0) + Math.max(0, (root.nowMs - root.appFoldSinceMs) / 1000)
    return live
  }
  readonly property var topAppsList: Model.topApps(root.liveAppSeconds, root.configuredTopApps)
  readonly property double topAppsMax: Model.topAppsMax(root.topAppsList)
  readonly property double totalAppSeconds: {
    var t = 0
    for (var id in root.liveAppSeconds) t += (Number(root.liveAppSeconds[id]) || 0)
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
  readonly property var topAppsWeekList: root.rangeAppsList
  readonly property double topAppsWeekMax: Model.topAppsMax(root.topAppsWeekList)
  readonly property double totalWeekAppSeconds: root.totalRangeAppSeconds
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
  property bool pomodoroEnabled: false
  property string pomodoroPhase: "focus"
  property int pomodoroCycles: 0

  readonly property bool countdownArmed: root.countdownRunning || root.pomodoroEnabled
    || (root.countdownRemaining > 0 && root.countdownRemaining < root.countdownTotal)
  readonly property bool timerArmed: root.swRunning || root.swBase > 0
  readonly property double countdownSeconds: root.countdownRunning ? Math.max(0, (root.countdownEnd - root.nowMs) / 1000) : root.countdownRemaining
  readonly property double stopwatchSeconds: root.swBase + (root.swRunning && root.swStartedAt > 0 ? Math.max(0, (root.nowMs - root.swStartedAt) / 1000) : 0)
  readonly property bool timerInBar: root.countdownArmed || root.timerArmed
  readonly property color timerActiveColor: root.timerTab === "countdown"
    ? (root.countdownRunning ? Color.accent : (root.countdownRemaining > 0 ? root.barForeground : Qt.darker(root.barForeground, 1.4)))
    : (root.swRunning || root.swBase > 0 ? Color.accent : Qt.darker(root.barForeground, 1.4))
  readonly property string cdStatusText: {
    var phase = root.pomodoroEnabled
      ? (root.pomodoroPhase === "break" ? "Break · cycle " + root.pomodoroCycles : "Focus · cycle " + (root.pomodoroCycles + 1)) + " · "
      : ""
    if (root.countdownRunning) return phase + "Running · ends " + Model.clockTime(root.countdownEnd)
    if (root.countdownRemaining <= 0) return phase + "Finished"
    if (root.countdownRemaining < root.countdownTotal) return phase + "Paused · " + Model.timerText(root.countdownRemaining) + " of " + Model.timerText(root.countdownTotal)
    return phase + "Set · " + Model.timerText(root.countdownTotal)
  }
  readonly property string swStatusText: root.swBase > 0
    ? (root.swRunning ? "Running" : "Paused · " + Model.longTime(root.swBase))
    : "Ready"

  // -------------------------------------------------------------------------
  // Bar button
  // -------------------------------------------------------------------------

  readonly property string barText: {
    if (root.countdownArmed) return "󰔟 " + Model.timerText(root.countdownSeconds)
    if (root.timerArmed) return "󰔒 " + Model.stopwatchText(root.stopwatchSeconds)
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
    if (root.countdownRunning) return (root.pomodoroEnabled ? (root.pomodoroPhase === "break" ? "Pomodoro break" : "Pomodoro focus") : "Countdown") + " · " + Model.longTime(root.countdownSeconds) + " left · click to open"
    if (root.countdownArmed) return (root.pomodoroEnabled ? "Pomodoro" : "Countdown") + " paused · " + Model.longTime(root.countdownRemaining) + " left · click to open"
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
      if (el > 0 && root.activeNow) {
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
      root.idleDays = Model.pruneDays(Model.rollover(root.idleDays, root.todayKey, Math.round(root.idleSecondsToday)), 60)
      root.appDays = Model.rolloverApps(root.appDays, root.todayKey, root.appSeconds)
      root.appSeconds = {}
      root.appDays = Model.pruneApps(root.appDays, 60)
      root.hourSeconds = {}
      root.rolloverTimeline(root.todayKey, key, now)
      root.todayKey = key
      root.lastBreakReminderBucket = 0
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
    if (!root.bootId || !root.statsLoaded) return
    var id = ""
    var count = 0
    try {
      var tl = ToplevelManager.activeToplevel
      if (tl) id = String(tl.appId || tl.title || "").trim()
      count = ToplevelManager.toplevels && ToplevelManager.toplevels.values
        ? ToplevelManager.toplevels.values.length : 0
    } catch (e) {}
    root.openToplevels = count
    root.appListRefresh += 1
    if (!root.configuredTrackApps) {
      root.activeAppId = ""
      root.appFoldSinceMs = 0
      return
    }
    var now = Date.now()
    if (root.activeAppId && root.appFoldSinceMs > 0) {
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
    root.checkUsageGoals()
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
      "idleDays": root.idleDays,
      "todayIdleSeconds": root.todayIdleSeconds,
      "activeSessionsToday": root.activeSessionsToday,
      "longestActiveBlock": root.longestActiveBlock,
      "appSeconds": root.appSeconds,
      "appDays": root.appDays,
      "hourSeconds": root.hourSeconds,
      "focusDays": root.focusDays,
      "focusLog": root.focusLog,
      "timelineDays": root.timelineDays,
      "manualRecords": root.manualRecords,
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
      "laps": root.laps,
      "pomodoro": {
        "enabled": root.pomodoroEnabled,
        "phase": root.pomodoroPhase,
        "cycles": root.pomodoroCycles
      }
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
    if (delta > 0) {
      root.maybeBreakReminder()
      root.scheduleSave()
    }
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
    // Keep this distinct from PC uptime: it measures the current shell session.
    root.sessionStart = now

    if (root.pcBootEpochMs <= 0 && sameBoot && Number(data.pcBootEpochMs) > 0) {
      root.pcBootEpochMs = Number(data.pcBootEpochMs)
    }

    var key = Model.dayKey(new Date())
    root.daySeconds = data.days && typeof data.days === "object" ? Model.pruneDays(data.days, 60) : {}
    root.idleDays = data.idleDays && typeof data.idleDays === "object" ? Model.pruneDays(data.idleDays, 60) : {}
    root.appDays = data.appDays && typeof data.appDays === "object" ? Model.pruneApps(data.appDays, 60) : {}
    root.focusDays = data.focusDays && typeof data.focusDays === "object" ? Model.pruneDays(data.focusDays, 60) : {}
    root.focusLog = Array.isArray(data.focusLog) ? data.focusLog.slice(-180) : []
    root.timelineDays = data.timelineDays && typeof data.timelineDays === "object" ? data.timelineDays : {}
    root.manualRecords = Array.isArray(data.manualRecords) ? data.manualRecords : []
    if (String(data.todayKey) === key) {
      root.todayKey = key
      root.todaySeconds = Number(data.todaySeconds) || 0
      root.todayIdleSeconds = Number(data.todayIdleSeconds) || 0
      root.activeSessionsToday = Number(data.activeSessionsToday) || 0
      root.longestActiveBlock = Number(data.longestActiveBlock) || 0
      root.appSeconds = data.appSeconds && typeof data.appSeconds === "object" ? data.appSeconds : {}
      root.hourSeconds = data.hourSeconds && typeof data.hourSeconds === "object" ? data.hourSeconds : {}
    } else {
      if (String(data.todayKey) && Number(data.todaySeconds) > 0) {
        root.daySeconds = Model.rollover(root.daySeconds, String(data.todayKey), Number(data.todaySeconds))
      }
      if (String(data.todayKey) && Number(data.todayIdleSeconds) > 0) {
        root.idleDays = Model.rollover(root.idleDays, String(data.todayKey), Number(data.todayIdleSeconds))
      }
      if (String(data.todayKey) && data.appSeconds && typeof data.appSeconds === "object") {
        root.appDays = Model.rolloverApps(root.appDays, String(data.todayKey), data.appSeconds)
      }
      var previousKey = String(data.todayKey || "")
      if (previousKey) {
        var oldDay = Model.parseKey(previousKey)
        var oldEnd = new Date(oldDay.getFullYear(), oldDay.getMonth(), oldDay.getDate() + 1).getTime()
        root.rolloverTimeline(previousKey, key, oldEnd, now)
      }
      root.todayKey = key
      root.todaySeconds = 0
      root.todayIdleSeconds = 0
      root.activeSessionsToday = 0
      root.longestActiveBlock = 0
      root.appSeconds = {}
      root.hourSeconds = {}
    }
    var currentlyActive = true
    try { currentlyActive = !idleMonitor.isIdle } catch (e) {}
    root.activeNow = currentlyActive
    if (root.activeSessionsToday === 0 && (root.todaySeconds > 0 || currentlyActive))
      root.activeSessionsToday = 1
    root.activeSinceMs = currentlyActive ? now : 0
    root.idleSinceMs = currentlyActive ? 0 : now
    root.currentActiveBlock = 0
    root.appFoldSinceMs = currentlyActive ? now : 0
    if (root.pendingFocusCompletions > 0) {
      var mergedFocus = {}
      for (var focusDay in root.focusDays) mergedFocus[focusDay] = root.focusDays[focusDay]
      mergedFocus[root.todayKey] = (Number(mergedFocus[root.todayKey]) || 0) + root.pendingFocusCompletions
      root.focusDays = Model.pruneDays(mergedFocus, 60)
      root.pendingFocusCompletions = 0
    }
    root.statsLoaded = true
    root.lastBreakReminderBucket = Math.floor(root.todaySeconds / (root.breakReminderMinutes * 60))
    root.timelineStateChanged(root.activeNow, now)
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

  Process {
    id: restoreProcess
    command: ["bash", "-lc", "true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBackup(String(text).trim())
    }
  }

  function applyTimers(raw) {
    var data = {}
    try { data = raw && raw.length > 0 ? JSON.parse(raw) : {} } catch (e) {}
    var now = Date.now()
    var sameBoot = String(data.bootId || "") === root.bootId
    var cd = data.countdown || {}
    var total = Number(cd.total) > 0 ? Number(cd.total) : root.configuredCustomMinutes * 60
    root.countdownTotal = total

    var expiredDown = !!cd.running && Number(cd.end) > 0 && Number(cd.end) <= now
    if (cd.running && Number(cd.end) > now) {
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
      root.countdownRunning = false
      root.countdownRemaining = 0
    }

    var pom = data.pomodoro || {}
    root.pomodoroEnabled = pom.enabled === true
    root.pomodoroPhase = pom.phase === "break" ? "break" : "focus"
    root.pomodoroCycles = Math.max(0, Math.floor(Number(pom.cycles) || 0))

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
    if (expiredDown) root.finishCountdown()
    else root.scheduleSave()
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
        root.timelineStateChanged(false, now)
      } else {
        root.activeNow = true
        root.activeSessionsToday += 1
        root.activeSinceMs = now
        root.idleSinceMs = 0
        root.appFoldSinceMs = now
        root.timelineStateChanged(true, now)
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
    root.pomodoroEnabled = false
    root.countdownRunning = false
    root.countdownRemaining = root.countdownTotal
    root.scheduleSave()
  }

  function selectPreset(minutes) {
    root.pomodoroEnabled = false
    root.countdownTotal = Math.max(1, Math.round(minutes * 60))
    root.countdownRemaining = root.countdownTotal
    root.startCountdown()
  }

  function adjustCustom(deltaMin) {
    root.pomodoroEnabled = false
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
    if (root.pomodoroEnabled) {
      var focusDone = root.pomodoroPhase !== "break"
      if (focusDone) {
        root.recordFocusCompletion()
        root.pomodoroCycles++
        if (!root.statsLoaded) root.pendingFocusCompletions++
        else {
          var focus = {}
          for (var day in root.focusDays) focus[day] = root.focusDays[day]
          focus[root.todayKey] = (Number(focus[root.todayKey]) || 0) + 1
          root.focusDays = Model.pruneDays(focus, 60)
        }
      }
      root.pomodoroPhase = focusDone ? "break" : "focus"
      root.countdownTotal = (focusDone ? 5 : 25) * 60
      root.countdownRemaining = root.countdownTotal
      root.countdownEnd = Date.now() + root.countdownTotal * 1000
      root.countdownRunning = true
      if (!focusDone) {
        root.focusStartedAt = Date.now()
        root.focusAppSnapshot = JSON.parse(JSON.stringify(root.liveAppSeconds))
      }
      root.scheduleSave()
      root.notifyFinished(focusDone ? "Focus complete" : "Break complete",
        focusDone ? "5 minute break · cycle " + root.pomodoroCycles : "25 minute focus · cycle " + (root.pomodoroCycles + 1))
      return
    }
    root.countdownRunning = false
    root.countdownRemaining = 0
    root.scheduleSave()
    root.notifyFinished()
  }

  function togglePomodoro() {
    if (root.pomodoroEnabled) {
      root.pomodoroEnabled = false
      root.countdownRunning = false
      root.countdownRemaining = root.countdownTotal
      root.scheduleSave()
      return
    }
    root.pomodoroEnabled = true
    root.pomodoroPhase = "focus"
    root.pomodoroCycles = 0
    root.countdownTotal = 25 * 60
    root.countdownRemaining = root.countdownTotal
    root.focusStartedAt = Date.now()
    root.focusAppSnapshot = JSON.parse(JSON.stringify(root.liveAppSeconds))
    root.startCountdown()
  }

  function notifyMessage(title, detail) {
    var bin = Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-notification-send"
    Util.execArgv([bin, "--app-name", "Usage & Timer",
      "-g", "󰔟", "-u", "normal", "-t", "8000", title, detail])
  }

  function notifyFinished(title, detail) {
    root.notifyMessage(title || "Time's up", detail || (Model.longTime(root.countdownTotal) + " countdown finished"))
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

  readonly property var countdownSections: ["tab", "presets", "custom", "cdaction", "pomodoro"]
  readonly property var stopwatchSections: ["tab", "swaction"]
  readonly property var settingsSections: ["tab", "setgoal", "setcustom", "setidle", "setbarmode", "setapps", "settop", "sethistory", "setbreak", "setbreakmin", "setlimits", "setbackup", "setrestore", "setexport", "setclear", "setreset"]
  readonly property var visibleSections: root.timerTab === "stopwatch" ? root.stopwatchSections
    : (root.timerTab === "settings" ? root.settingsSections : root.countdownSections)

  function sectionCount(section) {
    switch (section) {
      case "tab": return 3
      case "presets": return 5
      case "custom": return 2
      case "cdaction": return 2
      case "pomodoro": return 1
      case "swaction": return 3
      case "setgoal": return 2
      case "setcustom": return 2
      case "setidle": return 2
      case "setbarmode": return 1
      case "setapps": return 1
      case "settop": return 2
      case "sethistory": return 2
      case "setbreak": return 1
      case "setbreakmin": return 2
      case "setlimits": return 1
      case "setbackup": return 1
      case "setrestore": return 1
      case "setexport": return 1
      case "setclear": return 1
      case "setreset": return 1
    }
    return 0
  }

  function sectionIsHorizontal(section) {
    return section === "tab" || section === "presets" || section === "custom"
      || section === "setgoal" || section === "setcustom" || section === "setidle"
      || section === "settop" || section === "sethistory" || section === "setbreakmin"
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
      case "pomodoro":
        root.togglePomodoro()
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
      case "setbreak":
        root.writeOverride("breakReminders", !root.breakRemindersEnabled)
        break
      case "setbreakmin":
        root.writeOverride("breakReminderMinutes", Math.max(20, Math.min(240, root.breakReminderMinutes + (index === 1 ? 10 : -10))))
        break
      case "setlimits":
        root.setGoalFromDraft()
        break
      case "setexport":
        root.exportCsv()
        break
      case "setbackup":
        root.exportBackup()
        break
      case "setrestore":
        if (root.restoreArmed) { root.restoreArmed = false; root.restoreBackup(root.backupPathDraft) }
        else root.restoreArmed = true
        break
      case "setclear":
        if (root.clearHistoryArmed) root.clearUsageHistory()
        else root.clearHistoryArmed = true
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
      root.timerTab = root.countdownArmed ? "countdown" : (root.timerArmed ? "stopwatch" : root.timerTab)
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
    alignTop: true
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(dir) { root.switchPanel(dir) }
      blocked: root.categoryEditorActive || root.recordEditorActive || root.settingsEditorActive || root.timelineEditorActive
      onTextKey: function(t) {
        if (t === "t" || t === "T" || t === "s" || t === "S") root.switchTimerTab()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
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

          Column {
            id: dashboardContent
            width: parent.width
            spacing: Style.space(12)
            visible: root.reviewPage === ""

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

          // ---- Usage metrics (two-column cards) ----
          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(8)

            StatCard {
              label: "TODAY ACTIVE"
              value: Model.longTime(root.activeSecondsToday)
              valueColor: Color.accent
              width: (parent.width - Style.space(10)) / 2
            }

            StatCard {
              label: "SHELL SESSION"
              value: Model.longTime(root.sessionSeconds)
              pageKey: "session"
              width: (parent.width - Style.space(10)) / 2
            }

            StatCard {
              label: "PC ON"
              value: Model.longTime(root.pcOnSeconds)
              width: (parent.width - Style.space(10)) / 2
            }

            StatCard {
              label: "IDLE TODAY"
              value: Model.longTime(root.idleSecondsToday)
              width: (parent.width - Style.space(10)) / 2
            }
          }

          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(8)

            StatCard {
              label: "SESSIONS"
              value: String(root.activeSessionsToday)
              width: (parent.width - Style.space(10)) / 2
            }

            StatCard {
              label: "LONGEST"
              value: Model.longTime(root.longestActiveBlockSeconds)
              width: (parent.width - Style.space(10)) / 2
            }

            StatCard {
              label: "OPEN APPS"
              value: String(root.openToplevels)
              pageKey: "open"
              width: (parent.width - Style.space(10)) / 2
            }

            StatCard {
              label: "UNIQUE APPS"
              value: String(root.uniqueApplicationRows().length)
              pageKey: "unique"
              width: (parent.width - Style.space(10)) / 2
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
                text: "LAST " + root.historyRangeDays + " DAYS"
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
                model: [7, 14, 30]
                delegate: RangeChip {
                  required property int modelData
                  days: modelData
                  selected: modelData === root.historyRangeDays
                  onActivated: root.selectHistoryRange(modelData)
                }
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

            Text {
              visible: root.weekSeconds <= 0
              text: "Activity history will appear here as you use the PC."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
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
                text: "RECENT ACTIVITY BY HOUR"
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

            Text {
              visible: root.hourMax <= 1
              text: "Recent activity appears here as active time is recorded."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
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

          // ---- Today's active and idle timeline ----
          Column {
            width: parent.width
            spacing: Style.space(5)

            Item {
              width: parent.width
              implicitHeight: Math.max(timelineHeader.implicitHeight, timelineTotals.implicitHeight)
              PanelSectionHeader {
                id: timelineHeader
                text: "TODAY'S TIMELINE"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: timelineTotals
                text: "Active " + Model.compactTime(root.activeSecondsToday) + " · Idle " + Model.compactTime(root.idleSecondsToday)
                color: Qt.darker(root.barForeground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Item {
              id: timelineTrack
              width: parent.width
              height: Style.space(18)
              Rectangle { anchors.fill: parent; radius: height / 2; color: Util.alpha(root.barForeground, 0.1) }
              Repeater {
                model: root.todayTimeline
                delegate: Rectangle {
                  required property var modelData
                  property double dayStart: new Date(new Date(root.nowMs).getFullYear(), new Date(root.nowMs).getMonth(), new Date(root.nowMs).getDate()).getTime()
                  property double dayEnd: new Date(new Date(root.nowMs).getFullYear(), new Date(root.nowMs).getMonth(), new Date(root.nowMs).getDate() + 1).getTime()
                  property double segmentStart: Math.max(dayStart, Number(modelData.start) || dayStart)
                  property double segmentEnd: Math.min(dayEnd, Number(modelData.end) > 0 ? Number(modelData.end) : root.nowMs)
                  x: timelineTrack.width * Math.max(0, (segmentStart - dayStart) / Math.max(1, dayEnd - dayStart))
                  width: Math.max(Style.space(2), timelineTrack.width * Math.max(0, (segmentEnd - segmentStart) / Math.max(1, dayEnd - dayStart)))
                  height: timelineTrack.height
                  radius: height / 2
                  color: modelData.active ? Color.accent : Util.alpha(root.bar.foreground, 0.38)
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(14)
              Row {
                spacing: Style.space(5)
                Rectangle { width: Style.space(7); height: Style.space(7); radius: width / 2; color: Color.accent; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Active"; color: Qt.darker(root.barForeground, 1.35); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
              }
              Row {
                spacing: Style.space(5)
                Rectangle { width: Style.space(7); height: Style.space(7); radius: width / 2; color: Util.alpha(root.bar.foreground, 0.38); anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Idle"; color: Qt.darker(root.barForeground, 1.35); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
              }
            }

            Text {
              visible: root.todayTimeline.length === 0
              text: "Your active and idle periods will appear here as you use the PC."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
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

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(8)

              StatCard {
                label: "STREAK"
                value: root.streakCount > 0 ? root.streakCount + " days" : "—"
                valueColor: root.streakCount > 0 ? Color.accent : root.barForeground
                width: (parent.width - Style.space(10)) / 2
              }

              StatCard {
                label: "BEST DAY"
                value: Model.longTime(root.bestDaySeconds)
                width: (parent.width - Style.space(10)) / 2
              }

              StatCard {
                label: "AVERAGE"
                value: Model.longTime(root.avgDaySeconds)
                width: (parent.width - Style.space(10)) / 2
              }

              StatCard {
                label: "FOCUS"
                value: root.focusRatio + "%"
                width: (parent.width - Style.space(10)) / 2
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

          // ---- Completed focus sessions over the selected period ----
          Column {
            width: parent.width
            spacing: Style.space(5)
            Item {
              width: parent.width
              implicitHeight: Math.max(focusHeader.implicitHeight, focusSummary.implicitHeight)
              PanelSectionHeader {
                id: focusHeader
                text: "FOCUS HISTORY"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: focusSummary
                text: root.focusHistoryTotal + " sessions · " + Model.longTime(root.focusHistoryTotal * 25 * 60)
                color: Qt.darker(root.barForeground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Text {
              visible: root.focusHistoryTotal === 0
              text: "Complete a Pomodoro focus block to start your history."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            Row {
              visible: root.focusHistoryTotal > 0
              width: parent.width
              spacing: Style.space(5)
              Repeater {
                model: root.focusHistoryList
                delegate: FocusDayBar {
                  required property var modelData
                  required property int index
                  width: (parent.width - Style.space((root.focusHistoryList.length - 1) * 5)) / root.focusHistoryList.length
                  sessions: modelData.seconds
                  maxSessions: root.focusHistoryMax
                  label: modelData.label
                  isToday: index === root.focusHistoryList.length - 1
                }
              }
            }
          }

          // ---- Top apps ----
          Column {
            visible: root.configuredTrackApps
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

            Text {
              visible: root.topAppsList.length === 0
              text: "No app time recorded today yet."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.topAppsList

              AppBar {
                required property var modelData
                required property int index
                width: parent.width
                icon: modelData.icon
                label: modelData.label
                category: root.categoryLabels[root.categoryForApp(modelData.id)]
                onCategoryClicked: root.cycleAppCategory(modelData.id)
                seconds: modelData.seconds
                maxSeconds: root.topAppsMax
                totalSeconds: root.totalAppSeconds
                accent: index === 0
              }
            }
          }

          // ---- Top apps over selected period ----
          Column {
            visible: root.configuredTrackApps
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(weekAppsHeaderLeft.implicitHeight, weekAppsHeaderRight.implicitHeight)

              PanelSectionHeader {
                id: weekAppsHeaderLeft
                text: "TOP APPS · " + root.historyRangeDays + " DAYS"
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

            Text {
              visible: root.topAppsWeekList.length > 0
              text: "TIME BY CATEGORY"
              color: Qt.darker(root.barForeground, 1.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.6
            }

            Row {
              visible: root.topAppsWeekList.length > 0
              width: parent.width
              spacing: Style.space(5)
              Repeater {
                model: ["work", "communication", "browsing", "other"]
                delegate: CategoryChip {
                  required property string modelData
                  title: root.categoryLabels[modelData]
                  value: Model.compactTime(root.categorySummary[modelData] || 0)
                }
              }
            }

            Text {
              visible: root.topAppsWeekList.length === 0
              text: "No app history in this period yet."
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.topAppsWeekList

              AppBar {
                required property var modelData
                required property int index
                width: parent.width
                icon: modelData.icon
                label: modelData.label
                category: root.categoryLabels[root.categoryForApp(modelData.id)]
                onCategoryClicked: root.cycleAppCategory(modelData.id)
                seconds: modelData.seconds
                maxSeconds: root.topAppsWeekMax
                totalSeconds: root.totalWeekAppSeconds
                accent: false
              }
            }
          }

          Text {
            visible: !root.configuredTrackApps
            text: "App insights are paused. Turn on app tracking in Settings to collect them."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
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
                ? (root.pomodoroEnabled ? "POMODORO" : (root.countdownRunning ? "IN PROGRESS" : "COUNTDOWN"))
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

          // ---- Pomodoro focus / short-break cycle ----
          Row {
            visible: root.timerTab === "countdown"
            width: parent.width
            ActionButton {
              section: "pomodoro"
              rowIndex: 0
              width: parent.width
              label: root.pomodoroEnabled ? "Stop focus cycle" : "Start Pomodoro · 25 / 5"
              primary: root.pomodoroEnabled
              onActivated: root.togglePomodoro()
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

            SettingAction {
              section: "setbreak"
              label: "Break reminders"
              valueText: root.breakRemindersEnabled ? "ON" : "OFF"
              hint: root.breakRemindersEnabled ? "click to disable" : "click to enable"
              accent: root.breakRemindersEnabled
              onActivated: root.writeOverride("breakReminders", !root.breakRemindersEnabled)
            }

            SettingStepper {
              section: "setbreakmin"
              label: "Active time between breaks"
              valueText: root.breakReminderMinutes + " min"
              detailText: "remind while active"
              onStepDown: root.writeOverride("breakReminderMinutes", Math.max(20, root.breakReminderMinutes - 10))
              onStepUp: root.writeOverride("breakReminderMinutes", Math.min(240, root.breakReminderMinutes + 10))
            }

            TextField {
              id: goalDraftField
              width: parent.width
              height: Style.space(34)
              placeholderText: "Daily limit: app:firefox=120 or category:work=240"
              selectByMouse: true
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              onTextChanged: root.goalDraft = text
              onActiveFocusChanged: root.settingsEditorActive = activeFocus
              background: BorderSurface {
                color: Style.normalFillFor(root.bar.foreground, Color.accent)
                borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                radius: Style.cornerRadius
              }
            }
            SettingAction {
              section: "setlimits"
              label: "Save app/category limit"
              valueText: "daily minutes"
              onActivated: root.setGoalFromDraft()
            }
            Repeater {
              model: root.goalRows()
              delegate: SettingAction {
                required property var modelData
                required property int index
                section: "goallimit"
                label: modelData.label
                valueText: modelData.minutes + " min/day · click to remove"
                onActivated: root.removeGoal(modelData.group, modelData.id)
              }
            }

            TextField {
              id: backupPathField
              width: parent.width
              height: Style.space(34)
              placeholderText: "Backup JSON path to restore"
              selectByMouse: true
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              onTextChanged: root.backupPathDraft = text
              onActiveFocusChanged: root.settingsEditorActive = activeFocus
              background: BorderSurface {
                color: Style.normalFillFor(root.bar.foreground, Color.accent)
                borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                radius: Style.cornerRadius
              }
            }

            SettingAction {
              section: "setbackup"
              label: "Create JSON backup"
              valueText: "history · timers · settings"
              onActivated: root.exportBackup()
            }
            SettingAction {
              section: "setrestore"
              label: root.restoreArmed ? "Confirm restore backup" : "Restore JSON backup"
              valueText: root.restoreArmed ? "current local data will be replaced" : "enter the file path above"
              dangerous: true
              onActivated: {
                if (!root.restoreArmed) root.restoreArmed = true
                else { root.restoreArmed = false; root.restoreBackup(root.backupPathDraft) }
              }
            }

            Text {
              text: "APP CATEGORIES · click a category beside an app to reassign it"
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.6
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(6)
              CategoryNameField { categoryKey: "work"; labelText: "Work"; width: (parent.width - Style.space(8)) / 2 }
              CategoryNameField { categoryKey: "communication"; labelText: "Communication"; width: (parent.width - Style.space(8)) / 2 }
              CategoryNameField { categoryKey: "browsing"; labelText: "Browsing"; width: (parent.width - Style.space(8)) / 2 }
              CategoryNameField { categoryKey: "other"; labelText: "Other"; width: (parent.width - Style.space(8)) / 2 }
            }

            SettingAction {
              section: "setexport"
              label: "Export data"
              valueText: "CSV · Downloads"
              hint: "save activity and app history"
              onActivated: root.exportCsv()
            }

            SettingAction {
              section: "setclear"
              label: root.clearHistoryArmed ? "Confirm clear history" : "Clear usage history"
              valueText: root.clearHistoryArmed ? "click again to erase tracked stats" : "remove activity, apps, focus and timeline data"
              hint: root.clearHistoryArmed ? "click to confirm" : "timer settings are kept"
              dangerous: true
              onActivated: {
                if (root.clearHistoryArmed) root.clearUsageHistory()
                else root.clearHistoryArmed = true
              }
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

          Column {
            id: reviewContent
            width: parent.width
            spacing: Style.space(12)
            visible: root.reviewPage !== ""

            Row {
              width: parent.width
              spacing: Style.space(10)
              FocusSurface {
                section: "reviewback"
                rowIndex: 0
                implicitWidth: Style.space(76)
                implicitHeight: Style.space(32)
                Text {
                  anchors.centerIn: parent
                  text: "‹ BACK"
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                onActivated: root.reviewPage = ""
              }
              Column {
                width: parent.width - Style.space(88)
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  text: root.reviewTitle()
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: root.reviewPage === "open" ? root.openToplevels + " windows currently open"
                    : root.reviewPage === "unique" ? root.uniqueApplicationRows().length + " apps recorded today"
                    : "Activity and timing for this shell session"
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: [
                  { key: "open", label: "OPEN APPS" },
                  { key: "unique", label: "UNIQUE APPS" },
                  { key: "session", label: "SESSION" }
                ]
                delegate: FocusSurface {
                  required property var modelData
                  required property int index
                  section: "reviewtabs"
                  rowIndex: index
                  implicitWidth: (parent.width - Style.space(12)) / 3
                  implicitHeight: Style.space(32)
                  current: root.reviewPage === modelData.key
                  Text {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(8)
                    text: modelData.label
                    color: root.reviewPage === modelData.key ? Color.accent : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                  }
                  onActivated: root.openReviewPage(modelData.key)
                }
              }
            }

            TextField {
              id: reviewSearchField
              visible: root.reviewPage !== "session"
              width: parent.width
              height: visible ? Style.space(34) : 0
              placeholderText: "Search apps, categories, or dates"
              selectByMouse: true
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              onTextChanged: root.reviewSearch = text
              background: BorderSurface {
                color: Style.normalFillFor(root.bar.foreground, Color.accent)
                borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                radius: Style.cornerRadius
              }
            }

            SettingAction {
              visible: root.undoRecord !== null
              section: "recordundo"
              label: "Undo deleted " + (root.undoRecord ? (root.undoRecord.kind === "app" ? "app entry" : "activity entry") : "record")
              valueText: root.undoRecord ? root.undoRecord.day : ""
              accent: true
              onActivated: root.undoDeleteRecord()
            }

            Column {
              visible: root.reviewPage === "session"
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: [
                  { label: "Shell session", value: Model.longTime(root.sessionSeconds) },
                  { label: "PC uptime", value: Model.longTime(root.pcOnSeconds) },
                  { label: "Active today · tracked + manual", value: Model.longTime(root.activeSecondsToday + root.manualSecondsToday("active")) },
                  { label: "Idle today · tracked + manual", value: Model.longTime(root.idleSecondsToday + root.manualSecondsToday("idle")) },
                  { label: "Active periods today", value: String(root.activeSessionsToday + root.manualActivityCountToday("active")) },
                  { label: "Longest active period", value: Model.longTime(root.longestActivityToday()) },
                  { label: "Focus sessions today", value: String(root.focusSessionsToday) },
                  { label: "Goal progress", value: root.goalPctText }
                ]
                delegate: Row {
                  required property var modelData
                  width: parent.width
                  Text {
                    width: parent.width * 0.58
                    text: modelData.label
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width * 0.42
                    text: modelData.value
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }

              PanelSectionHeader {
                text: "WEEKLY REPORT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }
              Repeater {
                model: [
                  { label: "Active this week", value: Model.longTime(root.weekSeconds) },
                  { label: "Daily average", value: Model.longTime(root.avgDaySeconds) },
                  { label: "Best day", value: Model.longTime(root.bestDaySeconds) },
                  { label: "Week over week", value: (root.weekCompare.deltaPct >= 0 ? "+" : "") + root.weekCompare.deltaPct + "%" }
                ]
                delegate: Row {
                  required property var modelData
                  width: parent.width
                  Text {
                    width: parent.width * 0.58
                    text: modelData.label
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    width: parent.width * 0.42
                    text: modelData.value
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }

              PanelSectionHeader {
                text: "FOCUS APP INSIGHTS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }
              Text {
                width: parent.width
                text: root.focusLog.length + " completed focus sessions · app usage is measured during each session"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: {
                  var total = {}
                  for (var i = 0; i < root.focusLog.length; i++)
                    for (var id in root.focusLog[i].apps) total[id] = (total[id] || 0) + Number(root.focusLog[i].apps[id])
                  var rows = []
                  for (var appId in total) rows.push({ id: appId, label: root.appDisplayName(appId), seconds: total[appId] })
                  rows.sort(function(a, b) { return b.seconds - a.seconds })
                  return rows.slice(0, 5)
                }
                delegate: Row {
                  required property var modelData
                  width: parent.width
                  Text {
                    width: parent.width * 0.65
                    text: modelData.label
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width * 0.35
                    text: Model.longTime(modelData.seconds)
                    color: Color.accent
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }

              Text {
                text: "RECENT ACTIVITY"
                visible: root.todayTimeline.length > 0
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
              Repeater {
                model: root.todayTimeline.slice(-8).reverse()
                delegate: Row {
                  required property var modelData
                  required property int index
                  width: parent.width
                  spacing: Style.space(8)
                  Rectangle {
                    width: Style.space(7); height: width; radius: width / 2
                    color: modelData.active ? Color.accent : Qt.darker(root.bar.foreground, 1.6)
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    width: parent.width - Style.space(55)
                    text: (modelData.active ? "Active" : "Idle") + " · "
                      + Qt.formatDateTime(new Date(modelData.start), "HH:mm") + " · "
                      + Model.longTime(Math.max(0, ((Number(modelData.end) || root.nowMs) - Number(modelData.start)) / 1000))
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  FocusSurface {
                    section: "timelineedit"
                    rowIndex: index
                    implicitWidth: Style.space(40)
                    implicitHeight: Style.space(26)
                    Text {
                      anchors.centerIn: parent
                      text: "EDIT"
                      color: Color.accent
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    onActivated: root.beginTimelineEdit(root.todayTimeline.length - 1 - index)
                  }
                }
              }

              Column {
                visible: root.timelineEditorActive
                width: parent.width
                spacing: Style.space(6)
                Text { text: "CORRECT TIMELINE · 24 HOUR TIME"; color: Color.accent; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                FocusSurface {
                  section: "timelinetype"
                  rowIndex: 0
                  implicitHeight: Style.space(30)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    text: "PERIOD TYPE · " + (root.timelineDraftActive ? "ACTIVE" : "IDLE") + "  ›"
                    color: Color.accent
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  onActivated: root.timelineDraftActive = !root.timelineDraftActive
                }
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  TextField {
                    width: (parent.width - Style.space(8)) / 2
                    height: Style.space(34)
                    text: root.timelineDraftStart
                    placeholderText: "Start HH:MM"
                    onTextChanged: root.timelineDraftStart = text
                    color: root.bar.foreground
                    background: BorderSurface { color: Style.normalFillFor(root.bar.foreground, Color.accent); borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent); radius: Style.cornerRadius }
                  }
                  TextField {
                    width: (parent.width - Style.space(8)) / 2
                    height: Style.space(34)
                    text: root.timelineDraftEnd
                    placeholderText: "End HH:MM"
                    onTextChanged: root.timelineDraftEnd = text
                    color: root.bar.foreground
                    background: BorderSurface { color: Style.normalFillFor(root.bar.foreground, Color.accent); borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent); radius: Style.cornerRadius }
                  }
                }
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  SettingAction { width: (parent.width - Style.space(8)) / 2; section: "timelinesave"; label: "Apply correction"; valueText: "recalculate totals"; onActivated: root.saveTimelineEdit() }
                  SettingAction { width: (parent.width - Style.space(8)) / 2; section: "timelinecancel"; label: "Cancel"; valueText: ""; onActivated: { root.timelineEditorActive = false; root.timelineDraftIndex = -1 } }
                }
              }

              PanelSectionHeader {
                text: "EDITABLE ACTIVITY RECORDS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }
              SettingAction {
                section: "recordaddactivity"
                label: "Add activity record"
                valueText: "Create a manual active or idle entry"
                hint: "editable history"
                onActivated: root.beginRecord("activity", null)
              }
              Repeater {
                model: root.manualActivityRecords()
                delegate: ManualRecordRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  entry: modelData
                  rowIndex: index
                  appRecord: false
                  onEditRequested: root.beginRecord("activity", entry)
                  onDeleteRequested: root.deleteManualRecord(entry.id)
                }
              }
              Text {
                visible: root.manualActivityRecords().length === 0
                text: "No manual activity records yet"
                width: parent.width
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              visible: root.reviewPage !== "session"
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.reviewPage === "open"
                  ? (root.appListRefresh >= 0 ? root.openApplicationRows().filter(function(row) { var q = root.reviewSearch.toLowerCase(); return !q || row.title.toLowerCase().indexOf(q) >= 0 || row.appId.toLowerCase().indexOf(q) >= 0 }) : [])
                  : (root.liveAppSeconds ? root.filteredUniqueApplicationRows() : [])
                delegate: Column {
                  required property var modelData
                  required property int index
                  width: parent.width
                  spacing: Style.space(3)
                  Text {
                    width: parent.width
                    text: root.reviewPage === "open" ? modelData.title : Model.appIcon(modelData.appId) + "  " + modelData.label
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Row {
                    width: parent.width
                    Text {
                      width: root.reviewPage === "open" ? parent.width - Style.space(56) : parent.width * 0.72
                      text: root.reviewPage === "open" ? modelData.appId : String(modelData.category).toUpperCase()
                      color: Qt.darker(root.bar.foreground, 1.4)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                    FocusSurface {
                      visible: root.reviewPage === "open"
                      section: "openactivate"
                      rowIndex: index
                      implicitWidth: Style.space(48)
                      implicitHeight: Style.space(26)
                      Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: parent.hasCursor ? root.selectedFill : "transparent"
                        border.color: Util.alpha(Color.accent, 0.55)
                        border.width: 1
                      }
                      Text {
                        anchors.centerIn: parent
                        text: "OPEN"
                        color: Color.accent
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      onActivated: root.activateOpenApplication(modelData.toplevel)
                    }
                    Text {
                      visible: root.reviewPage !== "open"
                      width: root.reviewPage === "open" ? 0 : parent.width * 0.28
                      text: Model.longTime(modelData.seconds)
                      color: Color.accent
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                      horizontalAlignment: Text.AlignRight
                    }
                  }
                  Row {
                    visible: root.reviewPage === "open"
                    width: parent.width
                    spacing: Style.space(8)
                    FocusSurface {
                      section: "openapprecord"
                      rowIndex: index
                      implicitWidth: Style.space(142)
                      implicitHeight: Style.space(30)
                      Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: parent.hasCursor ? root.selectedFill : Style.normalFillFor(root.bar.foreground, Color.accent)
                        border.color: Util.alpha(Color.accent, 0.45)
                        border.width: 1
                      }
                      Text {
                        anchors.centerIn: parent
                        text: "＋  ADD APP RECORD"
                        color: Color.accent
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      onActivated: root.beginAppRecord(modelData.appId)
                    }
                    Item { width: Math.max(0, parent.width - Style.space(222)); height: 1 }
                    FocusSurface {
                      section: "openappclose"
                      rowIndex: index
                      implicitWidth: Style.space(64)
                      implicitHeight: Style.space(30)
                      Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: parent.hasCursor ? root.selectedFill : "transparent"
                        border.color: Util.alpha(root.bar.foreground, 0.30)
                        border.width: 1
                      }
                      Text {
                        anchors.centerIn: parent
                        text: "CLOSE"
                        color: Qt.darker(root.bar.foreground, 1.2)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      onActivated: root.closeOpenApplication(modelData.toplevel)
                    }
                  }
                  Rectangle { width: parent.width; height: 1; color: Qt.darker(root.bar.foreground, 2.0) }
                }
              }
              Column {
                visible: root.reviewPage === "unique"
                width: parent.width
                spacing: Style.space(6)
                PanelSectionHeader {
                  text: "EDITABLE APP RECORDS"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                }
                SettingAction {
                  section: "recordaddapp"
                  label: "Add app record"
                  valueText: "Create or adjust tracked app time"
                  hint: "manual entry"
                  onActivated: root.beginRecord("app", null)
                }
                Repeater {
                model: root.filteredManualRecords("app")
                  delegate: ManualRecordRow {
                    required property var modelData
                    required property int index
                    width: parent.width
                    entry: modelData
                    rowIndex: index
                    appRecord: true
                    onEditRequested: root.beginRecord("app", entry)
                    onDeleteRequested: root.deleteManualRecord(entry.id)
                  }
                }
                Text {
                  visible: root.manualRecordsFor("app").length === 0
                  text: "No manual app records yet"
                  width: parent.width
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              Text {
                visible: root.reviewPage === "open"
                  ? root.openApplicationRows().length === 0
                  : root.uniqueApplicationRows().length === 0
                text: root.reviewPage === "open" ? "No open windows" : "No app time has been recorded today"
                width: parent.width
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
              }

            }

            Column {
              id: recordEditor
              visible: root.recordEditorKind !== ""
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: root.recordEditingId ? "EDIT RECORD" : "NEW RECORD"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              TextField {
                id: manualNameField
                visible: root.recordEditorKind === "app" || root.recordEditorKind === "activity"
                width: parent.width
                height: Style.space(34)
                text: ""
                placeholderText: root.recordEditorKind === "app" ? "Application ID" : "Note (optional)"
                selectByMouse: true
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                onTextChanged: root.recordDraftName = text
                onActiveFocusChanged: root.recordEditorActive = activeFocus
                background: BorderSurface {
                  color: Style.normalFillFor(root.bar.foreground, Color.accent)
                  borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                  radius: Style.cornerRadius
                }
              }

              TextField {
                id: manualAliasField
                visible: root.recordEditorKind === "app"
                width: parent.width
                height: Style.space(34)
                text: ""
                placeholderText: "Display name (optional alias)"
                selectByMouse: true
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                onTextChanged: root.recordDraftAlias = text
                onActiveFocusChanged: root.recordEditorActive = activeFocus
                background: BorderSurface {
                  color: Style.normalFillFor(root.bar.foreground, Color.accent)
                  borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                  radius: Style.cornerRadius
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                TextField {
                  id: manualDayField
                  width: (parent.width - Style.space(8)) * 0.58
                  height: Style.space(34)
                  text: ""
                  placeholderText: "YYYY-MM-DD"
                  selectByMouse: true
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  onTextChanged: root.recordDraftDay = text
                  onActiveFocusChanged: root.recordEditorActive = activeFocus
                  background: BorderSurface {
                    color: Style.normalFillFor(root.bar.foreground, Color.accent)
                    borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                    radius: Style.cornerRadius
                  }
                }
                TextField {
                  id: manualMinutesField
                  width: (parent.width - Style.space(8)) * 0.42
                  height: Style.space(34)
                  text: ""
                  placeholderText: "Minutes"
                  inputMethodHints: Qt.ImhDigitsOnly
                  selectByMouse: true
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  onTextChanged: root.recordDraftMinutes = text
                  onActiveFocusChanged: root.recordEditorActive = activeFocus
                  background: BorderSurface {
                    color: Style.normalFillFor(root.bar.foreground, Color.accent)
                    borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                    radius: Style.cornerRadius
                  }
                }
              }

              TextField {
                id: manualStartTimeField
                visible: root.recordEditorKind === "activity"
                width: parent.width
                height: Style.space(34)
                text: ""
                placeholderText: "Start time · HH:MM (24 hour)"
                selectByMouse: true
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                onTextChanged: root.recordDraftStartTime = text
                onActiveFocusChanged: root.recordEditorActive = activeFocus
                background: BorderSurface {
                  color: Style.normalFillFor(root.bar.foreground, Color.accent)
                  borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
                  radius: Style.cornerRadius
                }
              }

              FocusSurface {
                visible: root.recordEditorKind === "activity"
                section: "recordtype"
                rowIndex: 0
                implicitHeight: Style.space(32)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  text: "TYPE  ·  " + root.recordDraftActivity.toUpperCase() + "  ›"
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                onActivated: root.recordDraftActivity = root.recordDraftActivity === "active" ? "idle" : "active"
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                SettingAction {
                  width: (parent.width - Style.space(8)) / 2
                  section: "recordSave"
                  label: root.recordEditingId ? "Save changes" : "Create record"
                  valueText: ""
                  onActivated: root.saveManualRecord()
                }
                SettingAction {
                  width: (parent.width - Style.space(8)) / 2
                  section: "recordCancel"
                  label: "Cancel"
                  valueText: ""
                  onActivated: root.cancelRecordEdit()
                }
              }
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
    property string pageKey: ""
    property color valueColor: root.barForeground
    implicitHeight: Math.max(Style.space(44), cardColumn.implicitHeight + Style.space(12))

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: statCardMouse.containsMouse && statCard.pageKey.length > 0
        ? root.hoverFill : Style.normalFillFor(root.barForeground, Color.accent)
      borderSpec: statCardMouse.containsMouse && statCard.pageKey.length > 0
        ? Border.controlSpec("hover-cursor", root.barForeground, Color.accent)
        : Border.controlSpec("normal", root.barForeground, Color.accent)
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
        text: statCard.pageKey.length > 0 ? statCard.label + "  ›" : statCard.label
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

    MouseArea {
      id: statCardMouse
      anchors.fill: parent
      enabled: statCard.pageKey.length > 0
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.openReviewPage(statCard.pageKey)
    }
  }

  component ManualRecordRow: Item {
    id: manualRecordRow
    required property var entry
    required property int rowIndex
    required property bool appRecord
    signal editRequested()
    signal deleteRequested()
    width: parent ? parent.width : Style.space(300)
    implicitHeight: Style.space(48)

    Row {
      anchors.fill: parent
      spacing: Style.space(6)
      Column {
        width: parent.width - Style.space(116)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: manualRecordRow.appRecord ? String(manualRecordRow.entry.appId || "App")
            : (String(manualRecordRow.entry.kind || "active").toUpperCase() + " · " + String(manualRecordRow.entry.note || "Activity"))
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: String(manualRecordRow.entry.day || "") + " · " + Model.longTime(manualRecordRow.entry.seconds)
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      FocusSurface {
        section: "manualedit"
        rowIndex: manualRecordRow.rowIndex
        implicitWidth: Style.space(48)
        implicitHeight: Style.space(30)
        Text {
          anchors.centerIn: parent
          text: "EDIT"
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        onActivated: manualRecordRow.editRequested()
      }
      FocusSurface {
        section: "manualdelete"
        rowIndex: manualRecordRow.rowIndex
        implicitWidth: Style.space(54)
        implicitHeight: Style.space(30)
        Text {
          anchors.centerIn: parent
          text: "DELETE"
          color: Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        onActivated: manualRecordRow.deleteRequested()
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
    property string category: "Other"
    signal categoryClicked()
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
          width: parent.width - Style.space(24 + 96 + 48 + 64 + 32)
        }

        Text {
          id: appCategoryText
          textFormat: Text.PlainText
          text: appBar.category
          color: Qt.darker(root.barForeground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(96)
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignRight

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: appBar.categoryClicked()
          }
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
          width: Style.space(48)
          horizontalAlignment: Text.AlignRight
        }

        Text {
          textFormat: Text.PlainText
          text: Model.longTime(appBar.seconds)
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(64)
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

  component RangeChip: Item {
    id: rangeChip
    required property int days
    required property bool selected
    signal activated()
    width: Style.space(48)
    height: Style.space(26)
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: rangeChip.selected ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.barForeground, 0.07)
      border.color: rangeChip.selected ? Color.accent : Util.alpha(root.barForeground, 0.2)
      border.width: 1
    }
    Text {
      anchors.centerIn: parent
      text: rangeChip.days + "d"
      color: rangeChip.selected ? Color.accent : root.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: rangeChip.selected
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: rangeChip.activated()
    }
  }

  component CategoryChip: Item {
    id: categoryChip
    required property string title
    required property string value
    width: parent ? (parent.width - Style.space(15)) / 4 : Style.space(80)
    implicitHeight: Style.space(38)
    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(root.barForeground, 0.045)
      borderSpec: Border.controlSpec("normal", root.barForeground, Color.accent)
    }
    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(10)
      spacing: Style.space(1)
      Text {
        width: parent.width
        text: categoryChip.title.toUpperCase()
        color: Qt.darker(root.barForeground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: categoryChip.value
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }

  component FocusDayBar: Item {
    id: focusDayBar
    required property double sessions
    required property double maxSessions
    required property string label
    required property bool isToday
    implicitHeight: focusDayColumn.implicitHeight
    Column {
      id: focusDayColumn
      anchors.fill: parent
      spacing: Style.space(3)
      Text {
        width: parent.width
        text: focusDayBar.sessions > 0 ? String(Math.round(focusDayBar.sessions)) : ""
        color: focusDayBar.isToday ? Color.accent : Qt.darker(root.barForeground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
      Rectangle {
        width: parent.width
        height: Style.space(28)
        radius: Style.cornerRadius
        color: Util.alpha(root.barForeground, 0.08)
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: focusDayBar.sessions > 0 ? Math.max(Style.space(3), (parent.height - Style.space(3)) * focusDayBar.sessions / Math.max(1, focusDayBar.maxSessions)) : 0
          color: focusDayBar.isToday ? Color.accent : Util.alpha(root.barForeground, 0.48)
          radius: Style.cornerRadius
        }
      }
      Text {
        width: parent.width
        text: focusDayBar.label
        color: focusDayBar.isToday ? Color.accent : Qt.darker(root.barForeground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
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

  component CategoryNameField: Item {
    id: categoryNameField
    required property string categoryKey
    required property string labelText
    implicitHeight: Style.space(50)
    Column {
      anchors.fill: parent
      spacing: Style.space(3)
      Text {
        width: parent.width
        text: categoryNameField.labelText
        color: Qt.darker(root.barForeground, 1.35)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
      TextField {
        id: categoryNameInput
        width: parent.width
        height: Style.space(30)
        text: root.categoryLabels[categoryNameField.categoryKey]
        selectByMouse: true
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        onActiveFocusChanged: root.categoryEditorActive = activeFocus
        onEditingFinished: {
          root.setCategoryLabel(categoryNameField.categoryKey, text)
          focus = false
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
