import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "MediaModel.js" as MediaModel

BarWidget {
  id: root
  // Default matches the built-in; Bar overwrites with the layout entry id
  // (myles.media) when the clone is mounted.
  moduleName: "omarchy.media"

  // Prefer our own service (clone-safe). firstPartyServiceFor("omarchy.media")
  // resolves to the clone when owned; the narrow bar proxy is only a fallback.
  readonly property var mediaService: {
    var sh = bar && bar.shell
    if (!sh) return null
    if (typeof sh.serviceFor === "function") {
      var own = sh.serviceFor(moduleName)
        || sh.serviceFor("myles.media")
        || sh.serviceFor("omarchy.media")
      if (own) return own
    }
    if (typeof sh.firstPartyServiceFor === "function")
      return sh.firstPartyServiceFor("omarchy.media")
    return null
  }
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []
  readonly property var sourceEntries: mediaService ? mediaService.sourceEntries : []
  readonly property var providerEntries: mediaService ? mediaService.providerEntries : []
  readonly property var hubEntries: mediaService ? mediaService.hubEntries : []
  readonly property bool followMode: mediaService ? !!mediaService.followMode : true
  readonly property bool usingCliamp: mediaService ? !!mediaService.usingCliamp : false
  readonly property bool usingMpv: mediaService ? !!mediaService.usingMpv : false
  readonly property bool mediaIsVideo: mediaService ? !!mediaService.mediaIsVideo : false
  readonly property bool videoPipVisible: mediaService ? !!mediaService.videoPipVisible : false
  readonly property bool canShowVideoPip: mediaService ? mediaService.canShowVideoPip === true : false
  readonly property bool cliampOnline: mediaService ? !!mediaService.cliamp.online : false

  readonly property bool hasMedia: mediaService ? !!mediaService.hasMedia : false
  readonly property bool hasPlayer: mediaService ? !!mediaService.hasPlayer : false
  readonly property bool isPlaying: mediaService ? !!mediaService.isPlaying : false
  readonly property string playIcon: isPlaying ? "󰏤" : "󰐊"
  readonly property string title: mediaService && mediaService.hasPlayer ? mediaService.title : "No media"
  readonly property string artist: mediaService ? mediaService.artist : ""
  readonly property string barLabel: hasPlayer
    ? ((root.mediaIsVideo ? "󰕧  " : "") + title + (artist ? "  ·  " + artist : ""))
    : "No media"

  property bool popupOpen: false
  property real maxLabelWidth: 120

  readonly property bool canGoPrevious: mediaService ? !!mediaService.canGoPrevious : false
  readonly property bool canGoNext: mediaService ? !!mediaService.canGoNext : false
  readonly property bool canTogglePlaying: mediaService ? !!mediaService.canTogglePlaying : false
  readonly property bool canDownload: mediaService ? !!mediaService.canDownload : false
  readonly property bool downloadBusy: mediaService ? !!mediaService.downloadBusy : false
  readonly property bool currentIsFavorite: mediaService ? !!mediaService.currentIsFavorite : false

  function runTransport(action) {
    if (!root.mediaService || !root.hasPlayer) return
    var key = root.usingMpv ? "mpv"
      : (root.usingCliamp ? "cliamp" : (root.mediaService.playerKey(root.activePlayer) || ""))
    root.mediaService.runAction(action, false, key)
  }

  function toggleFavoriteNow() {
    if (!root.mediaService) return
    root.mediaService.favoriteCurrent()
  }

  function downloadOrCancelNow() {
    if (!root.mediaService) return
    if (root.downloadBusy) {
      root.mediaService.cancelDownload()
      return
    }
    if (root.canDownload) root.mediaService.downloadCurrent()
  }

  // Shape contract for shell.summon/hide/toggle (Bar.findPanelWidget).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    root.openPanel()
  }

  function close() {
    // Outside-click from KeyboardPanel — close the drawer immediately.
    root.forceClose()
  }

  function forceClose() {
    popupOpen = false
    if (!panelLoader.item) return
    if (panelLoader.item.forceClose)
      panelLoader.item.forceClose()
    else if (panelLoader.item.opened)
      panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity (clock pattern). KeyboardPanel reads popoutSwitchClosing off owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
      panelLoader.item.closeForPopoutSwitch()
    else
      root.forceClose()
  }

  function closePopup() { popupOpen = false }

  function openFavourites() {
    popupOpen = false
    if (!panelLoader.item) return
    if (panelLoader.item.openFavourites)
      panelLoader.item.openFavourites()
    else {
      if (!panelLoader.item.opened) panelLoader.item.open()
      if (root.mediaService) root.mediaService.openHub("favourites")
    }
  }

  function openDownloads() {
    popupOpen = false
    if (!panelLoader.item) return
    if (panelLoader.item.openDownloads)
      panelLoader.item.openDownloads()
    else {
      if (!panelLoader.item.opened) panelLoader.item.open()
      if (root.mediaService) {
        root.mediaService.openHub("downloads")
        root.mediaService.loadDownloads()
      }
    }
  }

  function openPanel() {
    popupOpen = false
    if (!panelLoader.item) return
    if (!panelLoader.item.opened) panelLoader.item.open()
  }

  function togglePopup() {
    // Dead dual-UI path removed — always use the full panel.
    root.togglePanel()
  }

  function togglePanel() {
    popupOpen = false
    if (!panelLoader.item) return
    // Bar glyph click should fully dismiss, not peel search/hub layers.
    if (panelLoader.item.opened) {
      if (panelLoader.item.forceClose) panelLoader.item.forceClose()
      else panelLoader.item.close()
    } else {
      panelLoader.item.open()
    }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Always-visible media card on the nav (same box language as appearance-picker).
  visible: true
  implicitWidth: Math.max(Style.space(140), card.implicitWidth)
  implicitHeight: Math.max(barSize, card.implicitHeight)

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Own panel IPC here (clock pattern). Panel sets manageIpc:false so base
  // Panel doesn't double-register omarchy.media.
  IpcHandler {
    target: "omarchy.media"

    function open(): void { root.openPanel() }
    function close(): void { root.forceClose() }
    function show(): void { root.openPanel() }
    function hide(): void { root.forceClose() }
    function toggle(): void { root.togglePanel() }
    function favourites(): void { root.openFavourites() }
    function downloads(): void { root.openDownloads() }
  }

  Rectangle {
    id: card
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    width: cardRow.implicitWidth + Style.space(10)
    height: Style.bar.iconSlot + Style.space(4)
    implicitWidth: width
    implicitHeight: height
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
    color: Qt.rgba(root.bar.barForeground.r, root.bar.barForeground.g, root.bar.barForeground.b,
                   root.hasPlayer && root.isPlaying ? 0.12 : 0.07)
    border.width: Math.max(1, Style.spacing.hairline)
    border.color: Qt.rgba(root.bar.barForeground.r, root.bar.barForeground.g, root.bar.barForeground.b,
                          root.hasPlayer && root.isPlaying ? 0.34 : 0.18)

    Row {
      id: cardRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      // Art + title: click opens panel / popup (handled by infoMouse)
      Item {
        id: infoBlock
        width: infoRow.implicitWidth
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter

        Row {
          id: infoRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Rectangle {
            id: artChip
            width: Style.space(18)
            height: Style.space(18)
            radius: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(root.bar.barForeground.r, root.bar.barForeground.g, root.bar.barForeground.b, 0.14)
            clip: true

            Image {
              anchors.fill: parent
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              source: root.mediaService && root.mediaService.artUrl ? root.mediaService.artUrl : ""
              visible: source !== ""
            }

            Text {
              anchors.centerIn: parent
              visible: !(root.mediaService && root.mediaService.artUrl)
              textFormat: Text.PlainText
              text: root.mediaIsVideo ? "󰕧" : "󰝚"
              color: root.bar.barForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Corner badge when PiP is active
            Rectangle {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              width: Style.space(7)
              height: Style.space(7)
              radius: width / 2
              visible: root.videoPipVisible
              color: Color.accent
            }
          }

          Item {
            id: scrollClip
            width: Math.min(root.maxLabelWidth, Math.max(Style.space(56), labelText.implicitWidth))
            height: labelText.height
            clip: true
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.bar.vertical

            Text {
              id: labelText
              textFormat: Text.PlainText
              text: root.barLabel
              color: root.hasPlayer ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.55)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter

              property bool needsScroll: implicitWidth > scrollClip.width && root.hasMedia

              NumberAnimation on x {
                id: scrollAnim
                running: labelText.needsScroll && !root.popupOpen && !root.bar.vertical
                  && !(panelLoader.item && panelLoader.item.opened)
                loops: Animation.Infinite
                duration: Math.max(6000, labelText.implicitWidth * 25)
                from: scrollClip.width
                to: -labelText.implicitWidth
                easing.type: Easing.Linear
              }
            }
          }
        }

        MouseArea {
          id: infoMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) root.runTransport("next")
            else if (mouse.button === Qt.RightButton) root.openFavourites()
            else root.togglePanel()
          }
          onWheel: function(wheel) {
            if (!root.mediaService) return
            if (wheel.angleDelta.y > 0) root.runTransport("previous")
            else if (wheel.angleDelta.y < 0) root.runTransport("next")
          }
          onEntered: if (root.bar) root.bar.showTooltip(root, root.barLabel)
          onExited: if (root.bar) root.bar.hideTooltip(root)
        }
      }

      // Divider between info and transport
      Rectangle {
        width: Math.max(1, Style.spacing.hairline)
        height: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        color: root.bar.barForeground
        opacity: 0.18
      }

      // Inline prev / play-pause / next — usable without opening popup
      Row {
        id: transportRow
        spacing: 1
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: prevBtn
          textFormat: Text.PlainText
          text: "󰒮"
          width: Style.space(18)
          height: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: root.canGoPrevious ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.7)
          opacity: root.canGoPrevious ? (prevMouse.containsMouse ? 1 : 0.85) : 0.35
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            id: prevMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.canGoPrevious ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.canGoPrevious) root.runTransport("previous")
          }
        }

        Text {
          id: playBtn
          textFormat: Text.PlainText
          text: root.playIcon
          width: Style.space(20)
          height: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: root.canTogglePlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.7)
          opacity: root.canTogglePlaying ? (playMouse.containsMouse ? 1 : 0.95) : 0.35
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            id: playMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.canTogglePlaying ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.canTogglePlaying) root.runTransport("playPause")
          }
        }

        Text {
          id: nextBtn
          textFormat: Text.PlainText
          text: "󰒭"
          width: Style.space(18)
          height: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: root.canGoNext ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.7)
          opacity: root.canGoNext ? (nextMouse.containsMouse ? 1 : 0.85) : 0.35
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            id: nextMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.canGoNext ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.canGoNext) root.runTransport("next")
          }
        }

        // Restore/dismiss the floating video without opening the drawer.
        Text {
          id: videoBtn
          textFormat: Text.PlainText
          text: "󰕧"
          width: Style.space(18)
          height: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: root.videoPipVisible ? Color.accent : root.bar.barForeground
          opacity: videoMouse.containsMouse ? 1 : 0.9
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
          visible: root.canShowVideoPip

          MouseArea {
            id: videoMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (!root.mediaService) return
              if (root.videoPipVisible) root.mediaService.dismissVideoPip()
              else root.mediaService.reopenVideoPip()
              root.armHoldOpen(1500)
            }
            onEntered: if (root.bar) root.bar.showTooltip(root, root.videoPipVisible ? "Hide video" : "Show video")
            onExited: if (root.bar) root.bar.hideTooltip(root)
          }
        }

        // Favourite + download — one-click without opening the drawer
        Text {
          id: favBtn
          textFormat: Text.PlainText
          text: root.currentIsFavorite ? "󰋑" : "󰋕"
          width: Style.space(18)
          height: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: root.currentIsFavorite ? Color.accent
            : (root.hasPlayer ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.7))
          opacity: root.hasPlayer ? (favMouse.containsMouse ? 1 : 0.9) : 0.35
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            id: favMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.hasPlayer) root.toggleFavoriteNow()
            onEntered: if (root.bar) root.bar.showTooltip(root, root.currentIsFavorite ? "Unfavourite" : "Favourite")
            onExited: if (root.bar) root.bar.hideTooltip(root)
          }
        }

        Text {
          id: dlBtn
          textFormat: Text.PlainText
          text: root.downloadBusy ? "󰜺" : "󰇚"
          width: Style.space(18)
          height: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: root.downloadBusy ? Color.accent
            : ((root.canDownload || root.downloadBusy) ? root.bar.barForeground
              : Qt.darker(root.bar.barForeground, 1.7))
          opacity: (root.canDownload || root.downloadBusy)
            ? (dlMouse.containsMouse ? 1 : 0.9) : 0.35
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            id: dlMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: (root.canDownload || root.downloadBusy) ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.canDownload || root.downloadBusy) root.downloadOrCancelNow()
            onEntered: if (root.bar) root.bar.showTooltip(root, root.downloadBusy ? "Cancel download" : "Download")
            onExited: if (root.bar) root.bar.hideTooltip(root)
          }
        }
      }
    }
  }

  // Keep wheel over empty card padding usable; info/transport own their clicks.
  MouseArea {
    anchors.fill: parent
    z: -1
    hoverEnabled: false
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) {
      if (!root.mediaService) return
      if (wheel.angleDelta.y > 0) root.runTransport("previous")
      else if (wheel.angleDelta.y < 0) root.runTransport("next")
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: false  // retired — left-click opens Panel; kept for QML type stability
    visible: false
    contentWidth: Style.space(1)
    contentHeight: Style.space(1)

    Item { width: 1; height: 1 }
  }

}
