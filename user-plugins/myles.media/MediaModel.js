function isProxyPlayer(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function hasMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
}

function hasTrackMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
}

function playerCanControl(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
}

// Any real MPRIS endpoint, including idle Radio Garden / cliamp with only a
// dbus name or identity — proxies stay filtered out.
function isListablePlayer(player) {
  if (!player || isProxyPlayer(player)) return false
  return !!(player.dbusName || player.identity || player.desktopEntry
    || hasTrackMetadata(player) || playerCanControl(player))
}

function canHandleAction(player, action) {
  if (!player) return false
  if (action === "next") return !!player.canGoNext
  if (action === "previous") return !!player.canGoPrevious
  if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
  if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
  if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
  if (action === "seek" || action === "setPosition")
    return !!(player.canSeek && player.positionSupported && player.lengthSupported && Number(player.length) > 0)
  if (action === "setVolume") return !!player.volumeSupported
  if (action === "toggleShuffle") return !!player.shuffleSupported
  if (action === "cycleLoop") return !!player.loopSupported
  return false
}

function canCycleSource(player) {
  return isListablePlayer(player)
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function streamLabelKey(label) {
  var key = String(label || "").toLowerCase()
  key = key.replace(/^pipewire alsa \[/, "")
  key = key.replace(/\]$/, "")
  key = key.replace(/^alsa playback \[/, "")
  key = key.replace(/[^a-z0-9]+/g, "")
  return key
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function playerAppLabel(player) {
  if (!player) return ""
  var dbus = String(player.dbusName || "")
  dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
  dbus = dbus.replace(/\.instance[0-9]+$/, "")
  return player.desktopEntry || player.identity || dbus
}

function playerHasPlaybackStream(player, playbackStreams) {
  var playerKey = streamLabelKey(playerAppLabel(player))
  if (!playerKey) return false

  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  for (var i = 0; i < streams.length; i++) {
    var streamKey = streamLabelKey(rawStreamLabel(streams[i]))
    if (!streamKey) continue
    if (streamKey === playerKey
        || streamKey.indexOf(playerKey) !== -1
        || playerKey.indexOf(streamKey) !== -1)
      return true
  }

  return false
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function trackSignature(player) {
  if (!player) return ""
  return [
    player.trackTitle || "",
    player.trackArtist || "",
    player.trackAlbum || "",
    player.trackArtUrl || ""
  ].join("\u001f")
}

function trackChanged(previousSignature, player) {
  return trackSignature(player) !== String(previousSignature || "")
}

function labelFor(player) {
  if (!player) return ""
  return player.trackTitle || player.identity || player.desktopEntry || playerAppLabel(player) || ""
}

function displayTitle(player) {
  if (!player) return ""
  if (player.trackTitle) return player.trackTitle
  return player.identity || player.desktopEntry || playerAppLabel(player) || "Media"
}

function displayArtist(player) {
  if (!player) return ""
  if (player.trackArtist) return player.trackArtist
  if (player.trackTitle) return player.identity || player.desktopEntry || ""
  return ""
}

function osdMessage(player, fallback) {
  if (!player) return fallback
  var label = labelFor(player)
  if (label && player.trackArtist) return label + " - " + player.trackArtist
  return label || fallback
}

// Quickshell may expose seconds; raw D-Bus is microseconds. Normalize.
function mediaSeconds(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return 0
  if (n > 100000) return n / 1000000
  return n
}

function formatClock(seconds) {
  var total = Math.max(0, Math.floor(mediaSeconds(seconds)))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var mm = (m < 10 && h > 0 ? "0" : "") + m
  var ss = (s < 10 ? "0" : "") + s
  return h > 0 ? (h + ":" + mm + ":" + ss) : (m + ":" + ss)
}

// Broadcast dial frequency from station titles ("Ramogi FM 107.1", "97.1 FM").
// Ignores bare numbers in names like "Radio 47".
function extractRadioFrequency(text) {
  var s = String(text || "")
  if (!s) return ""
  var best = ""
  var reDec = /(\d{2,3})[.,](\d{1,2})\s*(FM|AM|MHz)?/gi
  var m
  while ((m = reDec.exec(s))) {
    var whole = Number(String(m[1]) + "." + String(m[2]))
    if (!isFinite(whole)) continue
    var band = String(m[3] || "").toUpperCase()
    if (band === "MHZ") band = "FM"
    if (!band) {
      if (whole >= 87 && whole <= 108) band = "FM"
      else if (whole >= 530 && whole <= 1700) band = "AM"
      else continue
    }
    if (band === "FM" && (whole < 87 || whole > 108)) continue
    if (band === "AM" && (whole < 530 || whole > 1700)) continue
    var decimals = String(m[2]).length === 1 ? 1 : Math.min(2, String(m[2]).length)
    best = whole.toFixed(decimals) + " " + band
    if (band === "FM") return best
  }
  var reInt = /\b(\d{2,4})\s*(FM|AM)\b/gi
  while ((m = reInt.exec(s))) {
    var n = Number(m[1])
    band = String(m[2] || "").toUpperCase()
    if (!isFinite(n)) continue
    if (band === "FM" && (n < 87 || n > 108)) continue
    if (band === "AM" && (n < 530 || n > 1700)) continue
    return String(n) + " " + band
  }
  return best
}

function radioFrequencyFromHit(hit) {
  if (!hit || typeof hit !== "object") return ""
  var explicit = String(hit.frequency || hit.freq || "").trim()
  if (explicit) {
    var norm = extractRadioFrequency(explicit) || explicit
    return norm
  }
  return extractRadioFrequency([
    hit.title || "",
    hit.artist || "",
    hit.album || "",
    hit.detail || "",
    hit.subtitle || ""
  ].join(" "))
}

function gardenChannelIdFromPath(path) {
  var p = String(path || "")
  var m = p.match(/\/listen\/([A-Za-z0-9_-]+)(?:\/|$)/)
  return m ? m[1] : ""
}

function canSeekTrack(player) {
  return canHandleAction(player, "seek")
}

// Always-visible favorites in the sources list (launch when offline).
function favoriteDefs() {
  return [
    {
      id: "spotify",
      label: "Spotify",
      icon: "󰓇",
      match: ["spotify"],
      launch: "",
      focus: ""
    },
    {
      id: "cliamp",
      label: "cliamp",
      icon: "󰎆",
      match: ["cliamp"],
      bridge: "cliamp",
      launch: "pgrep -x cliamp >/dev/null || setsid cliamp -d >/dev/null 2>&1 &",
      focus: "cliamp"
    },
    {
      id: "mpv",
      label: "Media Player",
      icon: "󰐹",
      match: ["mpv"],
      // Stay in-drawer — never launch/focus an external mpv window from the panel.
      launch: "",
      focus: ""
    }
  ]
}

// App / special hubs. Cliamp providers (Radio, Podcasts, Local, …) are injected
// at the front of the source rail from the live provider roster.
// Default source-rail pins (first positions). User can pin/unpin any hub.
function defaultPinnedHubIds() {
  return ["favourites", "downloads", "local", "recents", "radio-garden", "spotify", "youtube"]
}

function simpleHash(s) {
  var h = 5381
  var str = String(s || "")
  for (var i = 0; i < str.length; i++)
    h = ((h << 5) + h) + str.charCodeAt(i)
  return (h >>> 0).toString(16)
}

function favoriteIdFromHit(hit) {
  if (!hit) return ""
  if (hit.id && String(hit.id).indexOf(":") !== -1 && !hit.title)
    return String(hit.id)
  var prov = String(hit.provider || "").toLowerCase()
  var kind = String(hit.kind || "").toLowerCase()
  var path = String(hit.path || "")
  if (prov === "radio-garden" || kind === "radio-garden") {
    var ch = String(hit.channelId || hit.albumId || "")
    if (!ch && path) {
      var m = path.match(/listen\/([^/]+)/)
      if (m) ch = m[1]
    }
    return ch ? ("radio-garden:" + ch) : ("radio-garden:" + simpleHash(path || hit.title || ""))
  }
  if (prov === "spotify" || kind === "spotify-track") {
    if (path.indexOf("spotify:track:") === 0) return "spotify:" + path.slice("spotify:track:".length)
    var isrc = String(hit.isrc || "").toUpperCase()
    if (isrc) return "spotify:" + isrc
    return "spotify:" + simpleHash(String(hit.searchHint || hit.title || "") + "|" + String(hit.artist || ""))
  }
  if (prov === "youtube" || kind === "youtube") {
    var vid = ""
    var ym = path.match(/[?&]v=([^&]+)/) || path.match(/youtu\.be\/([^?&/]+)/)
    if (ym) vid = ym[1]
    if (!vid && hit.track && hit.track.provider_meta)
      vid = String(hit.track.provider_meta["youtube.id"] || "")
    return vid ? ("youtube:" + vid) : ("youtube:" + simpleHash(path || hit.title || ""))
  }
  if (path)
    return (prov || kind || "item") + ":" + simpleHash(path)
  return (prov || kind || "item") + ":" + simpleHash(String(hit.title || "") + "|" + String(hit.artist || ""))
}

function normalizeHit(hit) {
  if (!hit || typeof hit !== "object") return null
  var out = {
    title: String(hit.title || ""),
    artist: String(hit.artist || ""),
    album: String(hit.album || ""),
    path: String(hit.path || ""),
    artUrl: String(hit.artUrl || ""),
    stream: !!hit.stream,
    video: hit.video === true || hit.isVideo === true,
    isVideo: hit.isVideo === true,
    ffprobeVideo: hit.ffprobeVideo,
    feed: !!hit.feed,
    kind: String(hit.kind || ""),
    albumId: String(hit.albumId || ""),
    provider: String(hit.provider || ""),
    providerLabel: String(hit.providerLabel || ""),
    detail: String(hit.detail || ""),
    channelId: String(hit.channelId || ""),
    gardenUrl: String(hit.gardenUrl || ""),
    isrc: String(hit.isrc || ""),
    deezerId: String(hit.deezerId || ""),
    searchHint: String(hit.searchHint || ""),
    frequency: String(hit.frequency || hit.freq || "")
  }
  if (!out.frequency)
    out.frequency = radioFrequencyFromHit(out)
  if (!out.channelId)
    out.channelId = gardenChannelIdFromPath(out.path) || String(hit.albumId || "")
  if (hit.track && typeof hit.track === "object") {
    try { out.track = JSON.parse(JSON.stringify(hit.track)) } catch (e) {}
  }
  return out
}

function parseFavouritesJson(text) {
  try {
    var data = JSON.parse(String(text || "{}"))
    var items = Array.isArray(data.items) ? data.items : []
    var out = []
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (!it || typeof it !== "object") continue
      var hit = normalizeHit(it.hit || it)
      if (!hit) continue
      var id = String(it.id || favoriteIdFromHit(hit) || "")
      if (!id) continue
      out.push({
        id: id,
        addedAt: Number(it.addedAt) || 0,
        folderIds: Array.isArray(it.folderIds) ? it.folderIds.map(String) : [],
        broken: !!it.broken,
        lastOkAt: Number(it.lastOkAt) || 0,
        hit: hit
      })
    }
    return { ok: true, version: Number(data.version) || 1, items: out }
  } catch (e) {
    return { ok: false, version: 1, items: [] }
  }
}

function parseRecentsJson(text) {
  try {
    var data = JSON.parse(String(text || "{}"))
    var items = Array.isArray(data.items) ? data.items : []
    var out = []
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (!it || typeof it !== "object") continue
      var hit = normalizeHit(it.hit || it)
      if (!hit) continue
      var id = String(it.id || favoriteIdFromHit(hit) || "")
      if (!id) continue
      out.push({ id: id, playedAt: Number(it.playedAt) || 0, hit: hit })
    }
    return { ok: true, items: out }
  } catch (e) {
    return { ok: false, items: [] }
  }
}

function parseFoldersJson(text) {
  try {
    var data = JSON.parse(String(text || "{}"))
    var folders = Array.isArray(data.folders) ? data.folders : []
    var out = []
    var seen = {}
    for (var i = 0; i < folders.length; i++) {
      var f = folders[i]
      if (!f || typeof f !== "object") continue
      var id = String(f.id || "").trim()
      var label = String(f.label || "").trim()
      if (!id || !label || seen[id]) continue
      seen[id] = true
      out.push({ id: id, label: label, accent: String(f.accent || "") })
    }
    return { ok: true, folders: out }
  } catch (e) {
    return { ok: false, folders: [] }
  }
}

function filterFavouriteItems(items, provider, folderId) {
  var list = Array.isArray(items) ? items : []
  var prov = String(provider || "").toLowerCase()
  var folder = String(folderId || "")
  var out = []
  for (var i = 0; i < list.length; i++) {
    var it = list[i]
    if (!it || !it.hit) continue
    if (prov) {
      var hp = String(it.hit.provider || "").toLowerCase()
      var hubMap = { "radio-garden": "radio-garden", "spotify": "spotify", "youtube": "youtube" }
      if (prov === "radio-garden" && hp !== "radio-garden") continue
      if (prov === "spotify" && hp !== "spotify") continue
      if (prov === "youtube" && hp !== "youtube") continue
      if (prov !== "radio-garden" && prov !== "spotify" && prov !== "youtube" && hp !== prov) continue
    }
    if (folder) {
      var ids = it.folderIds || []
      var found = false
      for (var f = 0; f < ids.length; f++) {
        if (String(ids[f]) === folder) { found = true; break }
      }
      if (!found) continue
    }
    out.push(it)
  }
  return out
}

function mediaHubDefs() {
  // Order here is only a fallback — Service.rebuildHubEntries puts pinned hubs first.
  return [
    {
      id: "favourites",
      label: "Favourites",
      icon: "󰋑",
      accent: "#E57373",
      searchable: false,
      appSync: false,
      appSearch: false,
      isLibraryHub: true,
      searchBackend: "",
      placeholder: "",
      blurb: "Loved tracks & stations",
      match: [],
      launch: "",
      openLabel: ""
    },
      {
        id: "downloads",
        label: "Downloads",
        icon: "󰇚",
        accent: "#81C784",
        searchable: false,
        appSync: false,
        appSearch: false,
        isDownloadsHub: true,
        searchBackend: "",
        placeholder: "",
        blurb: "Saved from Now Playing · ~/Downloads/Media (not the full disk library)",
        match: [],
        launch: "",
        openLabel: ""
      },
      {
        id: "recents",
        label: "Recents",
        icon: "󰥔",
        accent: "#90CAF9",
        searchable: false,
        appSync: false,
        appSearch: false,
        isRecentsHub: true,
        searchBackend: "",
        placeholder: "",
        blurb: "Recently played from this drawer",
        match: [],
        launch: "",
        openLabel: ""
      },
      {
        id: "radio-garden",
      label: "Radio Garden",
      icon: "󰑈",
      accent: "#4FC3F7",
      searchable: true,
      appSync: false,
      appSearch: true,
      matchChromiumRadio: true,
      searchBackend: "radio-garden-drawer",
      placeholder: "Search Radio Garden…",
      blurb: "Search & play stations in this drawer",
      match: ["radio garden", "radio.garden"],
      launch: "",
      openLabel: "",
      openUrl: ""
    },
    {
      id: "spotify",
      label: "Spotify",
      icon: "󰓇",
      accent: "#1DB954",
      searchable: true,
      appSync: false,
      appSearch: true,
      searchBackend: "spotify-drawer",
      placeholder: "Search Spotify…",
      blurb: "Search & play in this drawer",
      match: ["spotify"],
      launch: "",
      openLabel: ""
    },
    {
      id: "youtube",
      label: "YouTube",
      icon: "󰗃",
      accent: "#FF0000",
      searchable: true,
      searchBackend: "youtube",
      placeholder: "Search YouTube…",
      blurb: "Search and play in this drawer",
      match: ["youtube"],
      launch: "",
      openLabel: ""
    },
    {
      id: "mpv",
      label: "Media Player",
      icon: "󰐹",
      accent: "#78909C",
      searchable: false,
      appSync: false,
      searchBackend: "",
      placeholder: "",
      blurb: "Synced with mpv when it is already playing",
      match: ["mpv"],
      launch: "",
      openLabel: ""
    }
  ]
}

function hubDefById(id) {
  var key = String(id || "")
  if (!key) return null
  var hubs = mediaHubDefs()
  for (var i = 0; i < hubs.length; i++) {
    if (hubs[i].id === key) return hubs[i]
  }
  // Dynamic cliamp provider hubs (radio, podcast, local, …).
  var defs = cliampProviderDefs()
  for (var d = 0; d < defs.length; d++) {
    if (defs[d].id === key)
      return cliampProviderHubDef(defs[d].id, defs[d].label, defs[d].icon)
  }
  return null
}

function suggestSearchQueries(history, typed, limit) {
  var q = String(typed || "").trim().toLowerCase()
  var list = Array.isArray(history) ? history : []
  var out = []
  var seen = {}
  var cap = Math.max(1, Math.min(12, Number(limit) || 8))

  function push(item) {
    var s = String(item || "").trim()
    if (!s) return
    var key = s.toLowerCase()
    if (seen[key]) return
    seen[key] = true
    out.push(s)
  }

  if (!q) {
    for (var i = 0; i < list.length && out.length < cap; i++) push(list[i])
    return out
  }

  // Prefix matches first, then contains.
  for (var a = 0; a < list.length; a++) {
    var t = String(list[a] || "")
    if (t.toLowerCase().indexOf(q) === 0) push(t)
  }
  for (var b = 0; b < list.length && out.length < cap; b++) {
    var u = String(list[b] || "")
    if (u.toLowerCase().indexOf(q) !== -1) push(u)
  }
  return out.slice(0, cap)
}

function parseYoutubeSearchResults(text) {
  try {
    var data = JSON.parse(String(text || ""))
    if (!data || data.ok === false)
      return { ok: false, provider: "youtube", tracks: [], total: 0, error: data && data.error ? data.error : "failed" }
    return {
      ok: true,
      provider: "youtube",
      total: Number(data.total) || 0,
      tracks: Array.isArray(data.tracks) ? data.tracks : [],
      error: ""
    }
  } catch (e) {
    return { ok: false, provider: "youtube", tracks: [], total: 0, error: "bad-json" }
  }
}

function playerMatchesFavorite(player, fav) {
  if (!player || !fav) return false
  var hay = [
    player.desktopEntry || "",
    player.identity || "",
    player.dbusName || "",
    playerAppLabel(player)
  ].join(" ").toLowerCase()
  var matches = fav.match || []
  for (var i = 0; i < matches.length; i++) {
    if (hay.indexOf(String(matches[i]).toLowerCase()) !== -1) return true
  }

  // Radio Garden ships as a Chrome PWA (chrome-radio.garden__-*). Its MPRIS
  // identity is often just "Chrome", so require strong radio.garden signals —
  // never bare Chromium / Netflix / YouTube metadata.
  if (fav.id === "radio-garden" || fav.matchChromiumRadio) {
    var dbus = String(player.dbusName || "").toLowerCase()
    if (dbus.indexOf("radio.garden") !== -1 || hay.indexOf("radio.garden") !== -1)
      return true
    if (dbus.indexOf("chromium") === -1 && dbus.indexOf("chrome") === -1
        && hay.indexOf("chromium") === -1 && hay.indexOf("chrome") === -1)
      return false
    var title = String(player.trackTitle || "")
    var artist = String(player.trackArtist || "")
    var meta = [title, artist, player.trackAlbum || ""].join(" ").toLowerCase()
    if (meta.indexOf("radio.garden") !== -1 || meta.indexOf("radio garden") !== -1)
      return true
    var hasFreq = /\b\d{2,3}[.,]\d{1,2}\s*(fm|mhz)?\b|\b\d{3,4}\s*(am|fm)\b|\bfm\b|\bam\b|\bmhz\b/i.test(title)
    var locArtist = /,\s*[A-Z][A-Za-z]+/.test(artist)
    var len = Number(player.length || player.trackLength || 0)
    var openEnded = player.isPlaying && (len <= 0 || len >= 1e14)
    // Compound only: frequency-like title plus location artist or live length.
    if (hasFreq && (locArtist || openEnded)) return true
    return false
  }
  return false
}

// cliamp volume is dB in [-30, +6]; UI/MPRIS use linear 0..1.
var CLIAMP_VOL_DB_MIN = -30
var CLIAMP_VOL_DB_MAX = 6

function cliampDbToLinear(db) {
  var d = Number(db)
  if (!isFinite(d)) d = 0
  d = Math.max(CLIAMP_VOL_DB_MIN, Math.min(CLIAMP_VOL_DB_MAX, d))
  return (d - CLIAMP_VOL_DB_MIN) / (CLIAMP_VOL_DB_MAX - CLIAMP_VOL_DB_MIN)
}

function linearToCliampDb(linear) {
  var v = Number(linear)
  if (!isFinite(v)) v = cliampDbToLinear(0)
  v = Math.max(0, Math.min(1, v))
  return v * (CLIAMP_VOL_DB_MAX - CLIAMP_VOL_DB_MIN) + CLIAMP_VOL_DB_MIN
}

// Parse cliamp snapshot/result volume (dB). Missing key means 0 dB (cliamp default).
function parseCliampVolumeField(raw) {
  if (raw === undefined || raw === null || raw === "")
    return cliampDbToLinear(0)
  var n = Number(raw)
  if (!isFinite(n)) return cliampDbToLinear(0)
  return cliampDbToLinear(n)
}

function emptyCliampSnapshot() {
  return {
    online: false,
    playing: false,
    stopped: true,
    title: "",
    artist: "",
    album: "",
    artUrl: "",
    path: "",
    stream: false,
    position: 0,
    length: 0,
    seekable: false,
    shuffle: false,
    repeat: "Off",
    speed: 1.0,
    eqPreset: "Flat",
    playlistRevision: 0,
    index: 0,
    total: 0,
    device: "",
    volume: cliampDbToLinear(0),
    provider: ""
  }
}

function isPlaceholderCliampTitle(value) {
  var t = String(value || "").trim().toLowerCase()
  if (!t) return true
  if (t === "videoplayback" || t === "cliamp" || t === "index"
      || t === "channel" || t === "stream" || t === "audio" || t === "station")
    return true
  // Raw URL / path stubs — never show these as transport titles
  if (t.indexOf("watch?v=") === 0 || t.indexOf("youtu.be/") === 0) return true
  if (t.indexOf("https://") === 0 || t.indexOf("http://") === 0) return true
  if (/^youtube\s*[·\-–]\s*/.test(t)) return true
  return false
}

function firstUsefulCliampField() {
  var fallback = ""
  for (var i = 0; i < arguments.length; i++) {
    var v = arguments[i]
    if (v === undefined || v === null) continue
    var s = String(v).trim()
    if (!s) continue
    if (!fallback) fallback = s
    if (!isPlaceholderCliampTitle(s)) return s
  }
  return fallback
}

function parseCliampRemoteState(text) {
  var snap = emptyCliampSnapshot()
  try {
    var data = JSON.parse(String(text || ""))
    if (!data || data.ok === false) return snap
    var s = data.snapshot || data
    snap.online = true
    var state = String(s.state || "").toLowerCase()
    snap.playing = state === "playing"
    snap.stopped = state === "stopped" || state === ""
    // Prefer live `track` metadata over `logical_track` — radio.garden logical
    // rows are often titled "channel" while track has the real stream title.
    var logical = s.logical_track || {}
    var track = s.track || {}
    snap.title = firstUsefulCliampField(
      track.title, track.name, track.stream_title, track.station,
      logical.title, logical.name, logical.stream_title, logical.station,
      s.title
    )
    snap.artist = firstUsefulCliampField(
      track.artist, track.album_artist,
      logical.artist, logical.album_artist,
      s.artist
    )
    snap.album = firstUsefulCliampField(
      track.album, logical.album, track.station, logical.station, s.album
    )
    snap.artUrl = String(
      track.album_art_url || track.art || track.artwork || track.cover
      || logical.album_art_url || logical.art || s.artUrl || ""
    )
    snap.path = String(track.path || logical.path || s.path || "")
    snap.stream = !!(track.stream || logical.stream || s.stream)
    snap.position = Number(s.position || s.elapsed || 0) || 0
    snap.length = Number(
      track.duration_secs || logical.duration_secs || s.duration || s.length || 0
    ) || 0
    snap.seekable = !!s.seekable && snap.length > 0 && !snap.stream
    snap.shuffle = !!s.shuffle
    snap.repeat = String(s.repeat || "Off")
    snap.speed = Number(s.speed || 1.0) || 1.0
    snap.eqPreset = String(s.eq_preset || s.eqPreset || "Flat")
    snap.playlistRevision = Number(s.playlist_revision || 0) || 0
    snap.index = Number(s.index || 0) || 0
    snap.total = Number(s.total || 0) || 0
    snap.device = String(s.device || "")
    // Omitted volume key means 0 dB (cliamp default) — not "full"/1.0.
    if (s.volume === undefined || s.volume === null)
      snap.volume = cliampDbToLinear(0)
    else
      snap.volume = parseCliampVolumeField(s.volume)
    snap.provider = String(s.provider || track.provider || logical.provider || "")
  } catch (e) {
    return emptyCliampSnapshot()
  }
  return snap
}

function parseCliampQueueList(text) {
  var out = { ok: false, index: 0, total: 0, tracks: [] }
  try {
    var data = JSON.parse(String(text || "")) || {}
    out.ok = !!data.ok
    out.index = Number(data.index || 0) || 0
    out.total = Number(data.total || 0) || 0
    var tracks = data.tracks || []
    var rows = []
    for (var i = 0; i < tracks.length; i++) {
      var t = tracks[i] || {}
      rows.push({
        index: i,
        title: String(t.title || t.name || t.path || "Track"),
        artist: String(t.artist || ""),
        path: String(t.path || ""),
        provider: String(t.provider || "")
      })
    }
    out.tracks = rows
    if (!out.total) out.total = rows.length
  } catch (e) {}
  return out
}

function providerAccent(id) {
  var map = {
    radio: "#29B6F6",
    podcast: "#AB47BC",
    local: "#FFA726",
    spotify: "#1DB954",
    ytmusic: "#FF0000",
    youtube: "#FF0000",
    navidrome: "#4DB6AC",
    lyrion: "#7986CB",
    plex: "#E5A00D",
    jellyfin: "#00A4DC",
    emby: "#52B54B",
    qobuz: "#1E88E5",
    tidal: "#000000",
    soundcloud: "#FF5500",
    mixcloud: "#52AAD8",
    netease: "#E53935",
    yandex: "#FFCC00",
    audiobookshelf: "#8D6E63"
  }
  return map[String(id || "")] || "#90A4AE"
}

// Build a searchable hub card for a cliamp provider (Radio / Podcasts / …).
function cliampProviderHubDef(id, label, icon) {
  var key = String(id || "")
  var defs = cliampProviderDefs()
  var def = null
  for (var i = 0; i < defs.length; i++) {
    if (defs[i].id === key) { def = defs[i]; break }
  }
  var isLocal = key === "local"
  return {
    id: key,
    label: label || (def ? def.label : key),
    icon: icon || (def ? def.icon : "󰎆"),
    accent: providerAccent(key),
    searchable: true,
    appSync: false,
    appSearch: false,
    isCliampProvider: true,
    isLocalHub: isLocal,
    searchBackend: key,
    placeholder: isLocal ? "Filter local files…" : ("Search " + (label || key) + "…"),
    blurb: isLocal ? "Browse ~/Music, ~/Downloads/Media (+ custom roots)" : ("cliamp · " + (label || key)),
    match: [],
    launch: "",
    openLabel: ""
  }
}

// Full provider roster from `cliamp --provider` (+ Local from provider.list).
function cliampProviderDefs() {
  return [
    { id: "radio", label: "Radio", icon: "󰐹" },
    { id: "podcast", label: "Podcasts", icon: "󰦔" },
    { id: "local", label: "Local", icon: "󰉋" },
    { id: "spotify", label: "Spotify", icon: "󰓇" },
    { id: "ytmusic", label: "YouTube Music", icon: "󰗃" },
    { id: "youtube", label: "YouTube", icon: "󰗃" },
    { id: "navidrome", label: "Navidrome", icon: "󰎆" },
    { id: "lyrion", label: "Lyrion", icon: "󰎈" },
    { id: "plex", label: "Plex", icon: "󰚺" },
    { id: "jellyfin", label: "Jellyfin", icon: "󰥠" },
    { id: "emby", label: "Emby", icon: "󰥠" },
    { id: "qobuz", label: "Qobuz", icon: "󰎇" },
    { id: "tidal", label: "Tidal", icon: "󰎇" },
    { id: "soundcloud", label: "SoundCloud", icon: "󰓀" },
    { id: "mixcloud", label: "Mixcloud", icon: "󰓀" },
    { id: "netease", label: "NetEase", icon: "󰎄" },
    { id: "yandex", label: "Yandex Music", icon: "󰎄" },
    { id: "audiobookshelf", label: "Audiobookshelf", icon: "󰂺" }
  ]
}

function parseCliampProviderList(text) {
  try {
    var data = JSON.parse(String(text || ""))
    var result = (data.job && data.job.result) || data.result || data
    var list = result.providers || []
    if (!Array.isArray(list)) return []
    return list.map(function(p) {
      return {
        key: String(p.key || p.id || ""),
        name: String(p.name || p.key || ""),
        catalog: !!p.catalog,
        searchable: p.searchable !== false
      }
    }).filter(function(p) { return !!p.key })
  } catch (e) {
    return []
  }
}

function buildCliampProviderEntries(configured, activeProvider) {
  var configuredList = Array.isArray(configured) ? configured : []
  var defs = cliampProviderDefs()
  var seen = {}
  var entries = []

  function pushEntry(id, label, icon) {
    if (!id || seen[id]) return
    seen[id] = true
    entries.push({
      id: id,
      label: label || id,
      icon: icon || "󰎆",
      online: true,
      searchable: true,
      selected: String(activeProvider || "") === id,
      detail: String(activeProvider || "") === id ? "Active" : "Ready"
    })
  }

  for (var k = 0; k < configuredList.length; k++) {
    var conf = configuredList[k]
    if (!conf || !conf.key) continue
    var label = conf.name || conf.key
    var icon = "󰎆"
    for (var d = 0; d < defs.length; d++) {
      if (defs[d].id === conf.key) { label = defs[d].label; icon = defs[d].icon; break }
    }
    pushEntry(conf.key, label, icon)
  }

  return entries
}

function parseCliampSearchResults(text) {
  try {
    var data = JSON.parse(String(text || ""))
    if (!data || data.ok === false) return { ok: false, provider: "", tracks: [], total: 0, error: data && data.error ? data.error : "failed", hitProviders: [] }
    var hits = Array.isArray(data.hitProviders) ? data.hitProviders : []
    // Map provider ids → labels when script only returned ids.
    var labelMap = {}
    var defs = cliampProviderDefs()
    for (var d = 0; d < defs.length; d++) labelMap[defs[d].id] = defs[d].label
    var hitLabels = hits.map(function(h) { return labelMap[h] || h })
    var tracks = Array.isArray(data.tracks) ? data.tracks : []
    var failures = Array.isArray(data.perProvider) ? data.perProvider.filter(function(p) { return p && p.ok === false }) : []
    var error = tracks.length === 0 ? String(data.error || failures.map(function(p) { return String(p.label || p.provider || "Source") + ": " + String(p.error || "unavailable") }).join(" · ")) : ""
    return {
      ok: true,
      provider: String(data.provider || "all"),
      total: Number(data.total) || tracks.length,
      tracks: tracks,
      error: error,
      hitProviders: hitLabels
    }
  } catch (e) {
    return { ok: false, provider: "", tracks: [], total: 0, error: "bad-json", hitProviders: [] }
  }
}

function volumeModeNormalize(mode) {
  var m = String(mode || "system").toLowerCase()
  if (m === "player" || m === "linked" || m === "system") return m
  return "system"
}

function smartFolderDefs() {
  return [
    { id: "smart:radio", label: "Radio", icon: "󰐹", smart: true },
    { id: "smart:broken", label: "Broken", icon: "󰅙", smart: true },
    { id: "smart:unplayed", label: "Unplayed", icon: "󰐊", smart: true }
  ]
}

function filterSmartFavourites(items, smartId) {
  var list = items || []
  var out = []
  var key = String(smartId || "")
  for (var i = 0; i < list.length; i++) {
    var it = list[i]
    if (!it || typeof it !== "object") continue
    var hit = it.hit || it
    var prov = String(hit.provider || hit.kind || "").toLowerCase()
    var path = String(hit.path || "")
    var stream = !!hit.stream || path.indexOf("radio.garden") >= 0
    if (key === "smart:radio") {
      if (stream || prov.indexOf("radio") >= 0) out.push(it)
    } else if (key === "smart:broken") {
      if (it.broken) out.push(it)
    } else if (key === "smart:unplayed") {
      var plays = Number(it.playCount || it.plays || 0) || 0
      var last = Number(it.lastPlayed || it.playedAt || 0) || 0
      if (plays <= 0 && last <= 0) out.push(it)
    }
  }
  return out
}

function sleepTrackId(title, artist, path, album) {
  return [
    String(path || "").trim(),
    String(title || "").trim().toLowerCase(),
    String(artist || "").trim().toLowerCase(),
    String(album || "").trim().toLowerCase()
  ].join("|")
}

function videoExtensions() {
  return [".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".mpeg", ".mpg", ".ts", ".flv"]
}

function pathHasVideoExt(path) {
  var p = String(path || "").toLowerCase()
  var q = p.indexOf("?")
  if (q >= 0) p = p.substring(0, q)
  var exts = videoExtensions()
  for (var i = 0; i < exts.length; i++) {
    if (p.length >= exts[i].length && p.substring(p.length - exts[i].length) === exts[i])
      return true
  }
  return false
}

function isYoutubeUrl(path) {
  var u = String(path || "")
  return (u.indexOf("youtube.com/") !== -1 || u.indexOf("youtu.be/") !== -1)
    && u.indexOf("googlevideo.com") === -1
}

function isFacebookVideoUrl(path) {
  var u = String(path || "").trim().toLowerCase()
  if (/(?:^|\/\/)fb\.watch\//.test(u)) return true
  var m = u.match(/^(?:https?:\/\/)?(?:www\.|m\.|web\.)?facebook\.com\/([^?#]*)/)
  if (!m) return false
  var p = "/" + m[1]
  return /^\/(?:watch\/?|video\.php$|share\/[vr]\/|reel\/)/.test(p) || /\/videos\//.test(p)
}

function hitIsVideo(hit) {
  if (!hit || typeof hit !== "object") return false
  if (hit.video === true || hit.isVideo === true || hit.ffprobeVideo === true) return true
  if (hit.ffprobeVideo === false) return false
  var prov = String(hit.provider || "").toLowerCase()
  var kind = String(hit.kind || "").toLowerCase()
  var path = String(hit.path || "")
  // Explicit audio-only sources
  if (prov === "radio-garden" || kind === "radio-garden") return false
  if (prov === "spotify" || kind === "spotify-track" || kind === "spotify") return false
  if (path.indexOf("radio.garden") !== -1) return false
  if (path.indexOf("spotify:") === 0) return false
  // YouTube watch / provider is video-capable
  if (prov === "youtube" || kind === "youtube" || isYoutubeUrl(path)) return true
  if (prov === "facebook" || isFacebookVideoUrl(path)) return true
  if (pathHasVideoExt(path)) return true
  if (/\.(m3u8|mpd)(\?|$)/i.test(path)) return true
  return false
}

function emptyMpvSnapshot() {
  return {
    online: false,
    playing: false,
    paused: true,
    path: "",
    title: "",
    position: 0,
    length: 0,
    volume: 1.0,
    fullscreen: false,
    subs: false,
    loop: "no",
    playlistCount: 0,
    playlistPos: -1
  }
}

function parseMpvStatus(text) {
  var snap = emptyMpvSnapshot()
  try {
    var data = JSON.parse(String(text || "{}")) || {}
    snap.online = !!data.online
    snap.playing = !!data.playing
    snap.paused = data.paused !== undefined ? !!data.paused : !snap.playing
    snap.path = String(data.path || "")
    snap.title = String(data.title || "")
    snap.position = Number(data.position || 0) || 0
    snap.length = Number(data.length || 0) || 0
    snap.volume = isFinite(Number(data.volume)) ? Number(data.volume) : 1.0
    snap.fullscreen = !!data.fullscreen
    snap.subs = !!data.subs
    snap.loop = String(data.loop || "no")
    snap.playlistCount = Number(data.playlistCount || 0) || 0
    snap.playlistPos = data.playlistPos !== undefined ? Number(data.playlistPos) : -1
    if (data.geometry && typeof data.geometry === "object")
      snap.geometry = data.geometry
    if (data.aspectLock !== undefined) snap.aspectLock = !!data.aspectLock
    if (data.clickThrough !== undefined) snap.clickThrough = !!data.clickThrough
  } catch (e) {
    return emptyMpvSnapshot()
  }
  return snap
}

if (typeof module !== "undefined") {
  module.exports = {
    isProxyPlayer: isProxyPlayer,
    hasMetadata: hasMetadata,
    hasTrackMetadata: hasTrackMetadata,
    playerCanControl: playerCanControl,
    isListablePlayer: isListablePlayer,
    canHandleAction: canHandleAction,
    canCycleSource: canCycleSource,
    nodeProps: nodeProps,
    isPlaybackStream: isPlaybackStream,
    streamLabelKey: streamLabelKey,
    rawStreamLabel: rawStreamLabel,
    playerAppLabel: playerAppLabel,
    playerHasPlaybackStream: playerHasPlaybackStream,
    playerKey: playerKey,
    trackSignature: trackSignature,
    trackChanged: trackChanged,
    labelFor: labelFor,
    displayTitle: displayTitle,
    displayArtist: displayArtist,
    osdMessage: osdMessage,
    mediaSeconds: mediaSeconds,
    formatClock: formatClock,
    extractRadioFrequency: extractRadioFrequency,
    radioFrequencyFromHit: radioFrequencyFromHit,
    gardenChannelIdFromPath: gardenChannelIdFromPath,
    canSeekTrack: canSeekTrack,
    favoriteDefs: favoriteDefs,
    defaultPinnedHubIds: defaultPinnedHubIds,
    simpleHash: simpleHash,
    favoriteIdFromHit: favoriteIdFromHit,
    normalizeHit: normalizeHit,
    parseFavouritesJson: parseFavouritesJson,
    parseRecentsJson: parseRecentsJson,
    parseFoldersJson: parseFoldersJson,
    filterFavouriteItems: filterFavouriteItems,
    mediaHubDefs: mediaHubDefs,
    hubDefById: hubDefById,
    cliampProviderHubDef: cliampProviderHubDef,
    providerAccent: providerAccent,
    suggestSearchQueries: suggestSearchQueries,
    playerMatchesFavorite: playerMatchesFavorite,
    emptyCliampSnapshot: emptyCliampSnapshot,
    isPlaceholderCliampTitle: isPlaceholderCliampTitle,
    parseCliampRemoteState: parseCliampRemoteState,
    cliampDbToLinear: cliampDbToLinear,
    linearToCliampDb: linearToCliampDb,
    parseCliampVolumeField: parseCliampVolumeField,
    volumeModeNormalize: volumeModeNormalize,
    smartFolderDefs: smartFolderDefs,
    filterSmartFavourites: filterSmartFavourites,
    sleepTrackId: sleepTrackId,
    videoExtensions: videoExtensions,
    pathHasVideoExt: pathHasVideoExt,
    isYoutubeUrl: isYoutubeUrl,
    isFacebookVideoUrl: isFacebookVideoUrl,
    hitIsVideo: hitIsVideo,
    emptyMpvSnapshot: emptyMpvSnapshot,
    parseMpvStatus: parseMpvStatus,
    parseCliampQueueList: parseCliampQueueList,
    cliampProviderDefs: cliampProviderDefs,
    parseCliampProviderList: parseCliampProviderList,
    buildCliampProviderEntries: buildCliampProviderEntries,
    parseCliampSearchResults: parseCliampSearchResults,
    parseYoutubeSearchResults: parseYoutubeSearchResults
  }
}
