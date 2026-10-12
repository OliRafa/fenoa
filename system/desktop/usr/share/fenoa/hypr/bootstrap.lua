-- Fenoa's Hyprland bootstrap: puts the image defaults on the Lua module path and makes them
-- re-run on `hyprctl reload`.
--
-- Hyprland keeps one Lua state across config reloads, so `require` would hand back the cached
-- modules and none of their hl.* calls would run again — the reloaded config would lose every
-- binding and rule the defaults define. Drop them from package.loaded first. "noctalia" is the
-- palette module Noctalia's hyprland template renders into ~/.config/hypr/noctalia.lua; it changes
-- whenever the wallpaper or theme does, so it must reload too.

for module in pairs(package.loaded) do
  if module == "fenoa" or module:sub(1, 6) == "fenoa." or module == "noctalia" then
    package.loaded[module] = nil
  end
end

local defaults = "/usr/share/fenoa/hypr"
if not package.path:find(defaults, 1, true) then
  package.path = defaults .. "/?.lua;" .. defaults .. "/?/init.lua;" .. package.path
end
