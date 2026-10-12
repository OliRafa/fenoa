-- Hyprland configuration. https://wiki.hypr.land/Configuring/Start/
--
-- Fenoa's defaults live in /usr/share/fenoa/hypr and update with the image. This file is yours:
-- add overrides below the require and they win over the defaults.

dofile("/usr/share/fenoa/hypr/bootstrap.lua")
require("fenoa")

-- Your settings. Examples:
-- hl.monitor({ output = "DP-1", mode = "3440x1440@60", position = "auto-right", scale = 1 })
-- hl.config({ input = { kb_layout = "us,br", kb_options = "grp:alt_shift_toggle" } })
-- hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("uwsm-app -- mpv --player-operation-mode=pseudo-gui"))

-- Colours from the Noctalia palette. Noctalia's hyprland template renders ~/.config/hypr/noctalia.lua
-- and looks for require("noctalia") in this file before adding its own (unguarded) include; this
-- guarded form keeps the first login, before Noctalia has rendered anything, error-free.
local has_palette, noctalia = pcall(require, "noctalia")
if has_palette then
  noctalia.apply_theme()
end
