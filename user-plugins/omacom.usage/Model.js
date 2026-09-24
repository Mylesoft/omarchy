// Formatting and calendar helpers for the usage & timer plugin.

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// Countdown-style clock: "MM:SS" up to an hour, "H:MM:SS" beyond.
function timerText(totalSeconds) {
  var s = Math.max(0, Math.floor(Number(totalSeconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var ss = s % 60
  if (h > 0) return h + ":" + pad2(m) + ":" + pad2(ss)
  return pad2(m) + ":" + pad2(ss)
}

// Stopwatch-style clock: seconds always visible.
function stopwatchText(totalSeconds) {
  var s = Math.max(0, Math.floor(Number(totalSeconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var ss = s % 60
  return (h > 0 ? h + ":" : "") + pad2(m) + ":" + pad2(ss)
}

// "2h / 3h04m / 12m / 45s" — compact bar text for durations.
function compactTime(totalSeconds) {
  var s = Math.max(0, Math.floor(Number(totalSeconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.round((s % 3600) / 60)
  if (h > 0) return m > 0 ? h + "h" + pad2(m) : h + "h"
  if (m > 0) return m + "m"
  return Math.max(1, s) + "s"
}

// "2h 04m / 12m 30s / 45s" — descriptive duration.
function longTime(totalSeconds) {
  var s = Math.max(0, Math.floor(Number(totalSeconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var parts = []
  if (h > 0) parts.push(h + "h")
  if (m > 0) parts.push(m + "m")
  var ss = s % 60
  if (parts.length === 0) parts.push(ss + "s")
  return parts.join(" ")
}

// Local HH:MM for a millisecond timestamp, e.g. "14:32".
function clockTime(ms) {
  if (!(ms > 0)) return "--:--"
  var d = new Date(ms)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function dayKey(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function parseKey(key) {
  var parts = String(key || "").split("-")
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
}

function dayLabel(key) {
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parseKey(key).getDay()]
}

function fullDayLabel(key) {
  var d = parseKey(key)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return dayLabel(key) + " " + d.getDate() + " " + months[d.getMonth()]
}

// Fold the accumulator for prevKey into the day map, dropping any stale entry
// for that key first.
function rollover(days, prevKey, prevSeconds) {
  var next = {}
  for (var k in days) {
    if (days.hasOwnProperty(k) && k !== prevKey) next[k] = days[k]
  }
  if (prevSeconds > 0) next[prevKey] = prevSeconds
  return next
}

function pruneDays(days, keep) {
  var keys = Object.keys(days).sort()
  if (keys.length <= keep) return days
  var next = {}
  for (var i = keys.length - keep; i < keys.length; i++) next[keys[i]] = days[keys[i]]
  return next
}

// Last `count` days oldest→newest, today last, with the live accumulator for
// today folded in.
function history(days, todayKey, todaySeconds, count) {
  var out = []
  var base = new Date()
  for (var i = count - 1; i >= 0; i--) {
    var d = new Date(base.getFullYear(), base.getMonth(), base.getDate() - i)
    var key = dayKey(d)
    var seconds = 0
    if (key === todayKey) seconds = todaySeconds
    else if (days && days[key]) seconds = days[key]
    out.push({ key: key, label: count > 14 ? String(d.getDate()) : dayLabel(key), seconds: seconds })
  }
  return out
}

function weekTotal(entries) {
  var total = 0
  for (var i = 0; i < entries.length; i++) total += entries[i].seconds
  return total
}

// ---------------------------------------------------------------------------
// App tracking helpers
// ---------------------------------------------------------------------------

function humanize(s) {
  s = String(s || "").replace(/[-_]+/g, " ")
  if (!s) return ""
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function appLabel(appId) {
  var id = String(appId || "")
  var chrome = id.match(/^chrome-(.*?)--Default$/)
  if (chrome) return humanize(chrome[1]).replace(/^Youtube$/, "YouTube")
  var known = {
    "ai.opencode.desktop": "OpenCode",
    "chatgpt": "ChatGPT",
    "com.anthropic.Claude": "Claude",
    "cursor": "Cursor",
    "devin-desktop": "Devin",
    "omawrite": "Omawrite",
    "org.omarchy.agent": "Omarchy Agent",
    "brave-browser": "Brave",
    "firefox": "Firefox",
    "org.gnome.Nautilus": "Files",
    "dolphin": "Files",
    "code": "VS Code",
    "visual-studio-code": "VS Code",
    "foot": "Terminal",
    "kitty": "Terminal",
    "wezterm": "Terminal",
    "alacritty": "Terminal",
    "org.signal.Signal": "Signal"
  }
  if (known[id]) return known[id]
  return humanize(id.split(".").pop())
}

function appIcon(appId) {
  var id = String(appId || "").toLowerCase()
  if (id === "ai.opencode.desktop" || id === "chatgpt" || id === "com.anthropic.Claude"
    || id === "devin-desktop" || id === "omawrite" || id === "org.omarchy.agent"
    || id.indexOf("manus") >= 0) return "󰢌"
  if (id === "cursor" || id === "code" || id === "visual-studio-code" || id === "codium"
    || id.indexOf("jetbrains") >= 0 || id === "vim" || id === "neovim") return "󰄬"
  if (id === "foot" || id === "kitty" || id === "alacritty" || id === "wezterm"
    || id.indexOf("terminal") >= 0 || id === "org.codeberg.dnkl.foot") return "󰊠"
  if (id === "brave-browser" || id === "firefox" || id === "zen" || id === "org.mozilla.firefox"
    || id.indexOf("chrome") === 0 || id.indexOf("chromium") === 0) return "󰖟"
  if (id.indexOf("discord") >= 0 || id.indexOf("signal") >= 0 || id.indexOf("telegram") >= 0
    || id.indexOf("whatsapp") >= 0) return "󰇩"
  if (id.indexOf("nautilus") >= 0 || id.indexOf("dolphin") >= 0 || id.indexOf("thunar") >= 0
    || id.indexOf("thunar") >= 0) return "󰉑"
  if (id.indexOf("spotify") >= 0 || id.indexOf("vlc") >= 0) return "󰝚"
  return "󰂯"
}

// Sort appId -> seconds map into a top-apps list (highest first).
function topApps(appSeconds, count) {
  var out = []
  var max = Math.max(1, Number(count) || 5)
  for (var id in appSeconds) {
    if (!appSeconds.hasOwnProperty(id)) continue
    var s = Number(appSeconds[id]) || 0
    if (s <= 0) continue
    out.push({ id: id, label: appLabel(id), icon: appIcon(id), seconds: s })
  }
  out.sort(function(a, b) { return b.seconds - a.seconds })
  return out.slice(0, max)
}


// Default app grouping; per-app assignments can override these categories.
function appCategory(appId) {
  var id = String(appId || "").toLowerCase()
  if (id.indexOf("chrome") === 0 || id.indexOf("chromium") === 0 || id.indexOf("firefox") >= 0
    || id.indexOf("brave") >= 0 || id.indexOf("browser") >= 0 || id === "zen") return "browsing"
  if (id.indexOf("signal") >= 0 || id.indexOf("discord") >= 0 || id.indexOf("telegram") >= 0
    || id.indexOf("whatsapp") >= 0 || id.indexOf("slack") >= 0 || id.indexOf("teams") >= 0) return "communication"
  if (id.indexOf("code") >= 0 || id.indexOf("cursor") >= 0 || id.indexOf("jetbrains") >= 0
    || id.indexOf("terminal") >= 0 || id === "foot" || id === "kitty" || id === "alacritty"
    || id.indexOf("opencode") >= 0 || id.indexOf("claude") >= 0) return "work"
  return "other"
}

function topAppsMax(entries) {
  var m = 1
  for (var i = 0; i < entries.length; i++) m = Math.max(m, entries[i].seconds)
  return Math.max(1, m)
}

// Fold the app-seconds accumulator for prevKey into the per-day map.
function rolloverApps(appDays, prevKey, prevApps) {
  var next = {}
  for (var k in appDays) {
    if (!appDays.hasOwnProperty(k) || k === prevKey) continue
    next[k] = appDays[k]
  }
  if (prevApps && typeof prevApps === "object") {
    var kept = {}
    for (var id in prevApps) {
      if (prevApps.hasOwnProperty(id) && Number(prevApps[id]) > 0) kept[id] = prevApps[id]
    }
    if (Object.keys(kept).length > 0) next[prevKey] = kept
  }
  return next
}

function pruneApps(appDays, keep) {
  var keys = Object.keys(appDays).sort()
  if (keys.length <= keep) return appDays
  var next = {}
  for (var i = keys.length - keep; i < keys.length; i++) next[keys[i]] = appDays[keys[i]]
  return next
}

// ---------------------------------------------------------------------------
// Analytics helpers
// ---------------------------------------------------------------------------

// Fraction of the day elapsed (0..1) at a given timestamp.
function dayFraction(ms) {
  var d = new Date(ms || Date.now())
  var mins = d.getHours() * 60 + d.getMinutes()
  return Math.min(0.9999, Math.max(0, mins / 1440))
}

// Consecutive days (ending today) that met or exceeded the goal.
function streak(days, todayKey, todaySeconds, goalSeconds) {
  var streakCount = 0
  var base = new Date()
  if (Number(todaySeconds) >= Number(goalSeconds)) streakCount = 1
  for (var i = 1; i <= 366; i++) {
    var d = new Date(base.getFullYear(), base.getMonth(), base.getDate() - i)
    var key = dayKey(d)
    var secs = days && days[key] ? Number(days[key]) || 0 : 0
    if (secs >= Number(goalSeconds)) streakCount++
    else break
  }
  return streakCount
}

// Highest single-day active seconds across the stored days (incl. today).
function bestDay(days, todayKey, todaySeconds) {
  var best = 0
  for (var k in days) {
    if (!days.hasOwnProperty(k)) continue
    best = Math.max(best, Number(days[k]) || 0)
  }
  return Math.max(best, Number(todaySeconds) || 0)
}

// Average active seconds per day over the trailing `count` days.
function averageDay(days, todayKey, todaySeconds, count) {
  var total = 0
  var n = 0
  var base = new Date()
  for (var i = 0; i < count; i++) {
    var d = new Date(base.getFullYear(), base.getMonth(), base.getDate() - i)
    var key = dayKey(d)
    total += key === todayKey ? Number(todaySeconds) || 0 : (days && days[key] ? Number(days[key]) || 0 : 0)
    n++
  }
  return n > 0 ? total / n : 0
}

// Active seconds this week vs the previous 7 days.
function weekCompare(days, todayKey, todaySeconds) {
  var base = new Date()
  var thisWeek = 0
  var lastWeek = 0
  for (var i = 0; i < 7; i++) {
    var dd = new Date(base.getFullYear(), base.getMonth(), base.getDate() - i)
    var key = dayKey(dd)
    thisWeek += key === todayKey ? Number(todaySeconds) || 0 : (days && days[key] ? Number(days[key]) || 0 : 0)
    var pd = new Date(base.getFullYear(), base.getMonth(), base.getDate() - (i + 7))
    var pkey = dayKey(pd)
    lastWeek += days && days[pkey] ? Number(days[pkey]) || 0 : 0
  }
  var deltaPct = lastWeek > 0 ? Math.round(((thisWeek - lastWeek) / lastWeek) * 100) : (thisWeek > 0 ? 100 : 0)
  return { thisWeek: thisWeek, lastWeek: lastWeek, deltaPct: deltaPct }
}

// Estimated wall-clock time the daily goal will be reached, if on pace.
function goalEta(activeToday, goalSeconds, nowMs) {
  if (Number(activeToday) >= Number(goalSeconds)) return "done"
  var frac = dayFraction(nowMs)
  if (frac <= 0.05 || Number(activeToday) <= 0) return ""
  var pacePerHour = Number(activeToday) / frac
  if (!(pacePerHour > 0) || !isFinite(pacePerHour)) return ""
  var missing = Number(goalSeconds) - Number(activeToday)
  var etaMs = nowMs + (missing / pacePerHour) * 3600 * 1000
  var d = new Date(etaMs)
  if (d.getDate() !== new Date(nowMs).getDate()) return "tomorrow"
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// Aggregate per-app seconds across a selected trailing range and today's accumulator.
function topAppsAcross(appDays, appSeconds, todayKey, count, rangeDays) {
  var agg = {}
  var today = parseKey(todayKey)
  if (!isFinite(today.getTime())) today = new Date()
  var span = Math.max(1, Math.min(30, Number(rangeDays) || 7))
  var cutoff = dayKey(new Date(today.getFullYear(), today.getMonth(), today.getDate() - span + 1))
  for (var dk in appDays) {
    if (!appDays.hasOwnProperty(dk) || dk < cutoff || dk >= todayKey) continue
    var day = appDays[dk]
    if (!day || typeof day !== "object") continue
    for (var id in day) {
      if (!day.hasOwnProperty(id)) continue
      agg[id] = (agg[id] || 0) + (Number(day[id]) || 0)
    }
  }
  for (var id2 in appSeconds) {
    if (!appSeconds.hasOwnProperty(id2)) continue
    agg[id2] = (agg[id2] || 0) + (Number(appSeconds[id2]) || 0)
  }
  return topApps(agg, count)
}

var HOUR_ICONS = ['\uE251','\uE252','\uE253','\uE254','\uE255','\uE256','\uE257','\uE258','\uE259','\uE25A','\uE25B','\uE25C','\uE25D','\uE25E','\uE25F','\uE260','\uE261','\uE262','\uE263','\uE264','\uE265','\uE266','\uE267','\uE268']

// Often used to label the busiest hour: "14".
function hourLabel(h) {
  return pad2(h) + ":00"
}

// The hour with the most recorded active seconds (or -1 if none).
function busiestHour(hourSeconds) {
  var best = -1
  var bestS = 0
  for (var h in hourSeconds) {
    if (!hourSeconds.hasOwnProperty(h)) continue
    var s = Number(hourSeconds[h]) || 0
    if (s > bestS) { bestS = s; best = Number(h) }
  }
  return best
}

// 24 hour buckets {hour, label, seconds, isNow} oldest->now, plus the max.
function hourList(hourSeconds, nowMs) {
  var out = []
  var max = 1
  var nowH = new Date(nowMs || Date.now()).getHours()
  var first = Math.max(0, nowH - 12)
  for (var h = first; h <= nowH; h++) {
    var secs = hourSeconds && hourSeconds[h] !== undefined ? Number(hourSeconds[h]) || 0 : 0
    if (secs > 0 && secs > max) max = secs
    out.push({ hour: h, label: String(h), seconds: secs, isNow: h === nowH })
  }
  return { entries: out, max: Math.max(max, 1) }
}