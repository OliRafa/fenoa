-- Session autostart. uwsm has already imported the environment into systemd and D-Bus.

hl.on("hyprland.start", function()
  -- The shell: bar, launcher, notifications, OSD, lock screen, idle, polkit agent, night light,
  -- wallpaper. Run through uwsm in the session slice, so systemd-oomd (which may only kill what is
  -- in app.slice) never picks it; the apps it launches go to app.slice via uwsm-app
  -- (launch_apps_custom_command in /usr/share/fenoa/noctalia/fenoa.toml).
  hl.exec_cmd("uwsm-app -s s -- noctalia")
end)
