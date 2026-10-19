-- Keyboard and trackpad. https://wiki.hypr.land/Configuring/Basics/Variables/#input

-- Keyboard layout: the system setting, as fenoa/keyboard.lua resolves it (a Latin layout first, so
-- the letter bindings work). The login screen runs the same resolver, so the greeter and the session
-- agree. Override in ~/.config/hypr/hyprland.lua.
local keyboard = require("fenoa.keyboard").resolve()

hl.config({
  input = {
    kb_layout = keyboard.layout,
    kb_variant = keyboard.variant,
    kb_options = keyboard.options,
    follow_mouse = 1,
    sensitivity = 0,
    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      -- Natural scrolling, and physical clicks instead of taps: disable_while_typing alone does not
      -- stop every stray tap while typing, and turning off tap_to_click does (set it to true in
      -- hyprland.lua to tap). clickfinger_behavior makes a two-finger click a right click, three a
      -- middle click, wherever on the touchpad, instead of the bottom corners.
      natural_scroll = true,
      tap_to_click = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Three-finger horizontal swipe switches workspaces.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- foot scrolls by lines, so the global trackpad scroll factor makes it crawl.
hl.window_rule({ match = { class = "foot" }, scroll_touchpad = 2.0 })
