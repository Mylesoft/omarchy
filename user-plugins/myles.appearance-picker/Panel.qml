import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "myles.appearance-picker"
  property string currentTheme: ""
  property string currentWallpaper: ""
  property var themes: []
  property var wallpapers: []
  property string tab: "themes"
  property string pendingTheme: ""
  property string pendingWallpaper: ""
  property var themeQueue: []
  property var wallpaperQueue: []
  property bool cycleThemeWhenLoaded: false
  property bool cycleWallpaperWhenLoaded: false

  readonly property bool opened: popup.open
  property bool nightlightEnabled: false
  implicitWidth: group.implicitWidth
  implicitHeight: group.implicitHeight

  function injectPopup() {
    popup.anchorItem = group
    popup.bar = root.bar
    popup.owner = root
    popup.focusTarget = keyCatcher
  }

  function refresh() {
    if (!themeList.running) themeList.running = true
    if (!currentThemeProc.running) currentThemeProc.running = true
    if (!wallpaperList.running) wallpaperList.running = true
    if (!currentWallpaperProc.running) currentWallpaperProc.running = true
    if (!nightlightStatus.running) nightlightStatus.running = true
  }

  function open() {
    refresh()
    popup.open = true
  }

  function close() {
    popup.open = false
  }

  function togglePanel() {
    if (opened) close()
    else open()
  }

  function cycleTheme() {
    if (themes.length === 0) {
      cycleThemeWhenLoaded = true
      refresh()
      return
    }
    var base = currentTheme
    if (pendingTheme) base = pendingTheme
    if (themeQueue.length > 0) base = themeQueue[themeQueue.length - 1]
    var index = Model.nextIndex(themes, base)
    if (index >= 0) applyTheme(themes[index])
    else refresh()
  }

  function cycleWallpaper() {
    if (wallpapers.length === 0) {
      cycleWallpaperWhenLoaded = true
      refresh()
      return
    }
    var base = currentWallpaper
    if (pendingWallpaper) base = pendingWallpaper
    if (wallpaperQueue.length > 0) base = wallpaperQueue[wallpaperQueue.length - 1]
    var index = Model.nextIndex(wallpapers, base)
    if (index >= 0) applyWallpaper(wallpapers[index])
    else refresh()
  }

  function applyTheme(name) {
    if (!name) return
    if (themeSet.running) {
      themeQueue = themeQueue.concat([name])
      return
    }
    pendingTheme = name
    themeSet.command = ["omarchy-theme-set", name]
    themeSet.running = true
  }

  function applyWallpaper(path) {
    if (!path) return
    if (wallpaperSet.running) {
      wallpaperQueue = wallpaperQueue.concat([path])
      return
    }
    pendingWallpaper = path
    wallpaperSet.command = ["omarchy-theme-bg-set", path]
    wallpaperSet.running = true
  }

  function tabButtonColor(value, mouse) {
    return tab === value
      ? Style.selectedFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
      : mouse.containsMouse ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent) : "transparent"
  }

  onBarChanged: injectPopup()
  Component.onCompleted: {
    injectPopup()
    refresh()
  }

  Process {
    id: themeList
    command: ["bash", "-c", "omarchy theme list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.themes = Model.lines(text)
        if (root.cycleThemeWhenLoaded) {
          root.cycleThemeWhenLoaded = false
          root.cycleTheme()
        }
      }
    }
  }

  Process {
    id: currentThemeProc
    command: ["bash", "-c", "omarchy theme current"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentTheme = String(text || "").trim()
    }
  }

  Process {
    id: themeSet
    onExited: {
      root.currentTheme = root.pendingTheme
      root.pendingTheme = ""
      if (root.themeQueue.length > 0) {
        var nextTheme = root.themeQueue[0]
        root.themeQueue = root.themeQueue.slice(1)
        root.applyTheme(nextTheme)
      } else {
        root.refresh()
      }
    }
  }

  Process {
    id: wallpaperList
    command: ["bash", "-c", "theme=$(omarchy theme current); state=\"$HOME/.local/state/omarchy/current/theme/backgrounds\"; user=\"$HOME/.config/omarchy/backgrounds/$theme\"; find -L \"$user\" \"$state\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \\) -print 2>/dev/null | sort -u"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.wallpapers = Model.lines(text)
        if (root.cycleWallpaperWhenLoaded) {
          root.cycleWallpaperWhenLoaded = false
          root.cycleWallpaper()
        }
      }
    }
  }

  Process {
    id: currentWallpaperProc
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentWallpaper = String(text || "").trim()
    }
  }

  Process {
    id: nightlightStatus
    command: ["bash", "-c", "omarchy toggle nightlight --status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.nightlightEnabled = !!JSON.parse(String(text || "{}")).enabled
        } catch (error) {
          root.nightlightEnabled = false
        }
      }
    }
  }

  Process {
    id: nightlightToggle
    command: ["omarchy", "toggle", "nightlight"]
    onExited: root.refresh()
  }

  Process {
    id: wallpaperSet
    onExited: {
      root.currentWallpaper = root.pendingWallpaper
      root.pendingWallpaper = ""
      if (root.wallpaperQueue.length > 0) {
        var nextWallpaper = root.wallpaperQueue[0]
        root.wallpaperQueue = root.wallpaperQueue.slice(1)
        root.applyWallpaper(nextWallpaper)
      } else {
        root.refresh()
      }
    }
  }

  Rectangle {
    id: group
    width: groupRow.implicitWidth + Style.space(8)
    height: Style.bar.iconSlot + Style.space(4)
    implicitWidth: groupRow.implicitWidth + Style.space(8)
    implicitHeight: Style.bar.iconSlot + Style.space(4)
    radius: Style.cornerRadius
    color: Qt.rgba(root.bar ? root.bar.foreground.r : Color.foreground.r,
                   root.bar ? root.bar.foreground.g : Color.foreground.g,
                   root.bar ? root.bar.foreground.b : Color.foreground.b, 0.07)
    border.width: Style.spacing.hairline
    border.color: Qt.rgba(root.bar ? root.bar.foreground.r : Color.foreground.r,
                          root.bar ? root.bar.foreground.g : Color.foreground.g,
                          root.bar ? root.bar.foreground.b : Color.foreground.b, 0.16)

    Row {
      id: groupRow
      anchors.centerIn: parent
      spacing: 1

      BarIconButton {
        id: themeButton
        bar: root.bar
        fixedWidth: Style.bar.iconSlot
        fixedHeight: Style.bar.iconSlot
        text: "󰏘"
        tooltipText: "Left-click: next theme"
        onPressed: function(button) {
          if (button !== Qt.LeftButton) return
          root.cycleTheme()
        }
      }

      Rectangle {
        width: Style.spacing.hairline
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        color: root.bar ? root.bar.foreground : Color.foreground
        opacity: 0.18
      }

      BarIconButton {
        id: lightButton
        bar: root.bar
        fixedWidth: Style.bar.iconSlot
        fixedHeight: Style.bar.iconSlot
        text: "󰔎"
        active: root.nightlightEnabled
        tooltipText: root.nightlightEnabled ? "Left-click: turn daylight on" : "Left-click: turn night light on"
        onPressed: function(button) {
          if (button !== Qt.LeftButton || nightlightToggle.running) return
          nightlightToggle.running = true
        }
      }

      Rectangle {
        width: Style.spacing.hairline
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        color: root.bar ? root.bar.foreground : Color.foreground
        opacity: 0.18
      }

      BarIconButton {
        id: wallpaperButton
        bar: root.bar
        fixedWidth: Style.bar.iconSlot
        fixedHeight: Style.bar.iconSlot
        text: "󰸉"
        tooltipText: "Left-click: next wallpaper"
        onPressed: function(button) {
          if (button !== Qt.LeftButton) return
          root.cycleWallpaper()
        }
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: group
    bar: root.bar
    owner: root
    centerOnBar: true
    open: false
    contentWidth: Style.space(680)
    contentHeight: Style.space(470)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.tab = direction > 0 ? "wallpapers" : "themes" }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(12)

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "Appearance"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          Layout.fillWidth: true
        }
        Text {
          text: root.currentTheme ? Model.themeLabel(root.currentTheme) : "Loading…"
          color: Qt.rgba((root.bar ? root.bar.foreground : Color.foreground).r,
                         (root.bar ? root.bar.foreground : Color.foreground).g,
                         (root.bar ? root.bar.foreground : Color.foreground).b, 0.65)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        spacing: Style.space(4)
        Layout.fillWidth: true

        Repeater {
          model: [{ key: "themes", label: "󰏘  Themes" }, { key: "wallpapers", label: "󰸉  Wallpapers" }]
          delegate: Rectangle {
            required property var modelData
            width: Style.space(150)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: root.tabButtonColor(modelData.key, tabMouse)
            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: root.tab === modelData.key
                ? Style.selectedStateColor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
                : root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.tab = modelData.key
            }
          }
        }
      }

      ListView {
        visible: root.tab === "themes"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Style.space(3)
        model: root.themes
        delegate: Rectangle {
          required property string modelData
          width: ListView.view.width
          height: Style.space(38)
          radius: Style.cornerRadius
          color: modelData === root.currentTheme
            ? Style.selectedFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
            : rowMouse.containsMouse ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent) : "transparent"
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: Model.themeLabel(parent.modelData)
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.applyTheme(parent.modelData)
          }
        }
      }

      GridView {
        visible: root.tab === "wallpapers"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        cellWidth: Style.space(205)
        cellHeight: Style.space(145)
        model: root.wallpapers
        delegate: Rectangle {
          required property string modelData
          width: GridView.view.cellWidth - Style.space(8)
          height: GridView.view.cellHeight - Style.space(8)
          radius: Style.cornerRadius
          clip: true
          border.width: modelData === root.currentWallpaper ? Style.space(2) : Style.spacing.hairline
          border.color: modelData === root.currentWallpaper
            ? Style.normalBorderFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
            : Qt.rgba((root.bar ? root.bar.foreground : Color.foreground).r,
                      (root.bar ? root.bar.foreground : Color.foreground).g,
                      (root.bar ? root.bar.foreground : Color.foreground).b, 0.2)
          Image {
            anchors.fill: parent
            source: Util.fileUrl(parent.modelData)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
          }
          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, wallpaperMouse.containsMouse ? 0.18 : 0.4)
          }
          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(8)
            text: Model.wallpaperLabel(parent.modelData)
            color: "white"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          MouseArea {
            id: wallpaperMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.applyWallpaper(parent.modelData)
          }
        }
      }
    }
  }
}
