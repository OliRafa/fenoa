-- Retina panels: let Hyprland pick the scale (2x on every Apple Silicon laptop panel) and the
-- preferred mode; external displays get the same treatment. Override per output in
-- ~/.config/hypr/hyprland.lua, e.g.
--   hl.monitor({ output = "DP-1", mode = "3440x1440@60", position = "auto-right", scale = 1 })
-- Find output names with `hyprctl monitors`.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- XWayland apps (force_zero_scaling in fenoa.env) scale themselves by this factor.
hl.env("GDK_SCALE", "2")
