// Core unit tests for Model.js. Plain node, no deps:
//   node tests/test-core.js
// Runs the whole pure-function surface so QML panels can trust the math.
var assert = require("assert")
var M = require("../Model.js")

var checks = 0
function check(cond, label) {
  checks++
  assert.ok(cond, label)
}

var REQUIRED = [
  "dateKey", "keyForDate", "normalizedWeekStart", "weekStartSettingName",
  "toggledWeekStart", "weekdayOrder", "isoWeek", "dayOfYear", "daysInYear",
  "yearProgress", "yearProgressPercent", "parseAge", "parseBirthYear",
  "ageFromBirthYear", "parseLifeExpectancy", "lifeProgress",
  "lifeProgressPercent", "monthGrid", "stepMonth", "clockFormats",
  "clockNeedsSeconds", "clockFormatRing", "nextClockFormat", "isoWeekLiteral",
  "weatherGlyph", "weatherWord", "climateFromReport", "tempLabel",
  "climateLine", "parseCountryList", "holidayFlagsForDay",
  "holidayLabelsForDay", "upcomingHolidays", "computusEaster",
  "easterHolidaysForYear", "addDays", "parseEvents", "eventsForDay",
  "parsePlaces", "worldClockRows", "zoneTimeParts", "placeTimeString",
  "parseBirthdays", "birthdaysForDay", "upcomingPersonalEvents",
  "placeCatalog", "searchPlaces", "addPlace", "removePlaceAt", "serializePlaces"
]

for (var i = 0; i < REQUIRED.length; i++) {
  check(typeof M[REQUIRED[i]] === "function", "export " + REQUIRED[i] + " is a function")
}

// ---- date keys and week math ------------------------------------------
assert.strictEqual(M.dateKey(2025, 8, 5), "2025-09-05")
assert.strictEqual(M.keyForDate(new Date(2025, 8, 5)), "2025-09-05")
assert.strictEqual(M.normalizedWeekStart(0, 1), 0)
assert.strictEqual(M.normalizedWeekStart("bogus", 0), 0)
assert.strictEqual(M.normalizedWeekStart(null, null), 1)
assert.strictEqual(M.toggledWeekStart(1), 0)
assert.strictEqual(M.toggledWeekStart(0), 1)
assert.strictEqual(M.weekStartSettingName(0), "sunday")
assert.strictEqual(M.weekStartSettingName(1), "monday")
assert.deepStrictEqual(M.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0])

// ---- date arithmetic ----------------------------------------------------
assert.strictEqual(M.isoWeek(2025, 0, 1), 1)
assert.strictEqual(M.isoWeekLiteral(2025, 0, 1), "01")
assert.strictEqual(M.dayOfYear(2025, 0, 1), 1)
assert.strictEqual(M.dayOfYear(2025, 11, 31), 365)
assert.strictEqual(M.daysInYear(2024), 366)
assert.strictEqual(M.daysInYear(2025), 365)
assert.strictEqual(M.yearProgress(2025, 0, 1), 0)
assert.strictEqual(M.yearProgressPercent(2025, 11, 31), 100)

// ---- memento mori --------------------------------------------------------
assert.strictEqual(M.parseAge("30"), 30)
assert.strictEqual(M.parseAge("0"), 0)
assert.strictEqual(M.parseAge("300"), 0)
assert.strictEqual(M.parseAge("abc"), 0)
assert.strictEqual(M.parseBirthYear("1979", 2026), 1979)
assert.strictEqual(M.parseBirthYear("2099", 2026), 0)
assert.strictEqual(M.ageFromBirthYear(1979, 2026), 47)
assert.strictEqual(M.parseLifeExpectancy("100"), 100)
assert.strictEqual(M.parseLifeExpectancy("999"), 90)
assert.strictEqual(M.parseLifeExpectancy(""), 90)
assert.strictEqual(M.lifeProgressPercent(47, 90), 52)

// ---- clock formats -------------------------------------------------------
assert.strictEqual(M.clockFormats(false)[0], "dddd HH:mm")
assert.ok(M.clockNeedsSeconds("HH:mm:ss"), "seconds format ticks per second")
check(!M.clockNeedsSeconds("HH:mm"), "minute format does not need seconds")
check(!M.clockNeedsSeconds("'Sat' HH:mm"), "quoted literal s is not a token")
assert.deepStrictEqual(M.clockFormatRing("HH:mm", "HH:mm:ss", M.clockFormats(false)).slice(0, 2), ["dddd HH:mm", "dddd h:mm AP"])
assert.strictEqual(M.nextClockFormat(["HH:mm", "HH:mm:ss"], "HH:mm"), "HH:mm:ss")
assert.strictEqual(M.nextClockFormat(["HH:mm", "HH:mm:ss"], "HH:mm:ss"), "HH:mm")

// ---- calendar grid -------------------------------------------------------
var grid = M.monthGrid(2025, 2, 1, "2025-03-31")
assert.strictEqual(grid.length, 6)
assert.strictEqual(grid[0].days.length, 7)
assert.strictEqual(grid[0].days[0].day, 24)
var foundToday = false
for (var w = 0; w < grid.length; w++) {
  for (var d = 0; d < 7; d++) if (grid[w].days[d].today) foundToday = true
}
assert.ok(foundToday, "today cell flagged in March 2025 grid")
assert.deepStrictEqual(M.stepMonth(2025, 11, 1), { year: 2026, month: 0 })
assert.deepStrictEqual(M.stepMonth(2025, 0, -1), { year: 2024, month: 11 })// ---- weather and climate --------------------------------------------------
assert.strictEqual(M.weatherGlyph("63", true), "o")
assert.strictEqual(M.weatherGlyph("999", true), "")
assert.strictEqual(M.weatherGlyph("0", true), "*")
assert.strictEqual(M.weatherGlyph("0", false), "o")
assert.strictEqual(M.weatherWord("63"), "moderate rain")
assert.strictEqual(M.weatherWord(null), "clear")
var c = M.climateFromReport({ temperature_2m: 21.4, apparent_temperature: 20, weather_code: 63, is_day: 1 })
assert.deepStrictEqual(c, { temperature: 21.4, feelsLike: 20, glyph: "o", condition: "moderate rain", isDay: true })
assert.strictEqual(M.climateFromReport(null), null)
assert.strictEqual(M.tempLabel(21, true), "21\u00B0C")
assert.strictEqual(M.tempLabel(21, false), "70\u00B0F")
assert.strictEqual(M.tempLabel(0, false), "32\u00B0F")
assert.strictEqual(M.tempLabel("abc", true), "")
assert.strictEqual(M.climateLine({ temperature_2m: 21, weather_code: 63, is_day: 1 }, true), "21\u00B0C moderate rain")

// ---- holiday tables -------------------------------------------------------
var e = M.computusEaster(2025)
assert.deepStrictEqual(e, { year: 2025, month: 3, day: 20 })
var easter = M.easterHolidaysForYear(2025)
assert.strictEqual(M.holidayLabelsForDay(easter, 2025, 3, 18), "Good Friday")
assert.strictEqual(M.holidayFlagsForDay(easter, 2025, 3, 18), "KE UG")
assert.strictEqual(M.holidayLabelsForDay(easter, 2025, 3, 19), "Easter Saturday")
assert.strictEqual(M.holidayLabelsForDay(easter, 2025, 3, 20), "Easter Sunday")
assert.strictEqual(M.holidayLabelsForDay(easter, 2025, 3, 21), "Easter Monday")
assert.deepStrictEqual(M.addDays(2024, 11, 31, 1), { year: 2025, month: 0, day: 1 })
assert.deepStrictEqual(M.addDays(2025, 2, 31, 6), { year: 2025, month: 3, day: 6 })

var table = {
  "2025-03-10": { n: "Old", cc: "KE" },
  "2025-03-31": { n: "Eid al-Fitr", cc: "KE" },
  "2025-04-20": { n: "Filler", cc: "UG" }
}
assert.strictEqual(M.holidayFlagsForDay(table, 2025, 2, 31), "KE")
assert.strictEqual(M.holidayLabelsForDay(table, 2025, 2, 31), "Eid al-Fitr")
assert.strictEqual(M.holidayLabelsForDay(table, 2025, 2, 30), "")
var up = M.upcomingHolidays(table, 6, "2025-03-20")
assert.strictEqual(up.length, 2)
assert.strictEqual(up[0].key, "2025-03-31")
assert.strictEqual(up[0].dayOffset, 11)
assert.strictEqual(up[1].key, "2025-04-20")
for (var u = 0; u < up.length; u++) check(up[u].key >= "2025-03-20", "upcoming key " + up[u].key + " is not in the past")
assert.strictEqual(M.upcomingHolidays(table, 1, "2025-03-20").length, 1)
assert.deepStrictEqual(M.upcomingHolidays(null, 6, "2025-03-20"), [])

// ---- events ---------------------------------------------------------------
var ev = M.parseEvents("2025-04-05|Spring\n2025-04-05|Market\n2025-04-06|Fair\n\n2025-1-01|Bad\njunk")
assert.deepStrictEqual(ev["2025-04-05"], ["Spring", "Market"])
assert.deepStrictEqual(ev["2025-04-06"], ["Fair"])
check(!ev["2025-1-01"], "malformed date ignored")
assert.deepStrictEqual(M.eventsForDay(ev, 2025, 3, 5), ["Spring", "Market"])
assert.deepStrictEqual(M.eventsForDay(ev, 2025, 3, 7), [])
assert.deepStrictEqual(M.eventsForDay("2025-04-05|Walked", 2025, 3, 5), ["Walked"])
assert.strictEqual(M.eventsForDay(M.parseEvents("2025-01-01|One\n2025-01-01|One"), 2025, 0, 1).length, 1)
check(!M.parseEvents("2025-02-30|Impossible")["2025-02-30"], "invalid calendar date ignored")
var birthdays = M.parseBirthdays("04-05|Alice\n12-31|Bob\n02-30|Bad\n04-05|Alice")
assert.deepStrictEqual(birthdays["04-05"], ["Alice"])
assert.deepStrictEqual(M.birthdaysForDay(birthdays, 2026, 3, 5), ["Alice"])
assert.deepStrictEqual(M.birthdaysForDay(birthdays, 2026, 3, 6), [])
var personal = M.upcomingPersonalEvents(
  M.parseEvents("2026-04-06|Dentist\n2026-04-05|Market"),
  birthdays, 4, "2026-04-05")
assert.strictEqual(personal[0].name, "Alice")
assert.strictEqual(personal[0].kind, "birthday")
assert.strictEqual(personal[0].dayOffset, 0)
assert.strictEqual(personal[1].name, "Market")
assert.strictEqual(personal[2].name, "Dentist")

// ---- world clock ----------------------------------------------------------
var places = M.parsePlaces("Nairobi, KE\nnairobi, KE\ntokyo, JP\nbad line")
assert.strictEqual(places.length, 2)
assert.strictEqual(places[0].name, "Nairobi")
assert.strictEqual(places[0].cc, "KE")
assert.strictEqual(M.parseCountryList("Kenya, KE\nJapan, JP").length, 2)
var p = M.zoneTimeParts(new Date(0), 180)
assert.deepStrictEqual(p, { hour: 3, minute: 0, second: 0, ampm: "AM", hour12: 3 })
var half = M.zoneTimeParts(new Date(0), 210)
assert.strictEqual(half.minute, 30)
assert.strictEqual(half.ampm, "AM")
assert.strictEqual(M.placeTimeString(half), "3:30 AM")
var pm = M.zoneTimeParts(new Date(0), -480)
assert.strictEqual(pm.hour, 16)
assert.strictEqual(pm.ampm, "PM")
assert.strictEqual(pm.hour12, 4)
var rows = M.worldClockRows("Nairobi, KE\nTokyo, JP", new Date(0))
assert.strictEqual(rows.length, 2)
assert.strictEqual(rows[0].name, "Nairobi")
assert.strictEqual(rows[0].minute, 0)
assert.strictEqual(rows[0].time, "3:00 AM")
assert.strictEqual(rows[0].dateOffset, 0)
assert.strictEqual(rows[1].time, "9:00 AM")
assert.strictEqual(rows[1].ampm, "AM")
var rollover = M.worldClockRows("Tokyo, JP\nNew York, US", new Date(Date.UTC(2025, 0, 1, 23, 30)))
assert.strictEqual(rollover[0].dateOffset, 1)
assert.strictEqual(rollover[1].dateOffset, 0)


var Countries = require("../countries.js")
var catalog = M.placeCatalog(Countries.COUNTRIES)
check(catalog.length > 100, "placeCatalog includes countries")
var hits = M.searchPlaces(catalog, "nairo", 6)
assert.strictEqual(hits[0].name, "Nairobi")
assert.strictEqual(hits[0].cc, "KE")
assert.strictEqual(hits[0].zone, "Africa/Nairobi")
var added = M.addPlace("Nairobi, KE, Africa/Nairobi", "Paris", "FR", "Europe/Paris")
assert.strictEqual(added, "Nairobi, KE, Africa/Nairobi\nParis, FR, Europe/Paris")
assert.strictEqual(M.addPlace(added, "Paris", "FR", "Europe/Paris"), added)
assert.strictEqual(M.removePlaceAt(added, 0), "Paris, FR, Europe/Paris")
assert.strictEqual(M.serializePlaces(M.parsePlaces(added)), added)

console.log("PASS test-core: " + checks + " checks")