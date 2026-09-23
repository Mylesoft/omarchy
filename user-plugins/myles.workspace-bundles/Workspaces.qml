import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Frequent 1–10 on the rail. Hover/click 11 expands 12–20 on the bar.
// Hover any slot for name + window titles. Clicking any of 11–20 focuses
// that workspace and collapses the fan immediately.
BarWidget {
  id: root
  moduleName: "myles.workspace-bundles"

  property int hoverGroup: -1
  property int pinnedGroup: -1

  readonly property int focusedId: Hyprland.focusedWorkspace !== null
    ? Hyprland.focusedWorkspace.id : -1

  // Property (not a function) so expand/collapse bindings re-evaluate.
  readonly property bool fanOpen: pinnedGroup === 1 || hoverGroup === 1

  readonly property var frequentIds: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  readonly property var expandedIds: [12, 13, 14, 15, 16, 17, 18, 19, 20]

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function collectTitles(wsId) {
    var titles = []
    var seen = {}

    function pushTitle(value) {
      var t = value ? String(value).trim() : ""
      if (t === "" || seen[t]) return
      seen[t] = true
      titles.push(t)
    }

    try {
      var all = Hyprland.toplevels.values
      for (var i = 0; i < all.length; i++) {
        var top = all[i]
        if (!top || !top.workspace || top.workspace.id !== wsId) continue
        pushTitle(top.title)
        var ipc = top.lastIpcObject || {}
        if (!top.title) pushTitle(ipc.class || ipc.initialClass || ipc.initialTitle)
      }
    } catch (e) {}

    var ws = root.workspaceById(wsId)
    if (ws) {
      try {
        var local = ws.toplevels.values
        for (var j = 0; j < local.length; j++)
          pushTitle(local[j].title)
      } catch (e2) {}
      var wipc = ws.lastIpcObject || {}
      pushTitle(wipc.lastwindowtitle)
    }

    return titles
  }

  function previewText(wsId) {
    var ws = root.workspaceById(wsId)
    var name = (ws && ws.name) ? String(ws.name) : String(wsId)
    var label = "Workspace " + name
    var titles = root.collectTitles(wsId)
    if (titles.length === 0) return label + " · empty"
    var shown = titles.slice(0, 3).join("\n")
    if (titles.length > 3) shown += "\n+" + (titles.length - 3) + " more"
    return label + "\n" + shown
  }

  function setBundleHover(on) {
    if (on) {
      closeGrace.stop()
      if (root.hoverGroup !== 1) root.hoverGroup = 1
    } else {
      if (root.pinnedGroup === 1) {
        root.hoverGroup = -1
        return
      }
      closeGrace.restart()
    }
  }

  function closeBundle() {
    root.pinnedGroup = -1
    root.hoverGroup = -1
    closeGrace.stop()
  }

  // Focus a workspace and always fold the infrequent fan shut.
  function pickInfrequent(id) {
    root.closeBundle()
    root.focusWorkspace(id)
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function occupied(wsId) {
    if (root.collectTitles(wsId).length > 0) return true
    var ws = root.workspaceById(wsId)
    return ws !== null && ws.toplevels.values.length > 0
  }

  Timer {
    id: closeGrace
    interval: 280
    onTriggered: {
      if (root.pinnedGroup !== 1)
        root.hoverGroup = -1
    }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property real slotW: root.vertical ? root.barSize : Style.space(20)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    // Always 20 columns max; hidden 12–20 take no space while collapsed.
    columns: root.vertical ? 1 : 20
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.frequentIds

      WidgetButton {
        id: freqBtn
        required property int modelData

        readonly property bool focused: root.focusedId === modelData

        bar: root ? root.bar : null
        text: focused ? "\uDB85\uDCFB" : String(modelData)
        opacity: root.occupied(modelData) || focused ? 1 : 0.5
        active: focused
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.slotW
        fixedHeight: root.barSize
        tooltipText: root.previewText(modelData)

        onTooltipHoveredChanged: {
          if (freqBtn.tooltipHovered && root && root.bar)
            root.bar.showTooltip(freqBtn, root.previewText(modelData))
        }

        onPressed: function() {
          if (root && root.bar) root.bar.hideTooltip(freqBtn)
          root.closeBundle()
          root.focusWorkspace(modelData)
        }
      }
    }

    // 11 — always mounted; hover opens the on-bar expansion.
    WidgetButton {
      id: elevenBtn

      readonly property bool focused: root.focusedId === 11
      // After collapse, 11 stands in for the whole 11–20 group so you can
      // still see that you're on an infrequent workspace.
      readonly property bool inGroup: root.focusedId >= 11 && root.focusedId <= 20

      bar: root ? root.bar : null
      text: focused ? "\uDB85\uDCFB" : "11"
      opacity: root.occupied(11) || inGroup || root.fanOpen ? 1 : 0.55
      active: inGroup || root.pinnedGroup === 1
      horizontalMargin: 6
      verticalPadding: 6
      fixedWidth: root.slotW
      fixedHeight: root.barSize
      tooltipText: root.fanOpen ? root.previewText(11) : "Infrequent 11–20 — hover to expand on the bar"

      HoverHandler {
        onHoveredChanged: root.setBundleHover(hovered)
      }

      onTooltipHoveredChanged: {
        root.setBundleHover(elevenBtn.tooltipHovered)
        if (elevenBtn.tooltipHovered && root.fanOpen && root.bar)
          root.bar.showTooltip(elevenBtn, root.previewText(11))
      }

      onPressed: function() {
        if (root.bar) root.bar.hideTooltip(elevenBtn)
        // Closed → open the fan so 12–20 appear.
        if (!root.fanOpen) {
          root.pinnedGroup = 1
          return
        }
        // Already open → go to 11 and collapse.
        root.pickInfrequent(11)
      }
    }

    // 12–20 — shown only while fanOpen; click focuses and collapses.
    Repeater {
      model: root.expandedIds

      WidgetButton {
        id: bundleBtn
        required property int modelData

        visible: root.fanOpen
        Layout.preferredWidth: root.fanOpen ? root.slotW : 0
        Layout.preferredHeight: root.fanOpen ? root.barSize : 0

        readonly property bool focused: root.focusedId === modelData

        bar: root ? root.bar : null
        text: focused ? "\uDB85\uDCFB" : String(modelData)
        opacity: root.occupied(modelData) || focused ? 1 : 0.5
        active: focused
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.slotW
        fixedHeight: root.barSize
        tooltipText: root.previewText(modelData)

        HoverHandler {
          enabled: root.fanOpen
          onHoveredChanged: root.setBundleHover(hovered)
        }

        onTooltipHoveredChanged: {
          root.setBundleHover(bundleBtn.tooltipHovered)
          if (bundleBtn.tooltipHovered && root.bar)
            root.bar.showTooltip(bundleBtn, root.previewText(modelData))
        }

        onPressed: function() {
          if (root.bar) root.bar.hideTooltip(bundleBtn)
          root.pickInfrequent(modelData)
        }
      }
    }
  }
}
