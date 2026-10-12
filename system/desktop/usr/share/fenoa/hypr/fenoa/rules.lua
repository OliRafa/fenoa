-- Window rules. https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- Noctalia's settings window is a dialog, not a workspace tenant.
hl.window_rule({ match = { class = "dev.noctalia.Noctalia" }, float = true, size = { 1080, 920 } })

-- Small utility windows float.
hl.window_rule({ match = { class = "^(nm-connection-editor|system-config-printer|org.gnome.Calculator)$" }, float = true })
hl.window_rule({ match = { title = "^(Open File|Save File|Open Folder|Save As)(.*)$" }, float = true })

-- Picture-in-picture video stays on top in a corner.
hl.window_rule({ match = { title = "^Picture.in.[Pp]icture$" }, float = true, pin = true, keep_aspect_ratio = true })

-- Don't let idle lock or blank the screen while something is fullscreen (video, presentations).
hl.window_rule({ match = { fullscreen = true }, idle_inhibit = "fullscreen" })
