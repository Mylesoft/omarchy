function lines(output) {
  var result = []
  String(output || "").split("\n").forEach(function(value) {
    value = value.trim()
    if (value && result.indexOf(value) === -1) result.push(value)
  })
  return result
}

function nextIndex(values, current) {
  if (!values || values.length === 0) return -1
  return (values.indexOf(current) + 1 + values.length) % values.length
}

function wallpaperLabel(path) {
  return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "").replace(/[-_]+/g, " ")
}

function themeLabel(name) {
  return String(name || "").replace(/[-_]+/g, " ")
}

if (typeof module !== "undefined") {
  module.exports = {
    lines: lines,
    nextIndex: nextIndex,
    wallpaperLabel: wallpaperLabel,
    themeLabel: themeLabel
  }
}
