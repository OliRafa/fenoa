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
      -- Match macOS: natural scrolling, and physical clicks instead of taps. On the Asahi trackpad
      -- disable_while_typing alone does not stop stray taps while typing; turning off tap_to_click
      -- does. clickfinger_behavior makes a two-finger click a right click, three a middle click.
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

-- Three-finger horizontal swipe switches workspaces, as on macOS.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- foot scrolls by lines, so the global trackpad scroll factor makes it crawl.
hl.window_rule({ match = { class = "foot" }, scroll_touchpad = 2.0 })
