// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming through
// Qt.locale().

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "dddd HH:mm:ss",
  "dddd h:mm:ss AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

// Whether a format prints seconds, so the widget can tick once a second only
// for the formats that show them. Quoted literals go first: the s in a 'Sat'
// is text rather than a token, and an opening quote with no closing one runs
// to the end of the format the way Qt reads it.
function clockNeedsSeconds(format) {
  var text = String(format === undefined || format === null ? "" : format)
  return /s/.test(text.replace(/'[^']*'?/g, ""))
}

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared
// against today without dragging Date objects through bindings.
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to the locale's own first day when
// the setting is missing or nonsense.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch
// between. A calendar configured to any other start (Saturday, say) is
// shown as-is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

function daysRemaining(year, month, day) {
  return Math.max(0, daysInYear(year) - dayOfYear(year, month, day))
}

// Share of the year already behind you: whole days completed over days in
// the year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for
// all of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// Always six rows of seven days. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday. That is the
    // definition itself for Monday-start weeks, and the only answer that
    // stays stable for the other starts, where a row straddles two ISO
    // weeks but shares all of Monday through Thursday with one of them.
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ---- world clock, holidays, events, climate -------------------------- (pure)
// Same contract as the calendar math above: no Qt, no locale, so everything
// here runs unchanged under node in tests/test-core.js. The QML layer only
// ever hands plain values in and gets plain values back.

// WMO weather code -> a single panel-safe ASCII glyph. clear/partly-code
// nights are drawn with the night mark so a "sun *" / "moon o" distinction
// survives; the whole table can be swapped for emoji later without touching
// the math.
var WEATHER_GLYPH = {
  "0":  { day: "*", night: "o" },   // clear sky
  "1":  { day: "*", night: "o" },   // mainly clear
  "2":  { day: "*", night: "o" },   // partly cloudy
  "3":  { day: "*", night: "o" },   // overcast
  "45": { day: "=", night: "=" },   // fog
  "48": { day: "=", night: "=" },   // depositing rime fog
  "51": { day: "~", night: "~" },   // light drizzle
  "53": { day: "~", night: "~" },   // moderate drizzle
  "55": { day: "~", night: "~" },   // dense drizzle
  "61": { day: "o", night: "o" },   // slight rain
  "63": { day: "o", night: "o" },   // moderate rain
  "65": { day: "o", night: "o" },   // heavy rain
  "71": { day: "*", night: "*" },   // slight snow
  "73": { day: "*", night: "*" },   // moderate snow
  "75": { day: "*", night: "*" },   // heavy snow
  "80": { day: "o", night: "o" },   // light showers
  "81": { day: "o", night: "o" },   // moderate showers
  "82": { day: "o", night: "o" },   // violent showers
  "95": { day: "!", night: "!" },   // thunderstorm
  "96": { day: "!", night: "!" },   // thunderstorm, hail
  "99": { day: "!", night: "!" }    // severe thunderstorm, hail
}

var WEATHER_WORD = {
  "0": "clear",
  "1": "mainly clear",
  "2": "partly cloudy",
  "3": "overcast",
  "45": "fog",
  "48": "rime fog",
  "51": "light drizzle",
  "53": "moderate drizzle",
  "55": "dense drizzle",
  "61": "slight rain",
  "63": "moderate rain",
  "65": "heavy rain",
  "71": "slight snow",
  "73": "moderate snow",
  "75": "heavy snow",
  "80": "light showers",
  "81": "moderate showers",
  "82": "violent showers",
  "95": "thunderstorm",
  "96": "thunderstorm with hail",
  "99": "severe thunderstorm, hail"
}

function weatherGlyph(code, isDay) {
  var c = String(code === undefined || code === null ? "" : code)
  var entry = WEATHER_GLYPH[c]
  if (!entry) return ""
  return isDay === false ? (entry.night || entry.day) : (entry.day || entry.night)
}

function weatherWord(code) {
  var c = String(code === undefined || code === null ? "" : code)
  return WEATHER_WORD[c] || "clear"
}// Open-Meteo /v1/forecast `current` block -> the plain object the panel
// renders. A missing or unusable temperature kills the row; feelsLike falls
// back to the reported temperature and an unknown code to the clear marker.
function climateFromReport(report) {
  if (!report || typeof report !== "object") return null
  var temp = Number(report.temperature_2m)
  if (!isFinite(temp)) return null
  var feels = Number(report.apparent_temperature)
  var code = report.weather_code === undefined || report.weather_code === null
    ? "" : String(report.weather_code)
  var isDay = String(report.is_day) === "1"
  return {
    temperature: temp,
    feelsLike: isFinite(feels) ? feels : temp,
    glyph: weatherGlyph(code, isDay),
    condition: weatherWord(code),
    isDay: isDay
  }
}

// "21°C" when the panel runs metric, "70°F" otherwise — same number either
// way, rounded to the degree people actually quote.
function tempLabel(temp, celsius) {
  var value = Number(temp)
  if (!isFinite(value)) return ""
  if (celsius) return Math.round(value) + "\u00B0C"
  return Math.round(value * 9 / 5 + 32) + "\u00B0F"
}

// One-line weather report for the bar label: "21°C moderate rain".
function climateLine(report, celsius) {
  var c = climateFromReport(report)
  if (!c) return ""
  return tempLabel(c.temperature, celsius) + " " + c.condition
}// ---- holiday tables -------------------------------------------------------
// A table maps "yyyy-MM-dd" to { n: label, cc: "KE UG" }; cc is a
// space-separated list of ISO-3166 alpha-2 codes a holiday applies to, so one
// moving entry (Good Friday, Eid) can serve several countries at once.
function parseHolidayTable(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var table = {}
  var lines = text.split(/[\r\n]+/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (line === "") continue
    var parts = line.split("|")
    if (parts.length < 3) continue
    var key = parts[0].replace(/^\s+|\s+$/g, "")
    var cc = parts[1].replace(/^\s+|\s+$/g, "").toUpperCase()
    var n = parts[2].replace(/^\s+|\s+$/g, "")
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key) || cc === "" || n === "") continue
    table[key] = { n: n, cc: cc }
  }
  return table
}

function holidayTableForYear(fixedHolidays, globalHolidays, lunarHolidays, year) {
  var table = {}
  var rows = (fixedHolidays || []).concat(globalHolidays || [])
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var key = dateKey(year, Number(row.m) - 1, row.d)
    var existing = table[key]
    if (!existing) {
      table[key] = { n: row.n, cc: row.cc || "" }
    } else {
      existing.cc = (existing.cc + " " + (row.cc || "")).replace(/^\s+|\s+$/g, "")
      if (existing.n.indexOf(row.n) === -1) existing.n += " / " + row.n
    }
  }

  var lunar = lunarHolidays && lunarHolidays[year] ? lunarHolidays[year] : []
  for (var j = 0; j < lunar.length; j++) {
    var lunarRow = lunar[j]
    var lunarKey = lunarRow.d
    var lunarExisting = table[lunarKey]
    if (!lunarExisting) {
      table[lunarKey] = { n: lunarRow.n, cc: lunarRow.cc || "" }
    } else {
      lunarExisting.cc = (lunarExisting.cc + " " + (lunarRow.cc || "")).replace(/^\s+|\s+$/g, "")
      if (lunarExisting.n.indexOf(lunarRow.n) === -1) lunarExisting.n += " / " + lunarRow.n
    }
  }

  var easter = easterHolidaysForYear(year)
  var easterKeys = Object.keys(easter)
  for (var k = 0; k < easterKeys.length; k++) {
    var easterKey = easterKeys[k]
    var easterExisting = table[easterKey]
    var easterRow = easter[easterKey]
    if (!easterExisting) table[easterKey] = { n: easterRow.n, cc: easterRow.cc || "GLOBAL" }
    else {
      easterExisting.cc = (easterExisting.cc + " " + (easterRow.cc || "GLOBAL")).replace(/^\s+|\s+$/g, "")
      if (easterExisting.n.indexOf(easterRow.n) === -1) easterExisting.n += " / " + easterRow.n
    }
  }
  return table
}

function holidayFlagsForDay(table, year, month, day) {
  var hit = table && table[dateKey(year, month, day)]
  return hit ? hit.cc : ""
}

function holidayLabelsForDay(table, year, month, day) {
  var hit = table && table[dateKey(year, month, day)]
  return hit ? hit.n : ""
}

// Whole days between an "yyyy-MM-dd" key and today's key, so the panel can
// say "in 3 days". Built in UTC so a near-midnight local clock can never
// nudge the count.
function dayOffsetFrom(key, todayKey) {
  var to = new Date(Date.UTC(
    parseInt(key.slice(0, 4), 10), parseInt(key.slice(5, 7), 10) - 1,
    parseInt(key.slice(8, 10), 10)))
  var from = new Date(Date.UTC(
    parseInt(todayKey.slice(0, 4), 10), parseInt(todayKey.slice(5, 7), 10) - 1,
    parseInt(todayKey.slice(8, 10), 10)))
  return Math.round((to.getTime() - from.getTime()) / MS_PER_DAY)
}

// The next `limit` holidays on or after `todayKey`, sorted by date. Clamped
// to 1..30 so a stray setting cannot grow the panel into a yearbook.
function upcomingHolidays(table, limit, todayKey) {
  var cap = Math.max(1, Math.min(30, parseInt(limit, 10) || 6))
  var anchor = typeof todayKey === "string" && /^\d{4}-\d{2}-\d{2}$/.test(todayKey)
    ? todayKey : keyForDate(new Date())
  var out = []
  if (!table) return out
  var keys = Object.keys(table).sort()
  for (var i = 0; i < keys.length && out.length < cap; i++) {
    var key = keys[i]
    if (key < anchor) continue
    var hit = table[key]
    if (!hit) continue
    out.push({ key: key, name: hit.n, cc: hit.cc || "", dayOffset: dayOffsetFrom(key, anchor) })
  }
  return out
}

// Move a {year, month, day} triple by whole days, keeping the arithmetic in
// UTC so calendar panels and holiday tables never see a DST ripple.
function addDays(year, month, day, delta) {
  var d = new Date(Date.UTC(year, month, day))
  d.setUTCDate(d.getUTCDate() + delta)
  return { year: d.getUTCFullYear(), month: d.getUTCMonth(), day: d.getUTCDate() }
}// Computus (Meeus/Jones/Butcher, the "Anonymous Gregorian") for the Latin
// Church's Easter Sunday in the given Gregorian year. Returns the 0-based
// month to match the rest of the model.
function computusEaster(year) {
  var y = Number(year)
  var a = y % 19
  var b = Math.floor(y / 100)
  var c = y % 100
  var d = Math.floor(b / 4)
  var e = b % 4
  var f = Math.floor((b + 8) / 25)
  var g = Math.floor((b - f + 1) / 3)
  var h = (19 * a + b - d - g + 15) % 30
  var i = Math.floor(c / 4)
  var k = c % 4
  var l = (32 + 2 * e + 2 * i - h - k) % 7
  var m = Math.floor((a + 11 * h + 22 * l) / 451)
  var month = Math.floor((h + l - 7 * m + 114) / 31)
  var day = (h + l - 7 * m + 114) % 31 + 1
  return { year: y, month: month - 1, day: day }
}

// The Easter long-weekend map for a year: Good Friday and Easter Saturday
// run up to the computus Sunday, Easter Monday follows it.
function easterHolidaysForYear(year) {
  var e = computusEaster(year)
  var rows = [
    { d: addDays(e.year, e.month, e.day, -2), n: "Good Friday", cc: "KE UG" },
    { d: addDays(e.year, e.month, e.day, -1), n: "Easter Saturday", cc: "KE UG" },
    { d: { year: e.year, month: e.month, day: e.day }, n: "Easter Sunday", cc: "" },
    { d: addDays(e.year, e.month, e.day, 1), n: "Easter Monday", cc: "KE UG" }
  ]
  var out = {}
  for (var i = 0; i < rows.length; i++)
    out[dateKey(rows[i].d.year, rows[i].d.month, rows[i].d.day)] = { n: rows[i].n, cc: rows[i].cc }
  return out
}// ---- events ---------------------------------------------------------------
// Line-based "yyyy-MM-dd|label" definitions. One day may hold several lines;
// the map keeps labels in source order without duplicating a label.
function parseEvents(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var map = {}
  var lines = text.split(/[\r\n]+/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (line === "") continue
    var pipe = line.indexOf("|")
    if (pipe === -1) continue
    var key = line.slice(0, pipe).replace(/^\s+|\s+$/g, "")
    var label = line.slice(pipe + 1).replace(/^\s+|\s+$/g, "")
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key) || label === "") continue
    var year = parseInt(key.slice(0, 4), 10)
    var month = parseInt(key.slice(5, 7), 10) - 1
    var day = parseInt(key.slice(8, 10), 10)
    if (month < 0 || month > 11 || day < 1 ||
        day > new Date(Date.UTC(year, month + 1, 0)).getUTCDate()) continue
    if (!map[key]) map[key] = []
    if (map[key].indexOf(label) === -1) map[key].push(label)
  }
  return map
}

// Recurring birthdays are stored as "MM-dd|Name" lines. They are deliberately
// separate from dated events so a birthday follows its owner into every year.
function parseBirthdays(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var map = {}
  var lines = text.split(/[\r\n]+/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line) continue
    var pipe = line.indexOf("|")
    if (pipe === -1) continue
    var key = line.slice(0, pipe).replace(/^\s+|\s+$/g, "")
    var label = line.slice(pipe + 1).replace(/^\s+|\s+$/g, "")
    if (!/^\d{2}-\d{2}$/.test(key) || !label) continue
    var month = parseInt(key.slice(0, 2), 10)
    var day = parseInt(key.slice(3, 5), 10)
    if (month < 1 || month > 12 || day < 1 ||
        day > new Date(Date.UTC(2024, month, 0)).getUTCDate()) continue
    if (!map[key]) map[key] = []
    if (map[key].indexOf(label) === -1) map[key].push(label)
  }
  return map
}

function birthdaysForDay(value, year, month, day) {
  if (day === undefined) {
    day = month
    month = year
  }
  var map = value && typeof value === "object" ? value : parseBirthdays(value)
  return map[pad2(Number(month) + 1) + "-" + pad2(day)] || []
}

// Merge dated events and recurring birthdays into a compact upcoming list.
function upcomingPersonalEvents(eventsValue, birthdaysValue, limit, todayKey) {
  var cap = Math.max(1, Math.min(30, parseInt(limit, 10) || 8))
  var anchor = typeof todayKey === "string" && /^\d{4}-\d{2}-\d{2}$/.test(todayKey)
    ? todayKey : keyForDate(new Date())
  var year = parseInt(anchor.slice(0, 4), 10)
  var events = eventsValue && typeof eventsValue === "object" ? eventsValue : parseEvents(eventsValue)
  var birthdays = birthdaysValue && typeof birthdaysValue === "object" ? birthdaysValue : parseBirthdays(birthdaysValue)
  var out = []
  var keys = Object.keys(events)
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] < anchor) continue
    for (var j = 0; j < events[keys[i]].length; j++)
      out.push({ key: keys[i], name: events[keys[i]][j], kind: "event", dayOffset: dayOffsetFrom(keys[i], anchor) })
  }
  var birthdayKeys = Object.keys(birthdays)
  for (var b = 0; b < birthdayKeys.length; b++) {
    var parts = birthdayKeys[b].split("-")
    for (var y = year; y <= year + 1; y++) {
      var birthdayKey = dateKey(y, Number(parts[0]) - 1, Number(parts[1]))
      if (birthdayKey < anchor) continue
      for (var n = 0; n < birthdays[birthdayKeys[b]].length; n++)
        out.push({ key: birthdayKey, name: birthdays[birthdayKeys[b]][n], kind: "birthday", dayOffset: dayOffsetFrom(birthdayKey, anchor) })
    }
  }
  out.sort(function(a, b) { return a.key === b.key ? a.name.localeCompare(b.name) : a.key < b.key ? -1 : 1 })
  return out.slice(0, cap)
}

// Either an already-parsed events map or the raw definitions text; the panel
// hands over whichever it has handy. Unknown days read as an empty list.
function eventsForDay(eventsValue, year, month, day) {
  var map = eventsValue && typeof eventsValue === "object" ? eventsValue : parseEvents(eventsValue)
  return map[dateKey(year, month, day)] || []
}

// ---- world clock -----------------------------------------------------------
// Places are "Name, CC" or "Name, CC, Area/City" (IANA) lines. The optional
// zone is what lets multiple US cities keep distinct times (NY / LA / HNL).
var ZONE_ID = /^[A-Za-z0-9_+\-\/]+$/

// Well-known city names → IANA, so legacy "Name, CC" lines still split US
// coasts correctly without forcing every user to type the zone.
var CITY_ZONES = {
  "nairobi": "Africa/Nairobi",
  "tokyo": "Asia/Tokyo",
  "honolulu": "Pacific/Honolulu",
  "los angeles": "America/Los_Angeles",
  "new york": "America/New_York",
  "london": "Europe/London",
  "paris": "Europe/Paris",
  "berlin": "Europe/Berlin",
  "sydney": "Australia/Sydney",
  "singapore": "Asia/Singapore",
  "hong kong": "Asia/Hong_Kong",
  "dubai": "Asia/Dubai",
  "chicago": "America/Chicago",
  "denver": "America/Denver",
  "seattle": "America/Los_Angeles",
  "san francisco": "America/Los_Angeles",
  "toronto": "America/Toronto",
  "mexico city": "America/Mexico_City"
}

function parsePlaces(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var out = []
  var seen = {}
  var lines = text.split(/[\r\n]+/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (line === "") continue
    var parts = line.split(",")
    var name = (parts[0] || "").replace(/^\s+|\s+$/g, "")
    var cc = (parts[1] || "").replace(/^\s+|\s+$/g, "").toUpperCase()
    var zone = (parts[2] || "").replace(/^\s+|\s+$/g, "")
    if (name === "" || !/^[A-Z]{2}$/.test(cc)) continue
    if (zone !== "" && !ZONE_ID.test(zone)) zone = ""
    if (zone === "") {
      var known = CITY_ZONES[name.toLowerCase()]
      if (known) zone = known
    }
    var id = name.toLowerCase() + "|" + cc + "|" + zone
    if (seen[id]) continue
    seen[id] = true
    out.push({ name: name, cc: cc, zone: zone })
  }
  return out
}

// Round-trip the parsed list back to the multiline setting string.
function serializePlaces(places) {
  var lines = []
  var list = places || []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || !p.name || !p.cc) continue
    var line = p.name + ", " + p.cc
    if (p.zone) line += ", " + p.zone
    lines.push(line)
  }
  return lines.join("\n")
}

// Cities that matter more than a country's capital (US coasts, etc.).
var EXTRA_CITIES = [
  { name: "Nairobi", cc: "KE", zone: "Africa/Nairobi" },
  { name: "Tokyo", cc: "JP", zone: "Asia/Tokyo" },
  { name: "Honolulu", cc: "US", zone: "Pacific/Honolulu" },
  { name: "Los Angeles", cc: "US", zone: "America/Los_Angeles" },
  { name: "San Francisco", cc: "US", zone: "America/Los_Angeles" },
  { name: "Seattle", cc: "US", zone: "America/Los_Angeles" },
  { name: "New York", cc: "US", zone: "America/New_York" },
  { name: "Chicago", cc: "US", zone: "America/Chicago" },
  { name: "Denver", cc: "US", zone: "America/Denver" },
  { name: "London", cc: "GB", zone: "Europe/London" },
  { name: "Paris", cc: "FR", zone: "Europe/Paris" },
  { name: "Berlin", cc: "DE", zone: "Europe/Berlin" },
  { name: "Sydney", cc: "AU", zone: "Australia/Sydney" },
  { name: "Singapore", cc: "SG", zone: "Asia/Singapore" },
  { name: "Hong Kong", cc: "HK", zone: "Asia/Hong_Kong" },
  { name: "Dubai", cc: "AE", zone: "Asia/Dubai" },
  { name: "Toronto", cc: "CA", zone: "America/Toronto" },
  { name: "Mexico City", cc: "MX", zone: "America/Mexico_City" }
]

// Searchable catalog for the settings picker: country capitals plus the
// well-known cities above. `countries` is the COUNTRIES array from countries.js.
function placeCatalog(countries) {
  var out = []
  var seen = {}
  function offer(name, cc, zone) {
    var n = String(name || "").replace(/^\s+|\s+$/g, "")
    var code = String(cc || "").replace(/^\s+|\s+$/g, "").toUpperCase()
    var z = String(zone || "").replace(/^\s+|\s+$/g, "")
    if (n === "" || !/^[A-Z]{2}$/.test(code)) return
    if (z !== "" && !ZONE_ID.test(z)) z = ""
    var id = n.toLowerCase() + "|" + code + "|" + z
    if (seen[id]) return
    seen[id] = true
    out.push({ name: n, cc: code, zone: z, label: n + ", " + code })
  }
  var list = countries || []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    if (!row) continue
    offer(row.cap || row.n, row.c, row.tz)
  }
  for (var j = 0; j < EXTRA_CITIES.length; j++) {
    var city = EXTRA_CITIES[j]
    offer(city.name, city.cc, city.zone)
  }
  out.sort(function(a, b) {
    return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0)
  })
  return out
}

// Prefix matches on the city name sort first ("par" → Paris before Valparaiso).
function searchPlaces(catalog, query, limit) {
  var q = String(query || "").trim().toLowerCase()
  var max = limit === undefined ? 6 : limit
  var options = catalog || []
  var starts = []
  var contains = []
  for (var i = 0; i < options.length; i++) {
    var o = options[i]
    var label = String(o.label || "").toLowerCase()
    var name = String(o.name || "").toLowerCase()
    var zone = String(o.zone || "").toLowerCase()
    var cc = String(o.cc || "").toLowerCase()
    if (q === "") {
      starts.push(o)
    } else if (name.indexOf(q) === 0 || label.indexOf(q) === 0) {
      starts.push(o)
    } else if (name.indexOf(q) !== -1 || label.indexOf(q) !== -1
               || zone.indexOf(q) !== -1 || cc === q) {
      contains.push(o)
    }
    if (starts.length >= max && q === "") break
  }
  return starts.concat(contains).slice(0, max)
}

function addPlace(placesValue, name, cc, zone) {
  var places = parsePlaces(placesValue)
  var n = String(name || "").replace(/^\s+|\s+$/g, "")
  var code = String(cc || "").replace(/^\s+|\s+$/g, "").toUpperCase()
  var z = String(zone || "").replace(/^\s+|\s+$/g, "")
  if (n === "" || !/^[A-Z]{2}$/.test(code)) return serializePlaces(places)
  if (z !== "" && !ZONE_ID.test(z)) z = ""
  if (z === "") {
    var known = CITY_ZONES[n.toLowerCase()]
    if (known) z = known
  }
  var id = n.toLowerCase() + "|" + code + "|" + z
  for (var i = 0; i < places.length; i++) {
    var existing = places[i]
    var eid = existing.name.toLowerCase() + "|" + existing.cc + "|" + (existing.zone || "")
    if (eid === id) return serializePlaces(places)
  }
  places.push({ name: n, cc: code, zone: z })
  return serializePlaces(places)
}

function removePlaceAt(placesValue, index) {
  var places = parsePlaces(placesValue)
  var i = Number(index)
  if (!isFinite(i) || i < 0 || i >= places.length) return serializePlaces(places)
  places.splice(i, 1)
  return serializePlaces(places)
}

function parseCountryList(value) {
  return parsePlaces(value)
}

// Static UTC offsets (minutes east of UTC) for the countries in the picker,
// keyed by cc. Fallback only — live rows prefer a probed IANA offset.
var COUNTRY_OFFSETS = {
  AR: -180, AU: 600, BR: -180, CA: -300, CH: 60, CN: 480, DE: 60,
  EG: 120, ES: 60, FR: 60, GB: 0, GR: 120, HK: 480, IE: 60, IN: 330,
  IT: 60, JP: 540, KE: 180, KR: 540, MX: -360, NL: 60, NO: 60, NZ: 720,
  PH: 480, PL: 60, PT: 0, QA: 180, RU: 180, SA: 180, SE: 60, SG: 480,
  TR: 180, UA: 120, UG: 180, US: -300, ZA: 120
}

// "-0700" -> -420. Returns null for anything unparseable.
function parseOffset(text) {
  var m = /^([+-])(\d{2})(\d{2})$/.exec(String(text || "").trim())
  if (!m) return null
  var minutes = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
  return m[1] === "-" ? -minutes : minutes
}

// One "America/Los_Angeles|PDT|-0700" line from the date probe.
function parseProbeLine(line) {
  var fields = String(line || "").split("|")
  if (fields.length < 3) return null
  var id = fields[0].trim()
  var offset = parseOffset(fields[2])
  if (id === "" || offset === null) return null
  return { id: id, abbr: fields[1].trim(), offsetMinutes: offset }
}

// Whole probe stdout -> { "America/Los_Angeles": {abbr, offsetMinutes}, ... }
function parseProbe(text) {
  var map = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parsed = parseProbeLine(lines[i])
    if (parsed) map[parsed.id] = { abbr: parsed.abbr, offsetMinutes: parsed.offsetMinutes }
  }
  return map
}

function placeZoneIds(placesValue) {
  var places = parsePlaces(placesValue)
  var out = []
  var seen = {}
  for (var i = 0; i < places.length; i++) {
    var zone = places[i].zone
    if (!zone || seen[zone]) continue
    seen[zone] = true
    out.push(zone)
  }
  return out
}

// Wall-clock parts for a UTC instant shifted by offsetMinutes, read back from
// the UTC getters so the host timezone cannot leak into the math. hour12 is
// the 1-12 form the panel prints, ampm the AM/PM label beside it.
function zoneTimeParts(now, offsetMinutes) {
  var base = now && typeof now.getTime === "function" ? now.getTime() : (Number(now) || 0)
  var shifted = new Date(base + (Number(offsetMinutes) || 0) * 60000)
  var hour = shifted.getUTCHours()
  var minute = shifted.getUTCMinutes()
  var second = shifted.getUTCSeconds()
  return {
    hour: hour,
    minute: minute,
    second: second,
    ampm: hour < 12 ? "AM" : "PM",
    hour12: hour % 12 || 12
  }
}

function placeTimeString(parts) {
  if (!parts) return ""
  return parts.hour12 + ":" + pad2(parts.minute) + " " + parts.ampm
}

// The panel's world-clock rows: one per place. `probe` is an optional map of
// IANA id → {offsetMinutes} from the live `date` probe (DST-correct).
function worldClockRows(placesValue, now, probe) {
  var places = parsePlaces(placesValue)
  var rows = []
  var base = now && typeof now.getTime === "function" ? now.getTime() : (Number(now) || 0)
  var baseDay = Math.floor(base / MS_PER_DAY)
  for (var i = 0; i < places.length; i++) {
    var place = places[i]
    var cc = place.cc
    var zone = place.zone || ""
    var offset = COUNTRY_OFFSETS[cc] === undefined ? 0 : COUNTRY_OFFSETS[cc]
    var abbr = ""
    if (zone && probe && probe[zone] && probe[zone].offsetMinutes !== undefined) {
      offset = probe[zone].offsetMinutes
      abbr = probe[zone].abbr || ""
    }
    var parts = zoneTimeParts(now, offset)
    var shiftedDay = Math.floor((base + offset * 60000) / MS_PER_DAY)
    rows.push({
      name: place.name,
      cc: cc,
      zone: zone,
      abbr: abbr,
      hour: parts.hour,
      minute: parts.minute,
      second: parts.second,
      ampm: parts.ampm,
      hour12: parts.hour12,
      time: placeTimeString(parts),
      dateOffset: shiftedDay - baseDay
    })
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    addDays: addDays,
    ageFromBirthYear: ageFromBirthYear,
    climateFromReport: climateFromReport,
    climateLine: climateLine,
    clockFormatRing: clockFormatRing,
    clockFormats: clockFormats,
    clockNeedsSeconds: clockNeedsSeconds,
    computusEaster: computusEaster,
    dateKey: dateKey,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    daysRemaining: daysRemaining,
    easterHolidaysForYear: easterHolidaysForYear,
    eventsForDay: eventsForDay,
    birthdaysForDay: birthdaysForDay,
    holidayFlagsForDay: holidayFlagsForDay,
    holidayLabelsForDay: holidayLabelsForDay,
    holidayTableForYear: holidayTableForYear,
    isoWeek: isoWeek,
    isoWeekLiteral: isoWeekLiteral,
    keyForDate: keyForDate,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    nextClockFormat: nextClockFormat,
    normalizedWeekStart: normalizedWeekStart,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    parseCountryList: parseCountryList,
    parseEvents: parseEvents,
    parseBirthdays: parseBirthdays,
    parseLifeExpectancy: parseLifeExpectancy,
    parsePlaces: parsePlaces,
    parseProbe: parseProbe,
    placeCatalog: placeCatalog,
    placeTimeString: placeTimeString,
    placeZoneIds: placeZoneIds,
    removePlaceAt: removePlaceAt,
    searchPlaces: searchPlaces,
    serializePlaces: serializePlaces,
    addPlace: addPlace,
    stepMonth: stepMonth,
    tempLabel: tempLabel,
    toggledWeekStart: toggledWeekStart,
    upcomingHolidays: upcomingHolidays,
    upcomingPersonalEvents: upcomingPersonalEvents,
    weatherGlyph: weatherGlyph,
    weatherWord: weatherWord,
    weekStartSettingName: weekStartSettingName,
    weekdayOrder: weekdayOrder,
    worldClockRows: worldClockRows,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    zoneTimeParts: zoneTimeParts
  }
}
