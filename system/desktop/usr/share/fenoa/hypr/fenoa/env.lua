-- Session environment. uwsm also reads /usr/share/uwsm/env.d/10-fenoa for variables that apps
-- started outside the compositor need (PATH, TERMINAL).

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Prefer Wayland everywhere, with X11 fallbacks.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")

hl.config({
  xwayland = {
    -- XWayland apps render at 1x and are scaled by GDK_SCALE (fenoa.monitors) instead of being
    -- upscaled blurrily by the compositor on the Retina panel.
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})
