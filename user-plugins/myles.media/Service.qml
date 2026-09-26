import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  property string preferredPlayerKey: ""
  property bool followMode: true
  property var playerStartedAt: ({})
  property string activeWindowAppId: ""
  property string activeWindowTitle: ""
  property string lastFocusPlayerKey: ""
  property var pendingTrackOsd: null
  property int playSerial: 0
  property int positionTick: 0
  property var cliamp: MediaModel.emptyCliampSnapshot()
  property var mpv: MediaModel.emptyMpvSnapshot()
  property var extraPipIds: []
  property bool dualAudioEnabled: false
  property bool dualAudioActive: false
  property var castTargets: []
  property bool castBusy: false
  property string castStatus: ""
  property bool videoBackendActive: false
  property bool videoPipDismissed: false
  property bool videoFullscreen: false
  property bool videoClickThrough: false
  property real videoOpacity: 1.0
  property string videoPreset: "S"
  property bool videoSubs: false
  property bool videoAspectLock: true
  property string mpvLoopMode: "no"  // "no" | "inf"
  property var ffprobeCache: ({})
  property var sourceEntries: []
  property int sourceEntriesTick: 0
  property var cliampConfiguredProviders: []
  property string cliampActiveProvider: ""
  property var providerEntries: []
  property string pendingProviderSwitch: ""
  property string activeHubId: ""
  // User choice outlives the drawer's temporary activeHubId.
  property string selectedSourceId: ""
  property var hubEntries: []
  property string searchQuery: ""
  property string searchProvider: ""
  property var searchResults: []
  property bool searchBusy: false
  property string searchError: ""
  property int searchSerial: 0
  property int searchSlot: 0
  // Per-hub search history (persisted) + live autocomplete suggestions.
  property var searchHistoryByHub: ({})
  property var searchLastQueryByHub: ({})
  property var searchSuggestions: []
  // Source-rail pins (persisted). Defaults: Radio Garden, Spotify, YouTube.
  property var pinnedHubIds: []
  property bool downloadBusy: false
  property bool downloadChoicePending: false
  property var pendingDownloadPayload: null
  property string directUrl: ""
  property string sourceActionError: ""
  property bool downloadCancelled: false
  property string downloadError: ""
  property real downloadProgress: 0
  property string downloadStatus: ""
  property string downloadTitle: ""
  property var downloadItems: []
  property int downloadTick: 0
  readonly property int downloadCount: downloadItems ? downloadItems.length : 0
  readonly property string downloadsDir: Quickshell.env("HOME") + "/Downloads/Media"
  // Resolve scripts relative to this Service.qml (portable across users/machines).
  readonly property string pluginDir: {
    var s = String(Qt.resolvedUrl("."))
    if (s.indexOf("file://") === 0)
      s = s.substring(7)
    // file:///path → /path
    if (s.indexOf("//") === 0)
      s = s.substring(1)
    while (s.length > 1 && s.endsWith("/"))
      s = s.substring(0, s.length - 1)
    return s
  }
  function pluginScript(name) {
    return pluginDir + "/" + name
  }

  // Playback extras
  property real playbackSpeed: 1.0
  property string eqPreset: "Flat"
  property var eqPresets: ["Flat", "Rock", "Pop", "Jazz", "Classical", "Vocal", "Loudness", "Electronic", "Acoustic"]
  property var audioDevices: []
  property string activeAudioDevice: ""
  property var pipewireSinks: []
  property string lyricsText: ""
  property var lyricsLines: []
  property bool lyricsBusy: false
  property int sleepTimerMinutes: 0
  property int sleepRemainingSec: 0
  property bool sleepStopAfterTrack: false
  property string localFolderFilter: ""
  property var localFolders: []
  property var mediaSettings: ({})
  property string volumeMode: "system"  // system | player | linked
  property int cliampProbeFails: 0
  property string sleepTrackId: ""
  property bool extrasPinnedSetting: false
  property string extrasTabSetting: "nearby"
  property string settingsMessage: ""
  property string shareMessage: ""
  // Serialize cliamp-ctl calls so volume/EQ/queue don't cancel each other.
  property var ctlQueue: []
  property bool ctlBusy: false
  property var nearbyStations: []
  property bool nearbyBusy: false
  property bool cliampEventsActive: false
  // Live cliamp playlist (queue.list)
  property var queueItems: []
  property int queueIndex: -1
  property int queueTotal: 0
  property int queueTick: 0
  property int lastPlaylistRevision: -1
  property bool queueBusy: false
  // After switching a cliamp provider hub, restore its search once switch settles.
  property string pendingHubSearchRestore: ""
  // yt-dlp direct streams often report title "videoplayback" — keep the search hit label.
  property string playTitleOverride: ""
  property string playArtistOverride: ""
  property string playArtOverride: ""
  property string playPathOverride: ""
  property bool playStreamOverride: false
  property string playFrequencyOverride: ""
  property string resolvedRadioFrequency: ""
  property string radioResolveKey: ""
  // Items visible in the selected source pane, used by the transport buttons.
  property var sourceNavHits: []
  property int sourceNavIndex: -1

  // Library: favourites / recents / folders (persisted under stateDir).
  property var favouriteItems: []
  property var favouriteFolders: []
  property var recentItems: []
  property var lastPlayedHit: null
  property string libraryFilterProvider: ""
  property string libraryFilterFolder: ""
  property bool verifyBusy: false
  property string libraryMessage: ""
  property int libraryTick: 0

  // Persist outside the plugin directory. Writes under
  // ~/.config/omarchy/plugins/ trigger Omarchy's inotify plugin reload,
  // which destroys the open media drawer mid-typing / mid-source-switch.
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/media"
  readonly property string pinnedHubsPath: stateDir + "/pinned-hubs.json"
  readonly property string searchHistoryPath: stateDir + "/search-history.json"
  readonly property string favouritesPath: stateDir + "/favourites.json"
  readonly property string recentsPath: stateDir + "/recents.json"
  readonly property string foldersPath: stateDir + "/favourite-folders.json"
  readonly property string downloadsPath: stateDir + "/downloads.json"
  readonly property string legacyPinnedHubsPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/myles.media/pinned-hubs.json"
  readonly property string legacySearchHistoryPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/myles.media/search-history.json"
  readonly property int favouriteCount: favouriteItems ? favouriteItems.length : 0
  readonly property int recentCount: recentItems ? recentItems.length : 0
  readonly property bool currentIsFavorite: {
    var _t = libraryTick
    var hit = null
    try { hit = currentHit() } catch (e1) { hit = null }
    if (!hit) return false
    try { return !!isFavorite(hit) } catch (e2) { return false }
  }

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  // System (PC) volume — same sink the Omarchy audio panel / volume keys use.
  readonly property var defaultAudioSink: Pipewire.defaultAudioSink
  property string volumeSinkName: ""
  property bool cliampUnityGainArmed: false
  readonly property var systemVolumeSink: {
    var sink = defaultAudioSink
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name || "")) return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name || "") === volumeSinkName && n.audio)
        return n
    }
    return sink
  }
  readonly property bool systemVolumeReady: !!(systemVolumeSink && systemVolumeSink.audio)
  readonly property real systemVolume: {
    if (!systemVolumeReady) return 0
    var v = Number(systemVolumeSink.audio.volume)
    if (!isFinite(v)) return 0
    return Math.max(0, Math.min(1, v))
  }
  readonly property bool systemMuted: systemVolumeReady ? !!systemVolumeSink.audio.muted : false
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  // True when another source is actually audible — paused PiP must yield UI.
  readonly property bool otherSourceAudible: {
    if (cliamp && cliamp.playing) return true
    var list = players || []
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (p && p.isPlaying && isListablePlayer(p)) return true
    }
    return false
  }
  // Transport/title target mpv only when it's the audible (or preferred idle) backend.
  readonly property bool usingMpv: {
    if (!videoBackendActive || !(mpv && mpv.online)) return false
    if (mpv.playing) return true
    if (otherSourceAudible) return false
    if (preferredPlayerKey === "cliamp") return false
    if (preferredPlayerKey && preferredPlayerKey !== "mpv" && preferredPlayerKey !== "")
      return false
    return true
  }
  readonly property bool usingCliamp: !usingMpv && isUsingCliamp()
  // True only when video backend owns UI — never stick from a prior YouTube
  // hit while radio/cliamp/MPRIS is what's actually playing.
  readonly property bool mediaIsVideo: {
    if (usingMpv) return true
    if (mpv && mpv.online && videoBackendActive && !otherSourceAudible) return true
    // cliamp/MPRIS play audio-only even for YouTube URLs — don't flip video UI.
    return false
  }
  readonly property bool isPlaying: usingMpv
    ? !!mpv.playing
    : (usingCliamp ? !!cliamp.playing : !!(activePlayer && activePlayer.isPlaying))
  readonly property bool hasMedia: usingMpv
    ? !!(mpv.title || mpv.path || mpv.online)
    : (usingCliamp
      ? !!(cliamp.title || cliamp.artist || cliamp.online || playTitleOverride)
      : (activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)))
  readonly property bool hasPlayer: usingMpv
    ? !!mpv.online
    : (usingCliamp ? !!cliamp.online : activePlayer !== null)
  // Live backend title wins; play*Override only fills placeholders (yt-dlp
  // "videoplayback", radio "channel", etc.) so source switches update instantly.
  readonly property string title: {
    var live = liveTrackTitle()
    var override = String(playTitleOverride || "").trim()
    if (live && !isPlaceholderTrackTitle(live)) return live
    if (override && !isPlaceholderTrackTitle(override)) return override
    // Match last hit when path still lines up (paused radio after a video, etc.)
    if (lastPlayedHit && lastPlayedHit.title) {
      var hitTitle = String(lastPlayedHit.title || "").trim()
      if (hitTitle && !isPlaceholderTrackTitle(hitTitle)) {
        var hitPath = String(lastPlayedHit.path || "")
        var curPath = String(playPathOverride
          || (usingMpv ? (mpv && mpv.path) : "")
          || (usingCliamp ? (cliamp && cliamp.path) : "")
          || "")
        if (hitPath && curPath && (hitPath === curPath
            || curPath.indexOf(hitPath) === 0 || hitPath.indexOf(curPath) === 0
            || (String(lastPlayedHit.provider || "") === "radio-garden"
                && curPath.indexOf("radio.garden") >= 0)))
          return hitTitle
      }
    }
    if (override) return override
    if (live) return live
    if (usingMpv) return "Video"
    if (usingCliamp) return "cliamp"
    return ""
  }
  readonly property string artist: {
    var live = liveTrackArtist()
    var override = String(playArtistOverride || "").trim()
    if (live && !isPlaceholderTrackTitle(live)) return live
    if (override) return override
    return live || ""
  }
  readonly property string album: usingMpv
    ? ""
    : (usingCliamp
      ? (cliamp.album || "")
      : (activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""))
  readonly property string artUrl: {
    // Video: prefer search/hit artwork (YouTube thumbs) — mpv has no MPRIS art.
    if (usingMpv || (mpv && mpv.online && videoBackendActive)) {
      var ov = String(playArtOverride || "")
      if (ov) return ov
      if (lastPlayedHit && lastPlayedHit.artUrl) return String(lastPlayedHit.artUrl)
      // Derive YouTube thumb from watch URL / path
      var p = String((mpv && mpv.path) || playPathOverride || "")
      var m = p.match(/[?&]v=([^&]+)/) || p.match(/youtu\.be\/([^?&/]+)/)
      if (m && m[1]) return "https://i.ytimg.com/vi/" + m[1] + "/hqdefault.jpg"
      return ""
    }
    var live = usingCliamp
      ? String((cliamp && cliamp.artUrl) || "")
      : (activePlayer && activePlayer.trackArtUrl ? String(activePlayer.trackArtUrl) : "")
    if (live) return live
    return String(playArtOverride || "")
  }
  readonly property string identity: usingMpv
    ? "mpv"
    : (usingCliamp
      ? "cliamp"
      : (activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || MediaModel.playerAppLabel(activePlayer) || "") : ""))
  readonly property real trackPosition: {
    var _tick = positionTick
    if (usingMpv) return Number(mpv.position) || 0
    if (usingCliamp) return MediaModel.mediaSeconds(cliamp.position)
    return activePlayer && activePlayer.positionSupported ? MediaModel.mediaSeconds(activePlayer.position) : 0
  }
  readonly property real trackLength: usingMpv
    ? (Number(mpv.length) || 0)
    : (usingCliamp
      ? MediaModel.mediaSeconds(cliamp.length)
      : (activePlayer && activePlayer.lengthSupported ? MediaModel.mediaSeconds(activePlayer.length) : 0))
  readonly property bool canSeek: usingMpv
    ? (Number(mpv.length) || 0) > 0
    : (usingCliamp ? !!cliamp.seekable : MediaModel.canSeekTrack(activePlayer))
  // Prefer PC/system sink volume so the media slider matches keyboard/OSD volume.
  readonly property bool volumeSupported: {
    var mode = MediaModel.volumeModeNormalize(volumeMode)
    if (mode === "player")
      return usingMpv ? !!mpv.online : (usingCliamp ? !!cliamp.online : !!(activePlayer && activePlayer.volumeSupported))
    return systemVolumeReady
      || (usingMpv ? !!mpv.online : (usingCliamp ? !!cliamp.online : !!(activePlayer && activePlayer.volumeSupported)))
  }
  readonly property real mediaVolume: {
    var mode = MediaModel.volumeModeNormalize(volumeMode)
    if ((mode === "system" || mode === "linked") && systemVolumeReady)
      return systemMuted ? 0 : systemVolume
    var _tick = positionTick
    if (usingMpv) {
      var mv0 = Number(mpv.volume)
      return isFinite(mv0) ? Math.max(0, Math.min(1, mv0)) : 1
    }
    if (usingCliamp) {
      var cv = (cliamp && cliamp.volume !== undefined && cliamp.volume !== null)
        ? Number(cliamp.volume) : MediaModel.cliampDbToLinear(0)
      if (!isFinite(cv)) cv = MediaModel.cliampDbToLinear(0)
      return Math.max(0, Math.min(1, cv))
    }
    if (!activePlayer || !activePlayer.volumeSupported) return systemVolumeReady ? systemVolume : 0
    var mv = Number(activePlayer.volume)
    if (!isFinite(mv)) return 0
    return Math.max(0, Math.min(1, mv))
  }
  readonly property real volume: root.mediaVolume
  readonly property bool shuffleSupported: usingMpv ? false : (usingCliamp ? true : !!(activePlayer && activePlayer.shuffleSupported))
  readonly property bool shuffle: usingMpv ? false : (usingCliamp ? !!cliamp.shuffle : !!(activePlayer && activePlayer.shuffle))
  readonly property bool loopSupported: usingMpv ? true : (usingCliamp ? true : !!(activePlayer && activePlayer.loopSupported))
  readonly property int loopState: {
    if (usingMpv) {
      var mode = String(mpvLoopMode || (mpv && mpv.loop) || "no").toLowerCase()
      if (mode === "inf" || mode === "yes" || mode === "true" || mode === "1")
        return MprisLoopState.Track
      return MprisLoopState.None
    }
    if (usingCliamp) {
      var r = String(cliamp.repeat || "Off").toLowerCase()
      if (r === "one" || r === "track") return MprisLoopState.Track
      if (r === "all" || r === "playlist" || r === "on") return MprisLoopState.Playlist
      return MprisLoopState.None
    }
    return activePlayer && activePlayer.loopSupported ? activePlayer.loopState : MprisLoopState.None
  }
  readonly property bool canGoNext: usingMpv ? true : (usingCliamp ? !!cliamp.online : !!(activePlayer && activePlayer.canGoNext))
  readonly property bool canGoPrevious: usingMpv ? true : (usingCliamp ? !!cliamp.online : !!(activePlayer && activePlayer.canGoPrevious))
  readonly property bool canTogglePlaying: usingMpv
    ? !!mpv.online
    : (usingCliamp
      ? !!cliamp.online
      : !!(activePlayer && (activePlayer.canTogglePlaying || activePlayer.canPlay || activePlayer.canPause)))
  // PiP window can stay visible even when UI yields to another audible source.
  readonly property bool videoPipVisible: !!(mpv && mpv.online) && !videoPipDismissed && videoBackendActive
  // Remember last video so the drawer "show PiP" button still works after dismiss / crash.
  property string lastVideoPath: ""
  property string lastVideoTitle: ""
  property string lastVideoArt: ""
  // True when the user can pop the PiP even if it isn't rendering right now.
  readonly property bool canShowVideoPip: {
    if (videoPipVisible) return true
    if (mpv && mpv.online && videoBackendActive) return true
    if (lastVideoPath) return true
    if (lastPlayedHit && MediaModel.hitIsVideo(lastPlayedHit)) return true
    var path = String(mediaPath || playPathOverride || (cliamp && cliamp.path) || "")
    if (path && MediaModel.hitIsVideo({ path: path, provider: cliampActiveProvider || "" }))
      return true
    return false
  }
  readonly property bool searchAvailable: {
    var hub = activeHubDef()
    return !!(hub && hub.searchable)
  }
  readonly property string searchProviderLabel: {
    var hub = activeHubDef()
    return hub ? (hub.label || "") : ""
  }
  readonly property var activeHub: {
    var id = activeHubId
    if (!id) return null
    for (var i = 0; i < hubEntries.length; i++) {
      if (hubEntries[i] && hubEntries[i].id === id) return hubEntries[i]
    }
    return activeHubDef()
  }
  readonly property bool hubOpen: activeHubId !== ""
  readonly property string searchPlaceholder: {
    var hub = activeHubDef()
    return hub && hub.placeholder ? hub.placeholder : "Search…"
  }
  readonly property string mediaPath: {
    if (playPathOverride) return playPathOverride
    if (usingMpv) return String(mpv.path || "")
    if (usingCliamp) return String(cliamp.path || "")
    return ""
  }
  readonly property bool mediaIsStream: {
    if (playStreamOverride) return true
    if (usingMpv) return false
    if (usingCliamp) return !!cliamp.stream
    return false
  }
  readonly property string radioFrequency: {
    if (playFrequencyOverride) return playFrequencyOverride
    if (resolvedRadioFrequency) return resolvedRadioFrequency
    if (lastPlayedHit && typeof lastPlayedHit === "object") {
      var fromHit = MediaModel.radioFrequencyFromHit(lastPlayedHit)
      if (fromHit) return fromHit
    }
    return MediaModel.extractRadioFrequency([
      title || "",
      artist || "",
      album || "",
      mediaPath || ""
    ].join(" "))
  }
  readonly property bool canDownload: {
    if (!hasMedia && !title) return false
    if (downloadBusy) return false
    // Need a title at minimum (Spotify falls back to ytsearch).
    return String(title || "").trim().length > 0
      && String(title || "").toLowerCase() !== "no media"
  }
  readonly property bool canQueueCurrent: {
    if (String(mediaPath || "").trim()) return true
    var hit = lastPlayedHit
    return !!(hit && typeof hit === "object" && String(hit.path || "").trim())
  }

  function isProxyPlayer(player) {
    return MediaModel.isProxyPlayer(player)
  }

  function hasMetadata(player) {
    return MediaModel.hasMetadata(player)
  }

  function hasTrackMetadata(player) {
    return MediaModel.hasTrackMetadata(player)
  }

  function playerCanControl(player) {
    return MediaModel.playerCanControl(player)
  }

  function isListablePlayer(player) {
    return MediaModel.isListablePlayer(player)
  }

  function canHandleAction(player, action) {
    return MediaModel.canHandleAction(player, action)
  }

  function canCycleSource(player) {
    return MediaModel.canCycleSource(player)
  }

  function nodeProps(node) {
    return MediaModel.nodeProps(node)
  }

  function isPlaybackStream(node) {
    return MediaModel.isPlaybackStream(node)
  }

  function streamLabelKey(label) {
    return MediaModel.streamLabelKey(label)
  }

  function rawStreamLabel(node) {
    return MediaModel.rawStreamLabel(node)
  }

  function playerAppLabel(player) {
    return MediaModel.playerAppLabel(player)
  }

  function playerHasPlaybackStream(player) {
    return MediaModel.playerHasPlaybackStream(player, playbackStreams)
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    // Keep an explicitly selected source pinned while its player is briefly
    // absent (for example while a browser is starting or reconnecting).

    playSerial = serial
    playerStartedAt = next
  }

  function orderedSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (isListablePlayer(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (canCycleSource(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!oldest || order < oldestOrder)) {
          oldest = p
          oldestOrder = order
        } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return oldest || playingProxy || null
  }

  function newestPlayingPlayer(requirePlaybackStream) {
    var newest = null
    var newestOrder = -1
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !p.isPlaying || !isListablePlayer(p)) continue
      if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue
      var order = playerOrder(p, i + 1000)
      if (!newest || order > newestOrder) {
        newest = p
        newestOrder = order
      }
    }
    return newest
  }

  function normalizedAppId(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
  }

  function playerMatchesActiveWindow(player) {
    if (!player || !activeWindowAppId) return false
    var win = normalizedAppId(activeWindowAppId)
    if (!win || win === "quickshell" || win === "omarchymediapip") return false
    var values = [player.desktopEntry, player.identity, player.dbusName]
    var candidates = []
    for (var i = 0; i < values.length; i++) {
      var value = normalizedAppId(values[i])
      if (value) candidates.push(value)
    }
    // Chromium-based browsers expose different app ids across builds and MPRIS.
    if (win.indexOf("googlechrome") !== -1 || win.indexOf("chromium") !== -1)
      candidates.push("chrome", "chromium", "googlechrome")
    if (win.indexOf("firefox") !== -1) candidates.push("firefox")
    if (win.indexOf("spotify") !== -1) candidates.push("spotify")
    for (var j = 0; j < candidates.length; j++) {
      var candidate = candidates[j]
      if (candidate === win || candidate.indexOf(win) !== -1 || win.indexOf(candidate) !== -1)
        return true
    }
    return false
  }

  function focusedPlayingPlayer() {
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && p.isPlaying && isListablePlayer(p) && playerMatchesActiveWindow(p)) return p
    }
    return null
  }

  function pauseOtherPlayback(nextPlayer) {
    var nextKey = playerKey(nextPlayer)
    var nextIsCliamp = isCliampPlayer(nextPlayer)
    var nextIsMpv = normalizedAppId(MediaModel.playerAppLabel(nextPlayer)).indexOf("mpv") !== -1
    if (!nextIsCliamp) haltCliamp()
    if (mpv && mpv.online && mpv.playing && !nextIsMpv) {
      runVideoCtl(["pause", "{}"], false)
      applyMpvSnapshot(Object.assign({}, mpv, { playing: false, paused: true }))
    }
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || playerKey(p) === nextKey || !p.isPlaying) continue
      haltPlayer(p)
    }
  }

  function followPlayerNow(player) {
    if (!player || !player.isPlaying || !isListablePlayer(player)) return false
    // Auto-follow is useful until the user chooses a source. Once they do,
    // unrelated MPRIS play events must not steal the selected source.
    if (!followMode && preferredPlayerKey) return false
    var nextKey = playerKey(player)
    if (!nextKey) return false
    pauseOtherPlayback(player)
    preferredPlayerKey = ""
    followMode = true
    lastFocusPlayerKey = nextKey
    rebuildSourceEntries()
    return true
  }

  function updateActiveWindow(info) {
    var app = String((info && (info.class || info.initialClass || info.appId)) || "")
    var title = String((info && (info.title || info.initialTitle)) || "")
    var changed = app !== activeWindowAppId
    activeWindowAppId = app
    activeWindowTitle = title
    if (!changed) return
    var focused = focusedPlayingPlayer()
    if (focused) followPlayerNow(focused)
    else lastFocusPlayerKey = ""
  }

  function handlePlayerStarted(player) {
    if (!player || !player.isPlaying || !isListablePlayer(player)) return
    // A new play event is the strongest signal of the source the user just
    // started; immediately adopt it and pause all competing playback.
    followPlayerNow(player)
  }

  function selectActivePlayer() {
    if (!followMode && preferredPlayerKey) {
      var pinned = playerForKey(preferredPlayerKey)
      if (pinned && isListablePlayer(pinned)) return pinned
      // Do not silently display/control a different source while the chosen
      // player is temporarily unavailable.
      if (preferredPlayerKey !== "cliamp" && preferredPlayerKey !== "mpv") return null
    }

    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && isListablePlayer(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (isListablePlayer(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    var focused = focusedPlayingPlayer()
    if (focused) return focused
    if (preferred && preferred.isPlaying) return preferred
    if (followMode) {
      var newestPlaying = newestPlayingPlayer(true) || newestPlayingPlayer(false)
      if (newestPlaying) return newestPlaying
    }
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return oldestPlayingPlayer(true) || oldestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function labelFor(player) {
    return MediaModel.labelFor(player)
  }

  function osdMessage(player, fallback) {
    return MediaModel.osdMessage(player, fallback)
  }

  function trackSignature(player) {
    return MediaModel.trackSignature(player)
  }

  function formatClock(seconds) {
    return MediaModel.formatClock(seconds)
  }

  function isCliampPlayer(player) {
    if (!player) return false
    var entry = String(player.desktopEntry || "").toLowerCase()
    var identity = String(player.identity || "").toLowerCase()
    var key = String(playerKey(player) || "").toLowerCase()
    return entry.indexOf("cliamp") >= 0
      || identity.indexOf("cliamp") >= 0
      || key.indexOf("cliamp") >= 0
  }

  function isUsingCliamp() {
    if (videoBackendActive) return false
    if (!cliamp.online) return false
    if (preferredPlayerKey === "cliamp") return true
    if (!followMode && preferredPlayerKey && preferredPlayerKey !== "cliamp" && preferredPlayerKey !== "mpv")
      return false

    // cliamp's own MPRIS endpoint is the active source — use the native bridge
    // so shuffle/repeat/speed/EQ work (MPRIS reports those as unsupported).
    var active = selectActivePlayer()
    if (isCliampPlayer(active)) return true

    if (!cliamp.playing) return false
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && p.isPlaying && !isProxyPlayer(p) && !isCliampPlayer(p))
        return false
    }
    return true
  }

  function anyMprisPlaying() {
    for (var i = 0; i < players.length; i++) {
      if (players[i] && players[i].isPlaying && !isProxyPlayer(players[i])) return true
    }
    return false
  }

  function findPlayerForFavorite(fav) {
    if (!fav) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (isListablePlayer(p) && MediaModel.playerMatchesFavorite(p, fav)) return p
    }
    return null
  }

  function rebuildSourceEntries() {
    var favorites = MediaModel.favoriteDefs()
    var claimed = {}
    var entries = []
    var i

    for (i = 0; i < favorites.length; i++) {
      var fav = favorites[i]
      var matched = findPlayerForFavorite(fav)
      var isCliamp = fav.id === "cliamp"
      var online = isCliamp ? !!cliamp.online : !!matched
      var playing = isCliamp ? !!cliamp.playing : !!(matched && matched.isPlaying)
      var selected = false
      if (isCliamp) {
        selected = !followMode && preferredPlayerKey === "cliamp"
      } else if (matched) {
        selected = !followMode && preferredPlayerKey === playerKey(matched)
      }

      if (matched) claimed[playerKey(matched)] = true

      var detail = ""
      if (isCliamp && online) {
        var provLabel = cliampActiveProvider ? (" · " + cliampActiveProvider) : ""
        detail = playing
          ? ((cliamp.title || "Playing") + (cliamp.artist ? " · " + cliamp.artist : "") + provLabel)
          : (cliamp.title ? cliamp.title + " · Ready" : "Ready" + provLabel)
      } else if (matched) {
        var artist = MediaModel.displayArtist(matched)
        var title = MediaModel.displayTitle(matched)
        detail = playing ? title + (artist ? " · " + artist : "") : (artist || title || "Ready")
      } else {
        detail = isCliamp ? "Offline — start cliamp" : "Offline — click to open"
        if (fav.id === "spotify" || fav.id === "youtube" || fav.id === "radio-garden")
          detail = "Search in drawer"
      }

      entries.push({
        id: fav.id,
        kind: "favorite",
        label: fav.label,
        icon: fav.icon,
        detail: detail,
        online: online,
        playing: playing,
        selected: selected,
        playerKey: matched ? playerKey(matched) : (isCliamp ? "cliamp" : ""),
        bridge: isCliamp ? "cliamp" : "",
        launch: fav.launch || ""
      })
    }

    var live = sourcePlayers
    for (i = 0; i < live.length; i++) {
      var p = live[i]
      var key = playerKey(p)
      if (!key || claimed[key]) continue
      var app = p.identity || p.desktopEntry || MediaModel.playerAppLabel(p)
      var artist2 = MediaModel.displayArtist(p)
      entries.push({
        id: "mpris:" + key,
        kind: "mpris",
        label: MediaModel.displayTitle(p),
        icon: p.isPlaying ? "󰏤" : "󰐊",
        detail: artist2 && app && artist2 !== app ? (artist2 + " · " + app) : (artist2 || app || ""),
        online: true,
        playing: !!p.isPlaying,
        selected: !followMode && preferredPlayerKey === key,
        playerKey: key,
        bridge: "",
        launch: ""
      })
    }

    sourceEntries = entries
    sourceEntriesTick++
    rebuildProviderEntries()
  }

  function rebuildProviderEntries() {
    providerEntries = MediaModel.buildCliampProviderEntries(cliampConfiguredProviders, cliampActiveProvider)
    rebuildHubEntries()
  }

  function activeHubDef() {
    var hub = MediaModel.hubDefById(activeHubId)
    if (!hub || !hub.isCliampProvider) return hub
    var copy = Object.assign({}, hub)
    copy.configured = !root.hubNeedsSetup(activeHubId)
    return copy
  }

  function hubNeedsSetup(id) {
    if (String(id || "") === "local") return false
    var hub = MediaModel.hubDefById(id)
    if (!hub || !hub.isCliampProvider) return false
    for (var i = 0; i < cliampConfiguredProviders.length; i++) {
      if (cliampConfiguredProviders[i] && cliampConfiguredProviders[i].key === id) return false
    }
    return true
  }

  // Defer model replacement so in-flight clicks aren't dropped onto the
  // KeyboardPanel dismiss layer (which would close the drawer).
  property bool hubRebuildQueued: false
  function scheduleHubRebuild() {
    if (hubRebuildQueued) return
    hubRebuildQueued = true
    Qt.callLater(function() {
      root.hubRebuildQueued = false
      root.rebuildHubEntries()
    })
  }

  function rebuildHubEntries() {
    var entries = []
    var seen = {}

    function isPinned(id) {
      var pins = pinnedHubIds && pinnedHubIds.length
        ? pinnedHubIds
        : MediaModel.defaultPinnedHubIds()
      for (var p = 0; p < pins.length; p++) {
        if (pins[p] === id) return true
      }
      return false
    }

    function pushEntry(hub, online, playing, detail) {
      if (!hub || !hub.id || seen[hub.id]) return
      seen[hub.id] = true
      entries.push({
        id: hub.id,
        label: hub.label,
        icon: hub.icon,
        accent: hub.accent || MediaModel.providerAccent(hub.id),
        blurb: hub.blurb || "",
        detail: detail || hub.blurb || "",
        searchable: !!hub.searchable,
        appSync: !!hub.appSync,
        appSearch: !!hub.appSearch,
        isCliampProvider: !!hub.isCliampProvider,
        configured: !hub.isCliampProvider || !!online || hub.id === "local",
        isLibraryHub: !!hub.isLibraryHub,
        isDownloadsHub: !!hub.isDownloadsHub,
        isRecentsHub: !!hub.isRecentsHub || hub.id === "recents",
        isLocalHub: !!hub.isLocalHub || hub.id === "local",
        searchBackend: hub.searchBackend || "",
        placeholder: hub.placeholder || "",
        openLabel: hub.openLabel || "",
        launch: hub.launch || "",
        online: !!online,
        playing: !!playing,
        selected: selectedSourceId === hub.id,
        pinned: isPinned(hub.id)
      })
    }

    var defs = MediaModel.cliampProviderDefs()
    var configuredMap = {}
    for (var c = 0; c < cliampConfiguredProviders.length; c++) {
      var cp = cliampConfiguredProviders[c]
      if (cp && cp.key) configuredMap[cp.key] = cp
    }

    var appHubsPre = MediaModel.mediaHubDefs()

    function addProvider(id, label, icon, online) {
      if (!online && id !== "local") return
      var hub = MediaModel.cliampProviderHubDef(id, label, icon)
      var playing = usingCliamp && !!cliamp.playing && cliampActiveProvider === id
      var detail = hub.blurb
      if (playing) detail = cliamp.title || "Playing"
      else if (hub.id === "local" || hub.isLocalHub) detail = "Browse local files"
      else detail = "Search " + hub.label
      pushEntry(hub, online, playing, detail)
    }

    function addAppHub(hub) {
      if (!hub || seen[hub.id]) return
      var online = false
      var playing = false
      var detail = hub.blurb || ""

      if (hub.id === "favourites" || hub.isLibraryHub) {
        online = true
        var n = root.favouriteItems ? root.favouriteItems.length : 0
        detail = n === 0 ? "No favourites yet" : (n + (n === 1 ? " favourite" : " favourites"))
        pushEntry(hub, online, false, detail)
        return
      }

      if (hub.id === "downloads" || hub.isDownloadsHub) {
        online = true
        var dn = root.downloadItems ? root.downloadItems.length : 0
        if (root.downloadBusy)
          detail = "Downloading… " + Math.round(root.downloadProgress) + "%"
        else
          detail = dn === 0 ? "No downloads yet" : (dn + (dn === 1 ? " file" : " files"))
        pushEntry(hub, online, false, detail)
        return
      }

      if (hub.id === "recents" || hub.isRecentsHub) {
        online = true
        var rn = root.recentItems ? root.recentItems.length : 0
        detail = rn === 0 ? "Nothing played yet" : (rn + (rn === 1 ? " recent" : " recents"))
        pushEntry(hub, online, false, detail)
        return
      }

      if (hub.id === "spotify" || hub.id === "mpv" || hub.id === "radio-garden") {
        var matched = findPlayerForFavorite(hub)
        online = !!matched
        playing = !!(matched && matched.isPlaying)
        if (matched) {
          detail = MediaModel.displayTitle(matched)
          var a = MediaModel.displayArtist(matched)
          if (a) detail = detail + (detail ? " · " : "") + a
        } else if (hub.id === "spotify" || hub.id === "youtube" || hub.id === "radio-garden") {
          detail = "Search in drawer"
          online = true
        } else {
          detail = "Offline — open the app"
        }
      } else if (hub.id === "youtube") {
        online = true
        playing = usingCliamp && !!cliamp.playing && (
          cliampActiveProvider === "youtube"
          || String(cliamp.artUrl || "").indexOf("ytimg") !== -1
          || String(cliamp.path || "").indexOf("youtube") !== -1
          || String(playPathOverride || "").indexOf("youtube") !== -1
        )
        if (playing) detail = cliamp.title || playTitleOverride || "Playing"
      }

      pushEntry(hub, online, playing, detail)
    }

    // 1) Pinned hubs first (Radio Garden / Spotify / YouTube by default).
    var pins = pinnedHubIds && pinnedHubIds.length
      ? pinnedHubIds.slice()
      : MediaModel.defaultPinnedHubIds()
    for (var pi = 0; pi < pins.length; pi++) {
      var pinId = pins[pi]
      if (!pinId || seen[pinId]) continue
      var pinHub = MediaModel.hubDefById(pinId)
      if (!pinHub) continue
      if (pinHub.isCliampProvider) {
        var plabel = pinHub.label
        var picon = pinHub.icon
        for (var pd = 0; pd < defs.length; pd++) {
          if (defs[pd].id === pinId) {
            plabel = defs[pd].label || plabel
            picon = defs[pd].icon || picon
            break
          }
        }
        addProvider(pinId, plabel, picon, !!configuredMap[pinId])
      } else {
        addAppHub(pinHub)
      }
    }

    // 2) Remaining configured cliamp providers.
    for (var i = 0; i < cliampConfiguredProviders.length; i++) {
      var conf = cliampConfiguredProviders[i]
      if (!conf || !conf.key || seen[conf.key]) continue
      var label = conf.name || conf.key
      var icon = "󰎆"
      for (var d = 0; d < defs.length; d++) {
        if (defs[d].id === conf.key) { icon = defs[d].icon; label = defs[d].label || label; break }
      }
      addProvider(conf.key, label, icon, true)
    }

    // 3) Remaining app / special hubs.
    for (var h = 0; h < appHubsPre.length; h++) {
      if (seen[appHubsPre[h].id]) continue
      addAppHub(appHubsPre[h])
    }

    // Unconfigured providers stay out of every source list and drawer.
    var activeDef = MediaModel.hubDefById(activeHubId)
    if (activeDef && activeDef.isCliampProvider && hubNeedsSetup(activeHubId)) {
      activeHubId = ""
      searchQuery = ""
      searchResults = []
      searchBusy = false
      searchError = ""
    }

    hubEntries = entries
  }

  function syncHubToApp(hub) {
    if (!hub) return false
    playTitleOverride = ""
    playArtistOverride = ""
    playArtOverride = ""
    playPathOverride = ""
    playStreamOverride = false
    playFrequencyOverride = ""
    resolvedRadioFrequency = ""
    radioResolveKey = ""
    var matched = findPlayerForFavorite(hub)
    if (matched) {
      pendingFavoritePin = ""
      // Pin without transferring playback — transferring would raise the app
      // window and steal focus, which dismisses this drawer.
      return selectPlayer(playerKey(matched), false)
    }
    // App offline — wait for MPRIS once the user opens it (or we launch).
    pendingFavoritePin = hub.id
    preferredPlayerKey = ""
    followMode = true
    return false
  }

  function openHub(id) {
    var hub = MediaModel.hubDefById(id)
    if (!hub) return false

    if (hub.isCliampProvider && hubNeedsSetup(hub.id)) return false

    if (selectedSourceId !== hub.id) {
      selectedSourceId = hub.id
      var prefs = {}
      for (var prefKey in (mediaSettings || {})) prefs[prefKey] = mediaSettings[prefKey]
      prefs.selectedSourceId = hub.id
      mediaSettings = prefs
      persistSettings()
    }

    if (activeHubId !== hub.id) {
      sourceNavHits = []
      sourceNavIndex = -1
    }
    activeHubId = hub.id

    if (hub.isLibraryHub || hub.id === "favourites") {
      libraryFilterProvider = ""
      clearSearch()
      scheduleHubRebuild()
      return true
    }

    if (hub.isDownloadsHub || hub.id === "downloads") {
      clearSearch()
      loadDownloads()
      scheduleHubRebuild()
      return true
    }

    if (hub.isRecentsHub || hub.id === "recents") {
      clearSearch()
      loadLibrary()
      scheduleHubRebuild()
      return true
    }

    if (hub.appSync) {
      syncHubToApp(hub)
      restoreHubSearch(hub.id)
      scheduleHubRebuild()
      rebuildSourceEntries()
      return true
    }

    // Cliamp providers (Radio, Podcasts, Local, …): scope search to this hub.
    // Don't switch the live provider here — remotes collide with search restore.
    // Playback still switches via playSearchResult / selectCliampProvider.
    if (hub.isCliampProvider) {
      if (!cliamp.online) ensureCliampDaemon()
      preferredPlayerKey = "cliamp"
      followMode = false
      pendingFavoritePin = ""
      cliampActiveProvider = hub.id
      pendingHubSearchRestore = ""
    } else if (hub.id === "youtube" || hub.id === "spotify" || hub.id === "radio-garden") {
      if (!cliamp.online) ensureCliampDaemon()
      preferredPlayerKey = "cliamp"
      followMode = false
    }

    restoreHubSearch(hub.id)
    scheduleHubRebuild()
    return true
  }

  function closeHub() {
    activeHubId = ""
    clearSearch()
    scheduleHubRebuild()
    return true
  }

  function openHubExternal() {
    var hub = activeHubDef()
    if (!hub) return false
    if (hub.launch) {
      // After launch, pin the app when its MPRIS endpoint appears.
      if (hub.appSync) pendingFavoritePin = hub.id
      Util.execDetached(hub.launch)
      showOsd(hub.openLabel || hub.label, "media")
      return true
    }
    return false
  }

  function refreshCliampProviders() {
    if (!cliamp.online) {
      if (!providerListProc.running) {
        // Still show static roster offline; configured list stays until next success.
        rebuildProviderEntries()
      }
      return
    }
    if (!providerListProc.running) providerListProc.running = true
  }

  function openCliampSetup() {
    Util.execDetached("omarchy-launch-floating-terminal-with-presentation cliamp setup")
    showOsd("cliamp setup", "media")
  }

  function selectCliampProvider(providerId) {
    var id = String(providerId || "").toLowerCase()
    if (!id) return false
    if (hubNeedsSetup(id)) return false

    var entries = providerEntries
    var entry = null
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].id === id) { entry = entries[i]; break }
    }

    if (!entry) return false

    // Ensure cliamp is the active exclusive source.
    if (!cliamp.online) {
      pendingProviderSwitch = id
      return launchFavorite("cliamp")
    }

    preferredPlayerKey = "cliamp"
    followMode = false
    pendingFavoritePin = ""
    for (var j = 0; j < players.length; j++) {
      if (players[j] && players[j].isPlaying) haltPlayer(players[j])
    }

    pendingProviderSwitch = id
    cliampActiveProvider = id
    rebuildProviderEntries()
    if (providerSwitchProc.running) providerSwitchProc.running = false
    providerSwitchProc.command = [
      root.pluginScript("switch-provider.sh"),
      id
    ]
    providerSwitchProc.running = true
    showOsd(entry ? entry.label : id, "media-source")
    if (String(searchQuery || "").trim()) {
      searchResults = []
      searchError = ""
      searchDebounce.restart()
    }
    return true
  }

  function resolveSearchProvider() {
    var hub = activeHubDef()
    if (hub && hub.searchBackend) return hub.searchBackend
    return ""
  }

  function resolveSearchProviders() {
    var backend = resolveSearchProvider()
    return backend ? [backend] : []
  }

  function setSearchQuery(query) {
    searchQuery = String(query || "")
    refreshSearchSuggestions()
    var hub = activeHubDef()
    // Keep the drawer open and search live for every searchable hub
    // (Spotify / Radio Garden / YouTube / cliamp providers).
    if (hub && hub.searchable) {
      searchError = ""
      searchDebounce.restart()
      return
    }
    searchDebounce.stop()
  }

  function refreshSearchSuggestions() {
    var hubId = activeHubId || ""
    var hist = (searchHistoryByHub && searchHistoryByHub[hubId]) ? searchHistoryByHub[hubId] : []
    searchSuggestions = MediaModel.suggestSearchQueries(hist, searchQuery, 8)
  }

  function historyForHub(hubId) {
    var id = String(hubId || "")
    if (!id) return []
    var hist = searchHistoryByHub && searchHistoryByHub[id]
    return Array.isArray(hist) ? hist.slice() : []
  }

  function rememberSearchQuery(hubId, query, persistNow) {
    var id = String(hubId || "")
    var q = String(query || "").trim()
    if (!id || !q) return
    var map = searchHistoryByHub && typeof searchHistoryByHub === "object" ? searchHistoryByHub : {}
    var list = Array.isArray(map[id]) ? map[id].slice() : []
    var lower = q.toLowerCase()
    var next = [q]
    for (var i = 0; i < list.length; i++) {
      if (String(list[i]).toLowerCase() === lower) continue
      next.push(list[i])
      if (next.length >= 40) break
    }
    map[id] = next
    searchHistoryByHub = map

    var last = searchLastQueryByHub && typeof searchLastQueryByHub === "object" ? searchLastQueryByHub : {}
    last[id] = q
    searchLastQueryByHub = last
    refreshSearchSuggestions()
    // Live typing triggers runSearch often; coalesce disk writes so the
    // drawer isn't fighting IO (and never write into the plugin folder).
    if (persistNow === true) persistSearchHistory()
    else historyPersistTimer.restart()
  }

  function restoreHubSearch(hubId) {
    var id = String(hubId || "")
    var last = (searchLastQueryByHub && searchLastQueryByHub[id]) ? String(searchLastQueryByHub[id]) : ""
    searchResults = []
    searchError = ""
    searchBusy = false
    searchDebounce.stop()
    searchQuery = last
    refreshSearchSuggestions()
    // Local always lists the library (optionally filtered by last query).
    if (last || id === "local")
      root.runSearch()
  }


  function defaultPinnedHubIds() {
    return MediaModel.defaultPinnedHubIds()
  }

  function effectivePinnedHubIds() {
    if (pinnedHubIds && pinnedHubIds.length)
      return pinnedHubIds.slice()
    return defaultPinnedHubIds()
  }

  function isHubPinned(id) {
    var key = String(id || "")
    if (!key) return false
    var pins = effectivePinnedHubIds()
    for (var i = 0; i < pins.length; i++) {
      if (pins[i] === key) return true
    }
    return false
  }

  function toggleHubPin(id) {
    var key = String(id || "")
    if (!key || !MediaModel.hubDefById(key)) return false
    var pins = effectivePinnedHubIds()
    var next = []
    var found = false
    for (var i = 0; i < pins.length; i++) {
      if (pins[i] === key) { found = true; continue }
      next.push(pins[i])
    }
    if (!found) next.push(key)
    // Never leave the rail with zero pins — fall back to defaults.
    pinnedHubIds = next.length ? next : defaultPinnedHubIds()
    persistPinnedHubs()
    rebuildHubEntries()
    showOsd((found ? "Unpinned · " : "Pinned · ") + (MediaModel.hubDefById(key).label || key), "media")
    return true
  }

  function persistPinnedHubs() {
    var payload = JSON.stringify({ pinned: effectivePinnedHubIds() })
    if (pinnedSaveProc.running) pinnedSaveProc.running = false
    pinnedSaveProc.command = [
      "bash", "-lc",
      'mkdir -p "$1" && printf "%s" "$2" > "$3" && rm -f "$4"',
      "bash",
      root.stateDir,
      payload,
      root.pinnedHubsPath,
      root.legacyPinnedHubsPath
    ]
    pinnedSaveProc.running = true
  }

  function loadPinnedHubs() {
    if (!pinnedLoadProc.running) pinnedLoadProc.running = true
  }

  function applyPinnedHubsText(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      var list = data && Array.isArray(data.pinned) ? data.pinned : []
      var clean = []
      var seenPin = {}
      for (var i = 0; i < list.length; i++) {
        var id = String(list[i] || "")
        if (!id || seenPin[id] || !MediaModel.hubDefById(id)) continue
        seenPin[id] = true
        clean.push(id)
      }
      // Ensure Favourites + Downloads + Local stay available at the front of the rail.
      if (clean.length && !seenPin["favourites"])
        clean.unshift("favourites")
      if (clean.length && !seenPin["downloads"]) {
        var favIdx = clean.indexOf("favourites")
        clean.splice(favIdx >= 0 ? favIdx + 1 : 0, 0, "downloads")
        seenPin["downloads"] = true
      }
      if (clean.length && !seenPin["local"]) {
        var dnIdx = clean.indexOf("downloads")
        clean.splice(dnIdx >= 0 ? dnIdx + 1 : 0, 0, "local")
        seenPin["local"] = true
      }
      if (clean.length && !seenPin["recents"]) {
        var locIdx = clean.indexOf("local")
        clean.splice(locIdx >= 0 ? locIdx + 1 : 0, 0, "recents")
      }
      pinnedHubIds = clean.length ? clean : defaultPinnedHubIds()
    } catch (e) {
      pinnedHubIds = defaultPinnedHubIds()
    }
    rebuildHubEntries()
  }

  function persistSearchHistory() {
    var payload = JSON.stringify({
      queries: searchHistoryByHub || {},
      lastQuery: searchLastQueryByHub || {}
    })
    if (historySaveProc.running) historySaveProc.running = false
    historySaveProc.command = [
      "bash", "-lc",
      'mkdir -p "$1" && printf "%s" "$2" > "$3" && rm -f "$4"',
      "bash",
      root.stateDir,
      payload,
      root.searchHistoryPath,
      root.legacySearchHistoryPath
    ]
    historySaveProc.running = true
  }

  function loadSearchHistory() {
    if (!historyLoadProc.running) historyLoadProc.running = true
  }

  function applySearchHistoryText(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      searchHistoryByHub = (data && data.queries && typeof data.queries === "object") ? data.queries : {}
      searchLastQueryByHub = (data && data.lastQuery && typeof data.lastQuery === "object") ? data.lastQuery : {}
    } catch (e) {
      searchHistoryByHub = {}
      searchLastQueryByHub = {}
    }
    refreshSearchSuggestions()
  }

  // --- Library: favourites / recents / folders --------------------------------

  function bumpLibrary() {
    libraryTick = libraryTick + 1
    scheduleHubRebuild()
  }

  function currentHit() {
    if (lastPlayedHit && typeof lastPlayedHit === "object")
      return MediaModel.normalizeHit(lastPlayedHit)
    if (!hasPlayer && !playTitleOverride) return null
    var prov = ""
    if (usingCliamp) prov = String(cliampActiveProvider || cliamp.provider || "")
    else if (identity.toLowerCase().indexOf("spotify") !== -1) prov = "spotify"
    var hit = MediaModel.normalizeHit({
      title: title || "",
      artist: artist || "",
      album: album || "",
      path: playPathOverride || (usingCliamp ? String(cliamp.path || "") : ""),
      artUrl: artUrl || "",
      stream: playStreamOverride || (usingCliamp ? !!cliamp.stream : false),
      provider: prov,
      providerLabel: prov,
      kind: prov === "spotify" ? "spotify-track"
        : (prov === "youtube" ? "youtube"
          : (prov === "radio-garden" ? "radio-garden" : "")),
      searchHint: (artist + " " + title).trim()
    })
    if (!hit || (!hit.title && !hit.path)) return null
    return hit
  }

  function isFavorite(hitOrId) {
    var id = ""
    if (typeof hitOrId === "string") id = hitOrId
    else id = MediaModel.favoriteIdFromHit(hitOrId)
    if (!id) return false
    var items = favouriteItems || []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].id === id) return true
    }
    return false
  }

  function findFavourite(id) {
    var key = String(id || "")
    var items = favouriteItems || []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].id === key) return items[i]
    }
    return null
  }

  function listFavorites(provider, folderId) {
    var prov = provider !== undefined ? provider : libraryFilterProvider
    var folder = folderId !== undefined ? folderId : libraryFilterFolder
    if (String(folder).indexOf("smart:") === 0)
      return MediaModel.filterSmartFavourites(favouriteItems, folder)
    return MediaModel.filterFavouriteItems(favouriteItems, prov, folder)
  }

  function listRecents() {
    return recentItems ? recentItems.slice() : []
  }

  function toggleFavorite(hit) {
    var normalized = MediaModel.normalizeHit(hit)
    if (!normalized) return false
    var id = MediaModel.favoriteIdFromHit(normalized)
    if (!id) return false
    var items = favouriteItems ? favouriteItems.slice() : []
    var idx = -1
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].id === id) { idx = i; break }
    }
    if (idx >= 0) {
      items.splice(idx, 1)
      favouriteItems = items
      persistFavourites()
      bumpLibrary()
      showOsd("Removed · " + (normalized.title || "Favourite"), "media")
      return true
    }
    items.unshift({
      id: id,
      addedAt: Date.now() / 1000,
      folderIds: [],
      broken: false,
      lastOkAt: 0,
      hit: normalized
    })
    favouriteItems = items
    persistFavourites()
    bumpLibrary()
    showOsd("Saved · " + (normalized.title || "Favourite"), "media")
    return true
  }

  function favoriteCurrent() {
    var hit = currentHit()
    if (!hit) {
      showOsd("Nothing to favourite", "media")
      return false
    }
    return toggleFavorite(hit)
  }

  function playFavorite(idOrHit) {
    var hit = null
    if (idOrHit && typeof idOrHit === "object" && idOrHit.hit)
      hit = idOrHit.hit
    else if (idOrHit && typeof idOrHit === "object" && (idOrHit.path || idOrHit.title))
      hit = idOrHit
    else {
      var row = findFavourite(String(idOrHit || ""))
      if (row) hit = row.hit
    }
    if (!hit) return false
    return playSearchResult(hit)
  }

  function shuffleFavorites(provider, folderId) {
    var list = listFavorites(provider, folderId)
    if (!list.length) {
      showOsd("No favourites to shuffle", "media")
      return false
    }
    var pick = list[Math.floor(Math.random() * list.length)]
    if (!pick || !pick.hit) return false
    showOsd("Shuffle · " + (pick.hit.title || "Favourite"), "media")
    return playSearchResult(pick.hit)
  }

  function pushRecent(hit) {
    var normalized = MediaModel.normalizeHit(hit)
    if (!normalized) return
    var id = MediaModel.favoriteIdFromHit(normalized)
    if (!id) return
    lastPlayedHit = normalized
    var items = recentItems ? recentItems.slice() : []
    var next = [{ id: id, playedAt: Date.now() / 1000, hit: normalized }]
    for (var i = 0; i < items.length; i++) {
      if (!items[i] || items[i].id === id) continue
      next.push(items[i])
      if (next.length >= 20) break
    }
    recentItems = next
    persistRecents()
    bumpLibrary()
  }

  function createFolder(label) {
    var name = String(label || "").trim()
    if (!name) return false
    var id = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
    if (!id) id = "folder-" + MediaModel.simpleHash(name)
    var folders = favouriteFolders ? favouriteFolders.slice() : []
    for (var i = 0; i < folders.length; i++) {
      if (folders[i] && folders[i].id === id) {
        showOsd("Folder exists · " + name, "media")
        return false
      }
    }
    folders.push({ id: id, label: name, accent: "" })
    favouriteFolders = folders
    persistFolders()
    bumpLibrary()
    showOsd("Folder · " + name, "media")
    return true
  }

  function renameFolder(id, label) {
    var key = String(id || "")
    var name = String(label || "").trim()
    if (!key || !name) return false
    var folders = favouriteFolders ? favouriteFolders.slice() : []
    var found = false
    for (var i = 0; i < folders.length; i++) {
      if (folders[i] && folders[i].id === key) {
        folders[i] = { id: key, label: name, accent: folders[i].accent || "" }
        found = true
        break
      }
    }
    if (!found) return false
    favouriteFolders = folders
    persistFolders()
    bumpLibrary()
    return true
  }

  function deleteFolder(id) {
    var key = String(id || "")
    if (!key) return false
    var folders = []
    var list = favouriteFolders || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id !== key) folders.push(list[i])
    }
    favouriteFolders = folders
    if (libraryFilterFolder === key) libraryFilterFolder = ""
    var items = favouriteItems ? favouriteItems.slice() : []
    for (var j = 0; j < items.length; j++) {
      if (!items[j]) continue
      var ids = []
      var old = items[j].folderIds || []
      for (var k = 0; k < old.length; k++) {
        if (String(old[k]) !== key) ids.push(old[k])
      }
      items[j].folderIds = ids
    }
    favouriteItems = items
    persistFolders()
    persistFavourites()
    bumpLibrary()
    showOsd("Folder removed", "media")
    return true
  }

  function setItemFolders(itemId, folderIds) {
    var key = String(itemId || "")
    if (!key) return false
    var items = favouriteItems ? favouriteItems.slice() : []
    var found = false
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].id === key) {
        items[i].folderIds = Array.isArray(folderIds) ? folderIds.map(String) : []
        found = true
        break
      }
    }
    if (!found) return false
    favouriteItems = items
    persistFavourites()
    bumpLibrary()
    return true
  }

  function toggleItemFolder(itemId, folderId) {
    var key = String(itemId || "")
    var folder = String(folderId || "")
    if (!key || !folder) return false
    var row = findFavourite(key)
    if (!row) return false
    var ids = (row.folderIds || []).slice()
    var next = []
    var had = false
    for (var i = 0; i < ids.length; i++) {
      if (String(ids[i]) === folder) { had = true; continue }
      next.push(ids[i])
    }
    if (!had) next.push(folder)
    return setItemFolders(key, next)
  }

  function setLibraryFilterProvider(id) {
    libraryFilterProvider = String(id || "")
    bumpLibrary()
  }

  function setLibraryFilterFolder(id) {
    libraryFilterFolder = String(id || "")
    bumpLibrary()
  }

  function persistFavourites() {
    var payload = JSON.stringify({ version: 1, items: favouriteItems || [] })
    if (favouritesSaveProc.running) favouritesSaveProc.running = false
    favouritesSaveProc.command = [
      "bash", "-lc",
      'mkdir -p "$1" && printf "%s" "$2" > "$3"',
      "bash", root.stateDir, payload, root.favouritesPath
    ]
    favouritesSaveProc.running = true
  }

  function persistRecents() {
    var payload = JSON.stringify({ version: 1, items: recentItems || [] })
    if (recentsSaveProc.running) recentsSaveProc.running = false
    recentsSaveProc.command = [
      "bash", "-lc",
      'mkdir -p "$1" && printf "%s" "$2" > "$3"',
      "bash", root.stateDir, payload, root.recentsPath
    ]
    recentsSaveProc.running = true
  }

  function persistFolders() {
    var payload = JSON.stringify({ version: 1, folders: favouriteFolders || [] })
    if (foldersSaveProc.running) foldersSaveProc.running = false
    foldersSaveProc.command = [
      "bash", "-lc",
      'mkdir -p "$1" && printf "%s" "$2" > "$3"',
      "bash", root.stateDir, payload, root.foldersPath
    ]
    foldersSaveProc.running = true
  }

  function loadLibrary() {
    if (!favouritesLoadProc.running) favouritesLoadProc.running = true
    if (!recentsLoadProc.running) recentsLoadProc.running = true
    if (!foldersLoadProc.running) foldersLoadProc.running = true
  }

  function applyFavouritesText(text) {
    var parsed = MediaModel.parseFavouritesJson(text)
    favouriteItems = parsed.items || []
    bumpLibrary()
  }

  function applyRecentsText(text) {
    var parsed = MediaModel.parseRecentsJson(text)
    recentItems = parsed.items || []
    bumpLibrary()
  }

  function applyFoldersText(text) {
    var parsed = MediaModel.parseFoldersJson(text)
    favouriteFolders = parsed.folders || []
    bumpLibrary()
  }

  function exportLibrary() {
    if (libraryExportProc.running) libraryExportProc.running = false
    libraryExportProc.command = [
      root.pluginScript("library.sh"),
      "export",
      root.stateDir
    ]
    libraryExportProc.running = true
    showOsd("Exporting library…", "media")
    return true
  }

  function importLibrary() {
    if (libraryImportProc.running) libraryImportProc.running = false
    libraryImportProc.command = [
      root.pluginScript("library.sh"),
      "import",
      root.stateDir
    ]
    libraryImportProc.running = true
    showOsd("Importing library…", "media")
    return true
  }

  function verifyFavorites() {
    if (verifyBusy) return false
    verifyBusy = true
    if (verifyFavProc.running) verifyFavProc.running = false
    verifyFavProc.command = [
      root.pluginScript("verify-favourites.sh"),
      root.favouritesPath
    ]
    verifyFavProc.running = true
    showOsd("Checking favourite links…", "media")
    return true
  }

  function applyVerifyResult(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      if (data && Array.isArray(data.items)) {
        favouriteItems = data.items
        persistFavourites()
        bumpLibrary()
        var broken = Number(data.broken) || 0
        showOsd(broken ? (broken + " broken link(s)") : "All favourites OK", "media")
      }
    } catch (e) {
      showOsd("Verify failed", "media")
    }
    verifyBusy = false
  }

  function applySuggestion(text) {
    var q = String(text || "").trim()
    if (!q) return
    searchQuery = q
    refreshSearchSuggestions()
    runSearch()
  }

  function clearSearch() {
    searchQuery = ""
    searchResults = []
    searchError = ""
    searchBusy = false
    searchDebounce.stop()
    stopSearchProcs()
    refreshSearchSuggestions()
    // Local hub should re-list the library instead of staying empty.
    var hub = activeHubDef()
    if (hub && (hub.id === "local" || hub.isLocalHub))
      Qt.callLater(function() { root.runSearch() })
  }

  function stopSearchProcs() {
    if (searchProcA.running) searchProcA.running = false
    if (searchProcB.running) searchProcB.running = false
  }

  function activeSearchProc() {
    return searchSlot === 0 ? searchProcA : searchProcB
  }

  function runSearch() {
    var q = String(searchQuery || "").trim()
    var hub = activeHubDef()
    var backend = hub ? String(hub.searchBackend || "") : ""
    var isLocal = !!(hub && (hub.id === "local" || hub.isLocalHub || backend === "local"))
    searchProvider = backend || (hub ? hub.id : "")

    if (!hub || !hub.searchable) {
      searchResults = []
      searchBusy = false
      searchError = hub ? "This source has no in-panel search" : "Pick a source to search"
      return false
    }
    // Local hub browses the filesystem — empty query lists everything.
    if (!q && !isLocal) {
      searchResults = []
      searchBusy = false
      searchError = ""
      return false
    }

    searchBusy = true
    searchError = ""
    searchSerial += 1
    var serial = searchSerial
    if (q)
      rememberSearchQuery(hub.id, q)

    // Alternate process slots so an aborted search can't clobber the new serial.
    searchSlot = searchSlot === 0 ? 1 : 0
    var proc = activeSearchProc()
    var other = searchSlot === 0 ? searchProcB : searchProcA
    // Stop the previous slot so cliamp remotes aren't blocked by a hung search.
    if (other.running) other.running = false
    if (proc.running) proc.running = false

    if (isLocal) {
      // Filesystem library — not cliamp's empty local search index.
      proc.command = [
        root.pluginScript("list-local-media.sh"),
        q,
        "500",
        String(root.localFolderFilter || "")
      ]
    } else if (hub.appSearch || backend.indexOf("drawer") !== -1
        || backend === "spotify-app" || backend === "radio-garden-app"
        || backend === "spotify-drawer" || backend === "radio-garden-drawer") {
      // In-drawer catalog search — never launches Spotify / Radio Garden.
      proc.command = [
        root.pluginScript("search-drawer.sh"),
        hub.id,
        q,
        "12"
      ]
    } else if (backend === "youtube") {
      // bash -lc so yt-dlp from the user PATH is visible to Quickshell's Process env.
      proc.command = [
        "bash", "-lc",
        root.pluginScript("search-youtube.sh") + ' "$1" "$2"',
        "bash",
        q,
        "10"
      ]
    } else {
      if (!cliamp.online) ensureCliampDaemon()
      // Scoped to this hub only (podcast / …).
      proc.command = [
        root.pluginScript("search-provider.sh"),
        backend,
        q,
        "12"
      ]
    }
    proc.searchSerial = serial
    proc.running = true
    return true
  }

  function applySearchResults(text, serial) {
    if (serial !== searchSerial) return
    var hub = activeHubDef()
    var backend = hub ? String(hub.searchBackend || "") : ""
    var parsed
    if ((hub && hub.appSearch) || backend.indexOf("drawer") !== -1
        || backend === "spotify-app" || backend === "radio-garden-app"
        || backend === "spotify-drawer" || backend === "radio-garden-drawer") {
      try {
        parsed = JSON.parse(String(text || ""))
        if (!parsed || typeof parsed !== "object")
          parsed = { ok: false, tracks: [], error: "bad-json" }
        if (!Array.isArray(parsed.tracks)) parsed.tracks = []
      } catch (e) {
        parsed = { ok: false, tracks: [], error: "bad-json" }
      }
      if (parsed.ok && parsed.tracks.length === 0 && Array.isArray(parsed.perProvider)) {
        var failed = parsed.perProvider.filter(function(p) { return p && p.ok === false })
        if (failed.length)
          parsed.error = failed.map(function(p) { return String(p.label || p.provider || "Source") + ": " + String(p.error || "unavailable") }).join(" · ")
      }
    } else {
      parsed = backend === "youtube"
        ? MediaModel.parseYoutubeSearchResults(text)
        : MediaModel.parseCliampSearchResults(text)
    }
    searchBusy = false
    searchProvider = parsed.provider || backend

    if (!parsed.ok) {
      searchResults = []
      searchError = parsed.error || "Search failed"
      return
    }

    var tracks = parsed.tracks || []
    searchResults = tracks
    searchError = tracks.length === 0 ? (parsed.error || "No results") : ""
    // Local listing may include folder chips.
    if (hub && (hub.id === "local" || hub.isLocalHub)) {
      try {
        var rawLocal = JSON.parse(String(text || "{}"))
        if (rawLocal && Array.isArray(rawLocal.folders))
          root.localFolders = rawLocal.folders
      } catch (e2) {}
    }
  }

  function playSearchResult(hit) {
    if (!hit) return false
    sourceActionError = ""

    var hubPlay = activeHubDef()

    // Halt other audible backends before starting a new source.
    for (var i = 0; i < players.length; i++) {
      if (players[i] && players[i].isPlaying) haltPlayer(players[i])
    }

    if (hit.provider) cliampActiveProvider = String(hit.provider)
    else if (hubPlay && hubPlay.searchBackend) cliampActiveProvider = String(hubPlay.searchBackend)
    if (hubPlay && hubPlay.id === "youtube") cliampActiveProvider = "youtube"
    if (hubPlay && hubPlay.id === "radio-garden") cliampActiveProvider = "radio-garden"
    if (hubPlay && hubPlay.id === "spotify") cliampActiveProvider = "spotify"

    // Flatten to a plain JSON-safe payload (QML var objects can stringify poorly).
    var payload = {
      title: String(hit.title || ""),
      artist: String(hit.artist || ""),
      album: String(hit.album || ""),
      path: String(hit.path || ""),
      artUrl: String(hit.artUrl || ""),
      stream: !!hit.stream,
      feed: !!hit.feed,
      kind: String(hit.kind || ""),
      albumId: String(hit.albumId || ""),
      provider: String(hit.provider || cliampActiveProvider || ""),
      providerLabel: String(hit.providerLabel || ""),
      detail: String(hit.detail || ""),
      channelId: String(hit.channelId || ""),
      gardenUrl: String(hit.gardenUrl || ""),
      isrc: String(hit.isrc || ""),
      searchHint: String(hit.searchHint || ""),
      frequency: String(hit.frequency || ""),
      video: !!hit.video,
      isVideo: !!hit.isVideo,
      ffprobeVideo: hit.ffprobeVideo,
      queueOnly: !!hit.queueOnly
    }
    if (!payload.frequency)
      payload.frequency = MediaModel.radioFrequencyFromHit(payload)
    if (!payload.channelId)
      payload.channelId = MediaModel.gardenChannelIdFromPath(payload.path) || String(hit.albumId || "")
    if (hit.track && typeof hit.track === "object") {
      try { payload.track = JSON.parse(JSON.stringify(hit.track)) } catch (e) {}
    }

    // Ambiguous local files — ask ffprobe once and cache.
    if (payload.path && !MediaModel.isYoutubeUrl(payload.path)
        && !MediaModel.pathHasVideoExt(payload.path)
        && payload.ffprobeVideo === undefined
        && String(payload.provider || "") !== "radio-garden"
        && String(payload.provider || "") !== "spotify"
        && !payload.stream
        && payload.path.indexOf("://") === -1) {
      var cached = ffprobeCache[payload.path]
      if (cached === true || cached === false) {
        payload.ffprobeVideo = cached
        payload.video = cached
      } else {
        root.probeFfprobe(payload.path)
      }
    }

    playTitleOverride = payload.title || ""
    playArtistOverride = payload.artist || ""
    playArtOverride = payload.artUrl || ""
    playPathOverride = payload.path || ""
    playStreamOverride = !!payload.stream
    playFrequencyOverride = payload.frequency || ""
    resolvedRadioFrequency = payload.frequency || ""
    radioResolveKey = payload.channelId || ""
    if (payload.stream && payload.channelId && !payload.frequency)
      Qt.callLater(function() { root.resolveRadioChannel(payload.channelId || payload.path) })
    else if (payload.stream && payload.path && payload.path.indexOf("radio.garden") >= 0 && !payload.frequency)
      Qt.callLater(function() { root.resolveRadioChannel(payload.path) })

    // Optional YouTube split audio/video: cliamp streams audio-only while mpv renders video.
    if (MediaModel.hitIsVideo(payload) && !payload.queueOnly
        && dualAudioEnabled && MediaModel.isYoutubeUrl(payload.path)) {
      if (dualAudioProc.running) dualAudioProc.running = false
      dualAudioProc.pendingHit = payload
      dualAudioProc.command = [root.pluginScript("youtube-audio-only.sh"), JSON.stringify(payload)]
      dualAudioProc.running = true
      preferredPlayerKey = "mpv"
      followMode = false
      pendingFavoritePin = ""
      videoBackendActive = true
      videoPipDismissed = false
      showOsd("Starting split YouTube audio/video", "media")
      return true
    }

    // Video-capable hits play in the mpv PiP (A+V). Audio stays on cliamp.
    if (MediaModel.hitIsVideo(payload) && !payload.queueOnly) {
      dualAudioActive = false
      haltCliamp()
      preferredPlayerKey = "mpv"
      followMode = false
      pendingFavoritePin = ""
      videoBackendActive = true
      videoPipDismissed = false
      root.playVideoHit(payload)
      showOsd(payload.title || "Video", "media")
      pushRecent(payload)
      rebuildHubEntries()
      rebuildProviderEntries()
      return true
    }

    // Audio / queue path — stop video backend so only one engine is audible.
    root.stopVideoBackend(false)
    preferredPlayerKey = "cliamp"
    followMode = false
    pendingFavoritePin = ""
    videoBackendActive = false

    if (!cliamp.online) ensureCliampDaemon()
    if (playSearchProc.running) playSearchProc.running = false
    playSearchProc.command = [
      root.pluginScript("play-search-result.sh"),
      JSON.stringify(payload)
    ]
    playSearchProc.running = true
    showOsd(payload.title || "Play", "media")
    pushRecent(payload)
    rebuildHubEntries()
    rebuildProviderEntries()
    return true
  }

  function downloadCurrent(opts) {
    if (downloadBusy) return false
    opts = opts || {}
    var requestedHit = opts.hit && typeof opts.hit === "object"
      ? MediaModel.normalizeHit(opts.hit) : null
    if (!requestedHit && !canDownload) {
      downloadError = "nothing-playing"
      showOsd("Nothing to download", "media")
      return false
    }

    var hit = requestedHit || (lastPlayedHit && typeof lastPlayedHit === "object"
      ? MediaModel.normalizeHit(lastPlayedHit) : null)
    var trackTitle = String((requestedHit && requestedHit.title) || title || "")
    var trackArtist = String((requestedHit && requestedHit.artist) || artist || "")
    var trackAlbum = String((requestedHit && requestedHit.album) || album || "")
    var path = requestedHit ? String(requestedHit.path || "") : String(mediaPath || "")
    var provider = requestedHit ? String(requestedHit.provider || "") : (usingCliamp
      ? String(cliampActiveProvider || cliamp.provider || "")
      : (usingMpv ? String((hit && hit.provider) || "") : ""))
    var identity = requestedHit ? String(requestedHit.identity || "") : String(root.identity || "")
    var searchHint = hit ? String(hit.searchHint || "") : ""
    // Some players publish title metadata before their MPRIS path is ready.
    // Keep the durable source from the last played hit for both the drawer and
    // bar widget instead of launching yt-dlp with an empty URL.
    if (!path && hit) path = String(hit.path || "")
    if (!provider && hit) provider = String(hit.provider || "")

    // Prefer a durable YouTube watch URL over expired googlevideo CDN / ytsearch stubs.
    var cliampPath = usingCliamp ? String(cliamp.path || "") : ""
    var mpvPath = (usingMpv || (mpv && mpv.online))
      ? String((mpv && mpv.path) || playPathOverride || "") : ""
    if (!requestedHit) {
      if (cliampPath.indexOf("youtube.com/") !== -1 || cliampPath.indexOf("youtu.be/") !== -1)
        path = cliampPath
      else if (mpvPath.indexOf("youtube.com/") !== -1 || mpvPath.indexOf("youtu.be/") !== -1) {
        path = mpvPath
        if (!provider) provider = "youtube"
      } else if (path.indexOf("googlevideo.com") !== -1)
        path = cliampPath || mpvPath || path
      else if (mpvPath && !path)
        path = mpvPath
    }

    // Spotify MPRIS rarely exposes a downloadable URL — mark as spotify so the
    // script falls back to ytsearch.
    if (!requestedHit && !usingCliamp && activePlayer) {
      var hay = [
        activePlayer.desktopEntry || "",
        activePlayer.identity || "",
        activePlayer.dbusName || ""
      ].join(" ").toLowerCase()
      if (hay.indexOf("spotify") !== -1) {
        provider = "spotify"
        if (!path) path = "spotify:track"
      }
    }

    // Infer provider from path when unset.
    if (!provider) {
      if (path.indexOf("youtube.com/") !== -1 || path.indexOf("youtu.be/") !== -1)
        provider = "youtube"
      else if (path.indexOf("radio.garden") !== -1)
        provider = "radio-garden"
      else if (path.indexOf("spotify:") === 0 || path.indexOf("ytsearch") === 0)
        provider = "spotify"
    }

    var downloadFormat = String(opts.format || "")
    var videoHit = MediaModel.hitIsVideo(hit || { path: path, provider: provider })
    if (videoHit && downloadFormat !== "video" && downloadFormat !== "mp3") {
      pendingDownloadPayload = { hit: hit || { title: trackTitle, artist: trackArtist, path: path, provider: provider }, opts: opts }
      downloadChoicePending = true
      downloadError = ""
      showOsd("Choose video or MP3", "media")
      return true
    }
    downloadChoicePending = false

    var payload = {
      title: trackTitle,
      artist: trackArtist,
      album: trackAlbum,
      path: path,
      // Don't mark YouTube/Spotify as live radio captures.
      stream: requestedHit ? !!requestedHit.stream : !!(mediaIsStream && provider !== "youtube" && provider !== "spotify"
        && String(path).indexOf("youtube") === -1 && String(path).indexOf("youtu.be") === -1),
      provider: provider,
      identity: identity,
      searchHint: searchHint
    }
    payload.downloadFormat = downloadFormat || "mp3"
    if (opts.recordMinutes !== undefined && opts.recordMinutes !== null)
      payload.recordMinutes = Number(opts.recordMinutes)
    if (opts.recordSeconds !== undefined && opts.recordSeconds !== null)
      payload.recordSeconds = Number(opts.recordSeconds)

    downloadCancelled = false
    downloadBusy = true
    downloadError = ""
    downloadProgress = 0
    downloadStatus = "Starting…"
    downloadTitle = payload.title || "Download"
    if (downloadProc.running) downloadProc.running = false
    downloadProc.command = [
      root.pluginScript("download-current.sh"),
      JSON.stringify(payload)
    ]
    downloadProc.running = true
    showOsd("Downloading…", "media")
    scheduleHubRebuild()
    return true
  }

  function chooseDownloadFormat(format) {
    if (!downloadChoicePending || !pendingDownloadPayload) return false
    var pending = pendingDownloadPayload
    pendingDownloadPayload = null
    downloadChoicePending = false
    var next = Object.assign({}, pending.opts || {}, { hit: pending.hit, format: format })
    return downloadCurrent(next)
  }

  function cancelDownloadChoice() {
    downloadChoicePending = false
    pendingDownloadPayload = null
  }

  function playDirectUrl(rawUrl) {
    var u = String(rawUrl || "").trim()
    if (!/^https?:\/\//i.test(u)) { sourceActionError = "Enter a complete http(s) URL"; return false }
    var hostMatch = u.match(/^https?:\/\/([^/:?#]+)/i)
    var host = hostMatch ? hostMatch[1] : ""
    var provider = MediaModel.mediaProviderForUrl(u)
    var knownVideoSite = provider === "youtube" || provider === "facebook"
      || provider === "tiktok" || provider === "x"
    var title = u.split(/[/?#]/).filter(Boolean).pop() || host
    try { title = decodeURIComponent(title.replace(/\+/g, " ")) } catch (e) {}
    sourceActionError = ""
    directUrl = u
    var ok = playSearchResult({ title: title, path: u, provider: provider,
      video: knownVideoSite || MediaModel.pathHasVideoExt(u) || /\.(m3u8|mpd)(\?|$)/i.test(u),
      stream: /\.(m3u8|mpd)(\?|$)/i.test(u) })
    if (!ok) sourceActionError = "Could not start this URL. Check that it is public and playable."
    return ok
  }

  function downloadDirectUrl(rawUrl) {
    var u = String(rawUrl || "").trim()
    if (!/^https?:\/\//i.test(u)) { sourceActionError = "Enter a complete http(s) URL"; return false }
    var hostMatch = u.match(/^https?:\/\/([^/:?#]+)/i)
    var host = hostMatch ? hostMatch[1] : ""
    var provider = MediaModel.mediaProviderForUrl(u)
    var knownVideoSite = provider === "youtube" || provider === "facebook"
      || provider === "tiktok" || provider === "x"
    var title = u.split(/[/?#]/).filter(Boolean).pop() || host
    try { title = decodeURIComponent(title.replace(/\+/g, " ")) } catch (e) {}
    sourceActionError = ""
    directUrl = u
    return downloadCurrent({ hit: { title: title, path: u, provider: provider,
      video: knownVideoSite || MediaModel.pathHasVideoExt(u) || /\.(m3u8|mpd)(\?|$)/i.test(u), stream: false } })
  }

  function handleDownloadEvent(line) {
    var raw = String(line || "").trim()
    if (!raw) return
    // User already cancelled — ignore late stdout so the banner stays gone.
    if (downloadCancelled) return
    try {
      var data = JSON.parse(raw)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return

    if (data.event === "progress") {
      downloadBusy = true
      downloadProgress = Number(data.pct) || 0
      downloadStatus = String(data.status || "")
      if (data.title) downloadTitle = String(data.title)
      scheduleHubRebuild()
      return
    }

    if (data.event === "done" || data.ok !== undefined) {
      downloadBusy = false
      downloadProgress = data.ok ? 100 : downloadProgress
      downloadStatus = data.ok ? "Done" : String(data.error || "Failed")
      if (data.ok) {
        downloadError = ""
        var where = String(data.path || downloadsDir)
        var warn = String(data.warning || "")
        showOsd(warn ? warn : ("Saved · " + where.split("/").pop()), "media")
        downloadBannerClear.interval = 1800
        downloadBannerClear.restart()
      } else {
        var err = root.friendlyDownloadError(data.error || "download-failed")
        // Cancelled mid-flight from the script — hide banner entirely.
        if (err === "cancelled" || err === "canceled") {
          root.clearDownloadUi()
        } else {
          downloadError = err
          showOsd(downloadError.length > 48 ? "Download failed" : downloadError, "media")
          downloadBannerClear.interval = 3500
          downloadBannerClear.restart()
        }
      }
      loadDownloads()
      scheduleHubRebuild()
    }
  }

  function loadDownloads() {
    if (downloadListProc.running) downloadListProc.running = false
    downloadListProc.command = [
      root.pluginScript("download-current.sh"),
      "--list"
    ]
    downloadListProc.running = true
  }

  function applyDownloadsText(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      downloadItems = (data && Array.isArray(data.items)) ? data.items : []
    } catch (e) {
      downloadItems = []
    }
    downloadTick = downloadTick + 1
    scheduleHubRebuild()
  }

  function openDownloadsFolder() {
    Util.execDetached("xdg-open " + JSON.stringify(downloadsDir))
    showOsd("Downloads folder", "media")
    return true
  }

  function playDownload(item) {
    if (!item || !item.path) return false
    var downloads = []
    for (var i = 0; i < downloadItems.length; i++) {
      var saved = downloadItems[i]
      if (!saved || !saved.path || saved.status === "failed" || saved.status === "downloading") continue
      downloads.push({ title: saved.title || "", artist: saved.artist || "", path: saved.path,
        provider: "local", kind: "local", stream: false })
    }
    var selected = -1
    for (var j = 0; j < downloads.length; j++)
      if (String(downloads[j].path) === String(item.path)) { selected = j; break }
    sourceNavHits = downloads
    sourceNavIndex = selected
    return playSearchResult({
      title: String(item.title || ""),
      artist: String(item.artist || ""),
      path: String(item.path || ""),
      provider: "local",
      kind: "local",
      stream: false
    })
  }

  function playSourceHit(hits, index) {
    if (!Array.isArray(hits) || index < 0 || index >= hits.length || !hits[index]) return false
    sourceNavHits = hits.slice(0)
    sourceNavIndex = index
    return playSearchResult(hits[index])
  }

  function stepSourceHit(delta) {
    var hits = sourceNavHits || []
    if (hits.length < 2 || sourceNavIndex < 0) return false
    var nextIndex = (sourceNavIndex + delta + hits.length) % hits.length
    return playSourceHit(hits, nextIndex)
  }

  function removeDownload(item) {
    if (!item || !item.path) return false
    var p = String(item.path)
    // Confine deletes to ~/Downloads/Media (and its realpath).
    var rootDir = String(root.downloadsDir || "")
    if (!rootDir || p.indexOf(rootDir) !== 0) {
      showOsd("Refuse delete · outside Media folder", "media")
      return false
    }
    if (p.indexOf("..") >= 0) {
      showOsd("Refuse delete · bad path", "media")
      return false
    }
    Util.execDetached("rm -f -- " + JSON.stringify(p))
    Util.execDetached(root.pluginScript("download-current.sh") + " --remove " + JSON.stringify(p))
    var next = []
    var list = downloadItems || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].path) !== p) next.push(list[i])
    }
    downloadItems = next
    downloadTick = downloadTick + 1
    Qt.callLater(function() { root.loadDownloads() })
    showOsd("Removed download", "media")
    return true
  }

  function friendlyDownloadError(value) {
    var err = String(value || "download-failed").trim()
    var lower = err.toLowerCase()
    if (lower === "interrupted") return "Download interrupted · Retry"
    if (lower === "yt-dlp-missing") return "yt-dlp is missing · install it to download this source"
    if (lower.indexOf("ffmpeg") !== -1 || lower.indexOf("ffprobe") !== -1)
      return "ffmpeg is needed to convert this download"
    if (lower.indexOf("429") !== -1 || lower.indexOf("403") !== -1 || lower.indexOf("sign in") !== -1)
      return "The source refused the request · try again later"
    if (lower.indexOf("timed out") !== -1 || lower.indexOf("timeout") !== -1 || lower.indexOf("network") !== -1)
      return "Network request timed out · check your connection and retry"
    if (lower.indexOf("http-download-failed") !== -1 || lower.indexOf("stream-failed") !== -1)
      return "Could not fetch this media source · try again"
    return err.length > 100 ? err.slice(0, 97) + "…" : err
  }

  function retryDownload(item) {
    if (!item || downloadBusy) return false
    var path = String(item.sourcePath || "")
    var hint = String(item.searchHint || "")
    if (!path && !hint) {
      showOsd("This old download has no saved source · play it again to retry", "media")
      return false
    }
    var retryHit = {
      title: String(item.title || ""),
      artist: String(item.artist || ""),
      path: path,
      provider: String(item.provider || ""),
      searchHint: hint,
      stream: !!item.stream
    }
    var started = downloadCurrent({ hit: retryHit })
    if (started) showOsd("Retrying download", "media")
    return started
  }

  function cancelDownload() {
    if (!downloadBusy && !downloadProc.running && downloadError === "" && downloadProgress <= 0)
      return false
    downloadCancelled = true
    downloadBannerClear.stop()
    var wasRunning = !!downloadProc.running
    if (wasRunning) downloadProc.running = false
    // Kill only our download PID / process group — never pkill all yt-dlp.
    Util.execDetached("bash -lc 'pid=$(cat \"$HOME/.local/state/omarchy/media/download.pid\" 2>/dev/null); [[ -n $pid ]] && kill -TERM -$pid 2>/dev/null; [[ -n $pid ]] && kill -TERM $pid 2>/dev/null; rm -f \"$HOME/.local/state/omarchy/media/download.pid\"'")
    clearDownloadUi()
    // If the process was already dead, onExited won't run — drop the cancel latch.
    if (!wasRunning) downloadCancelled = false
    loadDownloads()
    scheduleHubRebuild()
    showOsd("Download cancelled", "media")
    return true
  }

  function clearDownloadUi() {
    downloadBusy = false
    downloadStatus = ""
    downloadError = ""
    downloadProgress = 0
    downloadTitle = ""
  }

  function queueSearchResult(hit) {
    if (!hit) return false
    var payload = {
      title: String(hit.title || ""),
      artist: String(hit.artist || ""),
      album: String(hit.album || ""),
      path: String(hit.path || ""),
      artUrl: String(hit.artUrl || ""),
      stream: !!hit.stream,
      feed: !!hit.feed,
      kind: String(hit.kind || ""),
      albumId: String(hit.albumId || ""),
      provider: String(hit.provider || cliampActiveProvider || ""),
      providerLabel: String(hit.providerLabel || ""),
      searchHint: String(hit.searchHint || ""),
      queueOnly: true
    }
    if (hit.track && typeof hit.track === "object") {
      try { payload.track = JSON.parse(JSON.stringify(hit.track)) } catch (e) {}
    }

    // Video hits join the mpv playlist so next/prev advances videos.
    if (MediaModel.hitIsVideo(payload) && payload.path) {
      if (!mpv.online) {
        // First video in queue — start playback immediately.
        var playHit = Object.assign({}, payload)
        playHit.queueOnly = false
        return playSearchResult(playHit)
      }
      runVideoCtl(["queue", JSON.stringify({
        path: payload.path,
        title: payload.title,
        mode: "append"
      })], true)
      showOsd("Queued video · " + (payload.title || "clip"), "media")
      mpvPollTimer.restart()
      return true
    }

    if (!cliamp.online) ensureCliampDaemon()
    if (playSearchProc.running) playSearchProc.running = false
    playSearchProc.command = [
      root.pluginScript("play-search-result.sh"),
      JSON.stringify(payload)
    ]
    playSearchProc.running = true
    showOsd("Queued · " + (payload.title || "track"), "media")
    Qt.callLater(function() { root.loadQueue() })
    return true
  }

  function loadQueue() {
    if (!cliamp.online) {
      queueItems = []
      queueIndex = -1
      queueTotal = 0
      queueTick++
      return false
    }
    if (queueProc.running) return true
    queueBusy = true
    queueProc.command = [root.pluginScript("cliamp-ctl.sh"), "queue-list", JSON.stringify({ offset: 0, limit: 48 })]
    queueProc.running = true
    return true
  }

  function applyQueueList(text) {
    var parsed = MediaModel.parseCliampQueueList(text)
    queueItems = parsed.tracks || []
    queueIndex = Number(parsed.index || 0)
    queueTotal = Number(parsed.total || queueItems.length || 0)
    queueBusy = false
    queueTick++
  }

  function playQueueIndex(index) {
    var idx = Math.max(0, Math.floor(Number(index) || 0))
    root.runCtl(["queue-play", JSON.stringify({ index: idx })])
    preferredPlayerKey = "cliamp"
    followMode = false
    showOsd("Playing queue · " + (idx + 1), "media")
    cliampRefreshTimer.interval = 400
    cliampRefreshTimer.restart()
    Qt.callLater(function() { root.loadQueue() })
    return true
  }

  function clearQueue() {
    root.runCtl(["queue-clear", "{}"])
    showOsd("Queue cleared", "media")
    Qt.callLater(function() { root.loadQueue() })
    return true
  }

  function removeQueueIndex(index) {
    var idx = Math.max(0, Math.floor(Number(index) || 0))
    root.runCtl(["queue-remove", JSON.stringify({ index: idx })])
    showOsd("Removed from queue", "media")
    Qt.callLater(function() { root.loadQueue() })
    return true
  }

  function moveQueueIndex(index, to) {
    var idx = Math.max(0, Math.floor(Number(index) || 0))
    var dest = Math.max(0, Math.floor(Number(to) || 0))
    root.runCtl(["queue-move", JSON.stringify({ index: idx, to: dest })])
    showOsd("Queue reordered", "media")
    Qt.callLater(function() { root.loadQueue() })
    return true
  }

  function playNextQueueIndex(index) {
    var idx = Math.max(0, Math.floor(Number(index) || 0))
    root.runCtl(["queue-enqueue", JSON.stringify({ index: idx })])
    showOsd("Play next", "media")
    Qt.callLater(function() { root.loadQueue() })
    return true
  }

  function queueCurrentTrack() {
    var hit = currentHit()
    var path = String(root.mediaPath || (hit && hit.path) || "")
    if (!path) {
      showOsd("Nothing to queue", "media")
      return false
    }
    return queueSearchResult({
      title: (hit && hit.title) || root.title || "",
      artist: (hit && hit.artist) || root.artist || "",
      album: (hit && hit.album) || root.album || "",
      path: path,
      artUrl: (hit && hit.artUrl) || root.artUrl || "",
      stream: !!(hit && hit.stream) || root.mediaIsStream,
      provider: (hit && hit.provider) || cliampActiveProvider || "local"
    })
  }

  function revealPath(path) {
    var p = String(path || "")
    if (!p) return false
    var dir = p
    var slash = p.lastIndexOf("/")
    if (slash > 0) dir = p.substring(0, slash)
    Util.execDetached("xdg-open " + JSON.stringify(dir))
    showOsd("Open folder", "media")
    return true
  }

  function copyPath(path) {
    var p = String(path || "")
    if (!p) return false
    Util.execDetached(["bash", "-lc", "printf %s " + JSON.stringify(p) + " | wl-copy || true"].join(" "))
    showOsd("Path copied", "media")
    return true
  }

  function setLocalFolderFilter(folder) {
    localFolderFilter = String(folder || "")
    if (activeHubId === "local")
      runSearch()
    return true
  }

  function addLocalRoot(path) {
    var p = String(path || "").trim()
    if (!p) return false
    var roots = (mediaSettings && mediaSettings.localRoots) ? mediaSettings.localRoots.slice() : []
    for (var i = 0; i < roots.length; i++) {
      if (String(roots[i]) === p) {
        showOsd("Folder already added", "media")
        return false
      }
    }
    roots.push(p)
    var next = {}
    var src = mediaSettings || {}
    for (var k in src) next[k] = src[k]
    next.localRoots = roots
    mediaSettings = next
    persistSettings()
    if (activeHubId === "local") runSearch()
    showOsd("Added library folder", "media")
    return true
  }

  function setPlaybackSpeed(v) {
    var speed = Math.max(0.25, Math.min(2.0, Number(v) || 1.0))
    playbackSpeed = speed
    root.runCtl(["speed", JSON.stringify({ value: speed })])
    var next = {}
    var src = mediaSettings || {}
    for (var k in src) next[k] = src[k]
    next.defaultSpeed = speed
    mediaSettings = next
    persistSettings()
    showOsd("Speed · " + speed.toFixed(2).replace(/\.00$/, "") + "×", "media")
    cliampRefreshTimer.interval = 400
    cliampRefreshTimer.restart()
    return true
  }

  function setEqPreset(name) {
    eqPreset = String(name || "Flat")
    root.runCtl(["eq", JSON.stringify({ name: eqPreset })])
    var next = {}
    var src = mediaSettings || {}
    for (var k in src) next[k] = src[k]
    next.defaultEq = eqPreset
    mediaSettings = next
    persistSettings()
    showOsd("EQ · " + eqPreset, "media")
    cliampRefreshTimer.interval = 400
    cliampRefreshTimer.restart()
    return true
  }

  function refreshEqPresets() {
    if (eqListProc.running) return true
    eqListProc.command = [root.pluginScript("cliamp-ctl.sh"), "eq-list", "{}"]
    eqListProc.running = true
    return true
  }

  function refreshAudioDevices() {
    devicesProc.command = [root.pluginScript("cliamp-ctl.sh"), "devices", "{}"]
    devicesProc.running = true
    sinksProc.command = [root.pluginScript("cliamp-ctl.sh"), "sinks", "{}"]
    sinksProc.running = true
    return true
  }

  function resolveRadioChannel(idOrPath) {
    var key = String(idOrPath || "").trim()
    if (!key) return false
    if (radioResolveProc.running) radioResolveProc.running = false
    radioResolveProc.command = [root.pluginScript("resolve-radio-channel.sh"), key]
    radioResolveProc.running = true
    return true
  }

  function applyRadioChannelResolve(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      if (!data || !data.ok) return
      var freq = String(data.frequency || "")
      if (!freq && data.title)
        freq = MediaModel.extractRadioFrequency(data.title)
      if (freq) {
        resolvedRadioFrequency = freq
        if (!playFrequencyOverride) playFrequencyOverride = freq
      }
      var titleNow = String(title || "").trim().toLowerCase()
      var isBadTitle = !titleNow || titleNow === "channel" || titleNow === "stream"
        || titleNow === "cliamp" || titleNow === "audio" || titleNow === "index"
      if (data.title && (isBadTitle || playTitleOverride === "" || playTitleOverride.toLowerCase() === "channel"))
        playTitleOverride = String(data.title)
      if (data.artist && (!artist || playArtistOverride === "" || isBadTitle))
        playArtistOverride = String(data.artist)
      if (data.path && !playPathOverride)
        playPathOverride = String(data.path)
      playStreamOverride = true
      if (lastPlayedHit && typeof lastPlayedHit === "object") {
        var next = {}
        for (var k in lastPlayedHit) next[k] = lastPlayedHit[k]
        if (data.title) next.title = String(data.title)
        if (data.artist) next.artist = String(data.artist)
        if (freq) next.frequency = freq
        if (data.channelId) next.channelId = String(data.channelId)
        if (data.gardenUrl) next.gardenUrl = String(data.gardenUrl)
        lastPlayedHit = next
      }
    } catch (e) {}
  }

  function setAudioDevice(name) {
    var n = String(name || "").trim()
    if (!n) return false
    activeAudioDevice = n
    root.runCtl(["device", JSON.stringify({ name: n })])
    showOsd("Output · " + n.split(".").pop(), "media")
    Qt.callLater(function() { root.refreshAudioDevices() })
    cliampRefreshTimer.interval = 500
    cliampRefreshTimer.restart()
    return true
  }

  function setPipewireSink(id) {
    var sid = String(id || "")
    if (!sid) return false
    root.runCtl(["set-sink", JSON.stringify({ id: sid })])
    // Also try matching a cliamp device by sink name when available.
    var sinks = pipewireSinks || []
    var sinkName = ""
    for (var i = 0; i < sinks.length; i++) {
      if (sinks[i] && String(sinks[i].id) === sid) {
        sinkName = String(sinks[i].name || "")
        break
      }
    }
    if (sinkName) {
      var devices = audioDevices || []
      for (var j = 0; j < devices.length; j++) {
        var dn = typeof devices[j] === "string" ? devices[j] : String((devices[j] && devices[j].name) || "")
        if (dn && (dn.indexOf(sinkName) >= 0 || sinkName.indexOf(dn.split(".").pop()) >= 0)) {
          Qt.callLater(function() { root.setAudioDevice(dn) })
          break
        }
      }
    }
    showOsd("PipeWire sink set", "media")
    Qt.callLater(function() { root.refreshAudioDevices() })
    return true
  }

  function fetchLyrics() {
    lyricsBusy = true
    lyricsText = ""
    lyricsLines = []
    if (lyricsProc.running) lyricsProc.running = false
    lyricsProc.command = [root.pluginScript("cliamp-ctl.sh"), "lyrics", "{}"]
    lyricsProc.running = true
    return true
  }

  function startSleepTimer(minutes, stopAfterTrack) {
    sleepTimerMinutes = Math.max(0, Math.floor(Number(minutes) || 0))
    sleepStopAfterTrack = !!stopAfterTrack
    sleepRemainingSec = sleepTimerMinutes * 60
    sleepTrackSig = MediaModel.sleepTrackId(root.title, root.artist, root.mediaPath, root.album)
    sleepTrackId = sleepTrackSig
    if (sleepRemainingSec <= 0 && !sleepStopAfterTrack) {
      sleepTimer.stop()
      showOsd("Sleep timer cleared", "media")
      return false
    }
    sleepTimer.restart()
    showOsd(sleepStopAfterTrack && sleepRemainingSec <= 0
      ? "Stop after this track"
      : ("Sleep · " + sleepTimerMinutes + "m"), "media")
    return true
  }

  function clearSleepTimer() {
    sleepTimerMinutes = 0
    sleepRemainingSec = 0
    sleepStopAfterTrack = false
    sleepTimer.stop()
    showOsd("Sleep timer off", "media")
    return true
  }

  function shareStation() {
    // Privacy-friendly: share only the current station/track URL when available.
    return shareCurrentLink() || shareLibraryBundle()
  }

  function shareLibraryBundle() {
    shareMessage = ""
    if (shareProc.running) shareProc.running = false
    shareProc.command = [root.pluginScript("share-station.sh")]
    shareProc.running = true
    showOsd("Exporting library…", "media")
    return true
  }

  function shareCurrentLink() {
    var path = String(root.mediaPath || "")
    var garden = ""
    if (lastPlayedHit && lastPlayedHit.gardenUrl)
      garden = String(lastPlayedHit.gardenUrl)
    if (!path && !garden && !(root.title || "").trim()) {
      showOsd("Nothing to share", "media")
      return false
    }
    shareMessage = ""
    var payload = {
      title: root.title || "",
      artist: root.artist || "",
      path: path,
      gardenUrl: garden
    }
    if (shareProc.running) shareProc.running = false
    shareProc.command = [
      root.pluginScript("share-station.sh"),
      "--current",
      JSON.stringify(payload)
    ]
    shareProc.running = true
    showOsd("Copying link…", "media")
    return true
  }

  function recordCurrent(minutes) {
    var mins = Math.max(0.25, Math.min(10, Number(minutes) || 1))
    return downloadCurrent({ recordMinutes: mins })
  }

  function loadNearbyStations() {
    if (nearbyBusy) return false
    nearbyBusy = true
    nearbyStations = []
    if (nearbyProc.running) nearbyProc.running = false
    nearbyProc.command = [
      root.pluginScript("search-drawer.sh"),
      "radio-garden",
      "__nearby__",
      "12"
    ]
    nearbyProc.running = true
    return true
  }

  function loadPopularStations() {
    if (nearbyBusy) return false
    nearbyBusy = true
    nearbyStations = []
    if (nearbyProc.running) nearbyProc.running = false
    nearbyProc.command = [
      root.pluginScript("search-drawer.sh"),
      "radio-garden",
      "__popular__",
      "12"
    ]
    nearbyProc.running = true
    return true
  }

  function applyNearbyText(text) {
    nearbyBusy = false
    try {
      var data = JSON.parse(String(text || "{}"))
      nearbyStations = (data && Array.isArray(data.tracks)) ? data.tracks : []
    } catch (e) {
      nearbyStations = []
    }
  }

  function applyCtlResult(text) {
    try {
      var data = JSON.parse(String(text || "{}")) || {}
      if (data.speed !== undefined && data.speed !== null)
        playbackSpeed = Number(data.speed) || playbackSpeed
      if (data.eq)
        eqPreset = String(data.eq)
      if (data.device)
        activeAudioDevice = String(data.device)
      if (data.active)
        activeAudioDevice = String(data.active)
      if (data.volume !== undefined && data.volume !== null) {
        var vol = Number(data.volume)
        if (isFinite(vol)) {
          var next = {}
          for (var k in cliamp) next[k] = cliamp[k]
          // ctl returns linear 0..1 after dB conversion
          next.volume = Math.max(0, Math.min(1, vol))
          cliamp = next
        }
      }
      if (data.ok === false && data.error)
        showOsd(String(data.error).slice(0, 48), "media")
      // Volume-only replies already updated cliamp.volume — skip snapshot refresh
      // so a lagging remote state can't snap the slider back mid-drag.
      var volumeOnly = data.volume !== undefined
        && data.speed === undefined && !data.eq && !data.device && !data.active
        && data.ok !== false
      if (!volumeOnly) {
        cliampRefreshTimer.interval = 350
        cliampRefreshTimer.restart()
      }
    } catch (e) {}
  }

  function persistSettings() {
    var payload = JSON.stringify(mediaSettings || {})
    settingsSaveProc.command = [
      "bash", "-lc",
      'mkdir -p "$1" && printf "%s" "$2" > "$3"',
      "bash",
      root.stateDir,
      payload,
      root.stateDir + "/settings.json"
    ]
    settingsSaveProc.running = true
  }

  function loadSettings() {
    if (!settingsLoadProc.running) settingsLoadProc.running = true
  }

  function applySettingsText(text) {
    var chosenBeforeLoad = selectedSourceId
    try {
      mediaSettings = JSON.parse(String(text || "{}")) || {}
    } catch (e) {
      mediaSettings = {}
    }
    var savedSource = String(mediaSettings.selectedSourceId || "")
    if (chosenBeforeLoad && MediaModel.hubDefById(chosenBeforeLoad)) {
      selectedSourceId = chosenBeforeLoad
      mediaSettings.selectedSourceId = chosenBeforeLoad
      Qt.callLater(function() { root.persistSettings() })
    } else if (savedSource && MediaModel.hubDefById(savedSource)) {
      selectedSourceId = savedSource
    }
    if (mediaSettings.defaultSpeed)
      playbackSpeed = Number(mediaSettings.defaultSpeed) || 1.0
    if (mediaSettings.defaultEq)
      eqPreset = String(mediaSettings.defaultEq || "Flat")
    if (mediaSettings.volumeMode)
      volumeMode = MediaModel.volumeModeNormalize(mediaSettings.volumeMode)
    extrasPinnedSetting = !!mediaSettings.extrasPinned
    extrasTabSetting = String(mediaSettings.extrasTab || "nearby")
    dualAudioEnabled = !!mediaSettings.dualAudioEnabled
    rebuildHubEntries()
  }

  function persistUiPrefs(extrasPinned, extrasTab) {
    var src = mediaSettings || {}
    var next = {}
    for (var k in src) next[k] = src[k]
    if (extrasPinned !== undefined) next.extrasPinned = !!extrasPinned
    if (extrasTab !== undefined && extrasTab !== "") next.extrasTab = String(extrasTab)
    next.volumeMode = MediaModel.volumeModeNormalize(volumeMode)
    next.dualAudioEnabled = !!dualAudioEnabled
    mediaSettings = next
    extrasPinnedSetting = !!next.extrasPinned
    extrasTabSetting = String(next.extrasTab || "nearby")
    persistSettings()
  }

  function clearSearchHistory(hubId) {
    var hub = String(hubId || activeHubId || "")
    var src = searchHistoryByHub || {}
    var next = {}
    for (var k in src) next[k] = src[k]
    if (hub) next[hub] = []
    else next = {}
    searchHistoryByHub = next
    searchSuggestions = []
    persistSearchHistory()
    showOsd(hub ? ("Cleared · " + hub) : "Search history cleared", "media")
    return true
  }

  function listSmartFavourites(smartId) {
    return MediaModel.filterSmartFavourites(favouriteItems || [], smartId)
  }

  function runCliamp(args) {
    var argv = ["cliamp"].concat(args || [])
    Util.execArgv(argv)
    cliampRefreshTimer.restart()
  }

  function patchCliamp(fields) {
    if (!fields || typeof fields !== "object") return
    var next = {}
    for (var k in cliamp) next[k] = cliamp[k]
    for (var f in fields) next[f] = fields[f]
    cliamp = next
  }

  function ensureCliampDaemon() {
    Util.execDetached("pgrep -x cliamp >/dev/null || setsid cliamp -d >/dev/null 2>&1 &")
    cliampRefreshTimer.interval = 400
    cliampRefreshTimer.restart()
  }

  function haltCliamp() {
    if (!cliamp.online || !cliamp.playing) return false
    runCliamp(["pause"])
    patchCliamp({ playing: false })
    return true
  }

  function isPlaceholderTrackTitle(value) {
    if (MediaModel.isPlaceholderCliampTitle)
      return MediaModel.isPlaceholderCliampTitle(value)
    var t = String(value || "").trim().toLowerCase()
    return !t || t === "videoplayback" || t === "cliamp" || t === "index"
      || t === "channel" || t === "stream" || t === "audio" || t === "station"
      || t.indexOf("watch?v=") === 0 || t.indexOf("youtu.be/") === 0
  }

  function liveTrackTitle() {
    if (usingMpv) {
      var mt = String((mpv && mpv.title) || "").trim()
      if (mt && !isPlaceholderTrackTitle(mt)) return mt
      // Avoid showing raw watch URLs / paths as the transport title
      return ""
    }
    if (usingCliamp) return String((cliamp && cliamp.title) || "").trim()
    if (activePlayer) return String(MediaModel.displayTitle(activePlayer) || "").trim()
    return ""
  }

  function liveTrackArtist() {
    if (usingMpv) return ""
    if (usingCliamp) return String((cliamp && cliamp.artist) || "").trim()
    if (activePlayer) return String(MediaModel.displayArtist(activePlayer) || "").trim()
    return ""
  }

  function clearPlayOverrides() {
    playTitleOverride = ""
    playArtistOverride = ""
    playArtOverride = ""
    playPathOverride = ""
    playStreamOverride = false
    playFrequencyOverride = ""
    resolvedRadioFrequency = ""
    radioResolveKey = ""
  }

  // Fire-and-forget by default so sequential calls (save+hide) don't cancel each other.
  // capture:true runs via Process and applies the returned status JSON.
  function runVideoCtl(argvParts, capture) {
    var argv = [root.pluginScript("video-ctl.sh")].concat(argvParts || [])
    if (capture) {
      if (videoCtlProc.running) videoCtlProc.running = false
      videoCtlProc.command = argv
      videoCtlProc.running = true
    } else {
      Util.execArgv(argv)
    }
    return true
  }

  function applyMpvSnapshot(snap) {
    var wasOnline = !!(mpv && mpv.online)
    var previousPosition = Number(mpv && mpv.position) || 0
    var previousLength = Number(mpv && mpv.length) || 0
    var videoEnded = !!(mpv && mpv.playing && snap && !snap.playing
      && sourceNavIndex >= 0 && sourceNavIndex < sourceNavHits.length - 1
      && ((Number(snap.length) > 0 && Number(snap.position) >= Number(snap.length) - 2)
        || (previousLength > 0 && previousPosition >= previousLength - 2)))
    mpv = snap || MediaModel.emptyMpvSnapshot()
    if (snap && snap.subs !== undefined) videoSubs = !!snap.subs
    if (snap && snap.fullscreen !== undefined) videoFullscreen = !!snap.fullscreen
    if (snap && snap.loop !== undefined) mpvLoopMode = String(snap.loop || "no")
    if (snap && snap.geometry && typeof snap.geometry === "object") {
      var g = snap.geometry
      if (g.opacity !== undefined && isFinite(Number(g.opacity)))
        videoOpacity = Math.max(0.4, Math.min(1, Number(g.opacity)))
      if (g.clickThrough !== undefined) videoClickThrough = !!g.clickThrough
      if (g.aspectLock !== undefined) videoAspectLock = !!g.aspectLock
      if (g.lastPreset) videoPreset = String(g.lastPreset)
    }
    if (snap && snap.aspectLock !== undefined) videoAspectLock = !!snap.aspectLock
    if (snap && snap.clickThrough !== undefined) videoClickThrough = !!snap.clickThrough
    if (snap && snap.online && !videoPipDismissed)
      videoBackendActive = true
    if (videoEnded)
      Qt.callLater(function() { root.stepSourceHit(1) })
    if (snap && !snap.online && videoBackendActive && !videoPipDismissed) {
      // mpv quit from outside — drop backend so cliamp can take over cleanly
      videoBackendActive = false
    }
    // Leaving mpv: drop video-session overrides so the next live backend title shows.
    if (wasOnline && (!snap || !snap.online)) {
      var pathOv = String(playPathOverride || "")
      var wasVideoSession = MediaModel.isYoutubeUrl(pathOv)
        || MediaModel.pathHasVideoExt(pathOv)
        || (lastPlayedHit && MediaModel.hitIsVideo(lastPlayedHit) && !playStreamOverride)
      if (wasVideoSession) {
        playTitleOverride = ""
        playArtistOverride = ""
        playArtOverride = ""
        playPathOverride = ""
      }
    }
    // Promote a real mpv media-title once available (replace stubs OR prior track).
    if (snap && snap.online) {
      var mt = String(snap.title || "").trim()
      var snapPath = String(snap.path || "")
      var prevPath = String(playPathOverride || "")
      var pathChanged = !!(snapPath && prevPath && snapPath !== prevPath
        && snapPath.indexOf(prevPath) !== 0 && prevPath.indexOf(snapPath) !== 0)
      if (pathChanged) {
        // Playlist advance / new file — drop prior title/art immediately.
        playTitleOverride = (mt && !isPlaceholderTrackTitle(mt)) ? mt : ""
        playArtOverride = ""
        if (MediaModel.isYoutubeUrl(snapPath)) {
          var ym = snapPath.match(/[?&]v=([^&]+)/) || snapPath.match(/youtu\.be\/([^?&/]+)/)
          if (ym && ym[1])
            playArtOverride = "https://i.ytimg.com/vi/" + ym[1] + "/hqdefault.jpg"
        }
      } else if (mt && !isPlaceholderTrackTitle(mt)) {
        var ov = String(playTitleOverride || "").trim()
        if (!ov || isPlaceholderTrackTitle(ov) || ov.toLowerCase() !== mt.toLowerCase())
          playTitleOverride = mt
      }
      if (snapPath) playPathOverride = snapPath
    }
    positionTick++
  }

  function discoverCastTargets() {
    castBusy = true; castStatus = "Searching for Chromecast and DLNA devices…"
    castProc.mode = "discover"
    castProc.command = [root.pluginScript("cast-ctl.py"), "discover"]
    castProc.running = true
    return true
  }

  function castCurrent(target) {
    if (!target || !mediaPath) return false
    castBusy = true; castStatus = "Sending to " + String(target.name || "receiver")
    castProc.mode = "cast"
    castProc.command = [root.pluginScript("cast-ctl.py"), "cast", JSON.stringify(target),
      JSON.stringify({ path: String(mediaPath || ""), title: String(title || "Video"),
        artUrl: String(artUrl || ""), video: !!mediaIsVideo })]
    castProc.running = true
    return true
  }

  function setDualAudioEnabled(enabled) {
    dualAudioEnabled = !!enabled
    var next = {}; for (var k in (mediaSettings || {})) next[k] = mediaSettings[k]
    next.dualAudioEnabled = dualAudioEnabled
    mediaSettings = next; persistSettings()
    showOsd(dualAudioEnabled ? "Split YouTube audio enabled" : "Split YouTube audio disabled", "media")
    return true
  }

  function openExtraPiPCurrent() {
    var hit = resolveVideoPipHit()
    if (!hit) { showOsd("No video available for an extra PiP", "media"); return false }
    return openExtraPiP(hit)
  }

  function openExtraPiP(payload) {
    if (!payload || !MediaModel.hitIsVideo(payload)) return false
    var ids = (extraPipIds || []).slice()
    var id = ""
    for (var i = 2; i <= 4; i++) {
      var candidate = "p" + i
      if (ids.indexOf(candidate) < 0) { id = candidate; break }
    }
    if (!id) { showOsd("Up to three extra video windows are supported", "media"); return false }
    var idx = Number(id.substring(1)) - 2
    var params = { path: String(payload.path || ""), title: String(payload.title || ""),
      muted: true, instance: id, width: 320, height: 180,
      x: 24 + idx * 340, y: 100 + idx * 200 }
    if (!params.path) return false
    ids.push(id); extraPipIds = ids
    runVideoCtl(["play", JSON.stringify(params)], false)
    showOsd("Opened muted extra PiP", "media")
    return true
  }

  function closeExtraPiPs() {
    var ids = (extraPipIds || []).slice()
    for (var i = 0; i < ids.length; i++)
      runVideoCtl(["stop", JSON.stringify({ instance: ids[i] })], false)
    extraPipIds = []
    return true
  }

  function playVideoHit(payload, preserveAudio) {
    var path = String((payload && payload.path) || "")
    var title = String((payload && payload.title) || "")
    // Prefer durable YouTube watch URLs for mpv+ytdl.
    if (MediaModel.isYoutubeUrl(path)) {
      var m = path.match(/[?&]v=([^&]+)/) || path.match(/youtu\.be\/([^?&/]+)/)
      if (m) path = "https://www.youtube.com/watch?v=" + m[1]
    }
    if (!path) {
      showOsd("Nothing to play", "media")
      return false
    }
    if (!preserveAudio) haltCliamp()
    dualAudioActive = !!preserveAudio
    videoBackendActive = true
    videoPipDismissed = false
    preferredPlayerKey = "mpv"
    followMode = false
    // Reset overrides for this video session (don't keep prior track titles).
    playPathOverride = path
    playStreamOverride = false
    playFrequencyOverride = ""
    playTitleOverride = isPlaceholderTrackTitle(title) ? "" : title
    playArtistOverride = String((payload && payload.artist) || "")
    playArtOverride = String((payload && payload.artUrl) || "")
    if (!playArtOverride && MediaModel.isYoutubeUrl(path)) {
      var ym = path.match(/[?&]v=([^&]+)/) || path.match(/youtu\.be\/([^?&/]+)/)
      if (ym && ym[1])
        playArtOverride = "https://i.ytimg.com/vi/" + ym[1] + "/hqdefault.jpg"
    }
    lastPlayedHit = payload && typeof payload === "object" ? payload : lastPlayedHit
    lastVideoPath = path
    lastVideoTitle = isPlaceholderTrackTitle(title) ? "" : title
    lastVideoArt = String(playArtOverride || "")
    // Don't feed URL stubs into mpv force-media-title — ytdl will set the real name.
    var mpvTitle = isPlaceholderTrackTitle(title) ? "" : title
    applyMpvSnapshot(Object.assign({}, MediaModel.emptyMpvSnapshot(), {
      online: true, playing: true, paused: false, path: path, title: title || "Video"
    }))
    runVideoCtl(["play", JSON.stringify({ path: path, title: mpvTitle, muted: !!preserveAudio,
      start: Math.max(0, Number((payload && payload.startSeconds) || 0)) })], true)
    mpvPollTimer.interval = 400
    mpvPollTimer.restart()
    return true
  }

  function browserVideo(payloadJson) {
    var data
    try { data = JSON.parse(String(payloadJson || "{}")) } catch (e) { return "invalid-payload" }
    var path = String(data.url || "")
    if (!/^https:\/\//i.test(path) || !MediaModel.hitIsVideo({ path: path, video: true }))
      return "unsupported"
    if (String(playPathOverride || "") === path && videoBackendActive && mpv.online)
      return "ok"
    var provider = MediaModel.isYoutubeUrl(path) ? "youtube"
      : (MediaModel.isFacebookVideoUrl(path) ? "facebook"
        : (MediaModel.isXVideoUrl(path) ? "x"
          : (MediaModel.isTikTokVideoUrl(path) ? "tiktok" : "video")))
    var payload = { path: path, title: String(data.title || "Video").slice(0, 240),
      artUrl: String(data.poster || "").slice(0, 1500), provider: provider,
      kind: provider, video: true, startSeconds: Math.max(0, Number(data.startSeconds || 0)) }
    return playVideoHit(payload) ? "ok" : "unhandled"
  }

  function stopVideoBackend(quit) {
    videoBackendActive = false
    dualAudioActive = false
    // Always drop video-session overrides so titles/art follow the live backend.
    clearPlayOverrides()
    if (lastPlayedHit && MediaModel.hitIsVideo(lastPlayedHit)) {
      var cp = String((cliamp && cliamp.path) || "")
      var hp = String(lastPlayedHit.path || "")
      // Keep last hit only if cliamp is still on the same path (audio fallback).
      if (!cp || !hp || cp !== hp)
        lastPlayedHit = null
    }
    runVideoCtl(["stop", "{}"], !!quit)
    applyMpvSnapshot(MediaModel.emptyMpvSnapshot())
    mpvPollTimer.stop()
    return true
  }

  function dismissVideoPip() {
    videoPipDismissed = true
    // Single shell so geometry-save completes before hide.
    Util.execDetached(
      "CTL=" + JSON.stringify(root.pluginScript("video-ctl.sh"))
      + '; "$CTL" geometry-save "{}"; "$CTL" hide "{}"'
    )
    showOsd("Video PiP dismissed", "media")
    return true
  }

  function resolveVideoPipHit() {
    if (lastPlayedHit && MediaModel.hitIsVideo(lastPlayedHit))
      return lastPlayedHit
    var hit = currentHit()
    if (hit && MediaModel.hitIsVideo(hit))
      return hit
    var path = String(lastVideoPath || playPathOverride || (mpv && mpv.path)
      || mediaPath || (cliamp && cliamp.path) || "").trim()
    if (!path)
      return null
    if (!MediaModel.hitIsVideo({ path: path, provider: cliampActiveProvider || "" })
        && !MediaModel.isYoutubeUrl(path) && !MediaModel.pathHasVideoExt(path))
      return null
    return {
      path: path,
      title: String(lastVideoTitle || playTitleOverride || title || ""),
      artUrl: String(lastVideoArt || playArtOverride || artUrl || ""),
      provider: MediaModel.isYoutubeUrl(path) ? "youtube" : "local",
      kind: MediaModel.isYoutubeUrl(path) ? "youtube" : "local",
      video: true
    }
  }

  function reopenVideoPip() {
    var hit = resolveVideoPipHit()
    if (!hit) {
      showOsd("No video to show", "media")
      return false
    }
    videoPipDismissed = false
    videoBackendActive = true
    // mpv alive with this path — just bring the window back on-screen.
    var livePath = String((mpv && mpv.path) || "")
    var wantPath = String(hit.path || "")
    if (mpv && mpv.online && livePath && wantPath
        && (livePath === wantPath || livePath.indexOf(wantPath) === 0 || wantPath.indexOf(livePath) === 0)) {
      Util.execDetached(
        "CTL=" + JSON.stringify(root.pluginScript("video-ctl.sh"))
        + '; "$CTL" show "{}"; "$CTL" preset ' + JSON.stringify(JSON.stringify({ name: videoPreset || "S" }))
      )
      mpvPollTimer.restart()
      showOsd("Video PiP", "media")
      return true
    }
    // Start / restart video so the surface actually renders.
    return playVideoHit(hit)
  }

  function setVideoPreset(name) {
    videoPreset = String(name || "S")
    runVideoCtl(["preset", JSON.stringify({ name: videoPreset })], false)
    return true
  }

  function snapVideoCorner(corner) {
    runVideoCtl(["snap", JSON.stringify({ corner: corner || "br" })], false)
    return true
  }

  function setVideoOpacity(value) {
    videoOpacity = Math.max(0.4, Math.min(1, Number(value) || 1))
    runVideoCtl(["opacity", JSON.stringify({ value: videoOpacity })], false)
    return true
  }

  function setVideoClickThrough(enabled) {
    videoClickThrough = !!enabled
    runVideoCtl(["clickThrough", JSON.stringify({ enabled: videoClickThrough })], false)
    return true
  }

  function setVideoAspectLock(enabled) {
    videoAspectLock = !!enabled
    runVideoCtl(["aspectLock", JSON.stringify({ enabled: videoAspectLock })], false)
    return true
  }

  function toggleVideoAspectLock() {
    return setVideoAspectLock(!videoAspectLock)
  }

  function toggleVideoSubs() {
    runVideoCtl(["subs", JSON.stringify({ toggle: true })], true)
    videoSubs = !videoSubs
    return true
  }

  function setVideoFullscreen(enabled) {
    if (!(mpv && mpv.online)) {
      showOsd("No video window to fullscreen", "media")
      return false
    }
    videoFullscreen = !!enabled
    runVideoCtl(["fullscreen", JSON.stringify({ enabled: videoFullscreen })], true)
    return true
  }

  function toggleVideoFullscreen() {
    return setVideoFullscreen(!videoFullscreen)
  }

  function pauseVideoForLock() {
    if (!(mpv && mpv.online) || !mpv.playing) return false
    runVideoCtl(["pause", "{}"], false)
    applyMpvSnapshot(Object.assign({}, mpv, { playing: false, paused: true }))
    return true
  }

  function probeFfprobe(path) {
    var p = String(path || "").trim()
    if (!p || p.indexOf("://") !== -1) return false
    if (ffprobeCache[p] === true || ffprobeCache[p] === false) return true
    if (ffprobeProc.running) return false
    ffprobeProc.command = [
      root.pluginScript("video-ctl.sh"),
      "ffprobe",
      JSON.stringify({ path: p })
    ]
    ffprobeProc.running = true
    return true
  }

  function restoreVideoPrefsFromDisk() {
    // Pull opacity / click-through / aspect / preset from video-pip.json via status.
    runVideoCtl(["status", "{}"], true)
  }

  function playCliamp() {
    ensureCliampDaemon()
    var path = String(playPathOverride || (cliamp && cliamp.path) || "")
    var stream = !!(playStreamOverride || (cliamp && cliamp.stream))
    // radio.garden: after pause, plain `cliamp play` can leave the stream stopped.
    // Reload the URL the same way play-search-result does.
    if (stream && path && path.indexOf("radio.garden") !== -1 && !cliamp.playing) {
      Util.execArgv([
        "cliamp", "remote", "call", "url.load",
        "--params", JSON.stringify({ path: path, play: true }),
        "--wait"
      ])
      patchCliamp({ playing: true, stopped: false, path: path, stream: true })
      cliampRefreshTimer.interval = 400
      cliampRefreshTimer.restart()
      return true
    }
    runCliamp(["play"])
    patchCliamp({ playing: true, stopped: false })
    return true
  }

  function launchFavorite(id) {
    var favorites = MediaModel.favoriteDefs()
    for (var i = 0; i < favorites.length; i++) {
      var fav = favorites[i]
      if (fav.id !== id) continue
      if (fav.id === "cliamp") {
        pendingFavoritePin = "cliamp"
        preferredPlayerKey = "cliamp"
        followMode = false
        ensureCliampDaemon()
        Qt.callLater(function() { root.runCliamp(["play"]) })
        showOsd("Opening cliamp", "media")
        rebuildSourceEntries()
        return true
      }
      // Drawer-only sources (Spotify/YouTube/…) have empty launch — open their hub instead.
      if (!fav.launch) {
        if (MediaModel.hubDefById(fav.id))
          return openHub(fav.id)
        return false
      }
      Util.execDetached(fav.launch)
      preferredPlayerKey = ""
      followMode = true
      // Pin once the app registers MPRIS.
      pendingFavoritePin = fav.id
      showOsd("Opening " + fav.label, "media")
      return true
    }
    return false
  }

  property string pendingFavoritePin: ""

  function activateSource(entryOrId) {
    var entry = entryOrId
    if (typeof entryOrId === "string") {
      var list = sourceEntries
      entry = null
      for (var i = 0; i < list.length; i++) {
        if (list[i].id === entryOrId) { entry = list[i]; break }
      }
    }
    if (!entry) return false

    if (entry.bridge === "cliamp" || entry.id === "cliamp") {
      if (!cliamp.online) return launchFavorite("cliamp")
      preferredPlayerKey = "cliamp"
      followMode = false
      pendingFavoritePin = ""
      clearPlayOverrides()
      if (usingMpv || (mpv && mpv.online)) stopVideoBackend(false)
      // Stop other players, then resume cliamp.
      for (var j = 0; j < players.length; j++) {
        if (players[j] && players[j].isPlaying) haltPlayer(players[j])
      }
      if (!cliamp.playing) playCliamp()
      rebuildSourceEntries()
      showOsd(cliamp.title || "cliamp", "media-source")
      return true
    }

    if (entry.playerKey) {
      return selectPlayer(entry.playerKey, true)
    }

    return launchFavorite(entry.id)
  }

  function showOsd(actionLabel, iconName, player) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName || "media",
      message: osdMessage(player || activePlayer, actionLabel)
    }))
  }

  function scheduleOsd(actionLabel, iconName, player, waitForTrackChange, beforeTrackSignature) {
    if (waitForTrackChange) {
      pendingTrackOsd = {
        actionLabel: actionLabel,
        iconName: iconName,
        player: player,
        playerKey: playerKey(player),
        before: beforeTrackSignature,
        attempts: 0
      }
      trackOsdTimer.restart()
    } else {
      Qt.callLater(function() { root.showOsd(actionLabel, iconName, player) })
    }
  }

  function flushPendingTrackOsd(force) {
    var pending = pendingTrackOsd
    if (!pending) return

    var player = playerForKey(pending.playerKey) || pending.player
    if (force || MediaModel.trackChanged(pending.before, player) || pending.attempts >= 10) {
      pendingTrackOsd = null
      trackOsdTimer.stop()
      root.showOsd(pending.actionLabel, pending.iconName, player)
      return
    }

    pending.attempts = pending.attempts + 1
    pendingTrackOsd = pending
    trackOsdTimer.restart()
  }

  function selectPlayer(key, transferPlayback) {
    var player = playerForKey(key)
    if (!player || !isListablePlayer(player)) return false
    var nextKey = playerKey(player)
    preferredPlayerKey = nextKey
    followMode = false
    pendingFavoritePin = ""
    // Leaving cliamp/mpv — drop hit overrides so MPRIS title shows immediately.
    clearPlayOverrides()
    if (usingMpv) stopVideoBackend(false)
    if (transferPlayback !== false) {
      haltCliamp()
      transferPlaybackTo(player)
    }
    rebuildSourceEntries()
    return true
  }

  function followPlaying() {
    followMode = true
    preferredPlayerKey = ""
    pendingFavoritePin = ""
    clearPlayOverrides()
    rebuildSourceEntries()
    return true
  }

  function playPlayer(player) {
    if (!player) return false
    if (player.canPlay) {
      player.play()
      return true
    }
    if (player.canTogglePlaying && !player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  // Prefer pause so the source can resume mid-track when selected again.
  // Fall back to stop when pause isn't supported (some browser radios).
  function haltPlayer(player) {
    if (!player) return false
    if (pausePlayer(player)) return true
    try {
      if (typeof player.stop === "function") {
        player.stop()
        return true
      }
    } catch (e) {}
    return false
  }

  function transferPlaybackTo(next) {
    if (!next) return false
    var nextKey = playerKey(next)
    haltCliamp()
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || playerKey(p) === nextKey) continue
      if (p.isPlaying) haltPlayer(p)
    }
    if (!next.isPlaying) playPlayer(next)
    return true
  }

  function switchSource(delta, transferPlayback, showFeedback) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) {
        index = i
        break
      }
    }

    index = (index + delta + list.length) % list.length
    var next = list[index]
    var nextKey = playerKey(next)

    preferredPlayerKey = nextKey
    followMode = false
    clearPlayOverrides()
    if (usingMpv && nextKey !== "mpv") stopVideoBackend(false)

    if (transferPlayback !== false) transferPlaybackTo(next)

    if (showFeedback !== false) Qt.callLater(function() {
      root.showOsd("Source", "media-source", next)
    })

    return true
  }

  function playerForAction(action, targetKey) {
    var targeted = playerForKey(targetKey)
    if (targeted) return targeted

    if (action === "pause" || action === "playPause") {
      var oldest = oldestPlayingPlayer(true) || oldestPlayingPlayer(false)
      if (oldest) return oldest
    }

    if (canHandleAction(activePlayer, action)) return activePlayer

    var list = sourcePlayers
    for (var i = 0; i < list.length; i++) {
      if (canHandleAction(list[i], action)) return list[i]
    }

    return activePlayer
  }

  function setPosition(seconds, showFeedback, targetKey) {
    var next = Math.max(0, MediaModel.mediaSeconds(seconds))
    if (usingMpv || targetKey === "mpv") {
      if (!mpv.online) return false
      var mlen = Number(mpv.length) || 0
      if (mlen > 0) next = Math.min(mlen, next)
      runVideoCtl(["seek", JSON.stringify({ value: next, absolute: true })], false)
      if (dualAudioActive) runCtl(["seek-absolute", JSON.stringify({ value: next })])
      var msnap = {}
      for (var mk in mpv) msnap[mk] = mpv[mk]
      msnap.position = next
      mpv = msnap
      positionTick++
      if (showFeedback) showOsd("Seek", "media")
      return true
    }
    if (usingCliamp || targetKey === "cliamp") {
      if (!cliamp.online || !cliamp.seekable) return false
      var len = MediaModel.mediaSeconds(cliamp.length)
      if (len > 0) next = Math.min(len, next)
      var snap = {}
      for (var k in cliamp) snap[k] = cliamp[k]
      snap.position = next
      cliamp = snap
      positionTick++
      root.runCtl(["seek-absolute", JSON.stringify({ value: next })])
      if (showFeedback) showOsd("Seek", "media")
      cliampRefreshTimer.interval = 350
      cliampRefreshTimer.restart()
      return true
    }
    var player = playerForAction("setPosition", targetKey)
    if (!canHandleAction(player, "setPosition")) return false
    var length = MediaModel.mediaSeconds(player.length)
    next = Math.max(0, Math.min(length, next))
    // If Quickshell stores microseconds, write back in the same unit the player uses.
    var rawLength = Number(player.length)
    var value = (rawLength > 100000) ? next * 1000000 : next
    player.position = value
    positionTick++
    if (showFeedback) showOsd("Seek", "media", player)
    return true
  }

  function seekBy(offsetSeconds, showFeedback, targetKey) {
    if (usingMpv || targetKey === "mpv") {
      if (!mpv.online) return false
      var mcur = Number(mpv.position) || 0
      return setPosition(mcur + offsetSeconds, showFeedback, "mpv")
    }
    if (usingCliamp || targetKey === "cliamp") {
      if (!cliamp.online || !cliamp.seekable) return false
      var cur = MediaModel.mediaSeconds(cliamp.position)
      return setPosition(cur + offsetSeconds, showFeedback, "cliamp")
    }
    var player = playerForAction("seek", targetKey)
    if (!canHandleAction(player, "seek")) return false
    var current = MediaModel.mediaSeconds(player.position)
    return setPosition(current + offsetSeconds, showFeedback, playerKey(player))
  }

  function runCtl(argvParts) {
    if (!argvParts || !argvParts.length) return false
    var q = (ctlQueue || []).slice()
    q.push(argvParts)
    ctlQueue = q
    root.pumpCtlQueue()
    return true
  }

  function pumpCtlQueue() {
    if (ctlBusy || ctlProc.running) return
    var q = ctlQueue || []
    if (!q.length) return
    var next = q[0]
    ctlQueue = q.slice(1)
    ctlBusy = true
    ctlProc.command = [root.pluginScript("cliamp-ctl.sh")].concat(next)
    ctlProc.running = true
  }

  function setVolume(value, showFeedback, targetKey) {
    var next = Math.max(0, Math.min(1, Number(value)))
    if (!isFinite(next)) next = 0
    var mode = MediaModel.volumeModeNormalize(volumeMode)

    function setSystem(v) {
      if (!systemVolumeReady) return false
      if (systemVolumeSink.audio.muted && v > 0.001)
        systemVolumeSink.audio.muted = false
      systemVolumeSink.audio.volume = v
      return true
    }
    function setPlayer(v) {
      if (usingMpv || targetKey === "mpv") {
        var msnap = {}
        for (var mk in mpv) msnap[mk] = mpv[mk]
        msnap.volume = v
        mpv = msnap
        root.runVideoCtl(["volume", JSON.stringify({ value: v })], false)
        return true
      }
      if (usingCliamp || targetKey === "cliamp") {
        var snap = {}
        for (var k in cliamp) snap[k] = cliamp[k]
        snap.volume = v
        cliamp = snap
        root.runCtl(["volume", JSON.stringify({ value: v })])
        return true
      }
      var player = playerForAction("setVolume", targetKey)
      if (!canHandleAction(player, "setVolume")) return false
      player.volume = v
      return true
    }

    var ok = false
    if (mode === "system") {
      ok = setSystem(next)
      if (ok) root.ensureCliampUnityGain()
      if (!ok) ok = setPlayer(next)
    } else if (mode === "linked") {
      var a = setSystem(next)
      var b = setPlayer(next)
      ok = a || b
    } else {
      ok = setPlayer(next)
      if (!ok) ok = setSystem(next)
    }

    if (ok && showFeedback && shell) {
      shell.summon("omarchy.osd", JSON.stringify({
        icon: next <= 0.001 ? "volume-muted" : "volume",
        value: Math.round(next * 100)
      }))
    }
    return ok
  }

  function setVolumeMode(mode) {
    volumeMode = MediaModel.volumeModeNormalize(mode)
    var src = mediaSettings || {}
    var next = {}
    for (var k in src) next[k] = src[k]
    next.volumeMode = volumeMode
    mediaSettings = next
    persistSettings()
    if (volumeMode === "system") root.ensureCliampUnityGain()
    showOsd("Volume · " + volumeMode, "media")
    return true
  }

  function toggleMute(showFeedback) {
    var mode = MediaModel.volumeModeNormalize(volumeMode)
    if ((mode === "system" || mode === "linked") && systemVolumeReady) {
      systemVolumeSink.audio.muted = !systemVolumeSink.audio.muted
      if (showFeedback !== false && shell) {
        var muted = !!systemVolumeSink.audio.muted
        shell.summon("omarchy.osd", JSON.stringify({
          icon: muted ? "volume-muted" : "volume",
          value: muted ? 0 : Math.round(systemVolume * 100)
        }))
      }
      return true
    }
    if (mediaVolume > 0.001)
      return setVolume(0, showFeedback !== false)
    return setVolume(MediaModel.cliampDbToLinear(0), showFeedback !== false)
  }

  // cliamp's own gain stacks with PipeWire; pin it at 0 dB (unity) so the
  // media slider and keyboard volume are the same control (system/linked modes).
  function ensureCliampUnityGain() {
    var mode = MediaModel.volumeModeNormalize(volumeMode)
    if (mode === "player") return false
    if (!cliamp || !cliamp.online) return false
    var target = MediaModel.cliampDbToLinear(0)
    var cur = Number(cliamp.volume)
    if (!isFinite(cur)) cur = target
    if (Math.abs(cur - target) < 0.03) {
      cliampUnityGainArmed = true
      return false
    }
    root.runCtl(["volume", JSON.stringify({ value: target })])
    var snap = {}
    for (var k in cliamp) snap[k] = cliamp[k]
    snap.volume = target
    cliamp = snap
    cliampUnityGainArmed = true
    return true
  }

  function resolveVolumeSink() {
    if (!volumeSinkProc.running) volumeSinkProc.running = true
  }

  function toggleShuffle(showFeedback, targetKey) {
    if (usingCliamp || targetKey === "cliamp") {
      var nextShuffle = !cliamp.shuffle
      var next = {}
      for (var k in cliamp) next[k] = cliamp[k]
      next.shuffle = nextShuffle
      cliamp = next
      root.runCtl(["shuffle", JSON.stringify({ name: nextShuffle ? "on" : "off" })])
      cliampRefreshTimer.interval = 350
      cliampRefreshTimer.restart()
      if (showFeedback !== false) showOsd(nextShuffle ? "Shuffle on" : "Shuffle off", "media")
      return true
    }
    var player = playerForAction("toggleShuffle", targetKey)
    if (!canHandleAction(player, "toggleShuffle")) return false
    player.shuffle = !player.shuffle
    if (showFeedback !== false) showOsd(player.shuffle ? "Shuffle on" : "Shuffle off", "media", player)
    return true
  }

  function cycleLoop(showFeedback, targetKey) {
    if (usingMpv || targetKey === "mpv") {
      if (!mpv.online) return false
      runVideoCtl(["loop", JSON.stringify({ mode: "toggle" })], true)
      var next = (String(mpvLoopMode || "no").toLowerCase() === "inf"
        || String(mpvLoopMode || "no").toLowerCase() === "yes") ? "no" : "inf"
      mpvLoopMode = next
      applyMpvSnapshot(Object.assign({}, mpv, { loop: next }))
      if (showFeedback !== false)
        showOsd(next === "inf" ? "Repeat one" : "Repeat off", "media")
      return true
    }
    if (usingCliamp || targetKey === "cliamp") {
      var cur = String(cliamp.repeat || "Off").toLowerCase()
      var nextMode = "one"
      var label = "Repeat one"
      if (cur === "off" || cur === "none" || cur === "") {
        nextMode = "one"
        label = "Repeat one"
      } else if (cur === "one" || cur === "track") {
        nextMode = "all"
        label = "Repeat all"
      } else {
        nextMode = "off"
        label = "Repeat off"
      }
      var next = {}
      for (var k in cliamp) next[k] = cliamp[k]
      next.repeat = nextMode === "one" ? "One" : (nextMode === "all" ? "All" : "Off")
      cliamp = next
      root.runCtl(["repeat", JSON.stringify({ name: nextMode })])
      cliampRefreshTimer.interval = 350
      cliampRefreshTimer.restart()
      if (showFeedback !== false) showOsd(label, "media")
      return true
    }
    var player = playerForAction("cycleLoop", targetKey)
    if (!canHandleAction(player, "cycleLoop")) return false
    var current = player.loopState
    var next = MprisLoopState.None
    var label = "Repeat off"
    if (current === MprisLoopState.None) {
      next = MprisLoopState.Track
      label = "Repeat one"
    } else if (current === MprisLoopState.Track) {
      next = MprisLoopState.Playlist
      label = "Repeat all"
    } else {
      next = MprisLoopState.None
      label = "Repeat off"
    }
    player.loopState = next
    if (showFeedback !== false) showOsd(label, "media", player)
    return true
  }

  function runAction(action, showFeedback, targetKey) {
    if (action === "setPosition" || action === "seek" || action === "setVolume"
        || action === "toggleShuffle" || action === "cycleLoop" || action === "followPlaying") {
      if (action === "followPlaying") return followPlaying()
      if (action === "toggleShuffle") return toggleShuffle(showFeedback, targetKey)
      if (action === "cycleLoop") return cycleLoop(showFeedback, targetKey)
      return false
    }

    // mpv video PiP bridge
    if (usingMpv || targetKey === "mpv") {
      if (!mpv.online && action !== "play") return false
      var mvHandled = false
      var mvLabel = "Play/pause"
      var mvIcon = "media"
      if (action === "next") {
        if (stepSourceHit(1)) {
          mvLabel = "Next video"; mvIcon = "media-next"
          mvHandled = true
        } else if (Number(mpv.playlistCount || 0) > 1) {
          runVideoCtl(["playlistNext", "{}"], true)
          mvLabel = "Next video"; mvIcon = "media-next"
          mvHandled = true
        } else {
          // Seek +60s as chapter-less next for single-file video.
          seekBy(60, false, "mpv"); mvLabel = "Skip +60s"; mvIcon = "media-next"
          mvHandled = true
        }
      } else if (action === "previous") {
        var pos = Number(mpv.position || 0)
        if (stepSourceHit(-1)) {
          mvLabel = "Previous video"; mvIcon = "media-previous"
          mvHandled = true
        } else if (Number(mpv.playlistCount || 0) > 1 && pos < 3) {
          runVideoCtl(["playlistPrev", "{}"], true)
          mvLabel = "Previous video"; mvIcon = "media-previous"
          mvHandled = true
        } else {
          seekBy(-10, false, "mpv"); mvLabel = "Back 10s"; mvIcon = "media-previous"
          mvHandled = true
        }
      } else if (action === "play") {
        runVideoCtl(["resume", "{}"], false)
        if (dualAudioActive) runCtl(["play"])
        mvHandled = true; mvLabel = "Play"; mvIcon = "media-play"
        applyMpvSnapshot(Object.assign({}, mpv, { playing: true, paused: false }))
      } else if (action === "pause") {
        runVideoCtl(["pause", "{}"], false)
        if (dualAudioActive) runCtl(["pause"])
        mvHandled = true; mvLabel = "Pause"; mvIcon = "media-pause"
        applyMpvSnapshot(Object.assign({}, mpv, { playing: false, paused: true }))
      } else if (action === "playPause") {
        if (mpv.playing) {
          runVideoCtl(["pause", "{}"], false)
          if (dualAudioActive) runCtl(["pause"])
          applyMpvSnapshot(Object.assign({}, mpv, { playing: false, paused: true }))
          mvLabel = "Pause"; mvIcon = "media-pause"
        } else {
          runVideoCtl(["resume", "{}"], false)
          if (dualAudioActive) runCtl(["play"])
          applyMpvSnapshot(Object.assign({}, mpv, { playing: true, paused: false }))
          mvLabel = "Play"; mvIcon = "media-play"
        }
        mvHandled = true
      }
      if (mvHandled) {
        preferredPlayerKey = "mpv"
        followMode = false
        videoBackendActive = true
        if (showFeedback !== false) showOsd(mvLabel, mvIcon)
        mpvPollTimer.restart()
        return true
      }
      return false
    }

    // cliamp bridge transport
    if (usingCliamp || targetKey === "cliamp") {
      if (!cliamp.online && action !== "play") return false
      var handledBridge = false
      var bridgeLabel = "Play/pause"
      var bridgeIcon = "media"
      if (action === "next") {
        handledBridge = stepSourceHit(1)
        if (!handledBridge) { runCliamp(["next"]); handledBridge = true }
        bridgeLabel = "Next"; bridgeIcon = "media-next"
      } else if (action === "previous") {
        handledBridge = stepSourceHit(-1)
        if (!handledBridge) { runCliamp(["prev"]); handledBridge = true }
        bridgeLabel = "Previous"; bridgeIcon = "media-previous"
      } else if (action === "play") {
        playCliamp(); handledBridge = true; bridgeLabel = "Play"; bridgeIcon = "media-play"
      } else if (action === "pause") {
        runCliamp(["pause"])
        patchCliamp({ playing: false })
        handledBridge = true
        bridgeLabel = "Pause"
        bridgeIcon = "media-pause"
      } else if (action === "playPause") {
        if (cliamp.playing) {
          runCliamp(["pause"])
          patchCliamp({ playing: false })
          bridgeLabel = "Pause"
          bridgeIcon = "media-pause"
        } else {
          playCliamp()
          bridgeLabel = "Play"
          bridgeIcon = "media-play"
        }
        handledBridge = true
      }
      if (handledBridge) {
        preferredPlayerKey = "cliamp"
        followMode = false
        if (showFeedback !== false) showOsd(bridgeLabel, bridgeIcon)
        return true
      }
      return false
    }

    var player = playerForAction(action, targetKey)
    var key = playerKey(player)
    var actionLabel = "Play/pause"
    var iconName = "media"
    var beforeTrackSignature = trackSignature(player)
    var handled = false

    if (action === "next") {
      actionLabel = "Next"
      iconName = "media-next"
      if (player && player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      actionLabel = "Previous"
      iconName = "media-previous"
      if (player && player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      actionLabel = "Play"
      iconName = "media-play"
      if (player && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      actionLabel = "Pause"
      iconName = "media-pause"
      if (player && player.canPause) {
        player.pause()
        handled = true
      } else if (player && player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "playPause") {
      actionLabel = player && player.isPlaying ? "Pause" : "Play"
      iconName = player && player.isPlaying ? "media-pause" : "media-play"
      if (player && player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (player && !player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    }

    // Transport should not pin away from auto-follow.
    if (handled && key && !followMode) preferredPlayerKey = key
    if (showFeedback !== false)
      scheduleOsd(actionLabel, iconName, player, handled && (action === "next" || action === "previous"), beforeTrackSignature)
    return handled
  }

  function maybePinPendingFavorite() {
    if (!pendingFavoritePin) return
    var pin = pendingFavoritePin
    var fav = null
    var favorites = MediaModel.favoriteDefs()
    for (var i = 0; i < favorites.length; i++) {
      if (favorites[i].id === pin) { fav = favorites[i]; break }
    }
    if (!fav) fav = MediaModel.hubDefById(pin)
    if (!fav) { pendingFavoritePin = ""; return }
    var matched = findPlayerForFavorite(fav)
    if (matched) {
      selectPlayer(playerKey(matched), true)
      pendingFavoritePin = ""
      rebuildHubEntries()
    }
  }

  function applyCliampSnapshot(snap) {
    var wasOnline = !!cliamp.online
    var trackEnded = !!(cliamp.playing && snap && snap.online && !snap.playing
      && snap.stopped && !snap.stream && Number(snap.length) > 0)
    var prevRev = lastPlaylistRevision
    cliamp = snap
    if (trackEnded && sourceNavIndex >= 0 && sourceNavIndex < sourceNavHits.length - 1)
      Qt.callLater(function() { root.stepSourceHit(1) })
    if (snap && snap.online) {
      if (snap.speed && Math.abs(Number(snap.speed) - playbackSpeed) > 0.001)
        playbackSpeed = Number(snap.speed) || playbackSpeed
      if (snap.eqPreset)
        eqPreset = String(snap.eqPreset || eqPreset)
      if (snap.device)
        activeAudioDevice = String(snap.device)
      var rev = Number(snap.playlistRevision || 0) || 0
      if (rev !== prevRev || queueItems.length === 0) {
        lastPlaylistRevision = rev
        Qt.callLater(function() { root.loadQueue() })
      }
      // One volume with the OS — don't leave cliamp gain stacked.
      if (!cliampUnityGainArmed || !wasOnline)
        Qt.callLater(function() { root.ensureCliampUnityGain() })
    } else if (!snap || !snap.online) {
      queueItems = []
      queueIndex = -1
      queueTotal = 0
      queueTick++
      lastPlaylistRevision = -1
      cliampUnityGainArmed = false
    }
    // yt-dlp CDN streams report "videoplayback" — keep search-hit overrides until a real title appears.
    if (playTitleOverride) {
      var t = String(snap.title || "").trim()
      var isPlaceholder = isPlaceholderTrackTitle(t)
      if (!isPlaceholder && t.toLowerCase() !== playTitleOverride.toLowerCase()) {
        playTitleOverride = ""
        playArtistOverride = ""
        playArtOverride = ""
        // Keep path/stream/frequency — still describe the same play session.
      } else if (!isPlaceholder && t) {
        // Live title caught up to override — drop override so future switches track live.
        playTitleOverride = ""
        if (snap.artist) playArtistOverride = ""
        if (snap.artUrl) playArtOverride = ""
      }
    }
    // Live radio.garden streams often only report title "channel" — resolve dial metadata.
    if (snap && snap.online && (snap.stream || playStreamOverride)) {
      var pathNow = String(playPathOverride || snap.path || "")
      var cid = MediaModel.gardenChannelIdFromPath(pathNow)
      var resolveKey = cid || (pathNow.indexOf("radio.garden") >= 0 ? pathNow : "")
      if (resolveKey && resolveKey !== radioResolveKey) {
        radioResolveKey = resolveKey
        // Clear stale dial from the previous station until resolve returns.
        if (!playFrequencyOverride || MediaModel.gardenChannelIdFromPath(playPathOverride) !== cid) {
          resolvedRadioFrequency = ""
          if (cid && playFrequencyOverride) {
            var prevCid = MediaModel.gardenChannelIdFromPath(playPathOverride)
            if (prevCid && prevCid !== cid) playFrequencyOverride = ""
          }
        }
        Qt.callLater(function() { root.resolveRadioChannel(resolveKey) })
      }
    } else if (!snap || !snap.stream) {
      if (!playStreamOverride) {
        resolvedRadioFrequency = ""
        radioResolveKey = ""
      }
    }
    // A transient cliamp disconnect does not cancel the user's source choice.
    if ((!wasOnline || pendingFavoritePin === "cliamp") && snap.online && (preferredPlayerKey === "cliamp" || pendingFavoritePin === "cliamp")) {
      preferredPlayerKey = "cliamp"
      followMode = false
      pendingFavoritePin = ""
      for (var i = 0; i < players.length; i++) {
        if (players[i] && players[i].isPlaying) haltPlayer(players[i])
      }
      if (!snap.playing && !pendingProviderSwitch) playCliamp()
      refreshCliampProviders()
      if (pendingProviderSwitch) {
        var nextProv = pendingProviderSwitch
        pendingProviderSwitch = ""
        Qt.callLater(function() { root.selectCliampProvider(nextProv) })
      }
    }
    if (snap.provider) cliampActiveProvider = snap.provider
    rebuildSourceEntries()
    if (snap.online) refreshCliampProviders()
  }

  function applyCliampProviderList(text) {
    cliampConfiguredProviders = MediaModel.parseCliampProviderList(text)
    rebuildProviderEntries()
  }

  Component.onCompleted: {
    root.syncPlayingOrder()
    root.rebuildSourceEntries()
    root.rebuildProviderEntries()
    root.pinnedHubIds = root.defaultPinnedHubIds()
    root.rebuildHubEntries()
    root.loadPinnedHubs()
    root.loadSearchHistory()
    root.loadLibrary()
    root.loadDownloads()
    root.loadSettings()
    root.refreshAudioDevices()
    root.refreshEqPresets()
    root.loadQueue()
    root.resolveVolumeSink()
    // Scrub legacy state files from the plugin dir — writes there trigger
    // Omarchy's inotify reload and destroy the open drawer mid-use.
    legacyScrubProc.running = true
    cliampProbe.running = true
    cliampEventsProc.running = true
    mpvProbe.running = true
    Qt.callLater(function() { root.restoreVideoPrefsFromDisk() })
  }

  // Pause video when the session lock engages (don't keep decoding under lock).
  readonly property var lockService: shell ? shell.firstPartyServiceFor("omarchy.lock") : null
  Connections {
    target: root.lockService
    enabled: !!root.lockService
    function onLockedChanged() {
      if (root.lockService && root.lockService.locked)
        root.pauseVideoForLock()
    }
  }

  // Pause video when idle / screensaver cycle starts.
  readonly property var idleService: shell ? shell.firstPartyServiceFor("omarchy.idle") : null
  Connections {
    target: root.idleService
    enabled: !!root.idleService
    function onIdledThisCycleChanged() {
      if (root.idleService && root.idleService.idledThisCycle)
        root.pauseVideoForLock()
    }
    function onScreensaverStartedThisCycleChanged() {
      if (root.idleService && root.idleService.screensaverStartedThisCycle)
        root.pauseVideoForLock()
    }
  }

  onDefaultAudioSinkChanged: root.resolveVolumeSink()
  onUsingCliampChanged: {
    if (usingCliamp) Qt.callLater(function() { root.ensureCliampUnityGain() })
  }
  onPlayersChanged: {
    root.syncPlayingOrder()
    root.maybePinPendingFavorite()
    root.rebuildSourceEntries()
  }
  onPreferredPlayerKeyChanged: root.rebuildSourceEntries()
  onFollowModeChanged: root.rebuildSourceEntries()

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() {
        root.syncPlayingOrder()
        if (modelData && modelData.isPlaying) root.handlePlayerStarted(modelData)
        root.rebuildSourceEntries()
      }
      function onTrackTitleChanged() {
        if (modelData && modelData.isPlaying) root.handlePlayerStarted(modelData)
        root.rebuildSourceEntries()
      }
      function onTrackArtistChanged() {
        if (modelData && modelData.isPlaying) root.handlePlayerStarted(modelData)
      }
    }
  }

  Process {
    id: activeWindowProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.updateActiveWindow(JSON.parse(String(text || "{}"))) }
        catch (e) { root.updateActiveWindow({}) }
      }
    }
  }

  Timer {
    interval: 300
    repeat: true
    running: true
    onTriggered: if (!activeWindowProc.running) activeWindowProc.running = true
  }

  Timer {
    id: trackOsdTimer
    interval: 120
    repeat: false
    onTriggered: root.flushPendingTrackOsd(false)
  }

  Timer {
    id: positionTimer
    interval: 500
    repeat: true
    running: root.usingMpv
      ? !!root.mpv.playing
      : (root.usingCliamp
        ? !!root.cliamp.playing
        : !!(root.activePlayer && root.activePlayer.isPlaying && root.activePlayer.positionSupported))
    onTriggered: root.positionTick++
  }

  Timer {
    id: mpvPollTimer
    interval: 1500
    repeat: true
    running: root.videoBackendActive || !!(root.mpv && root.mpv.online)
    onTriggered: {
      interval = root.mpv.playing ? 1000 : 2500
      if (!mpvProbe.running) mpvProbe.running = true
    }
  }

  Process {
    id: mpvProbe
    command: [root.pluginScript("video-ctl.sh"), "status", "{}"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applyMpvSnapshot(MediaModel.parseMpvStatus(text))
      }
    }
  }

  Process {
    id: videoCtlProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var snap = MediaModel.parseMpvStatus(text)
        if (snap && (snap.online || snap.path || snap.title))
          root.applyMpvSnapshot(snap)
        else {
          // Non-status ops may return {ok,subs,...} — merge lightly
          try {
            var data = JSON.parse(String(text || "{}")) || {}
            if (data.subs !== undefined) root.videoSubs = !!data.subs
            if (data.playing !== undefined || data.online !== undefined)
              root.applyMpvSnapshot(MediaModel.parseMpvStatus(text))
          } catch (e) {}
        }
      }
    }
    onExited: function() {
      if (!mpvProbe.running) mpvProbe.running = true
    }
  }

  Process {
    id: ffprobeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}")) || {}
          var p = String(data.path || "")
          if (!p || data.video === null || data.video === undefined) return
          var next = Object.assign({}, root.ffprobeCache)
          next[p] = !!data.video
          root.ffprobeCache = next
        } catch (e) {}
      }
    }
  }

  Timer {
    id: cliampPollTimer
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      // When event stream is healthy, poll infrequently as a safety net.
      interval = root.cliampEventsActive ? 15000 : 2000
      if (!cliampProbe.running) cliampProbe.running = true
      if (root.cliamp.online && !providerListProc.running) providerListProc.running = true
      if (!cliampEventsProc.running) cliampEventsProc.running = true
    }
  }

  Timer {
    id: cliampRefreshTimer
    interval: 500
    repeat: false
    onTriggered: {
      cliampPollTimer.interval = 2000
      if (!cliampProbe.running) cliampProbe.running = true
    }
  }

  Process {
    id: cliampProbe
    command: ["cliamp", "remote", "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.cliampProbeFails = 0
        root.applyCliampSnapshot(MediaModel.parseCliampRemoteState(text))
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.cliampProbeFails = 0
        return
      }
      // Keep last good snapshot through brief flaky IPC; clear only after 3 fails.
      root.cliampProbeFails = Number(root.cliampProbeFails || 0) + 1
      if (root.cliampProbeFails >= 3)
        root.applyCliampSnapshot(MediaModel.emptyCliampSnapshot())
    }
  }

  Process {
    id: providerListProc
    command: ["cliamp", "remote", "call", "provider.list", "--wait"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCliampProviderList(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.rebuildProviderEntries()
    }
  }

  Process {
    id: providerSwitchProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || ""))
          if (data && data.ok && data.provider) {
            root.cliampActiveProvider = String(data.provider)
            root.pendingProviderSwitch = ""
            root.rebuildProviderEntries()
          }
        } catch (e) {}
        cliampRefreshTimer.restart()
        if (root.pendingHubSearchRestore) {
          var restoreId = root.pendingHubSearchRestore
          root.pendingHubSearchRestore = ""
          if (root.activeHubId === restoreId)
            root.restoreHubSearch(restoreId)
        }
      }
    }
    onExited: function() {
      cliampRefreshTimer.restart()
      if (root.pendingHubSearchRestore) {
        var restoreId = root.pendingHubSearchRestore
        root.pendingHubSearchRestore = ""
        if (root.activeHubId === restoreId)
          root.restoreHubSearch(restoreId)
      }
    }
  }

  Timer {
    id: searchDebounce
    interval: 380
    repeat: false
    onTriggered: root.runSearch()
  }

  Process {
    id: searchProcA
    property int searchSerial: 0
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (!t) return
        root.applySearchResults(text, searchProcA.searchSerial)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.searchBusy
          && searchProcA.searchSerial === root.searchSerial
          && !searchProcA.running)
        root.applySearchResults('{"ok":false,"error":"search-failed","tracks":[]}', searchProcA.searchSerial)
    }
  }

  Process {
    id: searchProcB
    property int searchSerial: 0
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (!t) return
        root.applySearchResults(text, searchProcB.searchSerial)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.searchBusy
          && searchProcB.searchSerial === root.searchSerial
          && !searchProcB.running)
        root.applySearchResults('{"ok":false,"error":"search-failed","tracks":[]}', searchProcB.searchSerial)
    }
  }

  Process {
    id: castProc
    property string mode: ""
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          if (castProc.mode === "discover") {
            root.castTargets = Array.isArray(data.devices) ? data.devices : []
            root.castStatus = root.castTargets.length
              ? ("Choose a receiver" + (data.notice ? " · " + String(data.notice) : ""))
              : (String(data.notice || "") || "No receivers found")
          } else {
            root.castStatus = data.ok ? "Casting" : String(data.error || "Cast failed")
          }
        } catch (e) { root.castStatus = "Cast helper returned invalid data" }
        root.castBusy = false
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.castStatus) root.castStatus = "Cast failed"
      root.castBusy = false
    }
  }

  Process {
    id: dualAudioProc
    property var pendingHit: null
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var ok = false
        try { var data = JSON.parse(String(text || "{}")); ok = data.ok === true } catch (e) {}
        if (ok && dualAudioProc.pendingHit) {
          root.dualAudioActive = true
          root.playVideoHit(dualAudioProc.pendingHit, true)
        } else if (dualAudioProc.pendingHit) {
          root.dualAudioActive = false
          root.showOsd("Split audio unavailable; playing video normally", "media")
          root.playVideoHit(dualAudioProc.pendingHit, false)
        }
        dualAudioProc.pendingHit = null
      }
    }
  }

  Process {
    id: playSearchProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || ""))
          if (data && data.provider) root.cliampActiveProvider = String(data.provider)
          if (data && data.path) root.playPathOverride = String(data.path)
          if (data && data.ok === false && data.error) {
            root.sourceActionError = String(data.error)
            root.showOsd(String(data.error), "media")
          } else if (data && data.ok) root.sourceActionError = ""
        } catch (e) {}
        cliampRefreshTimer.interval = 400
        cliampRefreshTimer.restart()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.sourceActionError) {
        root.sourceActionError = "Playback failed. The source may require sign-in or may be unavailable."
        root.showOsd("Play failed", "media")
      }
      cliampRefreshTimer.interval = 400
      cliampRefreshTimer.restart()
    }
  }

  Process {
    id: favouritesLoadProc
    command: [
      "bash", "-lc",
      'if [[ -f "$1" ]]; then cat "$1"; else echo "{\"version\":1,\"items\":[]}"; fi',
      "bash", root.favouritesPath
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFavouritesText(text)
    }
  }

  Process {
    id: favouritesSaveProc
    command: ["true"]
  }

  Process {
    id: recentsLoadProc
    command: [
      "bash", "-lc",
      'if [[ -f "$1" ]]; then cat "$1"; else echo "{\"version\":1,\"items\":[]}"; fi',
      "bash", root.recentsPath
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRecentsText(text)
    }
  }

  Process {
    id: recentsSaveProc
    command: ["true"]
  }

  Process {
    id: foldersLoadProc
    command: [
      "bash", "-lc",
      'if [[ -f "$1" ]]; then cat "$1"; else echo "{\"version\":1,\"folders\":[]}"; fi',
      "bash", root.foldersPath
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFoldersText(text)
    }
  }

  Process {
    id: foldersSaveProc
    command: ["true"]
  }

  Process {
    id: libraryExportProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          if (data && data.ok)
            root.showOsd("Exported · " + String(data.path || "").split("/").pop(), "media")
          else
            root.showOsd(String((data && data.error) || "Export failed"), "media")
        } catch (e) {
          root.showOsd("Export failed", "media")
        }
      }
    }
  }

  Process {
    id: libraryImportProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          if (data && data.ok) {
            root.loadLibrary()
            root.showOsd("Imported library", "media")
          } else {
            root.showOsd(String((data && data.error) || "Import failed"), "media")
          }
        } catch (e) {
          root.showOsd("Import failed", "media")
        }
      }
    }
  }

  Process {
    id: verifyFavProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyVerifyResult(text)
    }
    onExited: function(exitCode) {
      if (root.verifyBusy && exitCode !== 0) {
        root.verifyBusy = false
        root.showOsd("Verify failed", "media")
      }
    }
  }

  Process {
    id: downloadProc
    command: ["true"]
    stdout: SplitParser {
      onRead: function(data) { root.handleDownloadEvent(data) }
    }
    onExited: function(exitCode) {
      // User cancel already cleared UI — don't resurrect a failed banner.
      if (root.downloadCancelled) {
        root.downloadCancelled = false
        root.clearDownloadUi()
        root.loadDownloads()
        root.scheduleHubRebuild()
        return
      }
      if (!root.downloadBusy && root.downloadError === "" && root.downloadProgress <= 0)
        return
      if (root.downloadBusy || exitCode !== 0) {
        root.downloadBusy = false
        if (exitCode !== 0 && root.downloadError === "") {
          root.downloadError = root.friendlyDownloadError("download-failed")
          root.downloadStatus = "Failed"
          root.showOsd("Download failed", "media")
          downloadBannerClear.restart()
        } else if (exitCode === 0) {
          root.clearDownloadUi()
        }
        root.loadDownloads()
        root.scheduleHubRebuild()
      }
    }
  }

  Timer {
    id: downloadBannerClear
    interval: 3500
    repeat: false
    onTriggered: root.clearDownloadUi()
  }

  Process {
    id: downloadListProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDownloadsText(text)
    }
  }

  Process {
    id: ctlProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCtlResult(text)
    }
    onExited: function() {
      root.ctlBusy = false
      Qt.callLater(function() { root.pumpCtlQueue() })
    }
  }

  Process {
    id: nearbyProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyNearbyText(text)
    }
    onExited: function() { root.nearbyBusy = false }
  }

  // Prefer push events over 2s polling when the daemon is online.
  Process {
    id: cliampEventsProc
    command: ["cliamp", "remote", "events", "runtime.state"]
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        root.cliampEventsActive = true
        root.cliampProbeFails = 0
        try {
          var ev = JSON.parse(String(line || ""))
          var data = ev && ev.data ? ev.data : ev
          if (!data || typeof data !== "object") return
          // Wrap like remote state for the existing parser.
          var wrapped = JSON.stringify({ ok: true, snapshot: data })
          root.applyCliampSnapshot(MediaModel.parseCliampRemoteState(wrapped))
        } catch (e) {}
      }
    }
    onExited: function() {
      root.cliampEventsActive = false
      // Fall back to poll; retry events shortly.
      cliampEventsRetry.restart()
    }
  }

  Timer {
    id: cliampEventsRetry
    interval: 4000
    repeat: false
    onTriggered: {
      if (!cliampEventsProc.running)
        cliampEventsProc.running = true
    }
  }

  Process {
    id: volumeSinkProc
    command: ["omarchy-audio-output-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.volumeSinkName = String(text).trim()
    }
  }

  // Keep volume sink resolved (DSP / EasyEffects chains) like the audio panel.
  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resolveVolumeSink()
  }

  Process {
    id: eqListProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          if (data && data.presets && data.presets.length)
            root.eqPresets = data.presets
        } catch (e) {}
      }
    }
  }

  Process {
    id: queueProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyQueueList(text)
    }
    onExited: function(exitCode) {
      root.queueBusy = false
      if (exitCode !== 0 && root.queueItems.length === 0) {
        root.queueIndex = -1
        root.queueTotal = 0
        root.queueTick++
      }
    }
  }

  Process {
    id: radioResolveProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRadioChannelResolve(text)
    }
  }

  Process {
    id: lyricsProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lyricsBusy = false
        try {
          var data = JSON.parse(String(text || "{}"))
          root.lyricsLines = (data && data.lyrics) ? data.lyrics : []
          root.lyricsText = (data && data.text) ? String(data.text) : ""
          if (!root.lyricsText)
            root.lyricsText = "No lyrics for this track"
        } catch (e) {
          root.lyricsText = "Lyrics unavailable"
          root.lyricsLines = []
        }
      }
    }
    onExited: function() { root.lyricsBusy = false }
  }

  Process {
    id: devicesProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.audioDevices = (data && data.devices) ? data.devices : []
          if (data && data.active)
            root.activeAudioDevice = String(data.active)
        } catch (e) {
          root.audioDevices = []
        }
      }
    }
  }

  Process {
    id: sinksProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.pipewireSinks = (data && data.sinks) ? data.sinks : []
        } catch (e) {
          root.pipewireSinks = []
        }
      }
    }
  }

  Process {
    id: shareProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          if (data && data.ok) {
            root.shareMessage = String(data.url || data.path || "")
            var label = data.mode === "current"
              ? (data.clipboard ? "Link copied" : "Link ready")
              : ("Shared · " + String(data.path || "").split("/").pop())
            root.showOsd(label, "media")
          } else {
            root.shareMessage = String((data && data.error) || "failed")
            root.showOsd("Share failed", "media")
          }
        } catch (e) {
          root.shareMessage = "failed"
          root.showOsd("Share failed", "media")
        }
      }
    }
  }

  Process {
    id: settingsLoadProc
    command: [
      "bash", "-lc",
      'if [[ -f "$1" ]]; then cat "$1"; else echo "{}"; fi',
      "bash",
      root.stateDir + "/settings.json"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySettingsText(text)
    }
  }

  Process {
    id: settingsSaveProc
    command: ["true"]
  }

  Timer {
    id: sleepTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (root.sleepRemainingSec > 0) {
        root.sleepRemainingSec = root.sleepRemainingSec - 1
        if (root.sleepRemainingSec <= 0) {
          root.sleepTimerMinutes = 0
          root.sleepStopAfterTrack = false
          if (root.usingCliamp)
            root.haltCliamp()
          else
            root.runAction("pause", false)
          root.showOsd("Sleep timer — paused", "media")
          sleepTimer.stop()
        }
      } else if (!root.sleepStopAfterTrack) {
        sleepTimer.stop()
      }
    }
  }

  property string sleepTrackSig: ""
  onTitleChanged: {
    if (!root.sleepStopAfterTrack) return
    var sig = String(root.title || "") + "|" + String(root.artist || "")
    if (root.sleepTrackSig && root.sleepTrackSig !== sig) {
      root.sleepStopAfterTrack = false
      if (root.usingCliamp)
        root.haltCliamp()
      else
        root.runAction("pause", false)
      root.showOsd("Stopped after track", "media")
    }
    root.sleepTrackSig = sig
  }

  Process {
    id: pinnedLoadProc
    command: [
      "bash", "-lc",
      'if [[ -f "$1" ]]; then cat "$1"; elif [[ -f "$2" ]]; then cat "$2"; else echo "{}"; fi',
      "bash",
      root.pinnedHubsPath,
      root.legacyPinnedHubsPath
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPinnedHubsText(text)
    }
  }

  Process {
    id: pinnedSaveProc
    command: ["true"]
  }

  Process {
    id: historyLoadProc
    command: [
      "bash", "-lc",
      'if [[ -f "$1" ]]; then cat "$1"; elif [[ -f "$2" ]]; then cat "$2"; else echo "{}"; fi',
      "bash",
      root.searchHistoryPath,
      root.legacySearchHistoryPath
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySearchHistoryText(text)
    }
  }

  Process {
    id: historySaveProc
    command: ["true"]
  }

  Process {
    id: legacyScrubProc
    command: [
      "bash", "-lc",
      'rm -f "$1" "$2"',
      "bash",
      root.legacyPinnedHubsPath,
      root.legacySearchHistoryPath
    ]
  }

  Timer {
    id: historyPersistTimer
    interval: 800
    onTriggered: root.persistSearchHistory()
  }

  PwObjectTracker { objects: root.playbackStreams }
  PwObjectTracker {
    objects: {
      var list = []
      if (root.defaultAudioSink) list.push(root.defaultAudioSink)
      if (root.systemVolumeSink && root.systemVolumeSink !== root.defaultAudioSink)
        list.push(root.systemVolumeSink)
      return list
    }
  }

  function statusJson() {
    return JSON.stringify({
      hasPlayer: root.hasPlayer,
      hasMedia: root.hasMedia,
      playing: root.isPlaying,
      followMode: root.followMode,
      usingCliamp: root.usingCliamp,
      usingMpv: root.usingMpv,
      mediaIsVideo: !!root.mediaIsVideo,
      videoPipVisible: !!root.videoPipVisible,
      videoPipDismissed: !!root.videoPipDismissed,
      canShowVideoPip: !!root.canShowVideoPip,
      videoPreset: root.videoPreset || "S",
      videoOpacity: Number(root.videoOpacity) || 1,
      videoClickThrough: !!root.videoClickThrough,
      videoSubs: !!root.videoSubs,
      videoAspectLock: !!root.videoAspectLock,
      mpvLoopMode: root.mpvLoopMode || "no",
      identity: root.identity,
      desktopEntry: root.usingCliamp ? "cliamp" : (activePlayer ? (activePlayer.desktopEntry || "") : ""),
      title: root.title,
      artist: root.artist,
      album: root.album,
      artUrl: root.artUrl,
      canGoNext: root.canGoNext,
      canGoPrevious: root.canGoPrevious,
      canTogglePlaying: root.canTogglePlaying,
      canSeek: root.canSeek,
      trackPosition: root.trackPosition,
      trackLength: root.trackLength,
      mediaIsStream: !!root.mediaIsStream,
      radioFrequency: root.radioFrequency || "",
      volumeSupported: root.volumeSupported,
      volume: Math.round((Number(root.mediaVolume) || 0) * 1000) / 1000,
      volumePct: Math.round((Number(root.mediaVolume) || 0) * 100),
      systemVolume: Math.round((Number(root.systemVolume) || 0) * 1000) / 1000,
      systemMuted: !!root.systemMuted,
      shuffleSupported: root.shuffleSupported,
      loopSupported: root.loopSupported,
      sources: root.sourcePlayers.length,
      favorites: root.sourceEntries.length,
      cliampOnline: !!root.cliamp.online,
      cliampProvider: root.cliampActiveProvider,
      providers: root.providerEntries.length,
      searchProvider: root.searchProvider || root.resolveSearchProvider(),
      searchResults: root.searchResults.length,
      searchBusy: !!root.searchBusy,
      searchError: root.searchError || "",
      searchQuery: root.searchQuery || "",
      activeHub: root.activeHubId,
      hubs: root.hubEntries.length,
      pinnedHubs: root.effectivePinnedHubIds(),
      downloadBusy: !!root.downloadBusy,
      downloadError: root.downloadError || "",
      downloadProgress: Number(root.downloadProgress) || 0,
      downloadCount: root.downloadCount || 0,
      canDownload: root.canDownload === true,
      currentIsFavorite: root.currentIsFavorite === true,
      shuffle: !!root.shuffle,
      loopState: root.loopState,
      playbackSpeed: root.playbackSpeed,
      eqPreset: root.eqPreset,
      volumeMode: root.volumeMode,
      extrasTab: root.extrasTabSetting,
      pluginVersion: "1.11.0",
      canQueueCurrent: !!root.canQueueCurrent,
      queueTotal: root.queueTotal,
      queueIndex: root.queueIndex,
      suggestions: (root.searchSuggestions || []).length,
      firstHitPath: (root.searchResults.length && root.searchResults[0])
        ? String(root.searchResults[0].path || root.searchResults[0].title || "")
        : ""
    })
  }

  IpcHandler {
    target: "media"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.runAction("playPause", true) ? "ok" : "unhandled"
    }

    function next(): string {
      return root.runAction("next", true) ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.runAction("previous", true) ? "ok" : "unhandled"
    }

    function play(): string {
      return root.runAction("play", true) ? "ok" : "unhandled"
    }

    function pause(): string {
      return root.runAction("pause", true) ? "ok" : "unhandled"
    }

    function sourceNext(): string {
      return root.switchSource(1, true, true) ? "ok" : "unhandled"
    }

    function sourcePrevious(): string {
      return root.switchSource(-1, true, true) ? "ok" : "unhandled"
    }

    function sourceSwitch(): string {
      return root.switchSource(1, true, true) ? "ok" : "unhandled"
    }

    function sourceSwitchPrevious(): string {
      return root.switchSource(-1, true, true) ? "ok" : "unhandled"
    }

    function followPlaying(): string {
      return root.followPlaying() ? "ok" : "unhandled"
    }

    function selectSource(query: string): string {
      var q = String(query || "").toLowerCase()
      if (!q) return "missing-query"
      var providers = root.providerEntries
      for (var p = 0; p < providers.length; p++) {
        var pe = providers[p]
        if (String(pe.id).toLowerCase() === q || String(pe.label).toLowerCase().indexOf(q) !== -1) {
          return root.selectCliampProvider(pe.id) ? "ok" : "unhandled"
        }
      }
      var entries = root.sourceEntries
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        if (String(e.id).toLowerCase().indexOf(q) !== -1
            || String(e.label).toLowerCase().indexOf(q) !== -1
            || String(e.playerKey).toLowerCase().indexOf(q) !== -1) {
          return root.activateSource(e) ? "ok" : "unhandled"
        }
      }
      var list = root.sourcePlayers
      for (var j = 0; j < list.length; j++) {
        var pl = list[j]
        var key = root.playerKey(pl).toLowerCase()
        var label = root.labelFor(pl).toLowerCase()
        var identity = String(pl.identity || "").toLowerCase()
        if (key.indexOf(q) !== -1 || label.indexOf(q) !== -1 || identity.indexOf(q) !== -1) {
          return root.selectPlayer(root.playerKey(pl), true) ? "ok" : "unhandled"
        }
      }
      return "not-found"
    }

    function activateFavorite(id: string): string {
      return root.activateSource(String(id || "")) ? "ok" : "unhandled"
    }

    function selectProvider(id: string): string {
      return root.selectCliampProvider(String(id || "")) ? "ok" : "unhandled"
    }

    function search(query: string): string {
      var q = String(query || "")
      // Optional "hubId:query" so IPC can search without a prior openHub.
      var colon = q.indexOf(":")
      if (colon > 0) {
        var maybeHub = q.slice(0, colon)
        if (MediaModel.hubDefById(maybeHub)) {
          root.openHub(maybeHub)
          q = q.slice(colon + 1)
        }
      }
      if (!root.activeHubId) return "no-hub"
      if (!root.searchAvailable) return "unavailable"
      root.setSearchQuery(q)
      // App-local search skips debounce — run immediately (same as Enter in the panel).
      var hub = root.activeHubDef()
      if (hub && hub.appSearch)
        root.runSearch()
      return "ok"
    }

    function playResult(index: string): string {
      var i = parseInt(String(index || "0"), 10)
      if (!isFinite(i) || i < 0 || i >= root.searchResults.length) return "not-found"
      return root.playSearchResult(root.searchResults[i]) ? "ok" : "unhandled"
    }

    function openHub(id: string): string {
      return root.openHub(String(id || "")) ? "ok" : "unhandled"
    }

    function closeHub(): string {
      return root.closeHub() ? "ok" : "unhandled"
    }

    function download(): string {
      return root.downloadCurrent() ? "ok" : "unhandled"
    }

    function browserVideo(payloadJson: string): string {
      return root.browserVideo(payloadJson)
    }

    function applySuggestion(text: string): string {
      root.applySuggestion(String(text || ""))
      return "ok"
    }

    function ping(): string {
      return "ok"
    }

    function togglePin(id: string): string {
      return root.toggleHubPin(String(id || "")) ? "ok" : "unhandled"
    }

    function videoReopen(): string {
      return root.reopenVideoPip() ? "ok" : "unhandled"
    }

    function videoDismiss(): string {
      return root.dismissVideoPip() ? "ok" : "unhandled"
    }

    function videoPreset(name: string): string {
      return root.setVideoPreset(String(name || "S")) ? "ok" : "unhandled"
    }

    function videoSnap(corner: string): string {
      return root.snapVideoCorner(String(corner || "br")) ? "ok" : "unhandled"
    }

    function videoAspectLock(enabled: string): string {
      var v = String(enabled || "").toLowerCase()
      if (v === "toggle" || v === "")
        return root.toggleVideoAspectLock() ? "ok" : "unhandled"
      return root.setVideoAspectLock(v === "1" || v === "true" || v === "on") ? "ok" : "unhandled"
    }

    function playVideo(path: string): string {
      var p = String(path || "").trim()
      if (!p) return "missing-path"
      if (p.charAt(0) === "/") {
        var base = p.split("/").pop() || "Video"
        return root.playVideoHit({ path: p, title: base.replace(/\.[a-z0-9]+$/i, "") || base,
          provider: "local", kind: "local-video", video: true }) ? "ok" : "unhandled"
      }
      var title = ""
      var isYt = MediaModel.isYoutubeUrl(p)
      if (isYt) {
        // Leave title empty so mpv+ytdl fills media-title; UI shows a brief stub.
        var m = p.match(/[?&]v=([^&]+)/) || p.match(/youtu\.be\/([^?&/]+)/)
        title = m ? ("YouTube · " + m[1]) : "YouTube"
      } else {
        var base = p.split("/").pop() || "Video"
        title = base.replace(/\.[a-z0-9]+$/i, "") || base
      }
      return root.playSearchResult({
        path: p,
        title: title,
        provider: isYt ? "youtube" : "local",
        kind: isYt ? "youtube" : "local",
        video: true
      }) ? "ok" : "unhandled"
    }

    function stopVideo(): string {
      return root.stopVideoBackend(true) ? "ok" : "unhandled"
    }

    function videoClickThrough(enabled: string): string {
      var v = String(enabled || "").toLowerCase()
      if (v === "toggle" || v === "")
        return root.setVideoClickThrough(!root.videoClickThrough) ? "ok" : "unhandled"
      return root.setVideoClickThrough(v === "1" || v === "true" || v === "on") ? "ok" : "unhandled"
    }

    function toggleFavorite(): string {
      return root.favoriteCurrent() ? "ok" : "unhandled"
    }
  }
}
