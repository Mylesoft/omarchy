import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "MediaModel.js" as MediaModel

// Full media panel: art, seek, transport, shuffle/repeat, volume, sources.
// BarWidget owns the bar glyph and loads this via Loader (clock pattern).
Panel {
  id: root
  moduleName: "omarchy.media"
  ipcTarget: "omarchy.media"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Prefer own plugin service so title/transport track cliamp+mpv, not the
  // narrow first-party bar proxy (activePlayer-only).
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
  readonly property bool videoFullscreen: mediaService ? !!mediaService.videoFullscreen : false
  readonly property bool canShowVideoPip: mediaService ? mediaService.canShowVideoPip === true : false
  readonly property bool videoPipDismissed: mediaService ? !!mediaService.videoPipDismissed : false
  readonly property bool cliampOnline: mediaService ? !!(mediaService.cliamp && mediaService.cliamp.online) : false
  readonly property bool hubOpen: mediaService ? !!mediaService.hubOpen : false
  readonly property string activeHubId: mediaService ? (mediaService.activeHubId || "") : ""
  readonly property var activeHub: mediaService ? mediaService.activeHub : null
  readonly property bool hasPlayer: mediaService ? !!mediaService.hasPlayer : false
  readonly property bool isPlaying: mediaService ? !!mediaService.isPlaying : false
  readonly property string title: mediaService && mediaService.hasPlayer ? mediaService.title : "No media"
  readonly property string artist: mediaService ? mediaService.artist : ""
  readonly property string album: mediaService ? mediaService.album : ""
  readonly property string identity: mediaService ? (mediaService.identity || "") : ""
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool canSeek: mediaService ? !!mediaService.canSeek : false
  readonly property bool mediaIsStream: mediaService ? !!mediaService.mediaIsStream : false
  readonly property string radioFrequency: mediaService ? String(mediaService.radioFrequency || "") : ""
  readonly property real trackPosition: mediaService ? Number(mediaService.trackPosition) || 0 : 0
  readonly property real trackLength: mediaService ? Number(mediaService.trackLength) || 0 : 0
  readonly property bool volumeSupported: mediaService ? !!mediaService.volumeSupported : false
  readonly property real mediaVolume: {
    if (!mediaService) return 0
    var v = mediaService.mediaVolume
    if (v === undefined || v === null) v = mediaService.volume
    v = Number(v)
    return isFinite(v) ? Math.max(0, Math.min(1, v)) : 0
  }
  readonly property bool systemMuted: mediaService ? !!mediaService.systemMuted : false
  readonly property bool shuffleSupported: mediaService ? !!mediaService.shuffleSupported : false
  readonly property bool loopSupported: mediaService ? !!mediaService.loopSupported : false
  readonly property bool shuffling: mediaService ? !!mediaService.shuffle : false
  readonly property bool canGoPrevious: mediaService ? !!mediaService.canGoPrevious : false
  readonly property bool canGoNext: mediaService ? !!mediaService.canGoNext : false
  readonly property bool canTogglePlaying: mediaService ? !!mediaService.canTogglePlaying : false
  readonly property bool searchAvailable: mediaService ? !!mediaService.searchAvailable : false
  readonly property string searchProviderLabel: mediaService ? (mediaService.searchProviderLabel || "") : ""
  readonly property string searchPlaceholder: mediaService ? (mediaService.searchPlaceholder || "Search…") : "Search…"
  readonly property var searchResults: mediaService ? mediaService.searchResults : []
  readonly property bool searchBusy: mediaService ? !!mediaService.searchBusy : false
  readonly property string searchError: mediaService ? (mediaService.searchError || "") : ""
  readonly property bool downloadChoicePending: mediaService ? !!mediaService.downloadChoicePending : false
  readonly property string sourceActionError: mediaService ? String(mediaService.sourceActionError || "") : ""
  readonly property string searchQuery: mediaService ? (mediaService.searchQuery || "") : ""
  readonly property var searchSuggestions: mediaService ? (mediaService.searchSuggestions || []) : []
  readonly property bool downloadBusy: mediaService ? !!mediaService.downloadBusy : false
  readonly property bool canDownload: mediaService ? !!mediaService.canDownload : false
  readonly property string downloadError: mediaService ? (mediaService.downloadError || "") : ""
  readonly property real downloadProgress: mediaService ? Number(mediaService.downloadProgress || 0) : 0
  readonly property string downloadStatus: mediaService ? (mediaService.downloadStatus || "") : ""
  readonly property string downloadTitle: mediaService ? (mediaService.downloadTitle || "") : ""
  readonly property var downloadItems: {
    var _t = mediaService ? mediaService.downloadTick : 0
    return mediaService ? (mediaService.downloadItems || []) : []
  }
  readonly property int downloadCount: mediaService ? mediaService.downloadCount : 0
  readonly property real playbackSpeed: mediaService ? Number(mediaService.playbackSpeed || 1) : 1
  readonly property string eqPreset: mediaService ? (mediaService.eqPreset || "Flat") : "Flat"
  readonly property var eqPresets: mediaService ? (mediaService.eqPresets || ["Flat", "Rock", "Pop", "Jazz", "Classical", "Vocal", "Loudness"]) : ["Flat", "Rock", "Pop", "Jazz", "Classical", "Vocal", "Loudness"]
  readonly property string activeAudioDevice: mediaService ? (mediaService.activeAudioDevice || "") : ""
  readonly property string shareMessage: mediaService ? (mediaService.shareMessage || "") : ""
  readonly property string lyricsText: mediaService ? (mediaService.lyricsText || "") : ""
  readonly property bool lyricsBusy: mediaService ? !!mediaService.lyricsBusy : false
  readonly property int sleepRemainingSec: mediaService ? Number(mediaService.sleepRemainingSec || 0) : 0
  readonly property bool sleepStopAfterTrack: mediaService ? !!mediaService.sleepStopAfterTrack : false
  readonly property var audioDevices: mediaService ? (mediaService.audioDevices || []) : []
  readonly property var pipewireSinks: mediaService ? (mediaService.pipewireSinks || []) : []
  readonly property var queueItems: {
    var _t = mediaService ? mediaService.queueTick : 0
    return mediaService ? (mediaService.queueItems || []) : []
  }
  readonly property int queueIndex: mediaService ? Number(mediaService.queueIndex || 0) : 0
  readonly property int queueTotal: mediaService ? Number(mediaService.queueTotal || 0) : 0
  readonly property bool queueBusy: mediaService ? !!mediaService.queueBusy : false
  readonly property var localFolders: mediaService ? (mediaService.localFolders || []) : []
  readonly property string localFolderFilter: mediaService ? (mediaService.localFolderFilter || "") : ""
  readonly property bool isRecentsHub: !!(root.activeHub && (root.activeHub.isRecentsHub || root.activeHubId === "recents"))
  property bool showExtras: false
  property bool extrasPinned: false
  property bool extrasHover: false
  readonly property bool extrasOpen: extrasPinned || extrasHover
  property bool showQueue: false
  property bool showLyrics: false
  // Transport extras tab: nearby | share | sleep | output | speed | eq | lyrics
  property string extrasTab: "nearby"
  property bool searchFocused: false
  // Per-source pane: "search" | "favourites" | "downloads". Global hubs ignore this.
  property string hubPane: "search"
  property string folderDraft: ""
  property var contextHit: null
  readonly property int loopState: mediaService ? mediaService.loopState : MprisLoopState.None
  readonly property string loopIcon: {
    if (loopState === MprisLoopState.Track) return "󰑘"
    if (loopState === MprisLoopState.Playlist) return "󰑖"
    return "󰑗"
  }
  readonly property bool isLibraryHub: !!(root.activeHub && (root.activeHub.isLibraryHub || root.activeHubId === "favourites"))
  readonly property bool isDownloadsHub: !!(root.activeHub && (root.activeHub.isDownloadsHub || root.activeHubId === "downloads"))
  readonly property bool showLibraryPane: root.isLibraryHub || (root.hubOpen && root.hubPane === "favourites" && !root.isDownloadsHub && !root.isRecentsHub)
  readonly property bool showDownloadsPane: root.isDownloadsHub || (root.hubOpen && root.hubPane === "downloads")
  readonly property bool showRecentsPane: root.isRecentsHub || (root.hubOpen && root.hubPane === "recents")
  readonly property bool showSearchPane: root.searchAvailable && root.hubPane === "search" && !root.isLibraryHub && !root.isDownloadsHub && !root.isRecentsHub
  readonly property var libraryItems: {
    var _t = mediaService ? mediaService.libraryTick : 0
    if (!mediaService) return []
    if (root.isLibraryHub)
      return mediaService.listFavorites(mediaService.libraryFilterProvider || "", mediaService.libraryFilterFolder || "")
    return mediaService.listFavorites(root.activeHubId || "", mediaService.libraryFilterFolder || "")
  }
  readonly property var recentItems: {
    var _t = mediaService ? mediaService.libraryTick : 0
    return mediaService ? mediaService.listRecents() : []
  }
  readonly property var favouriteFolders: mediaService ? (mediaService.favouriteFolders || []) : []
  readonly property bool currentIsFavorite: mediaService ? !!mediaService.currentIsFavorite : false
  readonly property int favouriteCount: mediaService ? mediaService.favouriteCount : 0
  readonly property string libraryFilterProvider: mediaService ? (mediaService.libraryFilterProvider || "") : ""
  readonly property string libraryFilterFolder: mediaService ? (mediaService.libraryFilterFolder || "") : ""
  readonly property bool verifyBusy: mediaService ? !!mediaService.verifyBusy : false
  readonly property var libraryProviderChips: {
    var _t = mediaService ? mediaService.libraryTick : 0
    if (!mediaService) return []
    var items = mediaService.favouriteItems || []
    var seen = {}
    var out = []
    for (var i = 0; i < items.length; i++) {
      var p = items[i] && items[i].hit ? String(items[i].hit.provider || "") : ""
      if (!p || seen[p]) continue
      seen[p] = true
      out.push(p)
    }
    return out
  }

  function providerLabel(id) {
    var key = String(id || "")
    if (key === "radio-garden") return "Radio Garden"
    if (key === "spotify") return "Spotify"
    if (key === "youtube") return "YouTube"
    if (key === "podcast" || key === "podcasts") return "Podcasts"
    if (key === "radio") return "Radio"
    if (key === "local") return "Local"
    if (!key) return "All"
    return key.charAt(0).toUpperCase() + key.slice(1)
  }

  function hitIsFavorite(hit) {
    if (!root.mediaService || !hit) return false
    var _t = root.mediaService.libraryTick
    return !!root.mediaService.isFavorite(hit)
  }

  function openFavourites() {
    root.open()
    if (root.mediaService) root.mediaService.openHub("favourites")
    root.hubPane = "favourites"
    root.contextHit = null
    root.armHoldOpen(2000)
  }

  function openDownloads() {
    root.open()
    if (root.mediaService) {
      root.mediaService.openHub("downloads")
      root.mediaService.loadDownloads()
    }
    root.hubPane = "downloads"
    root.contextHit = null
    root.armHoldOpen(2000)
  }

  function toggleHitFavorite(hit) {
    if (!root.mediaService || !hit) return
    root.armHoldOpen(1200)
    root.mediaService.toggleFavorite(hit)
  }

  function playLibraryHit(hit) {
    if (!root.mediaService || !hit) return
    root.armHoldOpen(2000)
    root.mediaService.playSearchResult(hit)
  }

  function showHitContext(hit) {
    if (!hit) return
    root.contextHit = hit
    root.armHoldOpen(2500)
  }

  function clearHitContext() {
    root.contextHit = null
  }

  function shuffleLibrary() {
    if (!root.mediaService) return
    var prov = root.isLibraryHub ? root.libraryFilterProvider : (root.activeHubId || "")
    var folder = root.libraryFilterFolder
    root.armHoldOpen(2000)
    root.mediaService.shuffleFavorites(prov, folder)
  }

  function runTransport(action) {
    if (!root.mediaService || !root.hasPlayer) return
    var key = root.usingMpv ? "mpv"
      : (root.usingCliamp ? "cliamp" : (root.mediaService.playerKey(root.activePlayer) || ""))
    root.mediaService.runAction(action, false, key)
  }

  // Keep the drawer open through source select / search focus / typing.
  // Outside-click close is progressive: leave search → leave hub → close panel.
  property double dismissGuardUntil: 0
  // Sticky hold while the drawer is doing in-panel work that grows layout
  // (source expand, search results). Outside-click peel is fine; full dismiss
  // is blocked until this clears.
  property bool holdOpen: false
  // True while search is focused OR a source hub is expanded — full dismiss
  // is blocked for the whole interaction, not just a short timer.
  readonly property bool interacting: root.searchFocused || root.hubOpen || root.holdOpen

  function armDismissGuard(ms) {
    var until = Date.now() + Math.max(250, ms || 900)
    if (until > root.dismissGuardUntil)
      root.dismissGuardUntil = until
  }

  function armHoldOpen(ms) {
    root.holdOpen = true
    root.armDismissGuard(ms || 2000)
    holdOpenTimer.interval = Math.max(600, ms || 2000)
    holdOpenTimer.restart()
  }

  function blurSearch() {
    root.searchFocused = false
    if (searchField)
      searchField.focus = false
  }

  // Safe to call from nested handlers / Qt.callLater — ids are resolved on root.
  function focusSearchField() {
    if (!root.opened) return
    if (!searchField || !searchField.visible) return
    searchField.forceActiveFocus()
    root.searchFocused = searchField.activeFocus
    root.armHoldOpen(2000)
    if (!searchBlock || !panelFlick || !panelFlick.contentItem) return
    var mapped = searchBlock.mapToItem(panelFlick.contentItem, 0, 0)
    if (!mapped) return
    var bottom = mapped.y + searchBlock.height
    var viewBottom = panelFlick.contentY + panelFlick.height
    if (bottom > viewBottom)
      panelFlick.contentY = Math.max(0, bottom - panelFlick.height + Style.space(12))
  }

  function closeExtras() {
    root.extrasPinned = false
    root.extrasHover = false
    root.showExtras = false
    extrasHoverLeaveTimer.stop()
  }

  function armExtrasHover() {
    extrasHoverLeaveTimer.stop()
    root.extrasHover = true
    root.showExtras = true
  }

  function releaseExtrasHover() {
    if (root.extrasPinned) return
    extrasHoverLeaveTimer.restart()
  }

  function openExtrasTo(tabId) {
    var tab = String(tabId || "").trim()
    if (tab) root.extrasTab = tab
    root.extrasPinned = true
    root.extrasHover = true
    root.showExtras = true
    if (root.mediaService)
      root.mediaService.persistUiPrefs(true, root.extrasTab)
    if (tab === "output" && root.mediaService)
      root.mediaService.refreshAudioDevices()
    if (tab === "nearby" && root.mediaService)
      root.mediaService.loadNearbyStations()
    if (tab === "lyrics") {
      root.showLyrics = true
      if (root.mediaService) root.mediaService.fetchLyrics()
    }
    root.armHoldOpen(4000)
    Qt.callLater(function() {
      if (!extrasColumn || !panelFlick || !panelFlick.contentItem) return
      var mapped = extrasColumn.mapToItem(panelFlick.contentItem, 0, 0)
      if (!mapped) return
      panelFlick.contentY = Math.max(0, mapped.y - Style.space(8))
    })
  }

  function toggleExtrasPinned() {
    root.extrasPinned = !root.extrasPinned
    if (root.extrasPinned) {
      root.extrasHover = true
      root.showExtras = true
      if (root.mediaService) root.mediaService.refreshAudioDevices()
      // If last tab was cliamp-only while not on cliamp, land on a usable tab.
      if (!root.usingCliamp && (root.extrasTab === "speed" || root.extrasTab === "eq" || root.extrasTab === "lyrics"))
        root.extrasTab = "nearby"
      Qt.callLater(function() {
        if (!extrasColumn || !panelFlick || !panelFlick.contentItem) return
        var mapped = extrasColumn.mapToItem(panelFlick.contentItem, 0, 0)
        if (!mapped) return
        panelFlick.contentY = Math.max(0, mapped.y - Style.space(8))
      })
    } else {
      root.closeExtras()
    }
    if (root.mediaService)
      root.mediaService.persistUiPrefs(root.extrasPinned, root.extrasTab)
  }

  function forceClose() {
    root.dismissGuardUntil = 0
    root.holdOpen = false
    holdOpenTimer.stop()
    root.closeExtras()
    root.blurSearch()
    if (root.mediaService) root.mediaService.closeHub()
    controller.hide()
  }

  function close() {
    // Outside-click: peel settings first, then dismiss the drawer.
    if (root.extrasOpen || root.extrasPinned) {
      root.closeExtras()
      return
    }
    root.forceClose()
  }

  function toggle() {
    if (root.opened) root.forceClose()
    else root.open()
  }

  property real revealOpacity: opened ? 1 : 0
  Behavior on revealOpacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  Timer {
    id: holdOpenTimer
    interval: 2000
    onTriggered: root.holdOpen = false
  }

  Timer {
    id: extrasHoverLeaveTimer
    interval: 160
    onTriggered: {
      if (root.extrasPinned) return
      root.extrasHover = false
      root.showExtras = false
    }
  }

  onOpenedChanged: {
    if (!opened) {
      searchFocused = false
      holdOpen = false
      holdOpenTimer.stop()
      root.closeExtras()
      if (searchField) searchField.focus = false
      if (root.mediaService) root.mediaService.closeHub()
    } else if (root.mediaService) {
      root.mediaService.refreshAudioDevices()
      root.mediaService.loadQueue()
      // Restore persisted extras pin/tab (don't force-close if user pins settings).
      root.extrasTab = root.mediaService.extrasTabSetting || root.extrasTab || "nearby"
      if (root.mediaService.extrasPinnedSetting) {
        root.extrasPinned = true
        root.extrasHover = true
        root.showExtras = true
      } else {
        root.closeExtras()
      }
      if (!root.extrasTab) root.extrasTab = "nearby"
      // Don't land on a hidden cliamp-only tab when following another player.
      if (!root.usingCliamp && (root.extrasTab === "speed" || root.extrasTab === "eq" || root.extrasTab === "lyrics"))
        root.extrasTab = "nearby"
    }
  }

  onSearchQueryChanged: {
    if (!searchField) return
    if (searchField.text !== root.searchQuery)
      searchField.text = root.searchQuery
  }

  onActiveHubIdChanged: {
    if (root.isDownloadsHub)
      root.hubPane = "downloads"
    else if (root.isRecentsHub)
      root.hubPane = "recents"
    else if (root.isLibraryHub)
      root.hubPane = "favourites"
    else
      root.hubPane = "search"
    root.folderDraft = ""
    root.contextHit = null
    if (!searchField) return
    searchField.text = root.searchQuery
    // Source switches grow the card; hold open through the rebuild.
    if (root.activeHubId)
      root.armHoldOpen(2200)
  }

  onHubOpenChanged: {
    if (root.hubOpen)
      root.armHoldOpen(2200)
  }

  onSearchBusyChanged: {
    if (root.searchBusy)
      root.armHoldOpen(2500)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.searchFocused
      onCloseRequested: {
        // Escape peels one layer at a time; outside-click uses close()/forceClose.
        if (root.extrasOpen || root.extrasPinned) {
          root.closeExtras()
          return
        }
        if (root.searchFocused || (searchField && searchField.activeFocus)) {
          root.blurSearch()
          if (keyCatcher) keyCatcher.forceActiveFocus()
          return
        }
        if (root.hubOpen && root.mediaService) {
          root.mediaService.closeHub()
          return
        }
        root.forceClose()
      }
      onTabRequested: function(direction) {
        // Don't switch panels while typing a search.
        if (root.searchFocused) return
        root.switchPanel(direction)
      }
      onActivateRequested: {
        if (root.mediaService) root.mediaService.runAction("playPause", false)
      }
      onTextKey: function(t) {
        if (!root.mediaService) return
        if (t === "Escape" || t === "\u001b") {
          if (root.hubOpen) { root.mediaService.closeHub(); return }
        }
        if (t === "n" || t === "N") root.mediaService.runAction("next", false)
        else if (t === "p" || t === "P") root.mediaService.runAction("previous", false)
        else if (t === "f" || t === "F") root.mediaService.followPlaying()
        else if (t === "s" || t === "S") root.mediaService.runAction("toggleShuffle", false)
        else if (t === "r" || t === "R") root.mediaService.runAction("cycleLoop", false)
        else if (t === "b" || t === "B") {
          if (root.hubOpen) root.mediaService.closeHub()
        }
        else if (t === "/" ) {
          if (root.hubOpen && root.searchAvailable && searchField.visible)
            searchField.forceActiveFocus()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        opacity: root.revealOpacity

        // Scroll / flick dismisses settings instantly.
        onMovementStarted: {
          if (root.extrasOpen)
            root.closeExtras()
        }

        WheelHandler {
          // Wheel over the main panel closes settings — but not while hovering extras.
          onWheel: function(event) {
            if (!root.extrasOpen) return
            if (extrasColumn && extrasColumn.visible) {
              var p = extrasColumn.mapFromItem(panelFlick, event.x, event.y)
              if (p && p.x >= 0 && p.y >= 0 && p.x <= extrasColumn.width && p.y <= extrasColumn.height)
                return
            }
            root.closeExtras()
          }
        }

        // Do NOT put a z:1000 MouseArea over the drawer. Presses are not
        // propagated even with propagateComposedEvents — that steals focus
        // from the search TextField and can leak the release to the
        // KeyboardPanel dismiss layer (drawer closes on type / source pick).

        Column {
          id: body
          width: panelFlick.width
          spacing: Style.space(14)

          // SOURCES — always at top; selection expands below transport
          Column {
            id: homeHubs
            width: parent.width
            spacing: Style.space(8)
            visible: true

            PanelSectionHeader {
              text: "SOURCES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Right-click a source to pin it up front"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Flickable {
              id: hubFlick
              width: parent.width
              height: Style.space(118)
              contentWidth: hubRow.implicitWidth
              contentHeight: height
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.HorizontalFlick
              interactive: contentWidth > width

              Row {
                id: hubRow
                spacing: Style.space(10)
                height: parent.height

                Repeater {
                  model: root.hubEntries

                  BorderSurface {
                    id: hubCard
                    required property var modelData
                    readonly property var hub: modelData
                    readonly property bool hot: hub && hub.playing
                    readonly property bool selected: hub && root.activeHubId === hub.id

                    width: Style.space(112)
                    height: hubFlick.height
                    radius: Style.space(14)
                    color: selected || hot
                      ? Style.selectedFillFor(root.foreground, Color.accent)
                      : Util.alpha(root.foreground, 0.05)
                    borderSpec: selected || hot
                      ? Border.controlSpec("normal", root.foreground, Color.accent)
                      : Border.controlSpec("normal", root.foreground, root.foreground)

                    Column {
                      anchors.fill: parent
                      anchors.margins: Style.space(12)
                      spacing: Style.space(8)

                      Text {
                        textFormat: Text.PlainText
                        text: hubCard.hub ? (hubCard.hub.icon || "󰎆") : "󰎆"
                        color: hubCard.hub && hubCard.hub.accent
                          ? Qt.lighter(hubCard.hub.accent, (hubCard.hot || hubCard.selected) ? 1.15 : 1.0)
                          : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.iconLarge
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: hubCard.hub ? hubCard.hub.label : ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        width: parent.width
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: {
                          if (!hubCard.hub) return ""
                          if (hubCard.selected) return "Selected"
                          if (hubCard.hub.playing) return "Playing"
                          // Favourites / Downloads show live counts from detail.
                          if (hubCard.hub.isLibraryHub || hubCard.hub.id === "favourites"
                              || hubCard.hub.isDownloadsHub || hubCard.hub.id === "downloads")
                            return hubCard.hub.detail || (hubCard.hub.id === "downloads" ? "Saved files" : "Library")
                          if (hubCard.hub.pinned) return "Pinned"
                          if (hubCard.hub.appSearch) return "Search"
                          if (hubCard.hub.appSync) return hubCard.hub.online ? "Synced" : "App"
                          return hubCard.hub.searchable ? "Search" : "Select"
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        elide: Text.ElideRight
                      }
                    }

                    // Pin glyph (top-right). Right-click card toggles pin.
                    Text {
                      anchors.top: parent.top
                      anchors.right: parent.right
                      anchors.margins: Style.space(8)
                      visible: !!(hubCard.hub && hubCard.hub.pinned)
                      textFormat: Text.PlainText
                      text: "󰐃"
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      z: 2
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      // Capture panel id — nested function()/callLater scopes lose `root`.
                      property var panelRef: root
                      onClicked: function(mouse) {
                        var panel = panelRef
                        if (!panel || !panel.mediaService || !hubCard.hub) return
                        if (mouse.button === Qt.RightButton) {
                          panel.mediaService.toggleHubPin(hubCard.hub.id)
                          return
                        }
                        // Toggle off if already selected — never launches outside.
                        if (hubCard.selected) {
                          panel.mediaService.closeHub()
                          panel.blurSearch()
                          panel.armHoldOpen(900)
                          return
                        }
                        panel.armHoldOpen(2500)
                        panel.mediaService.openHub(hubCard.hub.id)
                        if (hubCard.hub.isDownloadsHub || hubCard.hub.id === "downloads") {
                          panel.hubPane = "downloads"
                          panel.mediaService.loadDownloads()
                          return
                        }
                        if (hubCard.hub.isRecentsHub || hubCard.hub.id === "recents") {
                          panel.hubPane = "recents"
                          panel.mediaService.loadLibrary()
                          return
                        }
                        if (hubCard.hub.isLibraryHub || hubCard.hub.id === "favourites") {
                          panel.hubPane = "favourites"
                          return
                        }
                        if (hubCard.hub.searchable) {
                          // Mark search focused immediately so Escape/keys don't
                          // dismiss the drawer before the TextField mounts.
                          panel.searchFocused = true
                          panel.hubPane = "search"
                          panel.armHoldOpen(2500)
                          Qt.callLater(function() {
                            if (panel && panel.focusSearchField)
                              panel.focusSearchField()
                          })
                        }
                      }
                    }
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              TextField {
                id: directUrlField
                width: parent.width - directUrlActions.implicitWidth - Style.space(8)
                placeholderText: "Paste a URL to play or download"
                text: root.mediaService ? String(root.mediaService.directUrl || "") : ""
                selectByMouse: true
                onAccepted: if (root.mediaService) root.mediaService.playDirectUrl(text)
              }
              Row {
                id: directUrlActions
                spacing: Style.space(6)
                Button {
                  text: "Play URL"
                  foreground: root.foreground
                  onClicked: if (root.mediaService) root.mediaService.playDirectUrl(directUrlField.text)
                }
                Button {
                  text: "Download"
                  foreground: root.foreground
                  onClicked: if (root.mediaService) root.mediaService.downloadDirectUrl(directUrlField.text)
                }
              }
            }

            Text {
              width: parent.width
              visible: root.sourceActionError !== ""
              text: root.sourceActionError
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            BorderSurface {
              width: parent.width
              visible: root.downloadChoicePending
              height: downloadChoiceRow.implicitHeight + Style.space(20)
              radius: Style.space(12)
              color: Util.alpha(Color.accent, 0.10)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              Row {
                id: downloadChoiceRow
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(8)
                Text {
                  text: "Download as"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
                Button { text: "Video"; foreground: root.foreground; onClicked: root.mediaService.chooseDownloadFormat("video") }
                Button { text: "MP3 audio"; foreground: root.foreground; onClicked: root.mediaService.chooseDownloadFormat("mp3") }
                Button { text: "Cancel"; foreground: root.dim; onClicked: root.mediaService.cancelDownloadChoice() }
              }
            }
          }

          // Now playing / transport — source expand appears below this block
          BorderSurface {
            width: parent.width
            height: heroInner.implicitHeight + Style.space(28)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(12)
            color: Util.alpha(Color.accent, 0.06)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

            Column {
              id: heroInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              anchors.rightMargin: Style.space(14)
              spacing: Style.space(12)

              Row {
                spacing: Style.space(14)
                width: parent.width

                BorderSurface {
                  width: Style.space(96)
                  height: Style.space(96)
                  radius: Style.spacing.labelGap
                  color: Style.normalFillFor(root.foreground, Color.accent)
                  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                  Image {
                    anchors.fill: parent
                    anchors.margins: Style.space(2)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: root.mediaService && root.mediaService.artUrl ? root.mediaService.artUrl : ""
                    visible: source !== ""
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: !(root.mediaService && root.mediaService.artUrl)
                    text: root.mediaIsVideo || root.usingMpv ? "󰕧" : "󰝚"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.displayLarge
                  }
                }

                Column {
                  spacing: Style.space(4)
                  width: parent.width - Style.space(110)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: root.title
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: root.artist
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: root.album || root.identity
                    color: Qt.darker(root.foreground, 1.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.hasPlayer

                // Seekable tracks — interactive scrubber
                PanelSlider {
                  width: parent.width
                  visible: root.canSeek && root.trackLength > 0
                  bar: root.bar
                  minimum: 0
                  maximum: Math.max(1, root.trackLength)
                  value: root.trackPosition
                  step: 5
                  onReleased: function(v) {
                    if (root.mediaService) root.mediaService.setPosition(v, false)
                  }
                }

                // Live / non-seekable — visual track with pulsing live marker + dial frequency
                Item {
                  width: parent.width
                  height: Math.max(Style.space(22), Style.space(14))
                  visible: !root.canSeek || root.trackLength <= 0

                  Rectangle {
                    id: liveTrack
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
                    radius: height / 2
                    color: Style.selectedFillFor(root.foreground, Color.accent)

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      height: parent.height
                      radius: parent.radius
                      color: root.foreground
                      width: parent.width * livePulse.progress
                      opacity: 0.55 + 0.35 * livePulse.progress

                      Behavior on width {
                        NumberAnimation { duration: 900; easing.type: Easing.InOutSine }
                      }
                    }
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(10, Style.space(10))
                    height: width
                    radius: width / 2
                    color: Color.accent
                    x: Math.max(0, Math.min(parent.width - width, parent.width * livePulse.progress - width / 2))
                    opacity: root.radioFrequency !== "" ? 0.35 : 0.85
                    visible: root.radioFrequency === ""

                    Behavior on x {
                      NumberAnimation { duration: 900; easing.type: Easing.InOutSine }
                    }
                  }

                  // Dial frequency centered on the live bar
                  Text {
                    anchors.centerIn: parent
                    visible: root.radioFrequency !== ""
                    textFormat: Text.PlainText
                    text: root.radioFrequency
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    style: Text.Outline
                    styleColor: Util.alpha(root.bar ? root.bar.background : Color.background, 0.85)
                  }

                  Timer {
                    id: livePulse
                    property real progress: 0.18
                    property bool rising: true
                    interval: 900
                    running: parent.visible && root.isPlaying
                    repeat: true
                    onTriggered: {
                      rising = !rising
                      progress = rising ? 0.82 : 0.18
                    }
                  }
                }

                Row {
                  width: parent.width
                  Text {
                    id: posLabel
                    textFormat: Text.PlainText
                    text: root.mediaService
                      ? root.mediaService.formatClock(root.trackPosition)
                      : "0:00"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Item { width: Math.max(0, parent.width - posLabel.width - lenLabel.width); height: 1 }
                  Text {
                    id: lenLabel
                    textFormat: Text.PlainText
                    text: {
                      if (root.canSeek && root.trackLength > 0 && root.mediaService)
                        return root.mediaService.formatClock(root.trackLength)
                      if (root.mediaIsStream || root.trackLength <= 0)
                        return root.radioFrequency !== "" ? ("LIVE · " + root.radioFrequency) : "LIVE"
                      return root.mediaService
                        ? root.mediaService.formatClock(root.trackLength)
                        : "0:00"
                    }
                    color: (root.mediaIsStream || !root.canSeek) ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.mediaIsStream || !root.canSeek
                  }
                }
              }

              // One compact toolbar: shuffle, transport, repeat, then utility actions.
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(2)
                visible: root.hasPlayer

                Button {
                  iconText: root.currentIsFavorite ? "󰋑" : "󰋕"
                  foreground: root.currentIsFavorite ? Color.accent : root.foreground
                  enabled: root.hasPlayer || !!(root.mediaService && root.mediaService.lastPlayedHit)
                  opacity: enabled ? 1.0 : 0.35
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(5)
                  onClicked: if (root.mediaService) root.mediaService.favoriteCurrent()
                }
                Button {
                  iconText: "󰒝"
                  foreground: root.shuffling ? Color.accent : root.foreground
                  enabled: root.shuffleSupported
                  opacity: enabled ? 1.0 : 0.35
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(5)
                  onClicked: if (root.mediaService) root.mediaService.runAction("toggleShuffle", true)
                }
                Button {
                  iconText: "󰒮"
                  foreground: root.foreground
                  enabled: root.canGoPrevious
                  opacity: enabled ? 1.0 : 0.4
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(5)
                  onClicked: root.runTransport("previous")
                }
                Button {
                  iconText: root.isPlaying ? "󰏤" : "󰐊"
                  foreground: root.foreground
                  enabled: root.canTogglePlaying
                  opacity: enabled ? 1.0 : 0.4
                  iconSize: Style.font.iconLarge
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(5)
                  onClicked: root.runTransport("playPause")
                }
                Button {
                  iconText: "󰒭"
                  foreground: root.foreground
                  enabled: root.canGoNext
                  opacity: enabled ? 1.0 : 0.4
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(5)
                  onClicked: root.runTransport("next")
                }
                Button {
                  iconText: root.loopIcon
                  foreground: root.loopState !== MprisLoopState.None ? Color.accent : root.foreground
                  enabled: root.loopSupported
                  opacity: enabled ? 1.0 : 0.35
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(5)
                  onClicked: if (root.mediaService) root.mediaService.runAction("cycleLoop", true)
                }
                Button {
                  iconText: root.downloadBusy ? "󰜺" : "󰇚"
                  foreground: root.downloadBusy ? Color.accent : root.foreground
                  enabled: root.canDownload || root.downloadBusy
                  opacity: enabled ? 1.0 : 0.35
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(5)
                  onClicked: {
                    if (!root.mediaService) return
                    if (root.downloadBusy) root.mediaService.cancelDownload()
                    else { root.mediaService.downloadCurrent(); root.armHoldOpen(3000) }
                  }
                }
                Button {
                  iconText: "󰐑"
                  foreground: root.showQueue ? Color.accent : root.foreground
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(5)
                  onClicked: {
                    root.showQueue = !root.showQueue
                    if (root.showQueue && root.mediaService) root.mediaService.loadQueue()
                  }
                }
                Item {
                  width: settingsGearBtn.width
                  height: settingsGearBtn.height
                  Button {
                    id: settingsGearBtn
                    iconText: "󰒓"
                    foreground: root.extrasOpen ? Color.accent : root.foreground
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(5)
                    onClicked: root.toggleExtrasPinned()
                  }
                  HoverHandler {
                    onHoveredChanged: {
                      if (hovered) {
                        root.armExtrasHover()
                        if (root.mediaService) root.mediaService.refreshAudioDevices()
                      } else root.releaseExtrasHover()
                    }
                  }
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.canShowVideoPip

                PanelSectionHeader {
                  text: "VIDEO WINDOW"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Row {
                  width: parent.width
                  spacing: Style.space(2)
                  Button {
                    iconText: "󰕧"
                    text: root.videoPipVisible ? "Hide" : "Show"
                    foreground: root.videoPipVisible ? Color.accent : root.foreground
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(5)
                    onClicked: {
                      if (!root.mediaService) return
                      if (root.videoPipVisible) root.mediaService.dismissVideoPip()
                      else root.mediaService.reopenVideoPip()
                    }
                  }
                  Text {
                    text: "Size"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Button {
                    text: "S"
                    foreground: (root.mediaService && root.mediaService.videoPreset === "S") ? Color.accent : root.foreground
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(4)
                    onClicked: if (root.mediaService) root.mediaService.setVideoPreset("S")
                  }
                  Button {
                    text: "M"
                    foreground: (root.mediaService && root.mediaService.videoPreset === "M") ? Color.accent : root.foreground
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(4)
                    onClicked: if (root.mediaService) root.mediaService.setVideoPreset("M")
                  }
                  Button {
                    text: "L"
                    foreground: (root.mediaService && root.mediaService.videoPreset === "L") ? Color.accent : root.foreground
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(4)
                    onClicked: if (root.mediaService) root.mediaService.setVideoPreset("L")
                  }
                  Button {
                    iconText: "󰊓"
                    text: root.videoFullscreen ? "Windowed" : "Full"
                    foreground: root.videoFullscreen ? Color.accent : root.foreground
                    horizontalPadding: Style.space(4)
                    verticalPadding: Style.space(4)
                    onClicked: if (root.mediaService)
                      root.mediaService.setVideoFullscreen(!root.videoFullscreen)
                  }
                  Button {
                    iconText: "󰕧"
                    text: "Extra PiP"
                    foreground: root.foreground
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(5)
                    onClicked: if (root.mediaService) root.mediaService.openExtraPiPCurrent()
                  }
                  Button {
                    iconText: "󰒡"
                    text: root.mediaService && root.mediaService.dualAudioEnabled ? "Split on" : "Split AV"
                    foreground: root.mediaService && root.mediaService.dualAudioEnabled ? Color.accent : root.foreground
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(5)
                    onClicked: if (root.mediaService)
                      root.mediaService.setDualAudioEnabled(!root.mediaService.dualAudioEnabled)
                  }
                  Button {
                    iconText: "󰓢"
                    text: root.mediaService && root.mediaService.castBusy ? "Searching…" : "Cast"
                    foreground: root.mediaService && root.mediaService.castTargets.length ? Color.accent : root.foreground
                    enabled: !!(root.mediaService && !root.mediaService.castBusy)
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(5)
                    onClicked: if (root.mediaService) root.mediaService.discoverCastTargets()
                  }
                  Button {
                    iconText: "󰅖"
                    text: "Close"
                    foreground: root.dim
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(5)
                    visible: !!(root.mediaService && root.mediaService.extraPipIds.length)
                    onClicked: if (root.mediaService) root.mediaService.closeExtraPiPs()
                  }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  visible: !!(root.mediaService
                    && (root.mediaService.castTargets.length || root.mediaService.castStatus))
                  Text {
                    text: root.mediaService ? String(root.mediaService.castStatus || "CAST RECEIVERS") : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Flow {
                    width: parent.width
                    spacing: Style.space(6)
                    Repeater {
                      model: root.mediaService ? root.mediaService.castTargets : []
                      Button {
                        required property var modelData
                        text: String(modelData.name || "Receiver")
                        foreground: root.foreground
                        onClicked: if (root.mediaService) root.mediaService.castCurrent(modelData)
                      }
                    }
                  }
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.hasPlayer

                PanelSectionHeader {
                  text: "ACTIONS"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Row {
                  width: parent.width
                  spacing: Style.space(4)

                  Button {
                    iconText: "󰒡"
                    text: "Share"
                    foreground: Color.accent
                    horizontalPadding: Style.space(4)
                    enabled: !!(root.mediaService && (root.mediaService.mediaPath || root.title))
                    opacity: enabled ? 1.0 : 0.35
                    onClicked: {
                      if (root.mediaService) root.mediaService.shareCurrentLink()
                      root.armHoldOpen(2000)
                    }
                  }
                  Button {
                    iconText: "󰐻"
                    text: "Nearby"
                    foreground: root.foreground
                    horizontalPadding: Style.space(4)
                    onClicked: root.openExtrasTo("nearby")
                  }
                  Button {
                    iconText: "󰻃"
                    text: "Record stream"
                    foreground: root.foreground
                    horizontalPadding: Style.space(4)
                    visible: root.mediaIsStream
                    enabled: root.canDownload && !root.downloadBusy
                    opacity: enabled ? 1.0 : 0.35
                    onClicked: {
                      if (root.mediaService) root.mediaService.recordCurrent(1)
                      root.armHoldOpen(4000)
                    }
                  }
                  Button {
                    iconText: "󰨖"
                    text: ""
                    tooltipText: "Subtitles"
                    foreground: (root.mediaService && root.mediaService.videoSubs) ? Color.accent : root.foreground
                    horizontalPadding: Style.space(1)
                    verticalPadding: Style.space(4)
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                    onClicked: if (root.mediaService) root.mediaService.toggleVideoSubs()
                  }
                  Button {
                    iconText: "󰘖"
                    text: ""
                    tooltipText: "Aspect ratio"
                    foreground: (root.mediaService && root.mediaService.videoAspectLock !== false) ? Color.accent : root.foreground
                    horizontalPadding: Style.space(1)
                    verticalPadding: Style.space(4)
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                    onClicked: if (root.mediaService) root.mediaService.toggleVideoAspectLock()
                  }
                  Button {
                    iconText: "󰍾"
                    text: ""
                    tooltipText: "Click-through"
                    foreground: (root.mediaService && root.mediaService.videoClickThrough) ? Color.accent : root.foreground
                    horizontalPadding: Style.space(1)
                    verticalPadding: Style.space(4)
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                    onClicked: if (root.mediaService)
                      root.mediaService.setVideoClickThrough(!root.mediaService.videoClickThrough)
                  }
                  Text {
                    text: "Snap"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                  }
                  Button {
                    text: "TL"
                    tooltipText: "Snap top left"
                    foreground: root.foreground
                    horizontalPadding: Style.space(1)
                    verticalPadding: Style.space(4)
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                    onClicked: if (root.mediaService) root.mediaService.snapVideoCorner("tl")
                  }
                  Button {
                    text: "TR"
                    tooltipText: "Snap top right"
                    foreground: root.foreground
                    horizontalPadding: Style.space(1)
                    verticalPadding: Style.space(4)
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                    onClicked: if (root.mediaService) root.mediaService.snapVideoCorner("tr")
                  }
                  Button {
                    text: "BL"
                    tooltipText: "Snap bottom left"
                    foreground: root.foreground
                    horizontalPadding: Style.space(1)
                    verticalPadding: Style.space(4)
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                    onClicked: if (root.mediaService) root.mediaService.snapVideoCorner("bl")
                  }
                  Button {
                    text: "BR"
                    tooltipText: "Snap bottom right"
                    foreground: root.foreground
                    horizontalPadding: Style.space(1)
                    verticalPadding: Style.space(4)
                    visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible
                    onClicked: if (root.mediaService) root.mediaService.snapVideoCorner("br")
                  }
                }

                // PiP opacity control.
                Column {
                  width: parent.width
                  spacing: Style.space(6)
                  visible: root.usingMpv || root.mediaIsVideo || root.videoPipVisible

                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                      textFormat: Text.PlainText
                      text: "Opacity"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    PanelSlider {
                      width: parent.width - Style.space(72) - opPct.width
                      bar: root.bar
                      minimum: 0.4
                      maximum: 1
                      step: 0.05
                      value: root.mediaService ? Number(root.mediaService.videoOpacity) || 1 : 1
                      onMoved: function(v) {
                        if (root.mediaService) root.mediaService.setVideoOpacity(v)
                      }
                      onReleased: function(v) {
                        if (root.mediaService) root.mediaService.setVideoOpacity(v)
                      }
                    }
                    Text {
                      id: opPct
                      textFormat: Text.PlainText
                      text: {
                        var o = root.mediaService ? Number(root.mediaService.videoOpacity) : 1
                        return Math.round((isFinite(o) ? o : 1) * 100) + "%"
                      }
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }

              // Volume
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.hasPlayer

                PanelSectionHeader {
                  text: "VOLUME"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    textFormat: Text.PlainText
                    text: {
                      if (root.systemMuted || root.mediaVolume <= 0.001) return "󰝟"
                      if (root.mediaVolume < 0.34) return "󰕿"
                      if (root.mediaVolume < 0.67) return "󰖀"
                      return "󰕾"
                    }
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  PanelSlider {
                    width: parent.width - Style.space(28) - volPct.width - Style.space(8)
                    bar: root.bar
                    minimum: 0
                    maximum: 1
                    step: 0.02
                    value: root.mediaVolume
                    onMoved: function(v) {
                      if (root.mediaService) root.mediaService.setVolume(v, false)
                    }
                    onReleased: function(v) {
                      if (root.mediaService) root.mediaService.setVolume(v, true)
                    }
                    onRightClicked: {
                      if (root.mediaService) root.mediaService.toggleMute(true)
                    }
                  }
                  Text {
                    id: volPct
                    textFormat: Text.PlainText
                    text: root.systemMuted ? "Mute" : (Math.round(root.mediaVolume * 100) + "%")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Row {
                  spacing: Style.space(6)
                  visible: !!(root.mediaService)
                  Repeater {
                    model: [
                      { id: "system", label: "System" },
                      { id: "player", label: "Player" },
                      { id: "linked", label: "Linked" }
                    ]
                    BorderSurface {
                      required property var modelData
                      readonly property bool selected: root.mediaService
                        && String(root.mediaService.volumeMode || "system") === modelData.id
                      height: Style.space(22)
                      width: volModeLabel.implicitWidth + Style.space(14)
                      radius: Style.space(6)
                      color: selected ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.05)
                      borderSpec: Border.none()
                      Text {
                        id: volModeLabel
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData.label
                        color: selected ? Color.accent : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.mediaService) root.mediaService.setVolumeMode(modelData.id)
                          root.armHoldOpen(1200)
                        }
                      }
                    }
                  }
                }
              }

              // Active download only — cancel clears this entirely (errors dismiss on tap)
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.downloadBusy
                  || (root.downloadProgress > 0 && root.downloadProgress < 100)
                  || (root.downloadError !== "" && root.downloadError !== "cancelled" && root.downloadError !== "canceled")

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    textFormat: Text.PlainText
                    text: root.downloadBusy
                      ? ("Downloading · " + Math.round(root.downloadProgress) + "%")
                      : "Download failed"
                    color: root.downloadError ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width - pctLabel.width - cancelDlBtn.width - Style.space(12)
                  }
                  Text {
                    id: pctLabel
                    textFormat: Text.PlainText
                    text: root.downloadBusy ? (Math.round(root.downloadProgress) + "%") : ""
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    visible: text !== ""
                  }
                  Button {
                    id: cancelDlBtn
                    text: root.downloadBusy ? "Cancel" : "Dismiss"
                    foreground: Color.accent
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.space(2)
                    onClicked: {
                      if (!root.mediaService) return
                      if (root.downloadBusy) root.mediaService.cancelDownload()
                      else root.mediaService.clearDownloadUi()
                    }
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(4)
                  radius: Style.space(2)
                  color: Util.alpha(root.foreground, 0.08)
                  visible: root.downloadBusy || (root.downloadProgress > 0 && root.downloadProgress < 100)
                  Rectangle {
                    width: Math.max(Style.space(4), parent.width * Math.max(0, Math.min(1, root.downloadProgress / 100)))
                    height: parent.height
                    radius: parent.radius
                    color: Color.accent
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.downloadBusy
                    ? (root.downloadStatus || root.downloadTitle || "")
                    : (root.downloadError || "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  visible: text !== ""
                }
              }

              // Live queue (transport)
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.showQueue

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    textFormat: Text.PlainText
                    text: root.queueTotal > 0
                      ? ("QUEUE · " + (root.queueIndex + 1) + " / " + root.queueTotal)
                      : (root.queueBusy ? "QUEUE · loading…" : "QUEUE · empty")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    width: parent.width - clearQueueBtn.width - queueNowBtn.width - Style.space(16)
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Button {
                    id: queueNowBtn
                    text: "Queue now"
                    foreground: root.foreground
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY
                    onClicked: {
                      if (root.mediaService) root.mediaService.queueCurrentTrack()
                      root.armHoldOpen(1500)
                    }
                  }
                  Button {
                    id: clearQueueBtn
                    text: "Clear"
                    foreground: root.dim
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY
                    enabled: root.queueTotal > 0
                    opacity: enabled ? 1.0 : 0.35
                    onClicked: {
                      if (root.mediaService) root.mediaService.clearQueue()
                      root.armHoldOpen(1200)
                    }
                  }
                }

                Repeater {
                  model: {
                    var _t = root.queueTotal
                    var items = root.queueItems || []
                    var start = Math.max(0, root.queueIndex)
                    var slice = []
                    for (var i = start; i < items.length && slice.length < 8; i++)
                      slice.push(items[i])
                    return slice
                  }
                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    height: Style.space(32)
                    readonly property bool isCurrent: modelData && modelData.index === root.queueIndex
                    readonly property int qIndex: modelData ? Number(modelData.index) : -1

                    Text {
                      anchors.left: parent.left
                      anchors.right: queueActions.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: (isCurrent ? "▶ " : "  ") + String((modelData && modelData.title) || "Track")
                      color: isCurrent ? Color.accent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Row {
                      id: queueActions
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(2)

                      Text {
                        textFormat: Text.PlainText
                        text: "󰒭"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(20)
                        horizontalAlignment: Text.AlignHCenter
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (root.mediaService) root.mediaService.playNextQueueIndex(qIndex)
                            root.armHoldOpen(1200)
                          }
                        }
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: "󰁝"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(18)
                        horizontalAlignment: Text.AlignHCenter
                        opacity: qIndex > 0 ? 1 : 0.3
                        MouseArea {
                          anchors.fill: parent
                          enabled: qIndex > 0
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (root.mediaService) root.mediaService.moveQueueIndex(qIndex, qIndex - 1)
                            root.armHoldOpen(1000)
                          }
                        }
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: "󰁅"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(18)
                        horizontalAlignment: Text.AlignHCenter
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (root.mediaService) root.mediaService.moveQueueIndex(qIndex, qIndex + 1)
                            root.armHoldOpen(1000)
                          }
                        }
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: "󰅖"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(18)
                        horizontalAlignment: Text.AlignHCenter
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (root.mediaService) root.mediaService.removeQueueIndex(qIndex)
                            root.armHoldOpen(1000)
                          }
                        }
                      }
                    }

                    MouseArea {
                      anchors.left: parent.left
                      anchors.right: queueActions.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.mediaService && modelData)
                          root.mediaService.playQueueIndex(modelData.index)
                        root.armHoldOpen(1500)
                      }
                    }
                  }
                }
              }

              // Extras — tabbed: Nearby / Share / Sleep / Output / Speed / EQ / Lyrics
              // Closed by default; gear / Settings opens; scroll/outside closes.
              Column {
                id: extrasColumn
                width: parent.width
                spacing: Style.space(10)
                visible: root.extrasOpen

                HoverHandler {
                  onHoveredChanged: {
                    if (hovered) root.armExtrasHover()
                    else root.releaseExtrasHover()
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "SETTINGS"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: {
                      var tabs = [
                        { id: "nearby", label: "Nearby", cliampOnly: false },
                        { id: "share", label: "Share", cliampOnly: false },
                        { id: "sleep", label: "Sleep", cliampOnly: false },
                        { id: "output", label: "Output", cliampOnly: false },
                        { id: "speed", label: "Speed", cliampOnly: true },
                        { id: "eq", label: "EQ", cliampOnly: true },
                        { id: "lyrics", label: "Lyrics", cliampOnly: true }
                      ]
                      var out = []
                      for (var i = 0; i < tabs.length; i++) {
                        if (tabs[i].cliampOnly && !root.usingCliamp) continue
                        out.push(tabs[i])
                      }
                      return out
                    }
                    delegate: BorderSurface {
                      required property var modelData
                      readonly property string tabId: modelData.id
                      readonly property bool selected: root.extrasTab === tabId
                      height: Style.space(28)
                      width: extrasChipLabel.implicitWidth + Style.space(18)
                      radius: Style.space(8)
                      color: selected ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                      borderSpec: Border.none()

                      Text {
                        id: extrasChipLabel
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String(modelData.label || "")
                        color: selected ? Color.accent : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: selected
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.extrasTab = tabId
                          if (root.mediaService)
                            root.mediaService.persistUiPrefs(root.extrasPinned, tabId)
                          if (tabId === "output" && root.mediaService)
                            root.mediaService.refreshAudioDevices()
                          if (tabId === "nearby" && root.mediaService)
                            root.mediaService.loadNearbyStations()
                          if (tabId === "lyrics") {
                            root.showLyrics = true
                            if (root.mediaService) root.mediaService.fetchLyrics()
                          }
                          root.armHoldOpen(2000)
                        }
                      }
                    }
                  }
                }

                // SPEED
                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.extrasTab === "speed" && root.usingCliamp

                  Text {
                    textFormat: Text.PlainText
                    text: "Playback speed · " + Number(root.playbackSpeed).toFixed(2).replace(/\.00$/, "") + "×"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)

                    Repeater {
                      model: [0.75, 1.0, 1.25, 1.5, 2.0]
                      Button {
                        required property var modelData
                        readonly property bool selected: Math.abs(root.playbackSpeed - Number(modelData)) < 0.01
                        text: Number(modelData).toFixed(2).replace(/\.00$/, "") + "×"
                        foreground: selected ? Color.accent : root.foreground
                        horizontalPadding: Style.space(14)
                        verticalPadding: Style.spacing.controlPaddingY
                        onClicked: {
                          if (root.mediaService) root.mediaService.setPlaybackSpeed(modelData)
                          root.armHoldOpen(1500)
                        }
                      }
                    }
                  }
                }

                // EQ
                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.extrasTab === "eq" && root.usingCliamp

                  Text {
                    textFormat: Text.PlainText
                    text: "Equalizer · " + (root.eqPreset || "Flat")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)

                    Repeater {
                      model: root.eqPresets
                      Button {
                        required property var modelData
                        readonly property bool selected: root.eqPreset === String(modelData)
                        text: String(modelData)
                        foreground: selected ? Color.accent : root.foreground
                        horizontalPadding: Style.space(14)
                        verticalPadding: Style.spacing.controlPaddingY
                        onClicked: {
                          if (root.mediaService) root.mediaService.setEqPreset(modelData)
                          root.armHoldOpen(1500)
                        }
                      }
                    }
                  }
                }

                // SLEEP
                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.extrasTab === "sleep"

                  Text {
                    textFormat: Text.PlainText
                    text: root.sleepRemainingSec > 0
                      ? ("Sleep timer · " + Math.floor(root.sleepRemainingSec / 60) + "m " + (root.sleepRemainingSec % 60) + "s left")
                      : (root.sleepStopAfterTrack ? "Sleep · stop after this track" : "Sleep timer · off")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)

                    Repeater {
                      model: [15, 30, 45, 60]
                      Button {
                        required property var modelData
                        text: String(modelData) + "m"
                        foreground: root.foreground
                        horizontalPadding: Style.space(14)
                        verticalPadding: Style.spacing.controlPaddingY
                        onClicked: {
                          if (root.mediaService) root.mediaService.startSleepTimer(modelData, false)
                          root.armHoldOpen(1500)
                        }
                      }
                    }

                    Button {
                      text: "This track"
                      foreground: root.sleepStopAfterTrack ? Color.accent : root.foreground
                      horizontalPadding: Style.space(14)
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        if (root.mediaService) root.mediaService.startSleepTimer(0, true)
                        root.armHoldOpen(1500)
                      }
                    }

                    Button {
                      text: "Off"
                      foreground: root.dim
                      horizontalPadding: Style.space(14)
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        if (root.mediaService) root.mediaService.clearSleepTimer()
                        root.armHoldOpen(1200)
                      }
                    }
                  }
                }

                // OUTPUT
                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.extrasTab === "output"

                  Text {
                    textFormat: Text.PlainText
                    text: "Audio output"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    width: parent.width
                    visible: !(root.pipewireSinks && root.pipewireSinks.length) && !(root.audioDevices && root.audioDevices.length)
                    textFormat: Text.PlainText
                    text: "No outputs detected"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)
                    visible: root.pipewireSinks && root.pipewireSinks.length > 0

                    Repeater {
                      model: root.pipewireSinks
                      Button {
                        required property var modelData
                        readonly property var sink: modelData
                        readonly property bool selected: !!(sink && sink.active)
                        text: sink ? ((selected ? "● " : "") + String(sink.name || sink.id || "Sink").slice(0, 36)) : "Sink"
                        foreground: selected ? Color.accent : root.foreground
                        horizontalPadding: Style.space(12)
                        verticalPadding: Style.spacing.controlPaddingY
                        onClicked: {
                          if (root.mediaService && sink) root.mediaService.setPipewireSink(sink.id)
                          root.armHoldOpen(1500)
                        }
                      }
                    }
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)
                    visible: root.audioDevices && root.audioDevices.length > 0

                    Repeater {
                      model: root.audioDevices
                      Button {
                        required property var modelData
                        readonly property string deviceName: typeof modelData === "string" ? modelData : String((modelData && (modelData.name || modelData.id)) || "")
                        readonly property bool selected: {
                          if (typeof modelData === "object" && modelData && modelData.active) return true
                          return deviceName !== "" && deviceName === root.activeAudioDevice
                        }
                        text: (selected ? "● " : "") + (deviceName.slice(0, 34) || "Device")
                        foreground: selected ? Color.accent : root.foreground
                        horizontalPadding: Style.space(12)
                        verticalPadding: Style.spacing.controlPaddingY
                        onClicked: {
                          if (root.mediaService) root.mediaService.setAudioDevice(deviceName)
                          root.armHoldOpen(1500)
                        }
                      }
                    }
                  }
                }

                // NEARBY / POPULAR RADIO
                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.extrasTab === "nearby"

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "Stations near you (approx) or popular picks from Radio Garden."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)
                    Button {
                      text: root.mediaService && root.mediaService.nearbyBusy ? "Loading…" : "Near me"
                      foreground: Color.accent
                      horizontalPadding: Style.space(14)
                      verticalPadding: Style.spacing.controlPaddingY
                      enabled: !(root.mediaService && root.mediaService.nearbyBusy)
                      onClicked: {
                        if (root.mediaService) root.mediaService.loadNearbyStations()
                        root.armHoldOpen(3000)
                      }
                    }
                    Button {
                      text: "Popular"
                      foreground: root.foreground
                      horizontalPadding: Style.space(14)
                      verticalPadding: Style.spacing.controlPaddingY
                      enabled: !(root.mediaService && root.mediaService.nearbyBusy)
                      onClicked: {
                        if (root.mediaService) root.mediaService.loadPopularStations()
                        root.armHoldOpen(3000)
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: !(root.mediaService && root.mediaService.nearbyBusy)
                      && !(root.mediaService && root.mediaService.nearbyStations && root.mediaService.nearbyStations.length)
                    textFormat: Text.PlainText
                    text: "Tap Near me or Popular to load stations."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Repeater {
                    model: root.mediaService ? (root.mediaService.nearbyStations || []) : []
                    delegate: Item {
                      required property var modelData
                      width: parent ? parent.width : 0
                      height: Style.space(30)
                      Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: {
                          var t = String((modelData && modelData.title) || "Station")
                          var f = String((modelData && modelData.frequency) || "")
                          return f ? (t + " · " + f) : t
                        }
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.mediaService && modelData)
                            root.mediaService.playSearchResult(modelData)
                          root.armHoldOpen(2000)
                        }
                      }
                    }
                  }
                }

                // LYRICS
                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.extrasTab === "lyrics" && root.usingCliamp

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      text: root.lyricsBusy ? "Fetching lyrics…" : "Lyrics"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      width: parent.width - refreshLyricsBtn.width - Style.space(8)
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Button {
                      id: refreshLyricsBtn
                      text: "Refresh"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        if (root.mediaService) root.mediaService.fetchLyrics()
                        root.armHoldOpen(2000)
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.lyricsBusy ? "Loading…" : (root.lyricsText || "No lyrics for this track")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    maximumLineCount: 18
                    elide: Text.ElideRight
                    lineHeight: 1.25
                  }
                }

                // SHARE
                Column {
                  width: parent.width
                  spacing: Style.space(10)
                  visible: root.extrasTab === "share"

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "Export the current station or track as a shareable link / file."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.title || "No media"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                      text: "Copy link"
                      foreground: Color.accent
                      horizontalPadding: Style.space(16)
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        if (root.mediaService) root.mediaService.shareCurrentLink()
                        root.armHoldOpen(2500)
                      }
                    }

                    Button {
                      text: "Export library"
                      foreground: root.foreground
                      horizontalPadding: Style.space(14)
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        if (root.mediaService) root.mediaService.shareLibraryBundle()
                        root.armHoldOpen(2500)
                      }
                    }

                    Button {
                      text: "Copy path"
                      foreground: root.foreground
                      horizontalPadding: Style.space(14)
                      verticalPadding: Style.spacing.controlPaddingY
                      enabled: !!(root.mediaService && root.mediaService.mediaPath)
                      opacity: enabled ? 1.0 : 0.35
                      onClicked: {
                        if (root.mediaService)
                          root.mediaService.copyPath(root.mediaService.mediaPath)
                        root.armHoldOpen(1500)
                      }
                    }
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)
                    visible: root.mediaIsStream
                    Button {
                      text: "Record 1m"
                      foreground: root.foreground
                      horizontalPadding: Style.space(12)
                      verticalPadding: Style.spacing.controlPaddingY
                      enabled: root.canDownload && !root.downloadBusy
                      opacity: enabled ? 1.0 : 0.35
                      onClicked: {
                        if (root.mediaService) root.mediaService.recordCurrent(1)
                        root.armHoldOpen(4000)
                      }
                    }
                    Button {
                      text: "Record 3m"
                      foreground: root.foreground
                      horizontalPadding: Style.space(12)
                      verticalPadding: Style.spacing.controlPaddingY
                      enabled: root.canDownload && !root.downloadBusy
                      opacity: enabled ? 1.0 : 0.35
                      onClicked: {
                        if (root.mediaService) root.mediaService.recordCurrent(3)
                        root.armHoldOpen(4000)
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: root.shareMessage !== ""
                    textFormat: Text.PlainText
                    text: root.shareMessage.indexOf("/") >= 0
                      ? ("Saved · " + root.shareMessage)
                      : root.shareMessage
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideMiddle
                  }
                }
              }

            }
          }

          // Source expand — stays in-drawer, directly under Now Playing / transport
          Column {
            id: hubDetail
            width: parent.width
            spacing: Style.space(10)
            visible: root.hubOpen

            PanelSectionHeader {
              text: root.activeHub ? root.activeHub.label.toUpperCase() : "SOURCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              visible: !!(root.activeHub && root.activeHub.blurb)
              textFormat: Text.PlainText
              text: root.activeHub ? (root.activeHub.blurb || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            // App-sync only (mpv) — Spotify/Radio Garden use the search field below
            BorderSurface {
              width: parent.width
              visible: !root.isLibraryHub && !root.searchAvailable && !!(root.activeHub && root.activeHub.appSync)
              height: launchInner.implicitHeight + Style.space(20)
              radius: Style.spacing.labelGap
              color: Util.alpha(root.foreground, 0.04)
              borderSpec: Border.none()

              Column {
                id: launchInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(14)
                spacing: Style.space(10)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: {
                    if (!root.activeHub) return ""
                    if (root.activeHub.playing)
                      return "Playing in the app — transport above controls it."
                    if (root.activeHub.online)
                      return "Synced with the app — use transport above."
                    return "App is offline. Open it to sync Now Playing."
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Button {
                  visible: !!(root.activeHub && root.activeHub.openLabel && !root.activeHub.online)
                  text: root.activeHub ? (root.activeHub.openLabel || "Open") : "Open"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: if (root.mediaService) root.mediaService.openHubExternal()
                }

                Button {
                  visible: !!(root.activeHub && root.activeHub.openLabel && root.activeHub.online)
                  text: "Focus app"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: if (root.mediaService) root.mediaService.openHubExternal()
                }
              }
            }

            // Offline hint for Spotify play (search still works in-drawer)
            Text {
              width: parent.width
              visible: !!(root.activeHub && root.activeHub.id === "spotify" && !root.activeHub.online && root.showSearchPane)
              textFormat: Text.PlainText
              text: "Search works without the app (cliamp Spotify when configured, else Deezer→ISRC). Results play in Spotify when it is open."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            // Search | Favourites | Downloads tabs (per-source). Global hubs skip this.
            Row {
              width: parent.width
              spacing: Style.space(8)
              visible: root.searchAvailable && !root.isLibraryHub && !root.isDownloadsHub

              BorderSurface {
                height: Style.space(28)
                width: searchTabLabel.implicitWidth + Style.space(20)
                radius: Style.space(8)
                color: root.hubPane === "search" ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                borderSpec: Border.none()
                Text {
                  id: searchTabLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "Search"
                  color: root.hubPane === "search" ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.hubPane === "search"
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.hubPane = "search"
                    root.clearHitContext()
                    root.armHoldOpen(1200)
                  }
                }
              }

              BorderSurface {
                height: Style.space(28)
                width: favTabLabel.implicitWidth + Style.space(20)
                radius: Style.space(8)
                color: root.hubPane === "favourites" ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                borderSpec: Border.none()
                Text {
                  id: favTabLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: {
                    var n = 0
                    if (root.mediaService)
                      n = root.mediaService.listFavorites(root.activeHubId || "", "").length
                    return n > 0 ? ("Favourites · " + n) : "Favourites"
                  }
                  color: root.hubPane === "favourites" ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.hubPane === "favourites"
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.hubPane = "favourites"
                    root.blurSearch()
                    root.clearHitContext()
                    root.armHoldOpen(1200)
                  }
                }
              }

              BorderSurface {
                height: Style.space(28)
                width: dlTabLabel.implicitWidth + Style.space(20)
                radius: Style.space(8)
                color: root.hubPane === "downloads" ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                borderSpec: Border.none()
                Text {
                  id: dlTabLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.downloadCount > 0 ? ("Downloads · " + root.downloadCount) : "Downloads"
                  color: root.hubPane === "downloads" ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.hubPane === "downloads"
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.hubPane = "downloads"
                    root.blurSearch()
                    root.clearHitContext()
                    if (root.mediaService) root.mediaService.loadDownloads()
                    root.armHoldOpen(1200)
                  }
                }
              }
            }

            // Library pane — global Favourites hub or per-source Favourites tab
            Column {
              id: libraryBlock
              width: parent.width
              spacing: Style.space(8)
              visible: root.showLibraryPane

              Row {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  text: "Shuffle"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  enabled: root.libraryItems && root.libraryItems.length > 0
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: root.shuffleLibrary()
                }

                Button {
                  text: root.verifyBusy ? "Checking…" : "Check links"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  enabled: !root.verifyBusy && root.favouriteCount > 0
                  opacity: enabled ? 1.0 : 0.4
                  visible: root.isLibraryHub
                  onClicked: if (root.mediaService) root.mediaService.verifyFavorites()
                }

                Button {
                  text: "Export"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  visible: root.isLibraryHub
                  onClicked: if (root.mediaService) root.mediaService.exportLibrary()
                }

                Button {
                  text: "Import"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  visible: root.isLibraryHub
                  onClicked: if (root.mediaService) root.mediaService.importLibrary()
                }
              }

              // Source filter chips (global hub only)
              Flow {
                width: parent.width
                spacing: Style.space(6)
                visible: root.isLibraryHub

                BorderSurface {
                  height: Style.space(26)
                  width: allProvLabel.implicitWidth + Style.space(16)
                  radius: Style.space(8)
                  color: root.libraryFilterProvider === "" ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                  borderSpec: Border.none()
                  Text {
                    id: allProvLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "All"
                    color: root.libraryFilterProvider === "" ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.mediaService) root.mediaService.setLibraryFilterProvider("")
                  }
                }

                Repeater {
                  model: root.libraryProviderChips
                  BorderSurface {
                    id: provChip
                    required property var modelData
                    readonly property string pid: String(modelData || "")
                    height: Style.space(26)
                    width: provChipLabel.implicitWidth + Style.space(16)
                    radius: Style.space(8)
                    color: root.libraryFilterProvider === provChip.pid ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                    borderSpec: Border.none()
                    Text {
                      id: provChipLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: root.providerLabel(provChip.pid)
                      color: root.libraryFilterProvider === provChip.pid ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.mediaService) root.mediaService.setLibraryFilterProvider(provChip.pid)
                    }
                  }
                }
              }

              // Folder chips
              Flow {
                width: parent.width
                spacing: Style.space(6)

                BorderSurface {
                  height: Style.space(26)
                  width: allFolderLabel.implicitWidth + Style.space(16)
                  radius: Style.space(8)
                  color: root.libraryFilterFolder === "" ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                  borderSpec: Border.none()
                  Text {
                    id: allFolderLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "All tags"
                    color: root.libraryFilterFolder === "" ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.mediaService) root.mediaService.setLibraryFilterFolder("")
                  }
                }

                Repeater {
                  model: root.favouriteFolders
                  BorderSurface {
                    id: folderChip
                    required property var modelData
                    readonly property var folder: modelData
                    height: Style.space(26)
                    width: folderChipLabel.implicitWidth + Style.space(16)
                    radius: Style.space(8)
                    color: root.libraryFilterFolder === (folderChip.folder ? folderChip.folder.id : "")
                      ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                    borderSpec: Border.none()
                    Text {
                      id: folderChipLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: folderChip.folder ? (folderChip.folder.label || "") : ""
                      color: root.libraryFilterFolder === (folderChip.folder ? folderChip.folder.id : "")
                        ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      onClicked: function(mouse) {
                        if (!root.mediaService || !folderChip.folder) return
                        if (mouse.button === Qt.RightButton) {
                          root.mediaService.deleteFolder(folderChip.folder.id)
                          return
                        }
                        root.mediaService.setLibraryFilterFolder(folderChip.folder.id)
                      }
                    }
                  }
                }

                Repeater {
                  model: MediaModel.smartFolderDefs()
                  BorderSurface {
                    id: smartChip
                    required property var modelData
                    readonly property var folder: modelData
                    height: Style.space(26)
                    width: smartChipLabel.implicitWidth + Style.space(16)
                    radius: Style.space(8)
                    color: root.libraryFilterFolder === (smartChip.folder ? smartChip.folder.id : "")
                      ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                    borderSpec: Border.none()
                    Text {
                      id: smartChipLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: smartChip.folder
                        ? ((smartChip.folder.icon || "") + " " + (smartChip.folder.label || ""))
                        : ""
                      color: root.libraryFilterFolder === (smartChip.folder ? smartChip.folder.id : "")
                        ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.mediaService && smartChip.folder)
                          root.mediaService.setLibraryFilterFolder(smartChip.folder.id)
                      }
                    }
                  }
                }

                BorderSurface {
                  height: Style.space(26)
                  width: addFolderLabel.implicitWidth + Style.space(16)
                  radius: Style.space(8)
                  color: Util.alpha(root.foreground, 0.06)
                  borderSpec: Border.none()
                  Text {
                    id: addFolderLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "+ Tag"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.folderDraft = " "
                      root.armHoldOpen(2500)
                      Qt.callLater(function() {
                        if (folderField) folderField.forceActiveFocus()
                      })
                    }
                  }
                }
              }

              TextField {
                id: folderField
                width: parent.width
                visible: root.folderDraft !== ""
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                placeholderText: "New tag name…"
                text: root.folderDraft === " " ? "" : root.folderDraft
                onTextChanged: root.folderDraft = text.length ? text : " "
                onAccepted: {
                  if (!root.mediaService) return
                  if (root.mediaService.createFolder(text))
                    root.folderDraft = ""
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.folderDraft = ""
                    event.accepted = true
                  }
                }
              }

              // Recents (global Favourites hub)
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: root.isLibraryHub && root.recentItems && root.recentItems.length > 0

                Text {
                  textFormat: Text.PlainText
                  text: "RECENTS"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Repeater {
                  model: root.recentItems

                  BorderSurface {
                    id: recentRow
                    required property var modelData
                    readonly property var item: modelData
                    readonly property var hit: item && item.hit ? item.hit : null

                    width: libraryBlock.width
                    height: recentInner.implicitHeight + Style.space(12)
                    radius: Style.spacing.labelGap
                    color: Util.alpha(root.foreground, 0.03)
                    borderSpec: Border.none()

                    Row {
                      id: recentInner
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(10)

                      Column {
                        width: parent.width - Style.space(36)
                        spacing: Style.space(2)
                        Text {
                          width: parent.width
                          textFormat: Text.PlainText
                          text: recentRow.hit ? (recentRow.hit.title || "Untitled") : "Untitled"
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          elide: Text.ElideRight
                        }
                        Text {
                          width: parent.width
                          textFormat: Text.PlainText
                          text: {
                            if (!recentRow.hit) return ""
                            var parts = []
                            if (recentRow.hit.providerLabel) parts.push(recentRow.hit.providerLabel)
                            else if (recentRow.hit.provider) parts.push(root.providerLabel(recentRow.hit.provider))
                            if (recentRow.hit.artist) parts.push(recentRow.hit.artist)
                            return parts.join(" · ")
                          }
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          visible: text !== ""
                        }
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: root.hitIsFavorite(recentRow.hit) ? "󰋑" : "󰋕"
                        color: root.hitIsFavorite(recentRow.hit) ? Color.accent : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -Style.space(6)
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleHitFavorite(recentRow.hit)
                        }
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      anchors.rightMargin: Style.space(36)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      onPressed: function(mouse) {
                        if (mouse.button !== Qt.LeftButton) return
                        mouse.accepted = true
                        root.playLibraryHit(recentRow.hit)
                      }
                      onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                          root.showHitContext(recentRow.hit)
                      }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                visible: !(root.libraryItems && root.libraryItems.length)
                textFormat: Text.PlainText
                text: root.isLibraryHub
                  ? "No favourites yet — heart a search result or Now Playing."
                  : ("No favourites for " + (root.activeHub ? root.activeHub.label : "this source") + " yet.")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                visible: root.libraryItems && root.libraryItems.length > 0
                textFormat: Text.PlainText
                text: "FAVOURITES"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Repeater {
                model: root.libraryItems

                BorderSurface {
                  id: favRow
                  required property var modelData
                  readonly property var item: modelData
                  readonly property var hit: item && item.hit ? item.hit : null
                  readonly property bool broken: !!(item && item.broken)

                  width: libraryBlock.width
                  height: favInner.implicitHeight + Style.space(12)
                  radius: Style.spacing.labelGap
                  color: Util.alpha(root.foreground, 0.03)
                  borderSpec: Border.none()
                  opacity: favRow.broken ? 0.5 : 1.0

                  Row {
                    id: favInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(10)

                    Column {
                      width: parent.width - Style.space(36)
                      spacing: Style.space(2)
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: favRow.hit ? (favRow.hit.title || "Untitled") : "Untitled"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: {
                          if (!favRow.hit) return favRow.broken ? "Broken link" : ""
                          var parts = []
                          if (favRow.broken) parts.push("Broken")
                          if (favRow.hit.providerLabel) parts.push(favRow.hit.providerLabel)
                          else if (favRow.hit.provider) parts.push(root.providerLabel(favRow.hit.provider))
                          if (favRow.hit.artist) parts.push(favRow.hit.artist)
                          if (favRow.hit.detail) parts.push(favRow.hit.detail)
                          return parts.join(" · ")
                        }
                        color: favRow.broken ? Color.accent : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        visible: text !== ""
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "󰋑"
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleHitFavorite(favRow.hit)
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: Style.space(36)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: function(mouse) {
                      if (mouse.button !== Qt.LeftButton) return
                      mouse.accepted = true
                      root.playLibraryHit(favRow.hit)
                    }
                    onClicked: function(mouse) {
                      if (mouse.button === Qt.RightButton)
                        root.showHitContext(favRow.hit)
                    }
                  }
                }
              }
            }


            // Recents hub pane
            Column {
              id: recentsBlock
              width: parent.width
              spacing: Style.space(8)
              visible: root.showRecentsPane

              Text {
                width: parent.width
                visible: !(root.recentItems && root.recentItems.length)
                textFormat: Text.PlainText
                text: "Nothing played yet — search and play a track to build recents."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                visible: root.recentItems && root.recentItems.length > 0
                textFormat: Text.PlainText
                text: "RECENTS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Repeater {
                model: root.recentItems

                BorderSurface {
                  id: hubRecentRow
                  required property var modelData
                  readonly property var item: modelData
                  readonly property var hit: item && item.hit ? item.hit : null

                  width: recentsBlock.width
                  height: hubRecentInner.implicitHeight + Style.space(12)
                  radius: Style.spacing.labelGap
                  color: Util.alpha(root.foreground, 0.03)
                  borderSpec: Border.none()

                  Row {
                    id: hubRecentInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(10)

                    Column {
                      width: parent.width - Style.space(36)
                      spacing: Style.space(2)
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: hubRecentRow.hit ? (hubRecentRow.hit.title || "Untitled") : "Untitled"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: {
                          if (!hubRecentRow.hit) return ""
                          var parts = []
                          if (hubRecentRow.hit.providerLabel) parts.push(hubRecentRow.hit.providerLabel)
                          else if (hubRecentRow.hit.provider) parts.push(root.providerLabel(hubRecentRow.hit.provider))
                          if (hubRecentRow.hit.artist) parts.push(hubRecentRow.hit.artist)
                          return parts.join(" · ")
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        visible: text !== ""
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: root.hitIsFavorite(hubRecentRow.hit) ? "󰋑" : "󰋕"
                      color: root.hitIsFavorite(hubRecentRow.hit) ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleHitFavorite(hubRecentRow.hit)
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: Style.space(36)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: function(mouse) {
                      if (mouse.button !== Qt.LeftButton) return
                      mouse.accepted = true
                      root.playLibraryHit(hubRecentRow.hit)
                    }
                    onClicked: function(mouse) {
                      if (mouse.button === Qt.RightButton)
                        root.showHitContext(hubRecentRow.hit)
                    }
                  }
                }
              }
            }

            // Downloads pane — global Downloads hub or per-source Downloads tab
            Column {
              id: downloadsBlock
              width: parent.width
              spacing: Style.space(8)
              visible: root.showDownloadsPane

              Row {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  text: "Refresh"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: {
                    if (root.mediaService) root.mediaService.loadDownloads()
                    root.armHoldOpen(1200)
                  }
                }

                Button {
                  text: "Open folder"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: {
                    if (root.mediaService) root.mediaService.openDownloadsFolder()
                    root.armHoldOpen(1200)
                  }
                }

                Button {
                  text: "Cancel"
                  foreground: Color.accent
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  visible: root.downloadBusy
                  onClicked: {
                    if (root.mediaService) root.mediaService.cancelDownload()
                    root.armHoldOpen(1200)
                  }
                }
              }

              // In-progress download callout
              BorderSurface {
                width: parent.width
                visible: root.downloadBusy
                height: dlBusyInner.implicitHeight + Style.space(16)
                radius: Style.spacing.labelGap
                color: Util.alpha(Color.accent, 0.10)
                borderSpec: Border.none()

                Column {
                  id: dlBusyInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(12)
                  spacing: Style.space(6)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: (root.downloadTitle || "Downloading") + " · " + Math.round(root.downloadProgress) + "%"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(4)
                    radius: Style.space(2)
                    color: Util.alpha(root.foreground, 0.10)
                    Rectangle {
                      width: Math.max(Style.space(4), parent.width * Math.max(0, Math.min(1, root.downloadProgress / 100)))
                      height: parent.height
                      radius: parent.radius
                      color: Color.accent
                    }
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.downloadStatus || "Working…"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              Text {
                width: parent.width
                visible: !(root.downloadItems && root.downloadItems.length) && !root.downloadBusy
                textFormat: Text.PlainText
                text: "No downloads yet — tap 󰇚 on Now Playing to save a track to ~/Downloads/Media."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                visible: root.downloadItems && root.downloadItems.length > 0
                textFormat: Text.PlainText
                text: "DOWNLOADS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Repeater {
                model: root.downloadItems

                BorderSurface {
                  id: dlRow
                  required property var modelData
                  readonly property var item: modelData
                  readonly property bool isFailed: !!(item && item.status === "failed")
                  readonly property bool isBusy: !!(item && item.status === "downloading")
                  readonly property bool isRetryable: !!(isFailed && item && (item.sourcePath || item.searchHint))

                  width: downloadsBlock.width
                  height: dlInner.implicitHeight + Style.space(12)
                  radius: Style.spacing.labelGap
                  color: Util.alpha(root.foreground, 0.03)
                  borderSpec: Border.none()
                  opacity: dlRow.isFailed ? 0.55 : 1.0

                  Row {
                    id: dlInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(10)

                    Column {
                      width: parent.width - Style.space(100)
                      spacing: Style.space(2)
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: dlRow.item ? (dlRow.item.title || "Untitled") : "Untitled"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: {
                          if (!dlRow.item) return ""
                          var bits = []
                          if (dlRow.item.artist) bits.push(dlRow.item.artist)
                          if (dlRow.item.sizeLabel) bits.push(dlRow.item.sizeLabel)
                          if (dlRow.isBusy) bits.push(Math.round(Number(dlRow.item.pct) || 0) + "%")
                          if (dlRow.isFailed) bits.push(root.mediaService
                            ? root.mediaService.friendlyDownloadError(dlRow.item.error || "failed")
                            : (dlRow.item.error || "failed"))
                          if (dlRow.item.provider) bits.push(root.providerLabel(dlRow.item.provider))
                          return bits.join(" · ")
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        visible: text !== ""
                      }
                      Rectangle {
                        width: parent.width
                        height: Style.space(3)
                        radius: Style.space(2)
                        visible: dlRow.isBusy
                        color: Util.alpha(root.foreground, 0.08)
                        Rectangle {
                          width: Math.max(Style.space(3), parent.width * Math.max(0, Math.min(1, Number(dlRow.item.pct || 0) / 100)))
                          height: parent.height
                          radius: parent.radius
                          color: Color.accent
                        }
                      }
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "󰑓"
                      width: dlRow.isRetryable ? Style.space(18) : 0
                      horizontalAlignment: Text.AlignHCenter
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      visible: dlRow.isRetryable
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.mediaService && dlRow.item)
                            root.mediaService.retryDownload(dlRow.item)
                          root.armHoldOpen(1200)
                        }
                      }
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "󰉋"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      visible: !!(dlRow.item && dlRow.item.path)
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.mediaService && dlRow.item)
                            root.mediaService.revealPath(dlRow.item.path)
                          root.armHoldOpen(1200)
                        }
                      }
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "󰆴"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.mediaService) root.mediaService.removeDownload(dlRow.item)
                          root.armHoldOpen(1200)
                        }
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: Style.space(56)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !dlRow.isBusy && !dlRow.isFailed && !!(dlRow.item && dlRow.item.path)
                    onClicked: {
                      if (root.mediaService) root.mediaService.playDownload(dlRow.item)
                      root.armHoldOpen(2000)
                    }
                  }
                }
              }
            }

            // Scoped search
            Column {
              id: searchBlock
              width: parent.width
              spacing: Style.space(6)
              visible: root.showSearchPane

              TextField {
                id: searchField
                width: parent.width
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                placeholderText: root.searchPlaceholder
                onActiveFocusChanged: {
                  root.searchFocused = activeFocus
                  if (activeFocus) root.armHoldOpen(2500)
                }
                onTextChanged: {
                  if (!root.mediaService) return
                  // Renew hold on every keystroke so results layout growth
                  // can't click-through-dismiss the drawer.
                  root.searchFocused = true
                  root.armHoldOpen(2500)
                  if (text === root.searchQuery) return
                  root.mediaService.setSearchQuery(text)
                }
                onAccepted: {
                  if (!root.mediaService) return
                  // Catalog search (Spotify / Radio Garden) submits on Enter.
                  if (root.activeHub && root.activeHub.appSearch) {
                    root.mediaService.runSearch()
                    return
                  }
                  if (root.searchResults && root.searchResults.length > 0)
                    root.mediaService.playSearchResult(root.searchResults[0])
                  else
                    root.mediaService.runSearch()
                }
                  Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (text !== "") {
                      text = ""
                      if (root.mediaService) root.mediaService.clearSearch()
                    } else {
                      // Drop search focus and collapse hub — keep drawer open.
                      root.blurSearch()
                      if (root.mediaService) root.mediaService.closeHub()
                      root.armHoldOpen(900)
                      Qt.callLater(function() {
                        if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
                      })
                    }
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down
                      && root.searchSuggestions && root.searchSuggestions.length > 0) {
                    // Apply first prediction
                    if (root.mediaService)
                      root.mediaService.applySuggestion(root.searchSuggestions[0])
                    event.accepted = true
                  } else if (event.key === Qt.Key_Tab
                      && root.searchSuggestions && root.searchSuggestions.length > 0) {
                    if (root.mediaService)
                      root.mediaService.applySuggestion(root.searchSuggestions[0])
                    event.accepted = true
                  }
                }
              }


              // Add custom local library root
              Row {
                width: parent.width
                spacing: Style.space(6)
                visible: root.activeHubId === "local"

                TextField {
                  id: localRootField
                  width: parent.width - addRootBtn.width - Style.space(6)
                  foreground: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  placeholderText: "Add folder path… e.g. ~/Audio"
                }

                Button {
                  id: addRootBtn
                  text: "Add"
                  foreground: root.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: {
                    if (!root.mediaService || !localRootField.text) return
                    root.mediaService.addLocalRoot(localRootField.text)
                    localRootField.text = ""
                    root.armHoldOpen(1500)
                  }
                }
              }

              // Local folder chips
              Flow {
                width: parent.width
                spacing: Style.space(6)
                visible: root.activeHubId === "local"

                BorderSurface {
                  id: localAllFolderChip
                  height: Style.space(28)
                  width: localAllFolderChipLabel.implicitWidth + Style.space(20)
                  radius: Style.space(8)
                  color: root.localFolderFilter === "" ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                  borderSpec: Border.none()
                  Text {
                    id: localAllFolderChipLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "All folders"
                    color: root.localFolderFilter === "" ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.mediaService) root.mediaService.setLocalFolderFilter("")
                      root.armHoldOpen(1500)
                    }
                  }
                }

                Repeater {
                  model: root.localFolders
                  BorderSurface {
                    id: locFolder
                    required property var modelData
                    readonly property string folderName: String(modelData || "")
                    readonly property bool active: root.localFolderFilter === locFolder.folderName
                    height: Style.space(28)
                    width: locFolderLabel.implicitWidth + Style.space(20)
                    radius: Style.space(8)
                    color: locFolder.active ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                    borderSpec: Border.none()
                    Text {
                      id: locFolderLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: locFolder.folderName
                      color: locFolder.active ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.mediaService) root.mediaService.setLocalFolderFilter(locFolder.folderName)
                        root.armHoldOpen(1500)
                      }
                    }
                  }
                }
              }

              // Past searches / autocomplete predictions for this source
              Flow {
                id: suggestFlow
                width: parent.width
                spacing: Style.space(6)
                visible: root.searchSuggestions && root.searchSuggestions.length > 0

                Repeater {
                  model: root.searchSuggestions

                  BorderSurface {
                    id: sugChip
                    required property var modelData
                    readonly property string suggestion: String(modelData || "")

                    height: Style.space(28)
                    width: sugLabel.implicitWidth + Style.space(20)
                    radius: Style.space(8)
                    color: Util.alpha(root.foreground, 0.06)
                    borderSpec: Border.none()

                    Text {
                      id: sugLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: sugChip.suggestion
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (!root.mediaService || !sugChip.suggestion) return
                        root.armHoldOpen(1500); root.mediaService.applySuggestion(sugChip.suggestion)
                      }
                    }
                  }
                }

                BorderSurface {
                  visible: !!(root.searchSuggestions && root.searchSuggestions.length > 0)
                  height: Style.space(28)
                  width: clearHistLabel.implicitWidth + Style.space(20)
                  radius: Style.space(8)
                  color: Util.alpha(root.foreground, 0.04)
                  borderSpec: Border.none()
                  Text {
                    id: clearHistLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "Clear history"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.mediaService)
                        root.mediaService.clearSearchHistory(root.activeHubId)
                      root.armHoldOpen(1000)
                    }
                  }
                }
              }

              Text {
                visible: root.searchBusy || root.searchError !== "" || ((root.searchQuery !== "" || root.activeHubId === "local") && root.searchResults.length === 0 && !root.searchBusy)
                width: parent.width
                textFormat: Text.PlainText
                text: root.searchBusy
                  ? (root.activeHubId === "local"
                      ? "Loading local files…"
                      : ("Searching " + (root.searchProviderLabel || "…") + "…"))
                  : (root.searchError || "No results")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.searchResults

                BorderSurface {
                  id: hitRow
                  required property var modelData
                  readonly property var hit: modelData
                  readonly property bool loved: root.hitIsFavorite(hit)

                  width: searchBlock.width
                  height: hitInner.implicitHeight + Style.space(12)
                  radius: Style.spacing.labelGap
                  color: Util.alpha(root.foreground, 0.03)
                  borderSpec: Border.none()

                  Row {
                    id: hitInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: hitRow.borderLeft + Style.space(10)
                    anchors.rightMargin: hitRow.borderRight + Style.space(10)
                    spacing: Style.space(10)

                    Text {
                      textFormat: Text.PlainText
                      text: {
                        var p = hitRow.hit ? String(hitRow.hit.provider || "") : ""
                        if (root.activeHubId === "radio-garden" || p === "radio") return "󰐹"
                        if (p === "podcast") return "󰦔"
                        if (p === "youtube") return "󰗃"
                        if (p === "local") return "󰉋"
                        if (hitRow.hit && hitRow.hit.feed) return "󰎐"
                        return "󰎇"
                      }
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      width: Style.space(20)
                      horizontalAlignment: Text.AlignHCenter
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      width: parent.width - Style.space(72)
                      spacing: Style.space(2)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        textFormat: Text.PlainText
                        text: hitRow.hit ? (hitRow.hit.title || "Untitled") : "Untitled"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        textFormat: Text.PlainText
                        text: {
                          if (!hitRow.hit) return ""
                          if (hitRow.hit.detail) return hitRow.hit.detail
                          var parts = []
                          if (hitRow.hit.providerLabel) parts.push(hitRow.hit.providerLabel)
                          if (hitRow.hit.artist) parts.push(hitRow.hit.artist)
                          if (hitRow.hit.album) parts.push(hitRow.hit.album)
                          return parts.join(" · ")
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                        visible: text !== ""
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "󰐑"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.mediaService && hitRow.hit)
                            root.mediaService.queueSearchResult(hitRow.hit)
                          root.armHoldOpen(1500)
                        }
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: hitRow.loved ? "󰋑" : "󰋕"
                      color: hitRow.loved ? Color.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleHitFavorite(hitRow.hit)
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: Style.space(56)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // Start on press so playback begins before mouse-up latency.
                    onPressed: function(mouse) {
                      if (mouse.button !== Qt.LeftButton) return
                      if (!root.mediaService || !hitRow.hit) return
                      mouse.accepted = true
                      root.armHoldOpen(2000)
                      root.mediaService.playSearchResult(hitRow.hit)
                    }
                    onClicked: function(mouse) {
                      if (mouse.button === Qt.RightButton && hitRow.hit)
                        root.showHitContext(hitRow.hit)
                    }
                  }
                }
              }
            }


              // Right-click actions strip (search + library)
              BorderSurface {
                width: parent.width
                visible: !!root.contextHit
                height: contextInner.implicitHeight + Style.space(16)
                radius: Style.spacing.labelGap
                color: Util.alpha(Color.accent, 0.08)
                borderSpec: Border.none()

                Column {
                  id: contextInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(12)
                  spacing: Style.space(8)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.contextHit ? ("Actions · " + (root.contextHit.title || "Item")) : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                      text: "Play"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        root.playLibraryHit(root.contextHit)
                        root.clearHitContext()
                      }
                    }

                    Button {
                      text: "Open muted PiP"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      visible: !!(root.contextHit && root.mediaService
                        && MediaModel.hitIsVideo(root.contextHit))
                      onClicked: {
                        if (root.mediaService) root.mediaService.openExtraPiP(root.contextHit)
                        root.clearHitContext()
                      }
                    }

                    Button {
                      text: "Queue"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        if (root.mediaService && root.contextHit)
                          root.mediaService.queueSearchResult(root.contextHit)
                        root.clearHitContext()
                        root.armHoldOpen(1500)
                      }
                    }

                    Button {
                      text: "Download"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: {
                        if (root.mediaService && root.contextHit)
                          root.mediaService.downloadCurrent({ hit: root.contextHit })
                        root.clearHitContext()
                      }
                    }

                    Button {
                      text: "Reveal"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      visible: !!(root.contextHit && root.contextHit.path && String(root.contextHit.path).indexOf("/") === 0)
                      onClicked: {
                        if (root.mediaService && root.contextHit)
                          root.mediaService.revealPath(root.contextHit.path)
                        root.clearHitContext()
                      }
                    }

                    Button {
                      text: "Copy path"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      visible: !!(root.contextHit && root.contextHit.path)
                      onClicked: {
                        if (root.mediaService && root.contextHit)
                          root.mediaService.copyPath(root.contextHit.path)
                        root.clearHitContext()
                      }
                    }

                    Button {
                      text: root.hitIsFavorite(root.contextHit) ? "Unfavourite" : "Favourite"
                      foreground: root.foreground
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: root.toggleHitFavorite(root.contextHit)
                    }

                    Button {
                      text: "Dismiss"
                      foreground: root.dim
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      onClicked: root.clearHitContext()
                    }
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: root.favouriteFolders && root.favouriteFolders.length > 0 && root.hitIsFavorite(root.contextHit)

                    Repeater {
                      model: root.favouriteFolders
                      BorderSurface {
                        id: ctxFolder
                        required property var modelData
                        readonly property var folder: modelData
                        readonly property bool inFolder: {
                          var _t = root.mediaService ? root.mediaService.libraryTick : 0
                          if (!root.mediaService || !root.contextHit || !ctxFolder.folder) return false
                          var id = MediaModel.favoriteIdFromHit(root.contextHit)
                          var row = root.mediaService.findFavourite(id)
                          if (!row || !row.folderIds) return false
                          for (var i = 0; i < row.folderIds.length; i++) {
                            if (String(row.folderIds[i]) === ctxFolder.folder.id) return true
                          }
                          return false
                        }
                        height: Style.space(26)
                        width: ctxFolderLabel.implicitWidth + Style.space(16)
                        radius: Style.space(8)
                        color: ctxFolder.inFolder ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.foreground, 0.06)
                        borderSpec: Border.none()
                        Text {
                          id: ctxFolderLabel
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: ctxFolder.folder ? ("Tag · " + (ctxFolder.folder.label || "")) : ""
                          color: ctxFolder.inFolder ? Color.accent : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (!root.mediaService || !root.contextHit || !ctxFolder.folder) return
                            var id = MediaModel.favoriteIdFromHit(root.contextHit)
                            root.mediaService.toggleItemFolder(id, ctxFolder.folder.id)
                            root.armHoldOpen(1200)
                          }
                        }
                      }
                    }
                  }
                }
              }

          }

        }
      }
    }
  }

}
