-- Retina panels: let Hyprland pick the scale (2x on every Apple Silicon laptop panel) and the
-- preferred mode; external displays get the same treatment. Override per output in
-- ~/.config/hypr/hyprland.lua, e.g.
--   hl.monitor({ output = "DP-1", mode = "3440x1440@60", position = "auto-right", scale = 1 })
-- Find output names with `hyprctl monitors`. XWayland apps scale by GDK_SCALE, set for the whole
-- session in /usr/share/uwsm/env.d/10-fenoa.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Lid closed with an external display attached: fenoa-hypr-clamshell turns the internal panel off
-- and leaves its name in $XDG_RUNTIME_DIR/fenoa-clamshell, so the panel stays off when the config is
-- reloaded (the catch-all rule above would otherwise switch it back on behind the closed lid).
local runtime = os.getenv("XDG_RUNTIME_DIR")
local clamshell = runtime and io.open(runtime .. "/fenoa-clamshell", "r")
if clamshell then
  local internal = clamshell:read("*l")
  clamshell:close()
  if internal and internal:match("^[%w._-]+$") then
    hl.monitor({ output = internal, disabled = true })
  end
end
