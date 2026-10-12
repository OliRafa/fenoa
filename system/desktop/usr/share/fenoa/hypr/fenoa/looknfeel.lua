-- Look and feel. Border colours follow the Noctalia palette: Noctalia's "hyprland" template renders
-- ~/.config/hypr/noctalia.lua, which ~/.config/hypr/hyprland.lua applies after these defaults.
-- https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
  -- Mitigate fullscreen artifacts seen on Asahi when a client is scanned out directly.
  render = {
    direct_scanout = 0,
  },

  general = {
    gaps_in = 5,
    gaps_out = 10,
    border_size = 2,
    resize_on_border = false,
    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    rounding = 12,

    shadow = {
      enabled = true,
      range = 4,
      render_power = 3,
      color = 0xee1a1a1a,
    },

    blur = {
      enabled = true,
      size = 3,
      passes = 2,
      vibrancy = 0.1696,
    },
  },

  animations = {
    enabled = true,
  },

  dwindle = {
    preserve_split = true,
    force_split = 2,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    focus_on_activate = true,
    anr_missed_pings = 3,
    -- Let a restarted shell re-acquire the session lock if Noctalia died while locked.
    allow_session_lock_restore = true,
  },

  cursor = {
    hide_on_key_press = true,
  },

  binds = {
    hide_special_on_workspace_change = true,
  },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 3.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "slide" })

-- Blur Noctalia's bar, panels, dock, notifications and OSD, and leave their animations to Noctalia.
hl.layer_rule({
  name = "noctalia",
  match = {
    namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
  },
  no_anim = true,
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})
