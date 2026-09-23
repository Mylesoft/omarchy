import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  // overview = ranked fleet list; detail = full analytics for one agent
  property string viewMode: "overview" // overview | detail
  // Ranking key for the overview list
  property string sortMode: "tokens" // tokens | today | prompts | sessions
  property int overviewCursor: 0

  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  readonly property var rankedProviders: {
    var rev = usage.dataRevision
    var list = []
    for (var i = 0; i < providers.length; i++)
      list.push(enrichProvider(providers[i]))
    var mode = sortMode
    list.sort(function(a, b) {
      var av = sortValue(a, mode)
      var bv = sortValue(b, mode)
      if (bv !== av) return bv - av
      return String(a.providerName).localeCompare(String(b.providerName))
    })
    return list
  }

  readonly property real maxProviderTokens: {
    var maximum = 0
    for (var i = 0; i < rankedProviders.length; i++)
      maximum = Math.max(maximum, Number(rankedProviders[i].allTimeTokens || 0))
    return maximum
  }
  readonly property string barTooltip: {
    if (rankedProviders.length === 0) return "Agents"
    return "Agents · provider windows differ; token sources may overlap"
  }

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function openOverview() {
    viewMode = "overview"
    cursorActive = true
    if (panelFlick) panelFlick.contentY = 0
  }

  function openDetail(providerId) {
    if (!providerId) return
    selectedProviderId = providerId
    viewMode = "detail"
    cursorActive = true
    if (panelFlick) panelFlick.contentY = 0
  }

  function openDetailAtCursor() {
    if (rankedProviders.length === 0) return
    var i = ((overviewCursor % rankedProviders.length) + rankedProviders.length) % rankedProviders.length
    openDetail(rankedProviders[i].providerId)
  }

  function moveOverviewCursor(delta) {
    if (rankedProviders.length === 0) return
    overviewCursor = ((overviewCursor + delta) % rankedProviders.length + rankedProviders.length) % rankedProviders.length
    cursorActive = true
  }

  function setSortMode(mode) {
    sortMode = mode
    overviewCursor = 0
  }

  function tokensFromModelUsage(usageByModel) {
    var total = 0
    var map = usageByModel || {}
    for (var id in map) {
      var bucket = map[id] || {}
      total += Number(bucket.inputTokens || 0)
        + Number(bucket.outputTokens || 0)
        + Number(bucket.cacheReadInputTokens || 0)
        + Number(bucket.cacheCreationInputTokens || 0)
    }
    return total
  }

  function enrichProvider(p) {
    if (!p) return null
    var allTime = tokensFromModelUsage(p.modelUsage)
    if (!(allTime > 0)) allTime = weekTotal(p)
    if (!(allTime > 0)) allTime = Number(p.todayTotalTokens || 0)
    var todayTok = Number(p.todayTotalTokens || 0)
    var weekTok = weekTotal(p)
    var weekAvg = weekTok / 7
    var pace = weekAvg > 0 ? (todayTok / weekAvg) : (todayTok > 0 ? 2 : 0)
    var topModel = ""
    var rows = modelRows(p)
    if (rows.length > 0) topModel = rows[0].name
    return {
      providerId: p.providerId,
      providerName: p.providerName,
      ready: p.ready,
      launchable: p.launchable !== false,
      usageStatusText: p.usageStatusText,
      authHelpText: p.authHelpText,
      tierLabel: p.tierLabel,
      balance: p.balance,
      limits: p.limits,
      allTimeTokens: allTime,
      todayTokens: todayTok,
      weekTokens: weekTok,
      totalPrompts: Number(p.totalPrompts || 0),
      totalSessions: Number(p.totalSessions || 0),
      todayPrompts: Number(p.todayPrompts || 0),
      hasPromptStats: p.hasPromptStats !== false,
      providerIDs: Array.isArray(p.providerIDs) ? p.providerIDs : [],
      activeDays: Number(p.activeDays || 0),
      pace: pace,
      topModel: topModel,
      raw: p
    }
  }

  function sortValue(row, mode) {
    if (mode === "today") return Number(row.todayTokens || 0)
    if (mode === "prompts") return Number(row.totalPrompts || 0)
    if (mode === "sessions") return Number(row.totalSessions || 0)
    return Number(row.allTimeTokens || 0)
  }

  function messageMetricLabel(p) {
    if (!p) return "recorded messages"
    if (p.providerId === "codex") return "model turns"
    if (p.providerId === "opencode") return "assistant messages"
    if (p.providerId === "claude") return "usage messages"
    if (p.providerId === "fireworks") return "provider messages"
    return "reported messages"
  }

  function providerScopeText(p) {
    if (!p) return ""
    if (p.providerId === "opencode") {
      var ids = Array.isArray(p.providerIDs) ? p.providerIDs : []
      var providersText = ids.length > 0 ? ids.join(", ") : "all configured providers"
      return "OpenCode local database · all providers (" + providersText + ") · cumulative processing volume includes cached and repeated context · not account billing"
    }
    if (p.providerId === "codex")
      return "Codex native sessions touched within 30 days plus retained Pi/OMP sessions routed to Codex · cache is separated from uncached input; repeated context counts on each turn"
    if (p.providerId === "claude")
      return "Available Claude transcripts and local integrations · history depends on files retained on this machine"
    if (p.providerId === "fireworks")
      return "Fireworks account usage · last 30 days · account scope"
    return trackedWindowLabel(p)
  }

  function providerScopeShort(p) {
    if (!p) return "local usage"
    if (p.providerId === "opencode") return "OpenCode · all providers"
    if (p.providerId === "codex") return "Codex + Pi/OMP"
    if (p.providerId === "claude") return "Claude local history"
    if (p.providerId === "fireworks") return "Fireworks · 30 days"
    return "local usage"
  }

  function sortLabel(mode) {
    if (mode === "today") return "Today tokens"
    if (mode === "prompts") return "Messages"
    if (mode === "sessions") return "Sessions"
    return "Tracked tokens"
  }

  function hasRecordedUsage(p) {
    if (!p) return false
    return tokensFromModelUsage(p.modelUsage) > 0 || Number(p.todayTotalTokens || 0) > 0
      || Number(p.totalPrompts || 0) > 0 || Number(p.totalSessions || 0) > 0
      || (Array.isArray(p.limits) && p.limits.length > 0) || !!p.balance
  }

  function emptyUsageMessage(p) {
    if (!p) return ""
    var status = String(p.usageStatusText || "")
    if (/auth|credential|sign.?in|unavailable|connect/i.test(status))
      return status + ". Check this agent’s sign-in or connection, then refresh."
    if (status.toLowerCase().indexOf("no usage") >= 0 || status.toLowerCase().indexOf("no usage data") >= 0)
      return "Installed, but no local usage has been found yet. Launch the agent, send a request, then refresh."
    return "No provider usage messages were found in local history. Launch the agent, send a request, then refresh."
  }

  function exactCount(value) {
    var n = Math.max(0, Math.floor(Number(value) || 0))
    return n.toLocaleString()
  }

  function trackedWindowLabel(p) {
    if (!p) return ""
    if (p.providerId === "codex" || p.providerId === "fireworks")
      return "Tracked window · last 30 days"
    if (p.providerId === "opencode")
      return "Tracked window · local OpenCode database"
    if (p.providerId === "claude")
      return "Tracked window · available local history"
    return "Tracked window · local history available to this collector"
  }

  function paceLabel(pace) {
    if (pace >= 1.5) return "Hot"
    if (pace >= 0.85) return "On pace"
    if (pace > 0) return "Quiet"
    return "Idle"
  }

  function paceColor(pace) {
    if (pace >= 1.5) return urgent
    if (pace >= 0.85) return foreground
    return dim
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  function launchProvider(providerId) {
    var id = String(providerId || "")
    if (!id || id === "fireworks") {
      launchAgent()
      return
    }
    // Plugin-local launcher mirrors omarchy-agent flags without changing the
    // user's default agent.
    var script = Qt.resolvedUrl("launch-agent.sh").toString().replace(/^file:\/\//, "")
    if (root.bar) root.bar.run("bash " + Util.shellQuote(script) + " " + Util.shellQuote(id))
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    // The OpenCode record has no subscription plan and no rate-limit windows,
    // so the hero line carries the day's numbers instead of a tier.
    if (p.providerId === "opencode") {
      var msgs = Number(p.todayPrompts || 0)
      var tok = Number(p.todayTotalTokens || 0)
      if (msgs > 0 || tok > 0) {
        return "Today · " + exactCount(msgs) + " " + messageMetricLabel(p) + " · "
          + usage.formatTokenCount(tok) + " tokens"
      }
      return "Local usage · no rate limits"
    }
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTokenCount(day) {
    if (!day) return 0
    var explicit = day.tokens !== undefined && day.tokens !== null
    return Number(explicit ? day.tokens : (day.messageCount || 0))
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(root.dayTokenCount(day)) + " tokens"
    // Collector fields are provider messages or model turns, never a promise
    // that this number equals user-entered prompts.
    var providerMessages = day.providerMessages !== undefined && day.providerMessages !== null
      ? day.providerMessages : (day.prompts !== undefined && day.prompts !== null ? day.prompts : null)
    if (providerMessages !== null)
      text += " · " + exactCount(providerMessages) + " " + messageMetricLabel(provider)
    else if (today && provider && provider.hasPromptStats !== false)
      text += " · " + exactCount(provider.todayPrompts) + " " + messageMetricLabel(provider)
        + " · " + exactCount(provider.todaySessions) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, root.dayTokenCount(days[i]))
    return peak
  }

  function weekTotal(p) {
    var days = p ? (p.recentDays || []) : []
    var total = 0
    for (var i = 0; i < days.length; i++) total += root.dayTokenCount(days[i])
    return total
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        model: id,
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite,
        cost: root.estCost(input, output, cacheRead, cacheWrite, root.costRatesFor(id))
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 10)
  }

  function modelTooltip(row) {
    if (!row) return ""
    var text = "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
    if (row.cost > 0) text += " · ≈ " + root.formatCost(row.cost)
    return text
  }

  // ---------------------------------------------------------------- today

  // One compact summary of the day so far, fed by the opencode record's
  // today* fields and its per-hour activity strip.
  readonly property var today: todayModel(provider)

  function todayModel(p) {
    if (!p) return null
    var prompts = Number(p.todayPrompts || 0)
    var sessions = Number(p.todaySessions || 0)
    var tokens = Number(p.todayTotalTokens || 0)
    // todayTokensByModel only keeps a rolling token total per model, so cost
    // uses each model's blended input/output rate rather than a real split.
    var cost = 0
    var byModel = p.todayTokensByModel || {}
    for (var model in byModel) {
      if (!byModel.hasOwnProperty(model)) continue
      cost += root.estCostFor(model, Number(byModel[model]) || 0)
    }
    var hoursList = []
    var peak = 1
    var hours = p.todayHourActivity || []
    for (var i = 0; i < hours.length; i++) {
      var h = hours[i] || {}
      var count = Number(h.count || 0)
      peak = Math.max(peak, count)
      hoursList.push({ hour: h.hour, label: h.label || "", count: count, tokens: Number(h.tokens || 0) })
    }
    // Compare only days the collector actually reported. Missing dates can
    // mean unavailable history, so they must not silently become zero days.
    var priorDays = []
    var recent = p.recentDays || []
    var todayKey = root.todayDate()
    for (var j = 0; j < recent.length; j++) {
      var day = recent[j] || {}
      var date = String(day.date || "")
      var hasTokenTotal = day.tokens !== undefined && day.tokens !== null
      if (date !== "" && date < todayKey && hasTokenTotal)
        priorDays.push({ date: date, tokens: Number(day.tokens) || 0 })
    }
    priorDays.sort(function(a, b) { return b.date.localeCompare(a.date) })
    priorDays = priorDays.slice(0, 7)
    var priorTotal = 0
    for (var k = 0; k < priorDays.length; k++) priorTotal += priorDays[k].tokens
    var priorAverage = priorDays.length > 0 ? priorTotal / priorDays.length : 0
    return {
      prompts: prompts,
      sessions: sessions,
      tokens: tokens,
      cost: cost,
      hours: hoursList,
      peak: peak,
      priorAverageTokens: priorAverage,
      priorDaysCount: priorDays.length,
      hasActivity: prompts > 0 || tokens > 0 || hoursList.length > 0
    }
  }

  function todayTrendText(t) {
    if (!t || t.priorDaysCount < 2) return ""
    if (!(t.priorAverageTokens > 0))
      return "No tokens on the previous " + t.priorDaysCount + " recorded days"
    var delta = Math.round((t.tokens / t.priorAverageTokens - 1) * 100)
    var direction = delta > 0 ? "above" : (delta < 0 ? "below" : "at")
    return Math.abs(delta) + "% " + direction + " the average of the previous "
      + t.priorDaysCount + " recorded days"
  }

  function copyUsageSummary() {
    var p = root.provider
    if (!p) return
    var tracked = root.tokensFromModelUsage(p.modelUsage)
    if (!(tracked > 0)) tracked = root.weekTotal(p)
    if (!(tracked > 0)) tracked = Number(p.todayTotalTokens || 0)
    var lines = [
      p.providerName + " usage summary",
      "Scope: " + root.providerScopeText(p),
      "Tracked tokens: " + root.exactCount(tracked),
      "Today: " + root.exactCount(p.todayTotalTokens) + " tokens",
      "Messages: " + root.exactCount(p.totalPrompts) + " " + root.messageMetricLabel(p),
      "Sessions: " + root.exactCount(p.totalSessions)
    ]
    if (root.today && root.today.cost > 0)
      lines.push("Estimated rate value today: " + root.formatCost(root.today.cost) + " (not billing)")
    root.bar.run("bash -lc " + Util.shellQuote("printf %s " + Util.shellQuote(lines.join("\n")) + " | wl-copy"))
  }

  // Per-model cost rates, USD per 1M tokens. A setting override wins; then a
  // small built-in table for recognizable models; then template defaults. The
  // panel labels every figure as an estimate, because these rates are rules
  // of thumb, not a billing ledger.
  function costRatesFor(model) {
    var userRates = root.settings && root.settings.costRates
    if (userRates && typeof userRates === "object") {
      var modelKey = String(model || "").toLowerCase()
      for (var key in userRates) {
        if (userRates.hasOwnProperty(key) && modelKey.indexOf(String(key).toLowerCase()) >= 0
          && userRates[key] && typeof userRates[key] === "object")
          return root.sanitizeCostRates(userRates[key])
      }
    }
    var table = {
      "big-pickle": { input: 5, output: 20, cacheRead: 0.5, cacheWrite: 6 },
      "claude-sonnet": { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
      "claude-opus": { input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75 },
      "claude-haiku": { input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25 },
      "gpt-5": { input: 2.5, output: 10, cacheRead: 0.5, cacheWrite: 0.5 },
      "gpt-4": { input: 2.5, output: 10, cacheRead: 0.5, cacheWrite: 0.5 },
      "gemini": { input: 1.25, output: 10, cacheRead: 0.25, cacheWrite: 0.25 }
    }
    var key2 = String(model || "").toLowerCase()
    for (var name in table) {
      if (table.hasOwnProperty(name) && key2.indexOf(name) >= 0) return table[name]
    }
    return { input: 2.5, output: 10, cacheRead: 0.3, cacheWrite: 3.75 }
  }

  function sanitizeCostRates(raw) {
    var input = Number(raw.input)
    var output = Number(raw.output)
    var cacheRead = Number(raw.cacheRead)
    var cacheWrite = Number(raw.cacheWrite)
    return {
      input: isFinite(input) && input >= 0 ? input : 0,
      output: isFinite(output) && output >= 0 ? output : 0,
      cacheRead: isFinite(cacheRead) && cacheRead >= 0 ? cacheRead : 0,
      cacheWrite: isFinite(cacheWrite) && cacheWrite >= 0 ? cacheWrite : 0
    }
  }

  function estCost(input, output, cacheRead, cacheWrite, rates) {
    var r = rates || {}
    return (Number(input) / 1e6) * Number(r.input || 0)
      + (Number(output) / 1e6) * Number(r.output || 0)
      + (Number(cacheRead) / 1e6) * Number(r.cacheRead || 0)
      + (Number(cacheWrite) / 1e6) * Number(r.cacheWrite || 0)
  }

  function estCostFor(model, totalTokens) {
    // A single token total with no input/output split approximates cost with
    // the model's blended rate: input + output halves of the table.
    var r = costRatesFor(model)
    var blended = ((r.input || 0) + (r.output || 0)) / 2
    return (Number(totalTokens) / 1e6) * blended
  }

  function formatCost(amount) {
    var value = Number(amount) || 0
    if (value >= 1000) return "$" + (value / 1000).toFixed(1) + "k"
    return "$" + value.toFixed(2)
  }

  // All-time estimated spend across the recorded model usage.
  readonly property real estimatedAllTimeCost: {
    var total = 0
    var rows = root.models
    for (var i = 0; i < rows.length; i++) total += rows[i].cost
    return total
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    var sync = ""
    if (usage.syncStatusText !== "") sync = usage.syncStatusText
    else if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      sync = "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    if (viewMode === "detail") return "←/→ or h/l or [/] switch agents · ↑/↓ scroll · r refresh · Esc back" + (sync ? " · " + sync : "")
    return sync
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    viewMode = "overview"
    overviewCursor = 0
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    tooltipText: root.barTooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) {
        if (root.rankedProviders.length > 0) {
          root.overviewCursor = (root.overviewCursor + 1) % root.rankedProviders.length
          root.openDetail(root.rankedProviders[root.overviewCursor].providerId)
          if (!root.opened) root.open()
        }
      } else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Taller than the control panels on purpose: this one is a dashboard, and
    // the whole point is reading limits and history without scrolling.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (root.viewMode === "overview") {
          if (dy !== 0) root.moveOverviewCursor(dy)
          else if (dx !== 0) root.moveOverviewCursor(dx)
          return
        }
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: {
        if (root.viewMode === "overview") root.openDetailAtCursor()
        else root.refreshNow()
      }
      onCloseRequested: {
        if (root.viewMode === "detail") root.openOverview()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "b" || t === "B") root.openOverview()
        else if (t === "1") root.setSortMode("tokens")
        else if (t === "2") root.setSortMode("today")
        else if (t === "3") root.setSortMode("prompts")
        else if (t === "4") root.setSortMode("sessions")
        else if (t === "[" || t === "h" || t === "H") root.selectProvider(root.providerIndex - 1)
        else if (t === "]" || t === "l" || t === "L") root.selectProvider(root.providerIndex + 1)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ========== OVERVIEW: ranked agent fleet ==========
          Column {
            id: overviewColumn
            visible: root.viewMode === "overview"
            width: parent.width
            spacing: Style.space(10)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: parent.width - Style.space(80)
                spacing: Style.space(2)
                Text {
                  text: "Agents"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.rankedProviders.length + " agent"
                    + (root.rankedProviders.length === 1 ? "" : "s")
                    + " · source windows differ; token totals may overlap"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Rectangle {
                width: Style.space(68)
                height: Style.space(28)
                radius: Style.cornerRadius
                anchors.verticalCenter: parent.verticalCenter
                color: refreshHover.containsMouse
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : root.alpha(root.foreground, 0.08)
                Text {
                  anchors.centerIn: parent
                  text: "Refresh"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: refreshHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.refreshNow()
                }
              }
            }

            // Sort chips
            Row {
              spacing: Style.space(4)
              Repeater {
                model: [
                  { id: "tokens", label: "Tracked" },
                  { id: "today", label: "Today" },
                  { id: "prompts", label: "Messages" },
                  { id: "sessions", label: "Sessions" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  width: Math.max(Style.space(56), sortChipLabel.implicitWidth + Style.space(16))
                  height: Style.space(28)
                  radius: Style.cornerRadius
                  color: root.sortMode === modelData.id
                    ? Style.selectedFillFor(root.foreground, Color.accent)
                    : root.alpha(root.foreground, 0.08)
                  Text {
                    id: sortChipLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.setSortMode(modelData.id)
                  }
                }
              }
            }

            Text {
              visible: root.rankedProviders.length === 0
              width: parent.width
              topPadding: Style.space(16)
              text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.rankedProviders
              delegate: Rectangle {
                id: agentCard
                required property var modelData
                required property int index
                width: overviewColumn.width
                height: agentRowCol.implicitHeight + Style.space(16)
                radius: Style.cornerRadius
                color: {
                  if (root.cursorActive && root.overviewCursor === index)
                    return Style.selectedFillFor(root.foreground, Color.accent)
                  return rowMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : root.alpha(root.foreground, 0.05)
                }
                border.width: Style.spacing.hairline
                border.color: root.alpha(root.foreground, 0.12)

                readonly property real relativeToLargest: root.maxProviderTokens > 0
                  ? modelData.allTimeTokens / root.maxProviderTokens : 0

                Column {
                  id: agentRowCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(6)

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      text: "#" + (index + 1)
                      color: index === 0 ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: index === 0
                      width: Style.space(28)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    // Mark
                    Item {
                      width: Style.space(28)
                      height: Style.space(28)
                      anchors.verticalCenter: parent.verticalCenter
                      property var candidates: root.iconCandidatesForProvider(modelData, root.surface)
                      property int candidateIndex: 0
                      Image {
                        id: rowMark
                        anchors.fill: parent
                        source: parent.candidateIndex < parent.candidates.length
                          ? parent.candidates[parent.candidateIndex] : ""
                        sourceSize.width: Style.space(40)
                        sourceSize.height: Style.space(40)
                        fillMode: Image.PreserveAspectFit
                        onStatusChanged: if (status === Image.Error && parent.candidateIndex < parent.candidates.length)
                          Qt.callLater(function() { parent.candidateIndex++ })
                      }
                      Text {
                        anchors.centerIn: parent
                        visible: rowMark.status !== Image.Ready
                        text: "󱚣"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                    }

                    Column {
                      width: parent.width - Style.space(28) - Style.space(28) - Style.space(72) - Style.space(24)
                      spacing: 1
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        width: parent.width
                        text: modelData.providerName
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        ToolTip.visible: nameHover.hovered
                        ToolTip.text: String(modelData.providerName || "")
                        ToolTip.delay: 350
                        HoverHandler { id: nameHover }
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: {
                          var bits = []
                          if (modelData.topModel) bits.push(modelData.topModel)
                          bits.push(providerScopeShort(modelData))
                          bits.push(exactCount(modelData.totalPrompts) + " " + messageMetricLabel(modelData))
                          bits.push(exactCount(modelData.totalSessions) + " sessions")
                          if (!(modelData.allTimeTokens > 0) && !(modelData.totalPrompts > 0))
                            bits = [modelData.usageStatusText || "No usage yet · open for details"]
                          return bits.join(" · ")
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        ToolTip.visible: detailHover.hovered
                        ToolTip.text: providerScopeText(modelData)
                          + " · " + String(modelData.usageStatusText || "")
                          + " · " + String(modelData.authHelpText || "")
                        ToolTip.delay: 350
                        HoverHandler { id: detailHover }
                      }
                    }

                    Column {
                      width: Style.space(72)
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        width: parent.width
                        text: {
                          if (root.sortMode === "today")
                            return usage.formatTokenCount(modelData.todayTokens)
                          if (root.sortMode === "prompts")
                            return exactCount(modelData.totalPrompts)
                          if (root.sortMode === "sessions")
                            return exactCount(modelData.totalSessions)
                          return usage.formatTokenCount(modelData.allTimeTokens)
                        }
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        ToolTip.visible: valueHover.hovered
                        ToolTip.text: root.sortMode === "prompts"
                          ? exactCount(modelData.totalPrompts) + " " + messageMetricLabel(modelData) + " (not user prompts)"
                          : root.sortMode === "sessions"
                            ? exactCount(modelData.totalSessions) + " sessions"
                            : exactCount(root.sortMode === "today" ? modelData.todayTokens : modelData.allTimeTokens) + " tokens"
                        ToolTip.delay: 350
                        HoverHandler { id: valueHover }
                      }
                      Text {
                        width: parent.width
                        text: root.sortMode === "prompts" ? messageMetricLabel(modelData)
                          : root.sortMode === "sessions" ? "sessions"
                          : root.sortMode === "today" ? "tokens today" : "tracked tokens"
                        color: root.paceColor(modelData.pace)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        horizontalAlignment: Text.AlignRight
                      }
                    }
                  }

                  // Relative token volume against the largest source. Sources can overlap.
                  Item {
                    width: parent.width
                    height: Style.space(6)
                    Rectangle {
                      anchors.fill: parent
                      radius: height / 2
                      color: root.track
                    }
                    Rectangle {
                      width: parent.width * Math.min(1, agentCard.relativeToLargest)
                      height: parent.height
                      radius: height / 2
                      color: index === 0 ? Color.accent : root.foreground
                      opacity: 0.85
                    }
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: Math.round(agentCard.relativeToLargest * 100) + "% of largest recorded token volume"
                      + (modelData.todayTokens > 0
                        ? " · today " + usage.formatTokenCount(modelData.todayTokens) : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    root.overviewCursor = index
                    if (mouse.button === Qt.RightButton)
                      root.launchProvider(modelData.providerId)
                    else
                      root.openDetail(modelData.providerId)
                  }
                  onEntered: { root.cursorActive = true; root.overviewCursor = index }
                }
              }
            }

            Text {
              visible: root.rankedProviders.length > 0
              width: parent.width
              text: "↑/↓ select · Enter details · Right-click launch · 1–4 sort · totals may overlap · Esc close"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          // ========== DETAIL: one agent ==========
          // ---------- Hero: provider mark · name · plan ----------
          Row {
            id: detailBackRow
            visible: root.viewMode === "detail"
            width: parent.width
            spacing: Style.space(4)

            Rectangle {
              width: Style.space(52)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: backMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : root.alpha(root.foreground, 0.08)
              Text {
                anchors.centerIn: parent
                text: "← All"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openOverview()
              }
            }

            Item {
              width: Math.max(0, detailBackRow.width - Style.space(202))
              height: 1
            }

            Rectangle {
              width: Style.space(52)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: copySummaryHover.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : root.alpha(root.foreground, 0.08)
              Text { anchors.centerIn: parent; text: "Copy"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea {
                id: copySummaryHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.copyUsageSummary()
              }
              ToolTip.visible: copySummaryHover.containsMouse
              ToolTip.text: "Copy this agent's usage summary"
            }

            Text {
              width: Style.space(30)
              text: root.providers.length > 0 ? (root.providerIndex + 1) + "/" + root.providers.length : "0/0"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              width: Style.space(24)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: prevProviderHover.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : root.alpha(root.foreground, 0.08)
              Text { anchors.centerIn: parent; text: "‹"; color: root.foreground; font.family: root.fontFamily }
              MouseArea {
                id: prevProviderHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selectProvider(root.providerIndex - 1)
              }
              ToolTip.visible: prevProviderHover.containsMouse
              ToolTip.text: "Previous agent · [ or h"
            }

            Rectangle {
              width: Style.space(24)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: nextProviderHover.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : root.alpha(root.foreground, 0.08)
              Text { anchors.centerIn: parent; text: "›"; color: root.foreground; font.family: root.fontFamily }
              MouseArea {
                id: nextProviderHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selectProvider(root.providerIndex + 1)
              }
              ToolTip.visible: nextProviderHover.containsMouse
              ToolTip.text: "Next agent · ] or l"
            }
          }

          PanelHero {
            id: hero
            visible: root.viewMode === "detail" && !!root.provider
            width: parent.width
            title: root.provider ? root.provider.providerName : ""
            meta: root.heroMeta(root.provider)
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                id: heroMark
                property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
                property string candidatesKey: candidates.join("\n")
                property int candidateIndex: 0
                onCandidatesKeyChanged: candidateIndex = 0

                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroMarkImage
                  anchors.fill: parent
                  source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                  onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                    Qt.callLater(function() { heroMark.candidateIndex++ })
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: heroMarkImage.status !== Image.Ready
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          // Detail fleet comparison strip
          Rectangle {
            visible: root.viewMode === "detail" && !!root.provider
            width: parent.width
            height: detailStatsCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.alpha(root.foreground, 0.06)
            border.width: Style.spacing.hairline
            border.color: root.alpha(root.foreground, 0.12)

            Column {
              id: detailStatsCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(4)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: {
                  var row = null
                  for (var i = 0; i < root.rankedProviders.length; i++) {
                    if (root.rankedProviders[i].providerId === root.selectedProviderId) {
                      row = root.rankedProviders[i]
                      break
                    }
                  }
                  if (!row) return ""
                  return usage.formatTokenCount(row.allTimeTokens) + " recorded tokens"
                    + " · cumulative processing volume; source totals are not deduplicated"
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: {
                  var p = root.provider
                  if (!p) return ""
                  return exactCount(p.totalPrompts) + " " + messageMetricLabel(p) + " · "
                    + exactCount(p.totalSessions) + " sessions · " + p.activeDays + " active days"
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.provider ? providerScopeText(root.provider) : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          Text {
            visible: false
            width: parent.width
            text: ""
          }

          // ---------- Provider switch ----------
          Flow {
            id: providerSwitch
            visible: root.viewMode === "detail" && root.providers.length > 1
            width: parent.width
            spacing: Style.spacing.sm
            height: childrenRect.height

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: implicitWidth
                height: implicitHeight
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: root.viewMode === "detail" && !!root.provider && String(root.provider.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider
                ? (String(root.provider.authHelpText || "") || String(root.provider.usageStatusText || "")) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            visible: root.viewMode === "detail" && !!root.provider
              && !root.hasRecordedUsage(root.provider)
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: root.emptyUsageMessage(root.provider)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(8)

              Rectangle {
                width: Style.space(76)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: refreshEmptyHover.containsMouse
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : Style.selectedFillFor(root.foreground, Color.accent)
                Text {
                  anchors.centerIn: parent
                  text: "Refresh"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: refreshEmptyHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.refreshNow()
                }
              }

              Rectangle {
                visible: root.provider && root.provider.launchable !== false
                width: Style.space(90)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: launchEmptyHover.containsMouse
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : root.alpha(root.foreground, 0.08)
                Text {
                  anchors.centerIn: parent
                  text: "Launch agent"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: launchEmptyHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.launchProvider(root.selectedProviderId)
                }
              }
            }
          }

          // ---------- Today: daytime summary + hourly activity ----------
          PanelSeparator {
            visible: root.viewMode === "detail" && todaySection.visible
            foreground: root.foreground
          }

          Column {
            id: todaySection
            visible: root.viewMode === "detail" && !!root.today && root.today.hasActivity
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TODAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(todayStats.implicitHeight, todayCost.implicitHeight)

              Text {
                id: todayStats
                textFormat: Text.PlainText
                text: {
                  var t = root.today
                  if (!t) return ""
                  var text = exactCount(t.prompts) + " " + messageMetricLabel(root.provider)
                  if (t.sessions > 0) text += " · " + t.sessions + " session" + (t.sessions === 1 ? "" : "s")
                  if (t.tokens > 0) text += " · " + usage.formatTokenCount(t.tokens) + " tokens"
                  return text
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.right: todayCost.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
              }

              Text {
                id: todayCost
                textFormat: Text.PlainText
                visible: !!root.today && root.today.cost > 0
                text: root.today ? "≈ " + root.formatCost(root.today.cost) + " rate est." : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }

              MouseArea {
                id: todaySummaryHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }

              PanelToolTip {
                visible: todaySummaryHover.containsMouse
                text: "OpenCode local token activity. Any rate estimate is not account billing; cached and repeated context is included in token totals."
                fontFamily: root.fontFamily
              }
            }

            Item {
              id: hourStrip
              visible: !!root.today && root.today.hours.length > 0
              width: parent.width
              implicitHeight: Style.space(40)

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(5)
                Repeater {
                  model: root.today ? root.today.hours : []
                  HourBar {
                    required property var modelData
                    act: modelData
                    peak: root.today ? root.today.peak : 1
                  }
                }
              }
            }

            Text {
              visible: root.today && root.today.priorDaysCount >= 2
              width: parent.width
              text: root.today ? root.todayTrendText(root.today) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Balance / limits ----------
          PanelSeparator {
            visible: root.viewMode === "detail" && (balanceSection.visible || limitsSection.visible)
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: root.viewMode === "detail" && !!root.balance
            width: parent.width
            spacing: Style.space(10)

            // The meter shows what is left, not what is used: a prepaid
            // account drains toward empty rather than filling toward a cap.
            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Prepaid credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                textFormat: Text.PlainText
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: limitsSection
            visible: root.viewMode === "detail" && root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Usage ----------
          PanelSeparator {
            visible: root.viewMode === "detail" && usageSection.visible
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: root.viewMode === "detail" && !!root.provider && root.provider.recentDays && root.provider.recentDays.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.provider ? (root.provider.recentDays || []) : []
            readonly property real peak: Math.max(1, root.weekPeak(root.provider))

            PanelSectionHeader {
              width: parent.width
              text: "RECENT TOKENS BY DAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: usageSection.days

              DayRow {
                required property var modelData
                required property int index

                width: usageSection.width
                day: modelData
                ratio: root.dayTokenCount(modelData) / usageSection.peak
                // By date, not by position: the Claude stats-cache fallback can
                // hand us a window that stops short of today.
                today: String(modelData.date || "") === root.todayDate()
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.weekTotal(root.provider) > 0
              width: parent.width
              text: "Recent total · " + usage.formatTokenCount(root.weekTotal(root.provider)) + " tokens"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }
          }

          // ---------- Models ----------
          PanelSeparator {
            visible: root.viewMode === "detail" && modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.viewMode === "detail" && root.models.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "RECORDED TOKENS BY MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.models

              ModelRow {
                required property var modelData
                width: modelSection.width
                row: modelData
                // Scaled to the heaviest model, so the top row is always full —
                // the same scale-to-peak the weekly chart uses for its busiest day.
                share: modelData.total / Math.max(1, root.models[0].total)
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.estimatedAllTimeCost > 0
              width: parent.width
              text: "Token-rate estimate · ≈ " + root.formatCost(root.estimatedAllTimeCost) + " · not account billing"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.viewMode === "detail" && text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
    }

    Text {
      id: resetText
      textFormat: Text.PlainText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

  }

  // One hour column in the today activity strip: a bar scaled to the busiest
  // hour, the hour label under it, and a tooltip with counts.
  component HourBar: Item {
    id: hourBar
    property var act: null
    property real peak: 1

    implicitWidth: Style.space(14)
    implicitHeight: Style.space(38)

    Rectangle {
      id: hourBarRect
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: hourBarLabel.top
      anchors.bottomMargin: Style.space(3)
      width: Style.space(9)
      height: Math.max(Style.space(3), Style.space(30) * root.clamp(hourBar.act ? hourBar.act.count / Math.max(1, hourBar.peak) : 0, 0.03, 1))
      radius: 2
      color: root.alpha(root.foreground, 0.65)

      Behavior on height {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: hourBarLabel
      textFormat: Text.PlainText
      text: hourBar.act ? hourBar.act.label : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
    }

    MouseArea {
      id: hourBarHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: hourBarHover.containsMouse
      text: hourBar.act
        ? String(hourBar.act.label || "") + ":00 · " + exactCount(hourBar.act.count) + " " + messageMetricLabel(root.provider)
          + " · " + usage.formatTokenCount(hourBar.act.tokens) + " tokens"
        : ""
      fontFamily: root.fontFamily
    }
  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      text: usage.formatTokenCount(dayRow.day ? root.dayTokenCount(dayRow.day) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }
}
