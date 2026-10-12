-- Fenoa's Hyprland bootstrap: puts the image defaults (/usr/share/fenoa/hypr) on the Lua module
-- path, so ~/.config/hypr/hyprland.lua can require("fenoa").
--
-- Nothing needs undoing on `hyprctl reload`: Hyprland closes the Lua state and runs the config in a
-- fresh one, so every require loads its module again and the defaults' hl.* calls re-run. The guard
-- only keeps the path from growing should this file run twice in one state.

local defaults = "/usr/share/fenoa/hypr"
if not package.path:find(defaults, 1, true) then
  package.path = defaults .. "/?.lua;" .. defaults .. "/?/init.lua;" .. package.path
end
