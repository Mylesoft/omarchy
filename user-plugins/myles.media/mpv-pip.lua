-- Omarchy media PiP helpers for myles.media
-- Double-click → fullscreen; Esc → exit fullscreen back to last PiP size.
-- Keep only PiP keyboard/mouse behavior; do not draw a title strip over video.

local mp = require("mp")

local function toggle_fs()
  local fs = mp.get_property_bool("fullscreen", false)
  mp.set_property_bool("fullscreen", not fs)
  mp.set_property("user-data/omarchy-pip-fs", fs and "0" or "1")
end

local function exit_fs()
  if mp.get_property_bool("fullscreen", false) then
    mp.set_property_bool("fullscreen", false)
    mp.set_property("user-data/omarchy-pip-fs", "0")
  end
end

mp.add_key_binding("MOUSE_BTN0_DBL", "omarchy-pip-dblclick", toggle_fs)
mp.add_key_binding("esc", "omarchy-pip-esc", exit_fs)

-- Keep window title stable for Hyprland matching
mp.observe_property("media-title", "string", function()
  mp.set_property("title", "omarchy-media-pip")
end)
