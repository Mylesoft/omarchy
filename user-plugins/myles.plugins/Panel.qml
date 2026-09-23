import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "myles.plugins"

  property var plugins: []
  property string query: ""
  property string filter: "all" // all | widgets | services | other
  property string pendingId: ""
  property bool pendingEnabled: false
  property bool busy: listProc.running || toggleProc.running
  property string statusText: ""

  readonly property bool opened: popup.open
  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var filters: [
    { id: "all", label: "All" },
    { id: "widgets", label: "Widgets" },
    { id: "services", label: "Services" },
    { id: "other", label: "Other" }
  ]

  readonly property var filteredPlugins: {
    var q = String(query || "").trim().toLowerCase()
    var out = []
    for (var i = 0; i < plugins.length; i++) {
      var p = plugins[i]
      if (!matchesFilter(p)) continue
      if (q.length > 0) {
        var hay = (String(p.name || "") + " " + String(p.id || "") + " " + kindsLabel(p)).toLowerCase()
        if (hay.indexOf(q) === -1) continue
      }
      out.push(p)
    }
    return out
  }

  readonly property int enabledCount: {
    var n = 0
    for (var i = 0; i < plugins.length; i++) if (plugins[i].enabled) n++
    return n
  }

  function injectPopup() {
    popup.anchorItem = barButton
    popup.bar = root.bar
    popup.owner = root
    popup.focusTarget = keyCatcher
  }

  function open() {
    refresh()
    popup.open = true
  }

  function close() {
    popup.open = false
    statusText = ""
  }

  function togglePanel() {
    if (opened) close()
    else open()
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function kindsOf(plugin) {
    return Array.isArray(plugin && plugin.kinds) ? plugin.kinds : []
  }

  function kindsLabel(plugin) {
    return kindsOf(plugin).join(", ")
  }

  function matchesFilter(plugin) {
    var kinds = kindsOf(plugin)
    if (filter === "all") return true
    if (filter === "widgets") return kinds.indexOf("bar-widget") !== -1
    if (filter === "services") return kinds.indexOf("service") !== -1
    // overlays, panels, menus, bars
    return kinds.indexOf("bar-widget") === -1 && kinds.indexOf("service") === -1
  }

  function canToggle(plugin) {
    if (!plugin) return false
    if (plugin.id === root.moduleName) return false
    if (plugin.enabled && plugin.canDisable === false) return false
    return true
  }

  function setEnabled(plugin, wantEnabled) {
    if (!plugin || !canToggle(plugin) || toggleProc.running) return
    if (!!plugin.enabled === !!wantEnabled) return

    // Optimistic flip so the switch feels instant.
    var next = []
    for (var i = 0; i < plugins.length; i++) {
      var row = plugins[i]
      if (row.id === plugin.id) {
        var copy = {}
        for (var k in row) copy[k] = row[k]
        copy.enabled = wantEnabled
        next.push(copy)
      } else {
        next.push(row)
      }
    }
    plugins = next

    pendingId = plugin.id
    pendingEnabled = wantEnabled
    statusText = (wantEnabled ? "Enabling " : "Disabling ") + plugin.name + "…"

    if (wantEnabled) {
      toggleProc.command = ["omarchy-shell", "shell", "enablePlugin", plugin.id, "{}"]
    } else {
      toggleProc.command = ["omarchy-shell", "shell", "setPluginEnabled", plugin.id, "false"]
    }
    toggleProc.running = true
  }

  function tabColor(id, mouse) {
    return filter === id
      ? Style.selectedFillFor(fg, Color.accent)
      : mouse.containsMouse ? Style.hoverFillFor(fg, Color.accent) : "transparent"
  }

  onBarChanged: injectPopup()
  Component.onCompleted: {
    injectPopup()
    refresh()
  }

  Process {
    id: listProc
    command: ["omarchy-shell", "shell", "listPlugins"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "[]"))
          if (!Array.isArray(parsed)) parsed = []
          parsed.sort(function(a, b) {
            var an = String(a.name || a.id || "")
            var bn = String(b.name || b.id || "")
            return an.localeCompare(bn)
          })
          root.plugins = parsed
        } catch (e) {
          root.statusText = "Failed to load plugins"
          root.plugins = []
        }
      }
    }
  }

  Process {
    id: toggleProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      var out = String(toggleProc.stdout.text || "").trim()
      var err = String(toggleProc.stderr.text || "").trim()
      if (code !== 0 || (out && out !== "ok")) {
        root.statusText = err || out || ("Toggle failed for " + root.pendingId)
      } else {
        root.statusText = (root.pendingEnabled ? "Enabled " : "Disabled ") + root.pendingId
      }
      root.pendingId = ""
      root.refresh()
    }
  }

  BarIconButton {
    id: barButton
    bar: root.bar
    fixedWidth: Style.bar.iconSlot
    fixedHeight: Style.bar.iconSlot
    text: "󰐱"
    active: root.opened
    tooltipText: "Plugins · " + root.enabledCount + "/" + root.plugins.length + " on"
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.togglePanel()
      else if (button === Qt.RightButton) root.refresh()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: barButton
    bar: root.bar
    owner: root
    centerOnBar: false
    open: false
    contentWidth: Style.space(420)
    contentHeight: Style.space(520)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: "Plugins"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          Layout.fillWidth: true
        }

        Text {
          text: root.enabledCount + " / " + root.plugins.length + " on"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      TextField {
        id: searchField
        Layout.fillWidth: true
        foreground: root.fg
        accent: Color.accent
        placeholderText: "Search plugins…"
        text: root.query
        onTextChanged: root.query = text
      }

      Row {
        spacing: Style.space(4)
        Repeater {
          model: root.filters
          delegate: Rectangle {
            required property var modelData
            width: tabLabel.implicitWidth + Style.space(16)
            height: Style.space(28)
            radius: Style.cornerRadius
            color: root.tabColor(modelData.id, tabMouse)

            Text {
              id: tabLabel
              anchors.centerIn: parent
              text: modelData.label
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.filter === modelData.id
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.filter = modelData.id
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Style.cornerRadius
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
        border.width: Style.spacing.hairline
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
        clip: true

        ListView {
          id: list
          anchors.fill: parent
          anchors.margins: Style.space(6)
          spacing: Style.space(4)
          clip: true
          model: root.filteredPlugins
          boundsBehavior: Flickable.StopAtBounds

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }

          delegate: Toggle {
            required property var modelData
            width: list.width
            label: modelData.name || modelData.id
            description: modelData.id
              + (kindsLabel(modelData) ? " · " + kindsLabel(modelData) : "")
              + (modelData.firstParty ? " · built-in" : " · third-party")
              + (modelData.id === root.moduleName ? " · this panel" : "")
            checked: !!modelData.enabled
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFamily
            opacity: canToggle(modelData) || modelData.enabled ? 1 : 0.55
            onClicked: {
              if (!canToggle(modelData)) return
              root.setEnabled(modelData, !modelData.enabled)
            }
          }

          Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: root.busy ? "Loading…" : "No plugins match"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.statusText.length > 0
        text: root.statusText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
