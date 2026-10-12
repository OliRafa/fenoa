-- Session environment variables (Wayland backends, cursor size, Qt/GTK theming) live in
-- /usr/share/uwsm/env.d/10-fenoa: uwsm exports them to systemd and D-Bus activation as well, so apps
-- started by either see the same environment as apps started by the compositor. hl.env would only
-- reach the compositor's own children.
--
-- XWayland apps are left to Hyprland's scaling: the right size at any monitor scale, slightly soft at
-- fractional ones. For pixel-sharp XWayland at an integer scale, add to ~/.config/hypr/hyprland.lua
--   hl.config({ xwayland = { force_zero_scaling = true } })
-- and `export GDK_SCALE=<that scale>` to ~/.config/uwsm/env. (Nearly every app Fenoa ships runs on
-- Wayland natively, so this rarely matters.)

hl.config({
  ecosystem = {
    no_update_news = true,
  },
})
