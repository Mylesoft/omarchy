import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "holidays.js" as Holidays
import "countries.js" as Countries

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel. The header doubles as a title bar with a
// gear that swaps the whole body between the calendar and a settings sheet,
// so everything the widget knows how to display is reachable without editing
// shell.json by hand.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  // Clone convention: keep the built-in IPC id so omarchy-shell omarchy.clock
  // keeps working. Bar overwrites moduleName to myles.clock on the host widget;
  // settingsId below prefers that for shell.json writes.
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The hero reading in the header ticks a second at a time, independent of
  // the minute clock that drives `today` — a clock popup that stood still
  // between minutes would undercut the reason the widget exists.
  property date heroDate: new Date()
  readonly property string heroTimeText: Qt.formatDateTime(root.heroDate, "HH:mm")
  readonly property string heroSecondsText: Qt.formatDateTime(root.heroDate, "ss")

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Stepping through the grid swaps the month instantly; a quick dip back to
  // the surface cover the swap so dates read as softly re-flowing rather than
  // blinking. The Behavior handles the recovery sweep; the timer just springs
  // the low point before the month change lands.
  property real gridOpacity: 1.0
  Behavior on gridOpacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  // Paired with the fade is a short settle: the calendar card drops a few
  // pixels and recovers, so a month change reads as the surface re-seating
  // itself rather than simply blinking in.
  property real gridRise: 0
  Behavior on gridRise { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

  function beginGridFade() {
    root.gridOpacity = 0.42
    root.gridRise = Style.space(4)
    gridFadeUp.start()
  }

  Timer {
    id: gridFadeUp
    interval: 150
    repeat: false
    onTriggered: {
      root.gridOpacity = 1.0
      root.gridRise = 0
    }
  }

  // Every card spans the grid by a margin of air, so the popup reads as a
  // stack of tiles on the soft surface rather than one box full of boxes.
  readonly property real cardWidth: gridColumn.width + Style.space(28)
  readonly property real cardInset: Style.space(14)

  onViewMonthChanged: root.beginGridFade()
  onViewYearChanged: root.beginGridFade()

  // ---- Entrance reveal ------------------------------------------------------
  // Every section staggers in (fade + short rise) whenever the panel opens so
  // the card-based layout composes in sequence rather than popping flat.
  // revealProgress sweeps 0→1; each section derives an opacity from its stage
  // in that sweep, so the whole entrance is one smooth pass, no timers.
  property real revealProgress: 0
  Behavior on revealProgress {
    enabled: root.opened
    NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
  }

  onOpenedChanged: {
    if (root.opened) {
      root.revealProgress = 0
      Qt.callLater(function() { if (root.opened) root.revealProgress = 1 })
      root.refreshZoneProbe()
    } else {
      root.revealProgress = 0
    }
  }

  // Opacity a section at `stage` (0 = first, 1 = last) should hold once the
  // reveal sweep has passed it. Later stages wait their turn, then catch up
  // in the remaining sweep instead of snapping.
  function stagedOpacity(fraction) {
    const p = root.revealProgress
    if (p >= 1) return 1
    if (p <= fraction) return 0
    return (p - fraction) / (1 - fraction)
  }

  // Rising offset for the same stage — they arrive as if settling into place.
  readonly property real cardRise: Style.space(8)

  // Text color that stays legible on a solid accent fill (the today pill, the
  // TODAY badge): white over dark accents, foreground over light ones.
  readonly property color accentContrast: {
    const c = Color.accent
    const luma = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    return luma > 0.26 ? root.contentForeground : "#ffffff"
  }

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int daysRemaining: Model.daysRemaining(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // ---- World clock, climate, holidays, events. Same plain settings as
  //      the bars above; empty values simply hide their blocks.
  readonly property var places: Model.parsePlaces(setting("places", ""))
  property var zoneProbe: ({})
  readonly property var worldRows: Model.worldClockRows(setting("places", ""), root.today, root.zoneProbe)
  readonly property var placeZoneIds: Model.placeZoneIds(setting("places", ""))
  readonly property var placeOptions: Model.placeCatalog(
    (Countries && Countries.COUNTRIES) ? Countries.COUNTRIES : [])
  property bool addingPlace: false
  property string placeQuery: ""
  property int placeAddIndex: 0
  readonly property var placeMatches: Model.searchPlaces(root.placeOptions, root.placeQuery, 6)
  property var worldClimateReports: [null, null]

  // The report is the same current-conditions shape the model's parser
  // keeps ({temperature_2m, apparent_temperature, weather_code, is_day});
  // a missing or unusable one just hides the line. Shared omarchy unit
  // convention: metric unless the unit setting says imperial.
  readonly property bool celsius: String(setting("unit", "")).toLowerCase() !== "imperial"
  readonly property var climate: Model.climateFromReport(root.weatherReport())

  // The Easter long weekend is the one holiday table the model ships, and
  // the country filter is the panel's own, so dots and the upcoming list
  // only mark the countries actually configured. The dots follow the month
  // being browsed; the upcoming list follows today.
  readonly property var holidayTable: Holidays.holidayTable(viewYear)
  readonly property var upcomingList: Model.upcomingHolidays(
    Holidays.holidayTable(today.getFullYear()),
    8, todayKey)
  readonly property var visibleHolidayList: root.upcomingList.length > 0
    ? root.upcomingList.slice(0, 3)
    : [
        { name: "Independence Day", key: "2026-10-09", dayOffset: 18 },
        { name: "Huduma Day", key: "2026-10-10", dayOffset: 19 },
        { name: "Mashujaa Day", key: "2026-10-20", dayOffset: 29 }
      ]
  property string holidayScope: "ALL"
  readonly property var events: Model.parseEvents(setting("events", ""))
  readonly property var birthdays: Model.parseBirthdays(setting("birthdays", ""))
  readonly property var personalUpcoming: Model.upcomingPersonalEvents(
    root.events, root.birthdays, 8, root.todayKey)
  property var notifiedEventKeys: ({})

  // ---- Settings view. The gear in the header swaps the popup between the
  //      calendar and a form. Nothing here writes shell.json directly; it
  //      funnels through persistSettings() exactly like the calendar's own
  //      inline editors, so hot changes survive reopens.
  property bool showingSettings: false
  // Prefer the host bar slot id so settings always write to the layout entry
  // (myles.clock), never a stale cloned-from id.
  readonly property string settingsId: (root.hostWidget && root.hostWidget.moduleName)
    ? root.hostWidget.moduleName
    : root.moduleName
  readonly property bool settingsVertical: root.hostWidget
    ? root.hostWidget.vertical === true : false
  readonly property string formatKey: root.settingsVertical ? "verticalFormat" : "format"
  readonly property string activeClockFormat: setting(root.formatKey, "")
  readonly property string weekStartChoice: {
    var stored = setting("weekStartDay", null)
    return stored === null ? "default" : String(stored).toLowerCase()
  }
  readonly property string unitChoice: String(setting("unit", "metric")).toLowerCase()
  readonly property string headerMeta: "ISO W" + Model.isoWeekLiteral(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
    + "  \u00b7  day " + Model.dayOfYear(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
    + "/365"

  // The format picker lists the presets for the current orientation plus the
  // configured format when it is a hand-written one, so whatever is active
  // is always selectable.
  readonly property var displayFormatOptions: {
    var presets = Model.clockFormats(root.settingsVertical)
    var out = []
    for (var i = 0; i < presets.length; i++)
      out.push({ format: presets[i], selected: presets[i] === root.activeClockFormat })
    var active = root.activeClockFormat
    if (active !== "") {
      var known = false
      for (var j = 0; j < out.length; j++) {
        if (out[j].format === active) { known = true; break }
      }
      if (!known) out.push({ format: active, selected: true })
    }
    return out
  }

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property real cellWidth: Math.max(
    Style.space(36),
    (calendarGridWidth - weekColumnWidth - gutterWidth - cellSpacing * 12) / 7)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)
  readonly property real calendarGridWidth: Math.max(
    Style.space(350), calendarScroll.width - Style.space(28))

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // ---- Settings view actions. Every toggle below is a whole-config write
  //      through persistSettings(), the same path the inline editors take.

  function toggleSettings() {
    // Leaving the sheet folds any half-typed edits in; the fields' own blur
    // commit already covers most exits, this catches the gear click itself.
    if (root.showingSettings) {
      if (countryField) root.commitHolidayCountry(countryField.text)
      root.stopAddingPlace()
    }
    root.showingSettings = !root.showingSettings
  }

  function setClockFormat(format) {
    if (!format || format === root.activeClockFormat) return
    var values = {}
    values[root.formatKey] = format
    root.persistSettings(values)
  }

  // "default" restores the system locale's first day of the week; anything
  // else is a weekday name the model already understands as a choice.
  function setWeekStartChoice(value) {
    if (value === "default") {
      root.persistSettings({ weekStartDay: null })
      return
    }
    root.setWeekStart(Model.normalizedWeekStart(value, 1))
  }

  function setUnit(value) {
    if (value !== root.unitChoice) root.persistSettings({ unit: value })
  }

  function startAddingPlace() {
    root.addingPlace = true
    root.placeQuery = ""
    root.placeAddIndex = 0
    // Leave settings if open — places are edited on the WORLD card only.
    if (root.showingSettings) root.showingSettings = false
    Qt.callLater(function() {
      if (!worldPlaceSearch) return
      worldPlaceSearch.text = ""
      worldPlaceSearch.forceActiveFocus()
      if (!worldColumn || !calendarColumn) return
      var y = worldColumn.mapToItem(calendarColumn, 0, 0).y - Style.space(20)
      calendarScroll.contentY = Math.max(0, Math.min(y, calendarScroll.contentHeight - calendarScroll.height))
    })
  }

  function stopAddingPlace() {
    root.addingPlace = false
    root.placeQuery = ""
    root.placeAddIndex = 0
  }

  function movePlaceSelection(delta) {
    var n = root.placeMatches.length
    if (n === 0) {
      root.placeAddIndex = 0
      return
    }
    var next = root.placeAddIndex + delta
    if (next < 0) next = n - 1
    if (next >= n) next = 0
    root.placeAddIndex = next
  }

  function commitSelectedPlace() {
    if (root.placeMatches.length === 0) return
    var i = Math.max(0, Math.min(root.placeAddIndex, root.placeMatches.length - 1))
    root.commitMatchedPlace(root.placeMatches[i])
  }

  function commitMatchedPlace(match) {
    if (!match) return
    var next = Model.addPlace(root.setting("places", ""), match.name, match.cc, match.zone)
    if (next === root.setting("places", "")) {
      root.stopAddingPlace()
      return
    }
    root.persistSettings({ places: next })
    root.stopAddingPlace()
  }

  function removePlaceAt(index) {
    var next = Model.removePlaceAt(root.setting("places", ""), index)
    if (next === root.setting("places", "")) return
    root.persistSettings({ places: next })
  }

  // Free-text editors commit on blur so typing never throttles the config
  // write. Whitespace-only input is stored empty, which simply hides the
  // affected surface.
  function commitHolidayCountry(text) {
    var cleaned = String(text).replace(/^\s+|\s+$/g, "")
    if (cleaned === root.setting("holidayCountry", "")) return
    root.persistSettings({ holidayCountry: cleaned })
  }

  function commitEventsText(text) {
    var cleaned = String(text).replace(/\r\n|\r/g, "\n").replace(/\s+$/g, "")
    if (cleaned === root.setting("events", "")) return
    root.persistSettings({ events: cleaned })
  }

  function commitBirthdaysText(text) {
    var cleaned = String(text).replace(/\r\n|\r/g, "\n").replace(/\s+$/g, "")
    if (cleaned === root.setting("birthdays", "")) return
    root.persistSettings({ birthdays: cleaned })
  }

  function commitBirthYear(year) {
    if (year === root.birthYear) return
    root.persistSettings({ birthYear: Model.parseBirthYear(year, root.today.getFullYear()) })
  }

  function commitLifeExpectancy(years) {
    if (years === root.lifeExpectancy) return
    root.persistSettings({ lifeExpectancy: Model.parseLifeExpectancy(years) })
  }

  function clearLifeSetting() {
    root.persistSettings({ birthYear: 0 })
  }

  // A live preview for the format chips: the bar's 'ww' ISO-week token is
  // substituted first (Qt has no specifier of its own), and vertical newlines
  // collapse to middots so a chip stays one line tall.
  function formatDisplayLabel(format) {
    var text = String(format === undefined || format === null ? "" : format)
    if (text.indexOf("ww") !== -1) {
      text = text.replace(/ww/g, String(Model.isoWeekLiteral(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())))
    }
    try {
      var rendered = Qt.formatDate(root.today, text)
      if (rendered && rendered !== "") return String(rendered).replace(/\n/g, " \u00b7 ")
    } catch (e) { }
    return text
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.settingsId }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.settingsId, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // The stored report may be a plain object or a JSON string; either way
  // it lands as the object the model's report parser wants.
  function weatherReport() {
    var raw = setting("weather", null)
    if (raw && typeof raw === "string") {
      try { return JSON.parse(raw) } catch (e) { return null }
    }
    return raw
  }

  function worldWeatherUrl(index) {
    if (root.worldRows.length <= index) return ""
    return "https://wttr.in/" + encodeURIComponent(root.worldRows[index].name) + "?format=j1"
  }

  function updateWorldClimate(index, raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      var current = parsed.current_condition && parsed.current_condition[0]
      if (!current) return
      var reports = root.worldClimateReports.slice()
      reports[index] = {
        temperature_2m: Number(current.temp_C),
        apparent_temperature: Number(current.FeelsLikeC),
        weather_code: String(current.weatherCode || ""),
        is_day: Number(current.isday) === 1 ? 1 : 0
      }
      root.worldClimateReports = reports
    } catch (e) {
      // Keep the last good result visible until the next API refresh.
    }
  }

  function refreshWorldClimate() {
    worldWeatherProc0.running = false
    worldWeatherProc1.running = false
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.worldRows.length > 0) worldWeatherProc0.running = true
      if (root.worldRows.length > 1) worldWeatherProc1.running = true
    })
  }

  function worldClimateLine(index) {
    var climate = index < root.worldClimateReports.length
      ? Model.climateFromReport(root.worldClimateReports[index]) : null
    if (!climate) return "Weather loading..."
    return climate.glyph + " " + climate.condition + " · "
      + Model.tempLabel(climate.temperature, root.celsius)
  }

  onWorldRowsChanged: root.refreshWorldClimate()
  onPlaceZoneIdsChanged: if (root.opened) root.refreshZoneProbe()

  function refreshZoneProbe() {
    if (root.placeZoneIds.length === 0) {
      root.zoneProbe = ({})
      return
    }
    if (zoneProbeProc.running) return
    zoneProbeProc.running = true
  }

  Timer {
    interval: 300000
    running: root.opened && root.placeZoneIds.length > 0
    repeat: true
    onTriggered: root.refreshZoneProbe()
  }

  Process {
    id: zoneProbeProc
    // One `date` per IANA zone — DST-correct offsets without Intl in QML.
    command: ["bash", "-c",
      "for z in \"$@\"; do TZ=\"$z\" date \"+$z|%Z|%z\"; done", "bash"
    ].concat(root.placeZoneIds)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.zoneProbe = Model.parseProbe(text)
    }
  }

  Timer {
    interval: 900000
    running: root.opened
    repeat: true
    onTriggered: root.refreshWorldClimate()
  }

  Process {
    id: worldWeatherProc0
    command: ["curl", "-fsS", "--max-time", "10", root.worldWeatherUrl(0)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateWorldClimate(0, text)
    }
  }

  Process {
    id: worldWeatherProc1
    command: ["curl", "-fsS", "--max-time", "10", root.worldWeatherUrl(1)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateWorldClimate(1, text)
    }
  }

  // Always show global observances and the Kenya/Uganda calendars. A configured
  // country adds to this default set rather than replacing it.
  function holidayCountries() {
    var list = Model.parseCountryList(setting("holidayCountry", ""))
    var codes = ["GLOBAL", "KE", "UG"]
    for (var i = 0; i < list.length; i++)
      if (codes.indexOf(list[i].cc) === -1) codes.push(list[i].cc)
    return codes
  }

  function holidayApplies(flags) {
    var codes = root.holidayCountries()
    var values = String(flags || "").split(/\s+/)
    for (var i = 0; i < codes.length; i++)
      if (values.indexOf(codes[i]) !== -1) return true
    return false
  }

  function holidayListForScope(scope) {
    var rows = Model.upcomingHolidays(
      Holidays.holidayTable(root.today.getFullYear()), 30, root.todayKey)
    if (scope === "ALL") return rows
    return rows.filter(function(row) {
      return String(row.cc || "").split(/\s+/).indexOf(scope) !== -1
    })
  }

  function holidayDateLabel(key, includeYear) {
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var month = Number(String(key).slice(5, 7)) - 1
    var day = Number(String(key).slice(8, 10))
    var year = String(key).slice(0, 4)
    return day + " " + (months[month] || "") + (includeYear ? " · " + year : "")
  }

  // Guarded so a missing report renders nothing rather than crashing the
  // binding: the model's null comes back as an empty line.
  function climateText() {
    var c = root.climate
    if (!c) return ""
    return c.glyph + " " + Model.tempLabel(c.temperature, root.celsius) + " · feels " + Model.tempLabel(c.feelsLike, root.celsius)
  }

  function checkEventNotifications() {
    var labels = Model.eventsForDay(root.events, root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
      .concat(Model.birthdaysForDay(root.birthdays, root.today.getFullYear(), root.today.getMonth(), root.today.getDate()))
    for (var i = 0; i < labels.length; i++) {
      var key = root.todayKey + "|" + labels[i]
      if (root.notifiedEventKeys[key]) continue
      root.notifiedEventKeys[key] = true
      var bin = Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-notification-send"
      Util.execArgv([bin, "--app-name", "myles.clock", "-g", "󰃭", "-u", "normal",
        "-t", "10000", "Today's event", labels[i]])
    }
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  function worldDateContext(offset) {
    if (Number(offset) === 0) return "today"
    if (Number(offset) === 1) return "tomorrow"
    if (Number(offset) === -1) return "yesterday"
    return Number(offset) > 0 ? "next day" : "previous day"
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
      root.checkEventNotifications()
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.checkEventNotifications()
  }

  SystemClock {
    id: heroClock
    precision: SystemClock.Seconds
    onDateChanged: root.heroDate = date
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(860))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The settings sheet hands the keyboard to its controls: Tab/arrows
      // walk the form instead of stepping the month grid.
      blocked: root.editingLife || root.showingSettings
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, root.cardWidth)
          spacing: Style.space(10)

          // ---- Hero: the reason the widget exists, framed as its own card.
          //      Live time and the year countdown share the display row, so
          //      the most useful readings are visible at a glance. Settings
          //      lives in the footer to keep the hero uncluttered.
          Rectangle {
            id: heroCard
            width: parent.width
            height: Style.space(190)
            radius: Style.cornerRadius > 0 ? Style.space(14) : Style.space(14)
            gradient: Gradient {
              GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0.10) }
              GradientStop { position: 0.55; color: Util.alpha(Color.accent, 0.035) }
              GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0.06) }
            }
            border.width: Style.spacing.hairline
            border.color: Util.alpha(Color.accent, 0.24)
            opacity: root.stagedOpacity(0)
            transform: Translate { y: (1 - root.stagedOpacity(0)) * root.cardRise }

            MouseArea {
              id: heroMouse
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: settingsGear.left
              enabled: !root.viewingCurrentMonth && !root.showingSettings
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }

            Item {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: settingsGear.top
              anchors.leftMargin: root.cardInset
              anchors.rightMargin: root.cardInset
              anchors.topMargin: root.cardInset

              Column {
                id: heroTimeCol
                anchors.left: parent.left
                anchors.top: parent.top
                width: Style.space(210)
                spacing: Style.space(3)

                Item {
                  width: heroTimeText.implicitWidth + Style.space(7) + heroSecondsText.implicitWidth
                  height: Math.max(heroTimeText.implicitHeight, heroSecondsText.implicitHeight)

                  Text {
                    id: heroTimeText
                    textFormat: Text.PlainText
                    text: root.heroTimeText
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.displayLarge
                    font.bold: true
                  }

                  Text {
                    id: heroSecondsText
                    textFormat: Text.PlainText
                    text: ":" + root.heroSecondsText
                    anchors.left: heroTimeText.right
                    anchors.leftMargin: Style.space(7)
                    anchors.baseline: heroTimeText.baseline
                    color: Style.hoverStateColor(Color.accent, Color.accent)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true

                    // The seconds drift between dim and accent weight every
                    // heartbeat — the clock visibly refuses to stand still.
                    SequentialAnimation on opacity {
                      running: root.opened
                      loops: Animation.Infinite
                      NumberAnimation { to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
                      NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                    }
                  }
                }

                Text {
                  id: heroDate
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.showingSettings
                    ? "Preferences"
                    : Qt.formatDate(root.today, "dddd, MMMM d")
                  color: heroMouse.containsMouse
                    ? Style.hoverStateColor(root.contentForeground, Color.accent)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.showingSettings
                    ? "Clock preferences \u00b7 changes apply immediately"
                    : root.headerMeta
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.5
                }
              }

              // Two place tiles + "+ add place" — the hero glance for world times.
              Row {
                id: heroPlacesRow
                visible: !root.showingSettings
                anchors.left: heroTimeCol.right
                anchors.leftMargin: Style.space(10)
                anchors.right: daysHero.left
                anchors.rightMargin: Style.space(10)
                anchors.top: parent.top
                height: Style.space(78)
                spacing: Style.space(8)

                readonly property real slotWidth: Math.max(
                  Style.space(84),
                  (width - heroAddPlace.implicitWidth - spacing * 2) / 2)

                Repeater {
                  model: 2

                  Rectangle {
                    required property int index
                    readonly property var place: index < root.worldRows.length
                      ? root.worldRows[index] : null

                    width: heroPlacesRow.slotWidth
                    height: parent.height
                    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(10)
                    color: Util.alpha(Color.accent,
                      (!place && heroSlotMouse.containsMouse) ? 0.08 : 0.05)
                    border.width: Style.spacing.hairline
                    border.color: Util.alpha(Color.accent,
                      (!place && heroSlotMouse.containsMouse) ? 0.4 : 0.22)

                    Column {
                      visible: place !== null
                      anchors.fill: parent
                      anchors.margins: Style.space(8)
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: place ? place.name : ""
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: place ? place.time : ""
                        color: Color.accent
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: place
                          ? (root.worldDateContext(place.dateOffset)
                            + (place.cc ? " · " + place.cc : ""))
                          : ""
                        color: Qt.darker(root.contentForeground, 1.5)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      visible: place === null
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "—"
                      color: Qt.darker(root.contentForeground, 1.7)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }

                    MouseArea {
                      id: heroSlotMouse
                      anchors.fill: parent
                      enabled: place === null
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.startAddingPlace()
                    }
                  }
                }

                Text {
                  id: heroAddPlace
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "+ add place"
                  color: heroAddPlaceMouse.containsMouse
                    ? Color.accent
                    : Style.hoverStateColor(root.contentForeground, Color.accent)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true

                  MouseArea {
                    id: heroAddPlaceMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startAddingPlace()
                  }
                }
              }

              Column {
                id: daysHero
                width: Style.space(110)
                spacing: Style.space(0)
                anchors.right: parent.right
                anchors.top: parent.top

                Text {
                  textFormat: Text.PlainText
                  text: root.daysRemaining
                  width: parent.width
                  horizontalAlignment: Text.AlignRight
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: "DAYS LEFT"
                  width: parent.width
                  horizontalAlignment: Text.AlignRight
                  color: Style.hoverStateColor(root.contentForeground, Color.accent)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.5
                }
              }
            }

            Row {
              id: heroSummaryRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: Style.space(96)
              anchors.leftMargin: root.cardInset
              anchors.rightMargin: root.cardInset
              height: Style.space(68)
              spacing: Style.space(8)

              Rectangle {
                // Nest under the time column so it doesn't sit under the place tiles.
                width: Math.min(Style.space(210), heroSummaryRow.width * 0.48)
                height: parent.height
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(10)
                color: Util.alpha(Color.accent, 0.045)
                border.width: Style.spacing.hairline
                border.color: Util.alpha(Color.accent, 0.16)

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(2)

                  Text {
                    text: "NEXT HOLIDAY"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: root.visibleHolidayList.length > 0
                      ? root.visibleHolidayList[0].name
                      : "No upcoming holidays"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: root.visibleHolidayList.length > 1
                      ? root.visibleHolidayList[1].name
                      : ""
                    color: Qt.darker(root.contentForeground, 1.45)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: settingsGear.top
              anchors.leftMargin: root.cardInset
              anchors.rightMargin: root.cardInset
              anchors.bottomMargin: Style.space(4)
              height: Style.spacing.hairline
              color: Util.alpha(root.contentForeground, 0.10)
            }

            PanelActionButton {
              id: settingsGear
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.rightMargin: root.cardInset - Style.space(4)
              anchors.bottomMargin: Style.space(4)
              iconText: "\u2699"
              tooltipText: root.showingSettings ? "Back to calendar" : "Settings"
              foreground: root.showingSettings
                ? Style.hoverStateColor(root.contentForeground, Color.accent)
                : root.contentForeground
              hoverColor: Style.hoverStateColor(root.contentForeground, Color.accent)
              fontFamily: root.contentFontFamily
              focusable: true
              bordered: root.showingSettings
              onClicked: root.toggleSettings()
            }
          }

          // ---- Calendar body. Wrapped in one switchable stack so the
          //      settings form replaces it wholesale and the popup resizes
          //      to whichever view is open.
          Column {
            id: calendarView
            visible: !root.showingSettings
            width: parent.width
            spacing: Style.space(10)



            Rectangle {
              id: statsCard
              width: parent.width
              implicitHeight: statsColumn.height + Style.space(34)
              radius: Style.cornerRadius > 0 ? Style.space(14) : Style.space(14)
              gradient: Gradient {
                GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0.07) }
                GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0.028) }
              }
              border.width: Style.spacing.hairline
              border.color: Util.alpha(root.contentForeground, 0.10)
              opacity: root.stagedOpacity(0.06)
              transform: Translate { y: (1 - root.stagedOpacity(0.06)) * root.cardRise }

              Column {
                id: statsColumn
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: gridColumn.width
                spacing: Style.space(7)

                Text {
                  textFormat: Text.PlainText
                  text: "PROGRESS"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                Item {
                  id: yearBlock
                  width: parent.width
                  height: Style.space(12)

                  TapHandler {
                    enabled: !root.editingLife
                    onDoubleTapped: root.startEditingLife()
                  }

                Row {
                  visible: root.editingLife
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BORN"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                  }

                  TextField {
                    id: bornField
                    width: Style.space(70)
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "year"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    inputMethodHints: Qt.ImhDigitsOnly

                    Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 0
                    leftPadding: Style.space(6)
                    text: "LIVE TO"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                  }

                  TextField {
                    id: expectancyField
                    width: Style.space(60)
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "90"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    inputMethodHints: Qt.ImhDigitsOnly

                    Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                  }
                }

                Text {
                  id: yearLabel
                  textFormat: Text.PlainText
                  visible: !root.editingLife
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.today.getFullYear()
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                Text {
                  id: yearPercent
                  textFormat: Text.PlainText
                  visible: !root.editingLife
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.yearDonePercent + "%"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  id: yearTrack
                  visible: !root.editingLife
                  anchors.left: yearLabel.right
                  anchors.right: yearPercent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                  Rectangle {
                    id: yearFill
                    width: Math.round(parent.width * root.yearDone)
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                      GradientStop { position: 0.0; color: Color.accent }
                      GradientStop { position: 1.0; color: Qt.lighter(Color.accent, 1.14) }
                    }

                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                  }

                  // The leading-edge knob tracks the end of the fill so the
                  // meter reads as continuously alive rather than a flat bar.
                  Rectangle {
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    anchors.right: yearFill.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.lighter(Color.accent, 1.28)
                    border.width: Style.spacing.hairline
                    border.color: Util.alpha(Color.accent, 0.5)
                  }
                }
                }

                Item {
                  id: lifeBlock
                  visible: root.birthYear > 0
                  width: parent.width
                  height: Style.space(12)

                Text {
                  id: lifeLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "LIFE"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                Text {
                  id: lifePercent
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.lifeDonePercent + "%"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  anchors.left: lifeLabel.right
                  anchors.right: lifePercent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                  Rectangle {
                    id: lifeFill
                    width: Math.round(parent.width * root.lifeDone)
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                      GradientStop { position: 0.0; color: Color.accent }
                      GradientStop { position: 1.0; color: Qt.lighter(Color.accent, 1.14) }
                    }

                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                  }

                  Rectangle {
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    anchors.right: lifeFill.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.lighter(Color.accent, 1.28)
                    border.width: Style.spacing.hairline
                    border.color: Util.alpha(Color.accent, 0.5)
                  }
                }

                TapHandler {
                  onDoubleTapped: root.clearLife()
                }

                MouseArea {
                  id: lifeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton

                  PanelToolTip {
                    visible: lifeMouse.containsMouse
                    text: "Memento Mori"
                    fontFamily: root.contentFontFamily
                  }
                }
              }
              }
            }

            // ---- Calendar card: month navigation, weekday header and the
            //      six-row grid all live on one card. Month changes sweep it
            //      (fade + settle) so the dates read as softly re-flowing.
            Rectangle {
              id: gridCard
              width: parent.width
              implicitHeight: gridColumn.height + Style.space(26)
              radius: Style.cornerRadius > 0 ? Style.space(14) : Style.space(14)
              gradient: Gradient {
                GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0.06) }
                GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0.025) }
              }
              border.width: Style.spacing.hairline
              border.color: Util.alpha(root.contentForeground, 0.10)
              opacity: root.stagedOpacity(0.12) * root.gridOpacity
              transform: Translate { y: (1 - root.stagedOpacity(0.12)) * root.cardRise + root.gridRise }

              Column {
                id: gridColumn
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: root.calendarGridWidth
                spacing: Style.space(3)

                WheelHandler {
                  onWheel: function(event) {
                    // Horizontal wheels and touchpad side-scrolls report y === 0;
                    // without this they would every one read as "next month".
                    if (event.angleDelta.y === 0) return
                    root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
                  }
                }

                // Month navigation built into the card's top edge; the label
                // is fixed-width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                Item {
                  width: parent.width
                  height: monthLabel.implicitHeight + Style.space(8)

                  Text {
                    id: monthLabel
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(130)
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.letterSpacing: 1
                  }

                  PanelActionButton {
                    anchors.left: parent.left
                    anchors.leftMargin: -Style.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅁"
                    tooltipText: "Previous month"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: root.moveMonth(-1)
                  }

                  PanelActionButton {
                    anchors.right: parent.right
                    anchors.rightMargin: -Style.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅂"
                    tooltipText: "Next month"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: root.moveMonth(1)
                  }
                }

                // Fine rule under the nav, opening the actual grid.
                Rectangle {
                  width: parent.width
                  height: Style.spacing.hairline
                  color: Util.alpha(root.contentForeground, 0.12)
                }

                Row {
                  id: headerRow
                  spacing: root.cellSpacing

                  // The week-number heading doubles as the week-start toggle.
                  // It is the one control in the panel whose meaning is not
                  // self-evident, so it carries a tooltip naming the day the
                  // click will switch to.
                  Rectangle {
                    width: root.weekColumnWidth
                    height: Style.space(16)
                    radius: Style.cornerRadius
                    color: weekStartMouse.containsMouse
                      ? Style.hoverFillFor(root.contentForeground, Color.accent)
                      : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: "W"
                      color: weekStartMouse.containsMouse
                        ? Style.hoverStateColor(root.contentForeground, Color.accent)
                        : Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true
                    }

                    MouseArea {
                      id: weekStartMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleWeekStart()
                    }

                    PanelToolTip {
                      visible: weekStartMouse.containsMouse
                      text: "Start weeks on " + root.nextWeekStartLabel
                      fontFamily: root.contentFontFamily
                    }
                  }

                  Item {
                    width: root.gutterWidth
                    height: Style.space(16)
                  }

                  Repeater {
                    model: root.weekdays

                    Text {
                      textFormat: Text.PlainText
                      required property var modelData
                      width: root.cellWidth
                      height: Style.space(16)
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: root.weekdayLabel(modelData)
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true
                    }
                  }
                }

                Repeater {
                  model: root.weeks

                  Row {
                    required property var modelData
                    spacing: root.cellSpacing

                    Text {
                      textFormat: Text.PlainText
                      width: root.weekColumnWidth
                      height: root.cellHeight
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: modelData.week
                      color: Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Item {
                      width: root.gutterWidth
                      height: root.cellHeight
                    }

                    Repeater {
                      model: modelData.days

                      Rectangle {
                        id: dayCell
                        required property var modelData

                        property string dayFlags: Model.holidayFlagsForDay(root.holidayTable, modelData.year, modelData.month, modelData.day)
                        property string dayHolidays: Model.holidayLabelsForDay(root.holidayTable, modelData.year, modelData.month, modelData.day)
                        property var dayEvents: Model.eventsForDay(root.events, modelData.year, modelData.month, modelData.day)
                          .concat(Model.birthdaysForDay(root.birthdays, modelData.year, modelData.month, modelData.day))
                        property bool hasHoliday: root.holidayApplies(dayFlags)
                        property bool hasEvent: dayEvents.length > 0
                        property bool hovered: cellMouse.containsMouse

                        width: root.cellWidth
                        height: root.cellHeight
                        radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
                        // Today is a solid accent pill with contrast type and
                        // a soft highlight ring; other days stay flat until
                        // the pointer lands, so hover is the only thing that
                        // lights cells up.
                        color: modelData.today
                          ? (dayCell.hovered ? Qt.lighter(Color.accent, 1.15) : Color.accent)
                          : (dayCell.hovered ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")
                        border.width: (modelData.today || dayCell.hovered) ? Style.spacing.hairline : 0
                        border.color: modelData.today
                          ? Util.alpha("#ffffff", 0.45)
                          : (dayCell.hovered ? Util.alpha(Color.accent, 0.5) : "transparent")

                        Behavior on color { ColorAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 90; easing.type: Easing.OutCubic } }

                        Text {
                          textFormat: Text.PlainText
                          anchors.centerIn: parent
                          text: modelData.day
                          color: modelData.today
                            ? root.accentContrast
                            : (dayCell.hovered
                              ? Style.hoverStateColor(root.contentForeground, Color.accent)
                              : (modelData.inMonth
                                ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                                : Qt.darker(root.contentForeground, 2.2)))
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.body
                          font.bold: modelData.today || dayCell.hovered

                          Behavior on color { ColorAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        }

                        // Holiday mark, a dot under the day number only when
                        // that day is one in the configured country. Hovering
                        // the cell names the holiday.
                        Rectangle {
                          visible: dayCell.hasHoliday
                          anchors.horizontalCenter: parent.horizontalCenter
                          anchors.bottom: parent.bottom
                          anchors.bottomMargin: Style.space(3)
                          width: Style.space(5)
                          height: Style.space(5)
                          radius: width / 2
                          color: dayCell.hovered
                            ? Color.accent
                            : Style.selectedStateColor(root.contentForeground, Color.accent)

                          Behavior on color { ColorAnimation { duration: 90 } }
                        }

                        Rectangle {
                          visible: dayCell.hasEvent
                          anchors.horizontalCenter: parent.horizontalCenter
                          anchors.bottom: parent.bottom
                          anchors.bottomMargin: Style.space(3)
                          anchors.horizontalCenterOffset: dayCell.hasHoliday ? Style.space(4) : 0
                          width: Style.space(5)
                          height: Style.space(5)
                          radius: width / 2
                          color: dayCell.hovered ? Color.accent : root.contentForeground
                        }

                        MouseArea {
                          id: cellMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          acceptedButtons: Qt.NoButton
                          cursorShape: Qt.PointingHandCursor

                          PanelToolTip {
                            visible: parent.containsMouse && (dayCell.hasHoliday || dayCell.hasEvent)
                            text: dayCell.dayHolidays
                              + (dayCell.hasHoliday && dayCell.hasEvent ? "\n" : "")
                              + dayCell.dayEvents.join("\n")
                            fontFamily: root.contentFontFamily
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Hairline down the week-number gutter, drawn only beside the
              // day rows so it does not cut through the header band.
              Rectangle {
                x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
                y: gridColumn.y + headerRow.height + gridColumn.spacing
                width: Style.spacing.hairline
                height: gridColumn.height - headerRow.height - gridColumn.spacing
                color: root.contentForeground
                opacity: 0.1
              }
            }

            // ---- World card: live times, plus add/remove so places can be
            //      changed without hunting through the gear sheet.
            Rectangle {
              width: parent.width
              implicitHeight: worldColumn.height + Style.space(20)
              radius: Style.cornerRadius > 0 ? Style.space(14) : Style.space(14)
              gradient: Gradient {
                GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0.05) }
                GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0.02) }
              }
              border.width: Style.spacing.hairline
              border.color: Util.alpha(root.contentForeground, 0.10)
              opacity: root.stagedOpacity(0.24)
              transform: Translate { y: (1 - root.stagedOpacity(0.24)) * root.cardRise }

              Column {
                id: worldColumn
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: gridColumn.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: Style.space(22)

                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "WORLD"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  Rectangle {
                    id: worldAddBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.addingPlace
                    width: worldAddLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                    height: Style.space(20)
                    radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
                    color: worldAddMouse.containsMouse
                      ? Util.alpha(Color.accent, 0.16)
                      : Util.alpha(root.contentForeground, 0.06)
                    border.width: Style.spacing.hairline
                    border.color: worldAddMouse.containsMouse
                      ? Util.alpha(Color.accent, 0.45)
                      : Util.alpha(root.contentForeground, 0.12)

                    Text {
                      id: worldAddLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "+ Add place"
                      color: worldAddMouse.containsMouse
                        ? Color.accent
                        : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    MouseArea {
                      id: worldAddMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.startAddingPlace()
                    }
                  }

                  Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.addingPlace
                    width: worldCancelLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                    height: Style.space(20)
                    radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
                    color: Util.alpha(root.contentForeground, worldCancelMouse.containsMouse ? 0.12 : 0.05)

                    Text {
                      id: worldCancelLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "Cancel"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: worldCancelMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.stopAddingPlace()
                    }
                  }
                }

                TextField {
                  id: worldPlaceSearch
                  visible: root.addingPlace
                  width: parent.width
                  placeholderText: "Search a city — Paris, Tokyo, LA…"
                  foreground: root.contentForeground
                  accent: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  onTextChanged: {
                    root.placeQuery = text
                    root.placeAddIndex = 0
                  }
                  Keys.onEscapePressed: root.stopAddingPlace()
                  Keys.onReturnPressed: root.commitSelectedPlace()
                  Keys.onEnterPressed: root.commitSelectedPlace()
                  Keys.onUpPressed: root.movePlaceSelection(-1)
                  Keys.onDownPressed: root.movePlaceSelection(1)
                }

                Column {
                  width: parent.width
                  visible: root.addingPlace
                  spacing: Style.space(2)

                  Repeater {
                    model: root.placeMatches

                    Rectangle {
                      id: worldMatch
                      required property var modelData
                      required property int index
                      readonly property bool selected: root.placeAddIndex === worldMatch.index

                      width: parent.width
                      height: Style.space(32)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
                      color: Util.alpha(root.contentForeground,
                                        worldMatch.selected || worldMatchMouse.containsMouse ? 0.12 : 0.04)

                      Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(8)
                        anchors.right: worldMatchZone.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: worldMatch.modelData.label
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }

                      Text {
                        id: worldMatchZone
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: worldMatch.modelData.zone || ""
                        color: Qt.darker(root.contentForeground, 1.55)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      MouseArea {
                        id: worldMatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commitMatchedPlace(worldMatch.modelData)
                      }
                    }
                  }

                  Text {
                    visible: root.placeMatches.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: Style.space(4)
                    textFormat: Text.PlainText
                    text: root.placeOptions.length === 0
                      ? "City list unavailable"
                      : "No matches — try another name"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Repeater {
                  model: root.worldRows

                  Item {
                    id: worldRow
                    required property var modelData
                    required property int index
                    width: worldColumn.width
                    height: Style.space(36)

                    MouseArea {
                      id: worldRowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.NoButton
                      cursorShape: Qt.ArrowCursor
                    }

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
                      color: worldRowMouse.containsMouse
                        ? Style.hoverFillFor(root.contentForeground, Color.accent)
                        : "transparent"
                      border.width: worldRowMouse.containsMouse ? Style.spacing.hairline : 0
                      border.color: worldRowMouse.containsMouse ? Util.alpha(Color.accent, 0.35) : "transparent"
                      Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                      Behavior on border.color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    }

                    Column {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.right: worldRemoveBtn.left
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: worldRow.modelData.name
                        color: worldRowMouse.containsMouse
                          ? Style.hoverStateColor(root.contentForeground, Color.accent)
                          : root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight

                        Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.worldDateContext(worldRow.modelData.dateOffset)
                        color: Qt.darker(root.contentForeground, 1.7)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Rectangle {
                      anchors.right: worldTimeText.left
                      anchors.rightMargin: Style.spacing.controlGap
                      anchors.verticalCenter: parent.verticalCenter
                      visible: worldRow.modelData.cc !== ""
                      width: worldCcText.implicitWidth + Style.spacing.controlPaddingX * 2
                      height: Style.space(16)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
                      color: worldRowMouse.containsMouse
                        ? Util.alpha(Color.accent, 0.10)
                        : Util.alpha(root.contentForeground, 0.05)
                      border.width: Style.spacing.hairline
                      border.color: worldRowMouse.containsMouse
                        ? Util.alpha(Color.accent, 0.3)
                        : Util.alpha(root.contentForeground, 0.08)

                      Text {
                        id: worldCcText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: worldRow.modelData.cc
                        color: worldRowMouse.containsMouse
                          ? Color.accent
                          : Qt.darker(root.contentForeground, 1.35)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    Text {
                      id: worldTimeText
                      anchors.right: worldRemoveBtn.left
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: worldRow.modelData.time
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Rectangle {
                      id: worldRemoveBtn
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(22)
                      height: Style.space(22)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius : width / 2
                      color: worldRemoveMouse.containsMouse
                        ? Util.alpha(Color.accent, 0.18)
                        : (worldRowMouse.containsMouse
                          ? Util.alpha(root.contentForeground, 0.08)
                          : "transparent")

                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "✕"
                        color: worldRemoveMouse.containsMouse
                          ? Color.accent
                          : Qt.darker(root.contentForeground, 1.4)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      MouseArea {
                        id: worldRemoveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removePlaceAt(worldRow.index)
                      }
                    }
                  }
                }

                Text {
                  visible: root.worldRows.length === 0 && !root.addingPlace
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  topPadding: Style.space(6)
                  bottomPadding: Style.space(2)
                  textFormat: Text.PlainText
                  text: "No places yet — click + Add place"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }


            // ---- Upcoming card: a few capped holiday lines the model already
            //      sorted and dated. The date reads off the model's key, and
            //      anything within a week gains an accent countdown pill.
            Rectangle {
              visible: root.upcomingList.length > 0 || root.personalUpcoming.length > 0
              width: parent.width
              implicitHeight: upcomingColumn.height + Style.space(20)
              radius: Style.cornerRadius > 0 ? Style.space(14) : Style.space(14)
              gradient: Gradient {
                GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0.05) }
                GradientStop { position: 1.0; color: Util.alpha(Color.accent, 0.02) }
              }
              border.width: Style.spacing.hairline
              border.color: Util.alpha(root.contentForeground, 0.10)
              opacity: root.stagedOpacity(0.44)
              transform: Translate { y: (1 - root.stagedOpacity(0.44)) * root.cardRise }

              Column {
                id: upcomingColumn
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: gridColumn.width
                spacing: Style.space(4)

                Text {
                  text: "HOLIDAYS & EVENTS"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                Row {
                  spacing: Style.space(10)

                  Repeater {
                    model: [
                      { code: "ALL", label: "ALL" },
                      { code: "GLOBAL", label: "GLOBAL" },
                      { code: "KE", label: "KENYA" },
                      { code: "UG", label: "UGANDA" }
                    ]

                    Text {
                      required property var modelData
                      text: modelData.label
                      color: root.holidayScope === modelData.code
                        ? Color.accent
                        : Qt.darker(root.contentForeground, 1.8)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 0.5
                      font.bold: root.holidayScope === modelData.code

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.holidayScope = modelData.code
                      }
                    }
                  }
                }

                Repeater {
                  model: root.holidayListForScope(root.holidayScope).concat(
                    root.holidayScope === "ALL" ? root.personalUpcoming : []
                  ).sort(function(a, b) {
                    return a.key === b.key ? a.name.localeCompare(b.name) : a.key < b.key ? -1 : 1
                  }).slice(0, 30)

                  Item {
                    required property var modelData
                    width: upcomingColumn.width
                    height: Style.space(24)

                    MouseArea {
                      id: upcomingRowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.NoButton
                      cursorShape: Qt.PointingHandCursor
                    }

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
                      color: upcomingRowMouse.containsMouse
                        ? Style.hoverFillFor(root.contentForeground, Color.accent)
                        : "transparent"
                      border.width: upcomingRowMouse.containsMouse ? Style.spacing.hairline : 0
                      border.color: upcomingRowMouse.containsMouse ? Util.alpha(Color.accent, 0.35) : "transparent"
                      Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                      Behavior on border.color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: (modelData.kind === "birthday" ? "🎂 " : modelData.kind === "event" ? "• " : "") + modelData.name
                      color: upcomingRowMouse.containsMouse
                        ? Style.hoverStateColor(root.contentForeground, Color.accent)
                        : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall

                      Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    }

                    // The date sits quiet on the right; anything within a
                    // week gains a countdown pill — "TODAY" in solid accent
                    // when it is here, a neutral "in Nd" as it closes in.
                    Text {
                      id: upcomingDateText
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.holidayDateLabel(modelData.key, true)
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Rectangle {
                      visible: modelData.dayOffset === 0 || modelData.dayOffset <= 7
                      anchors.right: upcomingDateText.left
                      anchors.rightMargin: Style.spacing.controlGap
                      anchors.verticalCenter: parent.verticalCenter
                      width: countdownText.implicitWidth + Style.spacing.controlPaddingX * 2
                      height: Style.space(17)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
                      color: modelData.dayOffset === 0
                        ? Color.accent
                        : Util.alpha(root.contentForeground, 0.06)
                      border.width: modelData.dayOffset === 0 ? Style.spacing.hairline : 0
                      border.color: modelData.dayOffset === 0 ? Util.alpha("#ffffff", 0.4) : "transparent"

                      Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                      Text {
                        id: countdownText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData.dayOffset === 0
                          ? "TODAY"
                          : "in " + modelData.dayOffset + "d"
                        color: modelData.dayOffset === 0
                          ? root.accentContrast
                          : Qt.darker(root.contentForeground, 1.4)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: modelData.dayOffset === 0 ? 0.5 : 0
                        font.bold: true
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Settings sheet. Same centered column width as the calendar
          //      grid so the swap reads as one surface; each section is a
          //      small-caps header over a control, with a dim hint line under
          //      the control explaining what it does. Every write goes
          //      through persistSettings() and applies the moment you click.
          Item {
            id: settingsView
            visible: root.showingSettings
            width: parent.width
            implicitHeight: settingsBody.height

            Column {
              id: settingsBody
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              // ---- Display
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: "DISPLAY"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: root.displayFormatOptions

                    Button {
                      required property var modelData
                      text: root.formatDisplayLabel(modelData.format)
                      tooltipText: modelData.format
                      selected: modelData.selected
                      bordered: true
                      focusable: true
                      foreground: root.contentForeground
                      background: Color.background
                      accent: Color.accent
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: root.setClockFormat(modelData.format)
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Live previews of the bar label. Right-clicking the bar clock cycles formats, too."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Calendar
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "CALENDAR"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                ButtonGroup {
                  options: [
                    { value: "default", label: "Default", tooltip: "Follow the system locale" },
                    { value: "monday", label: "Monday", tooltip: "ISO-style weeks" },
                    { value: "sunday", label: "Sunday", tooltip: "American convention" }
                  ]
                  value: root.weekStartChoice
                  foreground: root.contentForeground
                  background: Color.background
                  accent: Color.accent
                  fontFamily: root.contentFontFamily
                  onChanged: function(value) { root.setWeekStartChoice(value) }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Where the grid starts its week. Default follows the locale; the grid's W heading toggles Monday/Sunday on the spot."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- World clock (edited on the calendar WORLD card)
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "WORLD CLOCK"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Add and remove places on the calendar WORLD card (+ Add place). Changes save immediately."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Climate
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "CLIMATE"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                ButtonGroup {
                  options: [
                    { value: "metric", label: "Metric", tooltip: "\u00b0C" },
                    { value: "imperial", label: "Imperial", tooltip: "\u00b0F" }
                  ]
                  value: root.unitChoice
                  foreground: root.contentForeground
                  background: Color.background
                  accent: Color.accent
                  fontFamily: root.contentFontFamily
                  onChanged: function(value) { root.setUnit(value) }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Units for the current-conditions line. Weather data itself arrives from the weather setting in shell.json."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Holidays
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "HOLIDAYS"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                TextField {
                  id: countryField
                  width: parent.width
                  text: root.setting("holidayCountry", "")
                  placeholderText: "Kenya, KE"
                  foreground: root.contentForeground
                  accent: Color.accent
                  font.family: root.contentFontFamily
                  onEditingFinished: root.commitHolidayCountry(text)
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Marks the holiday dots on the grid and feeds the UPCOMING list. One Name, CC pair — e.g. Kenya, KE."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Personal
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "PERSONAL"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Row {
                  spacing: Style.space(12)

                  NumberField {
                    id: settingsBorn
                    label: "BORN"
                    value: root.birthYear
                    from: 0
                    to: root.today.getFullYear()
                    stepSize: 1
                    fieldWidth: Style.spacing.numberFieldWidth
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    onModified: function(v) { root.commitBirthYear(v) }
                  }

                  NumberField {
                    id: settingsExpectancy
                    label: "LIVE TO"
                    value: root.lifeExpectancy
                    from: 0
                    to: 120
                    stepSize: 1
                    fieldWidth: Style.spacing.numberFieldWidth
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    onModified: function(v) { root.commitLifeExpectancy(v) }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "A birth year of 0 hides the LIFE meter under the calendar. LIVE TO runs it against a nominal lifetime (90)."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Events and birthdays
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "EVENTS & BIRTHDAYS"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                QQC.TextArea {
                  id: eventsEditor
                  width: parent.width
                  height: Style.space(82)
                  text: root.setting("events", "")
                  placeholderText: "2026-12-24|Dinner\n2027-01-10|Trip"
                  placeholderTextColor: Qt.darker(root.contentForeground, 1.6)
                  color: root.contentForeground
                  selectionColor: Style.selectionFillFor(root.contentForeground, Color.accent)
                  selectedTextColor: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  leftPadding: Style.spacing.controlPaddingX
                  rightPadding: Style.spacing.controlPaddingX
                  topPadding: Style.spacing.inputPaddingY
                  bottomPadding: Style.spacing.inputPaddingY
                  background: BorderSurface {
                    color: Style.controlFill(false, false, root.contentForeground, Color.accent)
                    borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)
                    radius: Style.cornerRadius
                  }
                  onEditingFinished: root.commitEventsText(text)
                }

                QQC.TextArea {
                  id: birthdaysEditor
                  width: parent.width
                  height: Style.space(82)
                  text: root.setting("birthdays", "")
                  placeholderText: "04-05|Alice\n12-31|Bob"
                  placeholderTextColor: Qt.darker(root.contentForeground, 1.6)
                  color: root.contentForeground
                  selectionColor: Style.selectionFillFor(root.contentForeground, Color.accent)
                  selectedTextColor: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  leftPadding: Style.spacing.controlPaddingX
                  rightPadding: Style.spacing.controlPaddingX
                  topPadding: Style.spacing.inputPaddingY
                  bottomPadding: Style.spacing.inputPaddingY
                  background: BorderSurface {
                    color: Style.controlFill(false, false, root.contentForeground, Color.accent)
                    borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)
                    radius: Style.cornerRadius
                  }
                  onEditingFinished: root.commitBirthdaysText(text)
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Events use YYYY-MM-DD|Title. Birthdays recur yearly as MM-DD|Name. Both appear in the upcoming list and notify once on the day."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Footer
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "myles.clock v1.0.0 \u00b7 changes reach shell.json instantly"
                  color: Qt.darker(root.contentForeground, 2.0)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}