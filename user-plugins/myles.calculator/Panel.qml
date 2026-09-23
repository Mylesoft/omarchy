import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "CalcEngine.js" as Calc
import "Converters.js" as Conv

BarWidget {
  id: root
  moduleName: "myles.calculator"

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/calculator"
  readonly property string settingsPath: stateDir + "/settings.json"
  readonly property string ratesPath: stateDir + "/rates-cache.json"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/myles.calculator"

  property bool popupOpen: false
  readonly property bool opened: popup.open
  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  // Shared calc state
  property string mode: "standard" // standard | scientific | programmer | fx | units | tip
  property string expression: ""
  property string display: "0"
  property string lastResult: ""
  property real memory: 0
  property bool memorySet: false
  property bool justEvaluated: false
  property string angleMode: "deg"
  property bool useGrouping: true
  property var history: []

  // Programmer
  property int progBase: 10
  property int progBits: 32
  property string progInput: "0"
  property real progValue: 0
  property string progPendingOp: ""
  property real progPendingA: 0
  property bool progFresh: true

  // FX
  property string fxAmount: "1"
  property string fxFrom: "USD"
  property string fxTo: "KES"
  property var fxRates: ({})
  property string fxBase: "USD"
  property double fxFetchedAt: 0
  property string fxUpdatedLabel: ""
  property bool fxStale: false
  property bool fxLoading: false
  property string fxError: ""
  property string fxResult: "—"

  // Units
  property string unitCategory: "length"
  property string unitFrom: "m"
  property string unitTo: "ft"
  property string unitAmount: "1"
  property string unitResult: "—"

  // Tip
  property string tipBill: "1000"
  property string tipPercent: "10"
  property string tipPeople: "2"
  property string tipVat: "16"
  property string tipVatMode: "none" // none | add | extract
  property string tipTotal: "—"
  property string tipPerPerson: "—"
  property string tipVatAmount: "—"
  property string tipTipAmount: "—"

  readonly property var modes: [
    { id: "standard", label: "Std" },
    { id: "scientific", label: "Sci" },
    { id: "programmer", label: "Prog" },
    { id: "fx", label: "FX" },
    { id: "units", label: "Units" },
    { id: "tip", label: "Tip" }
  ]

  readonly property var fxCurrencyList: Conv.FX_CURRENCIES
  readonly property var unitCategories: Conv.categoryList()
  readonly property var unitFromList: Conv.unitIds(unitCategory)
  readonly property var unitToList: Conv.unitIds(unitCategory)

  readonly property string barTooltip: {
    if (mode === "fx" && fxResult !== "—" && !fxError)
      return "1 " + fxFrom + " = " + fxStripHint() + " " + fxTo
    if (lastResult)
      return "Calculator · " + lastResult
    return "Calculator"
  }

  function fxStripHint() {
    var r = Conv.convertCurrency(1, fxFrom, fxTo, fxRates, fxBase)
    if (r.error) return "…"
    return Conv.formatRate(r.value)
  }

  function injectPopup() {
    popup.anchorItem = barButton
    popup.bar = root.bar
    popup.owner = root
    popup.focusTarget = keyCatcher
  }

  function open() {
    popup.open = true
    popupOpen = true
    if (mode === "fx") refreshFx()
  }

  function close() {
    popup.open = false
    popupOpen = false
    persistSettings()
  }

  function togglePanel() {
    if (opened) close()
    else open()
  }

  function setMode(m) {
    mode = m
    if (m === "fx") refreshFx()
    if (m === "units") recomputeUnits()
    if (m === "tip") recomputeTip()
    persistSettings()
  }

  function fg() {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  function fontFamily() {
    return root.bar ? root.bar.fontFamily : Style.font.family
  }

  function softFill(alpha) {
    var c = fg()
    return Qt.rgba(c.r, c.g, c.b, alpha)
  }

  function tabColor(id, mouse) {
    return mode === id
      ? Style.selectedFillFor(fg(), Color.accent)
      : mouse.containsMouse ? Style.hoverFillFor(fg(), Color.accent) : "transparent"
  }

  function keyFill(mouse, accent) {
    if (accent)
      return mouse.containsMouse
        ? Style.selectedFillFor(fg(), Color.accent)
        : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
    return mouse.containsMouse ? Style.hoverFillFor(fg(), Color.accent) : softFill(0.08)
  }

  // ---- Persistence ----
  function saveJson(path, json) {
    var cmd = "mkdir -p " + Util.shellQuote(stateDir)
      + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(path) + ".tmp"
      + " && mv -f " + Util.shellQuote(path) + ".tmp " + Util.shellQuote(path)
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function persistSettings() {
    saveJson(settingsPath, JSON.stringify({
      mode: mode,
      angleMode: angleMode,
      useGrouping: useGrouping,
      memory: memory,
      memorySet: memorySet,
      lastResult: lastResult,
      fxFrom: fxFrom,
      fxTo: fxTo,
      fxAmount: fxAmount,
      unitCategory: unitCategory,
      unitFrom: unitFrom,
      unitTo: unitTo,
      tipVat: tipVat,
      tipVatMode: tipVatMode,
      progBase: progBase,
      progBits: progBits,
      history: history
    }))
  }

  function applySettings(raw) {
    try {
      var s = JSON.parse(String(raw || "{}"))
      if (s.mode) mode = s.mode
      if (s.angleMode) angleMode = s.angleMode
      if (s.useGrouping !== undefined) useGrouping = !!s.useGrouping
      if (typeof s.memory === "number") { memory = s.memory; memorySet = !!s.memorySet }
      if (s.lastResult) lastResult = String(s.lastResult)
      if (s.fxFrom) fxFrom = s.fxFrom
      if (s.fxTo) fxTo = s.fxTo
      if (s.fxAmount) fxAmount = String(s.fxAmount)
      if (s.unitCategory) unitCategory = s.unitCategory
      if (s.unitFrom) unitFrom = s.unitFrom
      if (s.unitTo) unitTo = s.unitTo
      if (s.tipVat) tipVat = String(s.tipVat)
      if (s.tipVatMode) tipVatMode = s.tipVatMode
      if (s.progBase) progBase = Number(s.progBase)
      if (s.progBits) progBits = Number(s.progBits)
      if (Array.isArray(s.history)) history = s.history
    } catch (e) {}
  }

  function applyRatesCache(raw) {
    try {
      var s = JSON.parse(String(raw || "{}"))
      if (!s.rates) return
      fxRates = s.rates
      fxBase = s.base || "USD"
      fxFetchedAt = s.fetchedAt || 0
      fxUpdatedLabel = s.updatedAt || ""
      fxStale = true
      recomputeFx()
    } catch (e) {}
  }

  // ---- Standard / Scientific ----
  function clearAll() {
    expression = ""
    display = "0"
    justEvaluated = false
  }

  function clearEntry() {
    display = "0"
    if (justEvaluated) expression = ""
    justEvaluated = false
  }

  function backspace() {
    if (justEvaluated) { clearAll(); return }
    if (display.length <= 1 || (display.length === 2 && display[0] === "-"))
      display = "0"
    else
      display = display.slice(0, -1)
  }

  function appendDigit(d) {
    if (justEvaluated) {
      expression = ""
      display = d === "." ? "0." : d
      justEvaluated = false
      return
    }
    if (d === "." && display.indexOf(".") !== -1) return
    if (display === "0" && d !== ".") display = d
    else if (display === "-0" && d !== ".") display = "-" + d
    else display = display + d
  }

  function appendOp(op) {
    if (justEvaluated) {
      expression = display + op
      justEvaluated = false
      display = "0"
      return
    }
    expression = expression + display + op
    display = "0"
  }

  function appendUnaryFunc(fn) {
    // Apply function to current display immediately
    var expr = fn + "(" + display + ")"
    var r = Calc.evaluate(expr, angleMode)
    if (r.error) { display = "Error"; return }
    display = Calc.formatNumber(r.value)
    justEvaluated = true
    pushHist(expr, display)
  }

  function toggleSign() {
    if (display === "0" || display === "Error") return
    if (display[0] === "-") display = display.slice(1)
    else display = "-" + display
  }

  function insertParen(p) {
    if (justEvaluated) {
      expression = ""
      justEvaluated = false
    }
    if (p === "(") {
      expression = expression + (display !== "0" && display !== "" ? display : "") + "("
      display = "0"
    } else {
      expression = expression + display + ")"
      display = "0"
    }
  }

  function insertConst(name) {
    var v = name === "π" ? Math.PI : Math.E
    display = Calc.formatNumber(v)
    justEvaluated = false
  }

  function applyPercent() {
    var r = Calc.evaluate(display + "%", angleMode)
    // Treat as display/100 for simple percent
    var n = Number(display)
    if (!isFinite(n)) { display = "Error"; return }
    display = Calc.formatNumber(n / 100)
  }

  function evaluateNow() {
    var full = expression + display
    if (!String(full).trim()) return
    var r = Calc.evaluate(full, angleMode)
    if (r.error) {
      display = "Error"
      justEvaluated = true
      return
    }
    var formatted = Calc.formatGrouped(r.value, useGrouping)
    pushHist(full, formatted)
    lastResult = formatted
    expression = ""
    display = Calc.formatNumber(r.value)
    justEvaluated = true
    persistSettings()
  }

  function pushHist(expr, result) {
    history = Calc.pushHistory(history, { expr: expr, result: result, at: Date.now() }, 50)
  }

  function recallHistory(item) {
    expression = ""
    display = String(item.result).replace(/,/g, "")
    justEvaluated = true
  }

  function clearHistory() {
    history = []
    persistSettings()
  }

  function memClear() { memory = 0; memorySet = false; persistSettings() }
  function memRecall() { display = Calc.formatNumber(memory); justEvaluated = true }
  function memAdd() {
    var n = Number(display)
    if (!isFinite(n)) return
    memory += n; memorySet = true; persistSettings()
  }
  function memSub() {
    var n = Number(display)
    if (!isFinite(n)) return
    memory -= n; memorySet = true; persistSettings()
  }
  function memStore() {
    var n = Number(display)
    if (!isFinite(n)) return
    memory = n; memorySet = true; persistSettings()
  }

  function copyResult() {
    var text = mode === "programmer" ? progDisplay()
      : mode === "fx" ? fxResult
      : mode === "units" ? unitResult
      : mode === "tip" ? tipTotal
      : display
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(String(text)) + " | wl-copy"])
  }

  // ---- Programmer ----
  function progDisplay() {
    return Calc.formatBase(progValue, progBase, progBits)
  }

  function progRefreshInput() {
    progInput = progDisplay()
  }

  function progDigit(ch) {
    if (progFresh) { progInput = ""; progFresh = false }
    var next = progInput === "0" ? ch : progInput + ch
    var parsed = Calc.parseBase(next, progBase)
    if (parsed.error) return
    progInput = next.toUpperCase()
    progValue = parsed.value
  }

  function progClear() {
    progValue = 0
    progInput = "0"
    progPendingOp = ""
    progFresh = true
  }

  function progOp(op) {
    if (progPendingOp && !progFresh) {
      var r = Calc.bitwiseOp(progPendingOp, progPendingA, progValue, progBits)
      if (!r.error) progValue = r.value
    }
    progPendingA = progValue
    progPendingOp = op
    progFresh = true
    progRefreshInput()
  }

  function progEquals() {
    if (!progPendingOp) return
    var r = Calc.bitwiseOp(progPendingOp, progPendingA, progValue, progBits)
    if (r.error) return
    progValue = r.value
    pushHist(progPendingOp + " " + progPendingA + "," + progValue, progDisplay())
    progPendingOp = ""
    progFresh = true
    progRefreshInput()
    lastResult = progDisplay()
  }

  function progNot() {
    var r = Calc.bitwiseOp("NOT", progValue, 0, progBits)
    if (!r.error) {
      progValue = r.value
      progRefreshInput()
      progFresh = true
    }
  }

  function setProgBase(b) {
    progBase = b
    progRefreshInput()
  }

  // ---- FX ----
  function refreshFx() {
    if (fxFetch.running) return
    fxLoading = true
    fxError = ""
    fxFetch.command = ["curl", "-fsS", "--max-time", "12", Conv.fxUrl(fxFrom)]
    fxFetch.running = true
  }

  function onFxFetched(raw) {
    fxLoading = false
    var parsed = Conv.parseFxResponse(raw, fxFrom)
    if (parsed.error) {
      fxError = parsed.error
      fxStale = true
      recomputeFx()
      return
    }
    fxRates = parsed.rates
    fxBase = parsed.base
    fxFetchedAt = parsed.fetchedAt
    fxUpdatedLabel = parsed.updatedAt
    fxStale = false
    fxError = ""
    saveJson(ratesPath, JSON.stringify({
      base: fxBase,
      rates: fxRates,
      updatedAt: fxUpdatedLabel,
      fetchedAt: fxFetchedAt
    }))
    recomputeFx()
  }

  function recomputeFx() {
    var r = Conv.convertCurrency(fxAmount, fxFrom, fxTo, fxRates, fxBase)
    if (r.error) { fxResult = fxRates && Object.keys(fxRates).length ? "—" : "…"; return }
    fxResult = Conv.formatRate(r.value)
  }

  function swapFx() {
    var t = fxFrom
    fxFrom = fxTo
    fxTo = t
    refreshFx()
  }

  // ---- Units ----
  function recomputeUnits() {
    var r = Conv.convertUnit(unitAmount, unitCategory, unitFrom, unitTo)
    if (r.error) { unitResult = "Error"; return }
    unitResult = Calc.formatNumber(r.value, 10)
  }

  function setUnitCategory(id) {
    unitCategory = id
    var ids = Conv.unitIds(id)
    unitFrom = ids[0] || ""
    unitTo = ids.length > 1 ? ids[1] : ids[0]
    recomputeUnits()
  }

  // ---- Tip ----
  function recomputeTip() {
    var r = Conv.tipSplit(tipBill, tipPercent, tipPeople, tipVat, tipVatMode)
    if (r.error) {
      tipTotal = tipPerPerson = tipVatAmount = tipTipAmount = "Error"
      return
    }
    tipTotal = Calc.formatGrouped(r.total, useGrouping)
    tipPerPerson = Calc.formatGrouped(r.perPerson, useGrouping)
    tipVatAmount = Calc.formatGrouped(r.vatAmount, useGrouping)
    tipTipAmount = Calc.formatGrouped(r.tipAmount, useGrouping)
  }

  // ---- Keyboard ----
  function handleTextKey(t) {
    if (mode === "fx" || mode === "units" || mode === "tip") return
    if (mode === "programmer") {
      var allowed = progBase === 16 ? "0123456789abcdefABCDEFxX"
        : progBase === 8 ? "01234567"
        : progBase === 2 ? "01"
        : "0123456789"
      if (allowed.indexOf(t) !== -1) {
        if (t === "x" || t === "X") return
        progDigit(t.toUpperCase())
      }
      return
    }
    if ("0123456789.".indexOf(t) !== -1) appendDigit(t)
    else if ("+-*/^%".indexOf(t) !== -1) appendOp(t)
    else if (t === "(" || t === ")") insertParen(t)
    else if (t === "=") evaluateNow()
    else if (t === "c" || t === "C") copyResult()
  }

  function handleReturn() {
    if (mode === "programmer") progEquals()
    else if (mode === "standard" || mode === "scientific") evaluateNow()
  }

  function handleDelete() {
    if (mode === "programmer") {
      if (progInput.length <= 1) { progClear(); return }
      progInput = progInput.slice(0, -1)
      var p = Calc.parseBase(progInput || "0", progBase)
      if (!p.error) progValue = p.value
      return
    }
    if (mode === "standard" || mode === "scientific") backspace()
  }

  onBarChanged: injectPopup()
  Component.onCompleted: {
    injectPopup()
    loadSettings.running = true
    loadRates.running = true
  }

  onFxAmountChanged: recomputeFx()
  onFxFromChanged: recomputeFx()
  onFxToChanged: recomputeFx()
  onUnitAmountChanged: recomputeUnits()
  onUnitFromChanged: recomputeUnits()
  onUnitToChanged: recomputeUnits()
  onTipBillChanged: recomputeTip()
  onTipPercentChanged: recomputeTip()
  onTipPeopleChanged: recomputeTip()
  onTipVatChanged: recomputeTip()
  onTipVatModeChanged: recomputeTip()

  Process {
    id: loadSettings
    command: ["bash", "-c", "cat " + Util.shellQuote(root.settingsPath) + " 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySettings(text)
    }
  }

  Process {
    id: loadRates
    command: ["bash", "-c", "cat " + Util.shellQuote(root.ratesPath) + " 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRatesCache(text)
    }
  }

  Process {
    id: fxFetch
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onFxFetched(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root.fxLoading = false
        root.fxError = "Network error"
        root.fxStale = true
        root.recomputeFx()
      }
    }
  }

  Timer {
    interval: 3600000
    running: root.opened && root.mode === "fx"
    repeat: true
    onTriggered: root.refreshFx()
  }

  // ===== Bar button =====
  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: "󰃬"
    tooltipText: root.barTooltip
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.togglePanel()
      else if (button === Qt.RightButton) root.copyResult()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: barButton
    bar: root.bar
    owner: root
    open: false
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(392))
    contentHeight: popup.fittedContentHeight(mainCol.implicitHeight)

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        // Let TextInputs in FX / Units / Tip own typing.
        if (fxAmountInput.activeFocus || unitAmountInput.activeFocus
            || tipBillInput.activeFocus || tipPercentInput.activeFocus
            || tipPeopleInput.activeFocus || tipVatInput.activeFocus) {
          if (event.key === Qt.Key_Escape) {
            root.close(); event.accepted = true
          }
          return
        }
        if (event.key === Qt.Key_Escape) {
          root.close(); event.accepted = true; return
        }
        if (event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_C || event.key === Qt.Key_Insert)) {
          root.copyResult(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Backspace) {
          root.handleDelete(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Delete) {
          root.handleDelete(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          var ids = ["standard", "scientific", "programmer", "fx", "units", "tip"]
          var i = ids.indexOf(root.mode)
          if (i < 0) i = 0
          var dir = ((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) ? -1 : 1
          i = (i + dir + ids.length) % ids.length
          root.setMode(ids[i])
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.handleReturn(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Plus) { root.handleTextKey("+"); event.accepted = true; return }
        if (event.key === Qt.Key_Minus) { root.handleTextKey("-"); event.accepted = true; return }
        if (event.key === Qt.Key_Asterisk) { root.handleTextKey("*"); event.accepted = true; return }
        if (event.key === Qt.Key_Slash) { root.handleTextKey("/"); event.accepted = true; return }
        if (event.text && event.text.length === 1) {
          root.handleTextKey(event.text)
          event.accepted = true
        }
      }

      Column {
        id: mainCol
        width: parent.width
        spacing: Style.space(10)

        // Header
        RowLayout {
          width: parent.width
          Text {
            text: "Calculator"
            color: root.fg()
            font.family: root.fontFamily()
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }
          Text {
            text: root.memorySet ? "M" : ""
            color: Color.accent
            font.family: root.fontFamily()
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Rectangle {
            width: Style.space(56)
            height: Style.space(28)
            radius: Style.cornerRadius
            color: copyMouse.containsMouse ? Style.hoverFillFor(root.fg(), Color.accent) : root.softFill(0.08)
            Text {
              anchors.centerIn: parent
              text: "Copy"
              color: root.fg()
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: copyMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.copyResult()
            }
          }
        }

        // Mode tabs
        Flickable {
          width: parent.width
          height: Style.space(34)
          contentWidth: tabRow.implicitWidth
          clip: true
          interactive: tabRow.implicitWidth > width

          Row {
            id: tabRow
            spacing: Style.space(4)
            Repeater {
              model: root.modes
              delegate: Rectangle {
                required property var modelData
                width: Style.space(58)
                height: Style.space(32)
                radius: Style.cornerRadius
                color: root.tabColor(modelData.id, tabMouse)
                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: root.mode === modelData.id
                    ? Style.selectedStateColor(root.fg(), Color.accent)
                    : root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.setMode(modelData.id)
                }
              }
            }
          }
        }

        // ===== STANDARD / SCIENTIFIC =====
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.mode === "standard" || root.mode === "scientific"

          Rectangle {
            width: parent.width
            height: Style.space(78)
            radius: Style.cornerRadius
            color: root.softFill(0.06)
            border.width: Style.spacing.hairline
            border.color: root.softFill(0.16)
            Column {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: 2
              Text {
                width: parent.width
                text: root.expression || " "
                color: root.softFill(0.55)
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
                elide: Text.ElideLeft
                horizontalAlignment: Text.AlignRight
              }
              Text {
                width: parent.width
                text: root.useGrouping ? (function() {
                  var n = Number(root.display)
                  if (root.display === "Error" || !isFinite(n)) return root.display
                  return Calc.formatGrouped(n, true)
                })() : root.display
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.display
                font.bold: true
                elide: Text.ElideLeft
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          Row {
            spacing: Style.space(6)
            visible: root.mode === "scientific"
            Repeater {
              model: [
                { id: "deg", label: "DEG" },
                { id: "rad", label: "RAD" }
              ]
              delegate: Rectangle {
                required property var modelData
                width: Style.space(52)
                height: Style.space(26)
                radius: Style.cornerRadius
                color: root.angleMode === modelData.id
                  ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.angleMode = modelData.id
                }
              }
            }
            Text {
              text: "Grouping"
              color: root.softFill(0.65)
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
              width: Style.space(40)
              height: Style.space(26)
              radius: Style.cornerRadius
              color: root.useGrouping ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
              Text {
                anchors.centerIn: parent
                text: root.useGrouping ? "On" : "Off"
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.useGrouping = !root.useGrouping
              }
            }
          }

          // Scientific row
          GridLayout {
            width: parent.width
            columns: 5
            columnSpacing: Style.space(4)
            rowSpacing: Style.space(4)
            visible: root.mode === "scientific"
            Repeater {
              model: [
                { t: "sin", a: function() { root.appendUnaryFunc("sin") } },
                { t: "cos", a: function() { root.appendUnaryFunc("cos") } },
                { t: "tan", a: function() { root.appendUnaryFunc("tan") } },
                { t: "ln", a: function() { root.appendUnaryFunc("ln") } },
                { t: "log", a: function() { root.appendUnaryFunc("log10") } },
                { t: "√", a: function() { root.appendUnaryFunc("sqrt") } },
                { t: "∛", a: function() { root.appendUnaryFunc("cbrt") } },
                { t: "x²", a: function() { root.appendOp("^"); root.appendDigit("2"); root.evaluateNow() } },
                { t: "xʸ", a: function() { root.appendOp("^") } },
                { t: "n!", a: function() { root.appendUnaryFunc("fact") } },
                { t: "π", a: function() { root.insertConst("π") } },
                { t: "e", a: function() { root.insertConst("e") } },
                { t: "1/x", a: function() {
                    var n = Number(root.display)
                    if (!isFinite(n) || n === 0) { root.display = "Error"; return }
                    root.display = Calc.formatNumber(1 / n); root.justEvaluated = true
                  } },
                { t: "|x|", a: function() { root.appendUnaryFunc("abs") } },
                { t: "exp", a: function() { root.appendUnaryFunc("exp") } }
              ]
              delegate: CalcKey {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(34)
                label: modelData.t
                onActivated: modelData.a()
              }
            }
          }

          // Memory + main keypad
          GridLayout {
            width: parent.width
            columns: 4
            columnSpacing: Style.space(4)
            rowSpacing: Style.space(4)
            Repeater {
              model: [
                { t: "MC", a: function() { root.memClear() } },
                { t: "MR", a: function() { root.memRecall() } },
                { t: "M+", a: function() { root.memAdd() } },
                { t: "M−", a: function() { root.memSub() } },
                { t: "C", a: function() { root.clearAll() } },
                { t: "CE", a: function() { root.clearEntry() } },
                { t: "⌫", a: function() { root.backspace() } },
                { t: "÷", a: function() { root.appendOp("/") }, accent: true },
                { t: "7", a: function() { root.appendDigit("7") } },
                { t: "8", a: function() { root.appendDigit("8") } },
                { t: "9", a: function() { root.appendDigit("9") } },
                { t: "×", a: function() { root.appendOp("*") }, accent: true },
                { t: "4", a: function() { root.appendDigit("4") } },
                { t: "5", a: function() { root.appendDigit("5") } },
                { t: "6", a: function() { root.appendDigit("6") } },
                { t: "−", a: function() { root.appendOp("-") }, accent: true },
                { t: "1", a: function() { root.appendDigit("1") } },
                { t: "2", a: function() { root.appendDigit("2") } },
                { t: "3", a: function() { root.appendDigit("3") } },
                { t: "+", a: function() { root.appendOp("+") }, accent: true },
                { t: "±", a: function() { root.toggleSign() } },
                { t: "0", a: function() { root.appendDigit("0") } },
                { t: ".", a: function() { root.appendDigit(".") } },
                { t: "=", a: function() { root.evaluateNow() }, accent: true }
              ]
              delegate: CalcKey {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(40)
                label: modelData.t
                accent: !!modelData.accent
                onActivated: modelData.a()
              }
            }
          }

          Row {
            spacing: Style.space(4)
            CalcKey {
              width: Style.space(70); height: Style.space(32); label: "("
              onActivated: root.insertParen("(")
            }
            CalcKey {
              width: Style.space(70); height: Style.space(32); label: ")"
              onActivated: root.insertParen(")")
            }
            CalcKey {
              width: Style.space(70); height: Style.space(32); label: "%"
              onActivated: root.applyPercent()
            }
            CalcKey {
              width: Style.space(70); height: Style.space(32); label: "MS"
              onActivated: root.memStore()
            }
            CalcKey {
              width: Style.space(88); height: Style.space(32); label: "A%of B"
              onActivated: {
                // Uses expression as A and display as B: result = A is what % of B
                var a = Number(root.expression.replace(/[^0-9.\-eE]/g, "") || root.display)
                // Simpler: memory is A, display is B
                if (!root.memorySet) {
                  root.memStore()
                  return
                }
                var r = Calc.percentOf(root.memory, Number(root.display))
                if (r.error) { root.display = "Error"; return }
                root.display = Calc.formatNumber(r.value)
                root.justEvaluated = true
                root.pushHist("M is % of display", root.display)
              }
            }
            CalcKey {
              width: Style.space(88); height: Style.space(32); label: "%Δ"
              onActivated: {
                if (!root.memorySet) {
                  root.memStore()
                  return
                }
                var r = Calc.percentChange(root.memory, Number(root.display))
                if (r.error) { root.display = "Error"; return }
                root.display = Calc.formatNumber(r.value)
                root.justEvaluated = true
                root.pushHist("% change M→display", root.display)
              }
            }
          }
        }

        // ===== PROGRAMMER =====
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.mode === "programmer"

          Rectangle {
            width: parent.width
            height: Style.space(90)
            radius: Style.cornerRadius
            color: root.softFill(0.06)
            border.width: Style.spacing.hairline
            border.color: root.softFill(0.16)
            Column {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(2)
              Text {
                width: parent.width
                text: "HEX  " + Calc.formatBase(root.progValue, 16, root.progBits)
                color: root.progBase === 16 ? root.fg() : root.softFill(0.55)
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
                font.bold: root.progBase === 16
              }
              Text {
                width: parent.width
                text: "DEC  " + Calc.formatBase(root.progValue, 10, root.progBits)
                color: root.progBase === 10 ? root.fg() : root.softFill(0.55)
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
                font.bold: root.progBase === 10
              }
              Text {
                width: parent.width
                text: "OCT  " + Calc.formatBase(root.progValue, 8, root.progBits)
                color: root.progBase === 8 ? root.fg() : root.softFill(0.55)
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
                font.bold: root.progBase === 8
              }
              Text {
                width: parent.width
                text: "BIN  " + Calc.formatBase(root.progValue, 2, Math.min(root.progBits, 32))
                color: root.progBase === 2 ? root.fg() : root.softFill(0.55)
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
                font.bold: root.progBase === 2
                elide: Text.ElideLeft
              }
            }
          }

          Row {
            spacing: Style.space(4)
            Repeater {
              model: [
                { b: 16, l: "HEX" }, { b: 10, l: "DEC" },
                { b: 8, l: "OCT" }, { b: 2, l: "BIN" }
              ]
              delegate: Rectangle {
                required property var modelData
                width: Style.space(52)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.progBase === modelData.b
                  ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData.l
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.setProgBase(modelData.b) }
              }
            }
            Repeater {
              model: [8, 16, 32, 64]
              delegate: Rectangle {
                required property int modelData
                width: Style.space(40)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.progBits === modelData
                  ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: { root.progBits = modelData; root.progRefreshInput() }
                }
              }
            }
          }

          GridLayout {
            width: parent.width
            columns: 4
            columnSpacing: Style.space(4)
            rowSpacing: Style.space(4)
            Repeater {
              model: [
                { t: "AND", a: function() { root.progOp("AND") }, accent: true },
                { t: "OR", a: function() { root.progOp("OR") }, accent: true },
                { t: "XOR", a: function() { root.progOp("XOR") }, accent: true },
                { t: "NOT", a: function() { root.progNot() }, accent: true },
                { t: "LSH", a: function() { root.progOp("LSH") }, accent: true },
                { t: "RSH", a: function() { root.progOp("RSH") }, accent: true },
                { t: "C", a: function() { root.progClear() } },
                { t: "=", a: function() { root.progEquals() }, accent: true },
                { t: "A", a: function() { root.progDigit("A") }, en: root.progBase === 16 },
                { t: "B", a: function() { root.progDigit("B") }, en: root.progBase === 16 },
                { t: "C", a: function() { root.progDigit("C") }, en: root.progBase === 16 },
                { t: "D", a: function() { root.progDigit("D") }, en: root.progBase === 16 },
                { t: "E", a: function() { root.progDigit("E") }, en: root.progBase === 16 },
                { t: "F", a: function() { root.progDigit("F") }, en: root.progBase === 16 },
                { t: "7", a: function() { root.progDigit("7") }, en: root.progBase > 8 },
                { t: "8", a: function() { root.progDigit("8") }, en: root.progBase > 8 },
                { t: "9", a: function() { root.progDigit("9") }, en: root.progBase === 16 || root.progBase === 10 },
                { t: "4", a: function() { root.progDigit("4") }, en: root.progBase > 2 },
                { t: "5", a: function() { root.progDigit("5") }, en: root.progBase > 2 },
                { t: "6", a: function() { root.progDigit("6") }, en: root.progBase > 2 },
                { t: "1", a: function() { root.progDigit("1") } },
                { t: "2", a: function() { root.progDigit("2") }, en: root.progBase > 2 },
                { t: "3", a: function() { root.progDigit("3") }, en: root.progBase > 2 },
                { t: "0", a: function() { root.progDigit("0") } }
              ]
              delegate: CalcKey {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(36)
                label: modelData.t
                accent: !!modelData.accent
                enabled: modelData.en === undefined ? true : !!modelData.en
                opacity: enabled ? 1 : 0.35
                onActivated: if (enabled) modelData.a()
              }
            }
          }
        }

        // ===== FX =====
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.mode === "fx"

          RowLayout {
            width: parent.width
            Text {
              text: root.fxLoading ? "Updating rates…"
                : (root.fxError ? root.fxError + (root.fxStale ? " · cached" : "")
                  : (root.fxStale ? "Cached · " : "Live · ") + Conv.timeAgo(root.fxFetchedAt))
              color: root.fxError ? Color.accent : root.softFill(0.65)
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
              Layout.fillWidth: true
            }
            Rectangle {
              width: Style.space(72)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: refreshMouse.containsMouse ? Style.hoverFillFor(root.fg(), Color.accent) : root.softFill(0.08)
              Text {
                anchors.centerIn: parent
                text: "Refresh"
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.refreshFx()
              }
            }
          }

          Text {
            text: "Amount"
            color: root.softFill(0.65)
            font.family: root.fontFamily()
            font.pixelSize: Style.font.caption
          }
          Rectangle {
            width: parent.width
            height: Style.space(40)
            radius: Style.cornerRadius
            color: root.softFill(0.06)
            border.width: Style.spacing.hairline
            border.color: root.softFill(0.16)
            TextInput {
              id: fxAmountInput
              anchors.fill: parent
              anchors.margins: Style.space(10)
              text: root.fxAmount
              color: root.fg()
              font.family: root.fontFamily()
              font.pixelSize: Style.font.body
              inputMethodHints: Qt.ImhFormattedNumbersOnly
              onTextChanged: root.fxAmount = text
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            ColumnLayout {
              Layout.fillWidth: true
              Text {
                text: "From"
                color: root.softFill(0.65)
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
              }
              Flow {
                Layout.fillWidth: true
                spacing: Style.space(4)
                Repeater {
                  model: root.fxCurrencyList
                  delegate: Rectangle {
                    required property string modelData
                    width: Style.space(48)
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: root.fxFrom === modelData
                      ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                    Text {
                      anchors.centerIn: parent
                      text: modelData
                      color: root.fg()
                      font.family: root.fontFamily()
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: { root.fxFrom = modelData; root.refreshFx() }
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            width: Style.space(48)
            height: Style.space(32)
            radius: Style.cornerRadius
            anchors.horizontalCenter: parent.horizontalCenter
            color: swapMouse.containsMouse ? Style.hoverFillFor(root.fg(), Color.accent) : root.softFill(0.08)
            Text {
              anchors.centerIn: parent
              text: "⇄"
              color: root.fg()
              font.pixelSize: Style.font.body
            }
            MouseArea {
              id: swapMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.swapFx()
            }
          }

          ColumnLayout {
            width: parent.width
            Text {
              text: "To"
              color: root.softFill(0.65)
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
            }
            Flow {
              Layout.fillWidth: true
              width: parent.width
              spacing: Style.space(4)
              Repeater {
                model: root.fxCurrencyList
                delegate: Rectangle {
                  required property string modelData
                  width: Style.space(48)
                  height: Style.space(28)
                  radius: Style.cornerRadius
                  color: root.fxTo === modelData
                    ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                  Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: root.fg()
                    font.family: root.fontFamily()
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: { root.fxTo = modelData; root.recomputeFx() }
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(72)
            radius: Style.cornerRadius
            color: root.softFill(0.06)
            border.width: Style.spacing.hairline
            border.color: root.softFill(0.16)
            Column {
              anchors.centerIn: parent
              spacing: 2
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.fxResult
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.display
                font.bold: true
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.fxTo + "  ·  1 " + root.fxFrom + " = " + root.fxStripHint() + " " + root.fxTo
                color: root.softFill(0.6)
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ===== UNITS =====
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.mode === "units"

          Flow {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.unitCategories
              delegate: Rectangle {
                required property var modelData
                width: Style.space(72)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.unitCategory === modelData.id
                  ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.setUnitCategory(modelData.id)
                }
              }
            }
          }

          Text {
            text: "Value"
            color: root.softFill(0.65)
            font.family: root.fontFamily()
            font.pixelSize: Style.font.caption
          }
          Rectangle {
            width: parent.width
            height: Style.space(40)
            radius: Style.cornerRadius
            color: root.softFill(0.06)
            border.width: Style.spacing.hairline
            border.color: root.softFill(0.16)
            TextInput {
              id: unitAmountInput
              anchors.fill: parent
              anchors.margins: Style.space(10)
              text: root.unitAmount
              color: root.fg()
              font.family: root.fontFamily()
              font.pixelSize: Style.font.body
              onTextChanged: root.unitAmount = text
            }
          }

          Text {
            text: "From"
            color: root.softFill(0.65)
            font.family: root.fontFamily()
            font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.unitFromList
              delegate: Rectangle {
                required property string modelData
                width: Math.max(Style.space(44), modelData.length * Style.space(10) + Style.space(16))
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.unitFrom === modelData
                  ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.unitFrom = modelData }
              }
            }
          }

          Text {
            text: "To"
            color: root.softFill(0.65)
            font.family: root.fontFamily()
            font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.unitToList
              delegate: Rectangle {
                required property string modelData
                width: Math.max(Style.space(44), modelData.length * Style.space(10) + Style.space(16))
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.unitTo === modelData
                  ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.unitTo = modelData }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(56)
            radius: Style.cornerRadius
            color: root.softFill(0.06)
            Text {
              anchors.centerIn: parent
              text: root.unitResult + " " + root.unitTo
              color: root.fg()
              font.family: root.fontFamily()
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }
        }

        // ===== TIP =====
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.mode === "tip"

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            Text {
              text: "Bill"
              color: root.softFill(0.65)
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: root.softFill(0.06)
              TextInput {
                id: tipBillInput
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: root.tipBill
                color: root.fg()
                font.family: root.fontFamily()
                onTextChanged: root.tipBill = text
              }
            }

            Text {
              text: "Tip %"
              color: root.softFill(0.65)
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: root.softFill(0.06)
              TextInput {
                id: tipPercentInput
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: root.tipPercent
                color: root.fg()
                font.family: root.fontFamily()
                onTextChanged: root.tipPercent = text
              }
            }

            Text {
              text: "People"
              color: root.softFill(0.65)
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: root.softFill(0.06)
              TextInput {
                id: tipPeopleInput
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: root.tipPeople
                color: root.fg()
                font.family: root.fontFamily()
                onTextChanged: root.tipPeople = text
              }
            }
          }

          Text {
            text: "VAT (Kenya 16%)"
            color: root.softFill(0.65)
            font.family: root.fontFamily()
            font.pixelSize: Style.font.caption
          }
          Row {
            spacing: Style.space(4)
            Repeater {
              model: [
                { id: "none", label: "Off" },
                { id: "add", label: "Add" },
                { id: "extract", label: "Extract" }
              ]
              delegate: Rectangle {
                required property var modelData
                width: Style.space(72)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.tipVatMode === modelData.id
                  ? Style.selectedFillFor(root.fg(), Color.accent) : root.softFill(0.08)
                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.tipVatMode = modelData.id }
              }
            }
            Rectangle {
              width: Style.space(56)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: root.softFill(0.06)
              visible: root.tipVatMode !== "none"
              TextInput {
                id: tipVatInput
                anchors.fill: parent
                anchors.margins: Style.space(6)
                text: root.tipVat
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                onTextChanged: root.tipVat = text
              }
            }
          }

          Rectangle {
            width: parent.width
            radius: Style.cornerRadius
            color: root.softFill(0.06)
            height: tipStats.implicitHeight + Style.space(20)
            Column {
              id: tipStats
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              spacing: Style.space(4)
              Text {
                text: "Tip  " + root.tipTipAmount
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.body
              }
              Text {
                visible: root.tipVatMode !== "none"
                text: "VAT  " + root.tipVatAmount
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.body
              }
              Text {
                text: "Total  " + root.tipTotal
                color: root.fg()
                font.family: root.fontFamily()
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: "Each  " + root.tipPerPerson
                color: Color.accent
                font.family: root.fontFamily()
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        // History (calc modes)
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: (root.mode === "standard" || root.mode === "scientific" || root.mode === "programmer")
                   && root.history.length > 0

          RowLayout {
            width: parent.width
            Text {
              text: "History"
              color: root.softFill(0.65)
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
              Layout.fillWidth: true
            }
            Text {
              text: "Clear"
              color: Color.accent
              font.family: root.fontFamily()
              font.pixelSize: Style.font.caption
              MouseArea { anchors.fill: parent; onClicked: root.clearHistory() }
            }
          }

          Repeater {
            model: root.history.slice(0, 5)
            delegate: Rectangle {
              required property var modelData
              width: mainCol.width
              height: Style.space(32)
              radius: Style.cornerRadius
              color: histMouse.containsMouse ? Style.hoverFillFor(root.fg(), Color.accent) : "transparent"
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                Text {
                  text: modelData.expr
                  color: root.softFill(0.55)
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
                Text {
                  text: modelData.result
                  color: root.fg()
                  font.family: root.fontFamily()
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
              MouseArea {
                id: histMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.recallHistory(modelData)
              }
            }
          }
        }
      }
    }
  }

  component CalcKey: Rectangle {
    id: keyRoot
    property string label: ""
    property bool accent: false
    signal activated()

    radius: Style.cornerRadius
    color: root.keyFill(keyMouse, accent)
    opacity: enabled ? 1 : 0.35

    Text {
      anchors.centerIn: parent
      text: keyRoot.label
      color: root.fg()
      font.family: root.fontFamily()
      font.pixelSize: Style.font.body
      font.bold: keyRoot.accent
    }
    MouseArea {
      id: keyMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: if (keyRoot.enabled) keyRoot.activated()
    }
  }
}
