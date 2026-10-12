-- Monitors: preferred mode, automatic placement and Hyprland's automatic scale for every output.
-- Pick your own per output in ~/.config/hypr/hyprland.lua; names come from `hyprctl monitors`, e.g.
--   hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.25 })
--   hl.monitor({ output = "DP-1", mode = "3440x1440@60", position = "auto-up", scale = 1 })
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
