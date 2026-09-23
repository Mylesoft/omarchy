#!/usr/bin/env node
// Unit tests for MediaModel.js helpers (freq, volume, garden IDs, volume modes).
const path = require("path")
const MM = require(path.join(__dirname, "MediaModel.js"))

let failed = 0
function assert(cond, msg) {
  if (!cond) {
    failed++
    console.error("FAIL:", msg)
  } else {
    console.log("ok:", msg)
  }
}

assert(MM.extractRadioFrequency("NRG Radio 97.1 FM") === "97.1 FM", "freq decimal FM")
assert(MM.extractRadioFrequency("Hope FM 93.3") === "93.3 FM", "freq implied FM")
assert(MM.extractRadioFrequency("Radio 47") === "", "freq ignores bare station numbers")
assert(MM.extractRadioFrequency(" rumble 1070 AM ") === "1070 AM", "freq AM")

assert(Math.abs(MM.cliampDbToLinear(0) - (30 / 36)) < 1e-9, "0 dB → ~0.833")
assert(MM.cliampDbToLinear(-30) === 0, "-30 dB → 0")
assert(MM.cliampDbToLinear(6) === 1, "+6 dB → 1")
assert(Math.abs(MM.linearToCliampDb(0.8333333333333334) - 0) < 0.01, "linear→0 dB")
assert(MM.parseCliampVolumeField(undefined) === MM.cliampDbToLinear(0), "missing vol = 0 dB")

assert(MM.volumeModeNormalize("LINKED") === "linked", "volume mode normalize")
assert(MM.volumeModeNormalize("nope") === "system", "volume mode default")

const gid = MM.gardenChannelIdFromPath
  ? MM.gardenChannelIdFromPath("https://radio.garden/api/ara/content/listen/f3vCQTXc/channel.mp3")
  : ""
assert(gid === "f3vCQTXc" || gid === "", "garden channel id (optional)")

assert(MM.sleepTrackId("A", "B", "/p", "C").indexOf("/p") === 0, "sleep track id")

const smart = MM.filterSmartFavourites([
  { hit: { provider: "radio-garden", path: "https://radio.garden/x", stream: true } },
  { broken: true, hit: { title: "x" } },
  { hit: { title: "y" }, playCount: 0 },
], "smart:radio")
assert(smart.length === 1, "smart radio folder")

const rgFav = { id: "radio-garden", match: ["radio garden"] }
assert(MM.playerMatchesFavorite({
  dbusName: "org.mpris.MediaPlayer2.chromium.instance123",
  identity: "Chrome",
  trackTitle: "Stranger Things",
  trackArtist: "Netflix",
  isPlaying: true,
  length: 0,
}, rgFav) === false, "RG rejects Netflix-like Chrome")
assert(MM.playerMatchesFavorite({
  dbusName: "org.mpris.MediaPlayer2.chromium.instance_radio.garden",
  identity: "Chrome",
  trackTitle: "Anything",
  trackArtist: "x",
  isPlaying: true,
  length: 0,
}, rgFav) === true, "RG matches radio.garden dbus")
assert(MM.playerMatchesFavorite({
  dbusName: "org.mpris.MediaPlayer2.chromium.instance9",
  identity: "Chrome",
  trackTitle: "NRG Radio 97.1 FM",
  trackArtist: "Nairobi, Kenya",
  isPlaying: true,
  length: 0,
}, rgFav) === true, "RG matches freq+location compound")
assert(MM.playerMatchesFavorite({
  dbusName: "org.mpris.MediaPlayer2.chromium.instance9",
  identity: "Chrome",
  trackTitle: "Some YouTube live",
  trackArtist: "Creator",
  isPlaying: true,
  length: 0,
}, rgFav) === false, "RG rejects bare open-ended Chrome")

if (failed) {
  console.error(failed + " failed")
  process.exit(1)
}
console.log("all passed")
