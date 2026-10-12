-- Session environment variables (Wayland backends, cursor size, Qt/GTK theming, GDK_SCALE) live in
-- /usr/share/uwsm/env.d/10-fenoa: uwsm exports them to systemd and D-Bus activation as well, so apps
-- started by either see the same environment as apps started by the compositor. hl.env would only
-- reach the compositor's own children.

hl.config({
  xwayland = {
    -- XWayland apps render at 1x and scale themselves by GDK_SCALE instead of being upscaled
    -- blurrily by the compositor on the Retina panel.
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})
