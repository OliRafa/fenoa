-- Key bindings. Shell surfaces (launcher, control center, notifications, OSD, lock, screenshots)
-- are Noctalia's and are driven over its IPC; window management is Hyprland's.
--
-- Keyboards without a Print key (many compact laptops) get the capture bindings on SUPER + F11/F12
-- too.

local f = require("fenoa.helpers")
local bind, launch, launch_or_focus, noctalia = f.bind, f.launch, f.launch_or_focus, f.noctalia

-- --- Apps -----------------------------------------------------------------------------------------
bind("SUPER + RETURN", "Terminal", launch("xdg-terminal-exec"))
bind("SUPER + SHIFT + RETURN", "Browser", launch("com.brave.Browser.desktop"))
bind("SUPER + SHIFT + B", "Browser", launch("com.brave.Browser.desktop"))
bind("SUPER + SHIFT + F", "File manager", launch("nautilus --new-window"))
bind("SUPER + SHIFT + N", "Editor", launch("xdg-terminal-exec nvim"))
bind("SUPER + SHIFT + M", "Music", launch("fenoa-webapp-spotify.desktop"))
bind("SUPER + SHIFT + E", "Email", launch("fenoa-webapp-proton-mail.desktop"))
bind("SUPER + SHIFT + C", "Calendar", launch("fenoa-webapp-proton-calendar.desktop"))
bind("SUPER + SHIFT + W", "WhatsApp",
  launch_or_focus("fenoa-webapp-whatsapp.desktop", "brave-web.whatsapp.com__-Default"))

-- --- Shell (Noctalia) -----------------------------------------------------------------------------
bind("SUPER + SPACE", "Launcher", noctalia("panel-toggle launcher"))
bind("SUPER + ALT + SPACE", "Control center", noctalia("panel-toggle control-center"))
bind("SUPER + CTRL + SPACE", "Wallpaper picker", noctalia("panel-toggle wallpaper"))
bind("SUPER + SHIFT + SPACE", "Toggle bar", noctalia("bar-toggle"))
bind("SUPER + CTRL + E", "Emoji picker", noctalia("panel-toggle launcher /emo"))
bind("SUPER + CTRL + V", "Clipboard history", noctalia("panel-toggle clipboard"))
bind("SUPER + CTRL + S", "Settings", noctalia("settings-toggle"))
bind("SUPER + ESCAPE", "Session menu", noctalia("panel-toggle session"))
bind("XF86PowerOff", "Session menu", noctalia("panel-toggle session"), { locked = true })
bind("SUPER + CTRL + L", "Lock", noctalia("session lock"))
bind("ALT + TAB", "Window switcher", noctalia("window-switcher hold"))

bind("SUPER + comma", "Dismiss notifications", noctalia("notification-clear-active"))
bind("SUPER + ALT + comma", "Open latest notification", noctalia("notification-invoke-latest"))
bind("SUPER + CTRL + comma", "Toggle do not disturb", noctalia("notification-dnd-toggle"))
bind("SUPER + CTRL + I", "Toggle keeping awake", noctalia("caffeine-toggle"))
bind("SUPER + CTRL + N", "Toggle night light", noctalia("nightlight-toggle"))

-- --- Media keys -----------------------------------------------------------------------------------
bind("XF86AudioRaiseVolume", "Volume up", noctalia("volume-up"), { locked = true, repeating = true })
bind("XF86AudioLowerVolume", "Volume down", noctalia("volume-down"), { locked = true, repeating = true })
bind("ALT + XF86AudioRaiseVolume", "Volume up a little", noctalia("volume-up 1"), { locked = true, repeating = true })
bind("ALT + XF86AudioLowerVolume", "Volume down a little", noctalia("volume-down 1"), { locked = true, repeating = true })
bind("XF86AudioMute", "Mute", noctalia("volume-mute"), { locked = true })
bind("XF86AudioMicMute", "Mute microphone", noctalia("mic-mute"), { locked = true })
bind("XF86MonBrightnessUp", "Brightness up", noctalia("brightness-up"), { locked = true, repeating = true })
bind("XF86MonBrightnessDown", "Brightness down", noctalia("brightness-down"), { locked = true, repeating = true })

-- Keyboard-backlight keys, on laptops whose firmware hands them to the OS. Others (ThinkPads' Fn +
-- Space) step the backlight in firmware and send nothing to bind.
bind("XF86KbdBrightnessUp", "Keyboard backlight up", "fenoa-kbd-backlight up", { locked = true, repeating = true })
bind("XF86KbdBrightnessDown", "Keyboard backlight down", "fenoa-kbd-backlight down", { locked = true, repeating = true })
bind("XF86KbdLightOnOff", "Keyboard backlight step", "fenoa-kbd-backlight cycle", { locked = true })

bind("XF86AudioPlay", "Play/pause", noctalia("media toggle"), { locked = true })
bind("XF86AudioPause", "Play/pause", noctalia("media toggle"), { locked = true })
bind("XF86AudioNext", "Next track", noctalia("media next"), { locked = true })
bind("XF86AudioPrev", "Previous track", noctalia("media previous"), { locked = true })

-- --- Capture --------------------------------------------------------------------------------------
bind("PRINT", "Screenshot region", noctalia("screenshot-region"))
bind("SHIFT + PRINT", "Screenshot display", noctalia("screenshot-fullscreen pick"))
bind("SUPER + F11", "Screenshot region", noctalia("screenshot-region"))
bind("SUPER + F12", "Screenshot display", noctalia("screenshot-fullscreen pick"))

-- --- Lid ------------------------------------------------------------------------------------------
-- With an external display attached, closing the lid turns the internal panel off instead of
-- leaving workspaces on a dark screen; with none, logind suspends as usual. "Lid Switch" is the
-- name the kernel's ACPI button driver gives a PC laptop's lid.
bind("switch:on:Lid Switch", nil, "fenoa-hypr-clamshell close", { locked = true })
bind("switch:off:Lid Switch", nil, "fenoa-hypr-clamshell open", { locked = true })

-- --- Windows --------------------------------------------------------------------------------------
bind("SUPER + W", "Close window", hl.dsp.window.close())
bind("SUPER + Q", "Close window", hl.dsp.window.close())
bind("SUPER + J", "Toggle split", hl.dsp.layout("togglesplit"))
bind("SUPER + P", "Pseudo-tile window", hl.dsp.window.pseudo())
bind("SUPER + T", "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
bind("SUPER + F", "Fullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind("SUPER + ALT + F", "Maximize", hl.dsp.window.fullscreen({ mode = "maximized" }))

-- The app goes fullscreen (a browser drops its tabs and toolbar, a video fills the window) but stays
-- in its tile: Hyprland keeps the window as it is and only tells the client it is fullscreen.
bind("SUPER + CTRL + F", "Tiled fullscreen", function()
  local window = hl.get_active_window()
  if window then
    local client = window.fullscreen_client == 2 and 0 or 2
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = client }))
  end
end)

-- Pop a window out: floating, 1300x900, centred and pinned above every workspace on its monitor
-- (a video, a call). Pressed on the popped-out window, it unpins it and puts it back in the tiling.
bind("SUPER + O", "Pop window out", function()
  local window = hl.get_active_window()
  if not window then
    return
  end
  local target = "address:" .. window.address
  if window.pinned then
    hl.dispatch(hl.dsp.window.pin({ window = target }))
    hl.dispatch(hl.dsp.window.float({ window = target, action = "toggle" }))
    return
  end
  if not window.floating then
    hl.dispatch(hl.dsp.window.float({ window = target, action = "toggle" }))
  end
  hl.dispatch(hl.dsp.window.resize({ window = target, x = 1300, y = 900 }))
  hl.dispatch(hl.dsp.window.center({ window = target }))
  hl.dispatch(hl.dsp.window.pin({ window = target }))
  hl.dispatch(hl.dsp.window.alter_zorder({ window = target, mode = "top" }))
end)

-- Ask every window to close (an app with unsaved work can still ask first), then go to workspace 1.
bind("CTRL + ALT + DELETE", "Close all windows", function()
  for _, window in ipairs(hl.get_windows()) do
    hl.dispatch(hl.dsp.window.close({ window = "address:" .. window.address }))
  end
  hl.dispatch(hl.dsp.focus({ workspace = "1" }))
end)

bind("SUPER + LEFT", "Focus left", hl.dsp.focus({ direction = "l" }))
bind("SUPER + RIGHT", "Focus right", hl.dsp.focus({ direction = "r" }))
bind("SUPER + UP", "Focus up", hl.dsp.focus({ direction = "u" }))
bind("SUPER + DOWN", "Focus down", hl.dsp.focus({ direction = "d" }))

bind("SUPER + SHIFT + LEFT", "Swap window left", hl.dsp.window.swap({ direction = "l" }))
bind("SUPER + SHIFT + RIGHT", "Swap window right", hl.dsp.window.swap({ direction = "r" }))
bind("SUPER + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
bind("SUPER + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))

-- code:20 / code:21 are the - and = keys, whatever the layout.
bind("SUPER + code:20", "Grow window left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
bind("SUPER + code:21", "Shrink window left", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
bind("SUPER + SHIFT + code:20", "Shrink window up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
bind("SUPER + SHIFT + code:21", "Grow window down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))
bind("SUPER + ALT + code:20", "Grow window left a little", hl.dsp.window.resize({ x = -25, y = 0, relative = true }))
bind("SUPER + ALT + code:21", "Shrink window left a little", hl.dsp.window.resize({ x = 25, y = 0, relative = true }))
bind("SUPER + SHIFT + ALT + code:20", "Shrink window up a little", hl.dsp.window.resize({ x = 0, y = -25, relative = true }))
bind("SUPER + SHIFT + ALT + code:21", "Grow window down a little", hl.dsp.window.resize({ x = 0, y = 25, relative = true }))
bind("SUPER + CTRL + code:20", "Grow window left a lot", hl.dsp.window.resize({ x = -300, y = 0, relative = true }))
bind("SUPER + CTRL + code:21", "Shrink window left a lot", hl.dsp.window.resize({ x = 300, y = 0, relative = true }))
bind("SUPER + CTRL + SHIFT + code:20", "Shrink window up a lot", hl.dsp.window.resize({ x = 0, y = -300, relative = true }))
bind("SUPER + CTRL + SHIFT + code:21", "Grow window down a lot", hl.dsp.window.resize({ x = 0, y = 300, relative = true }))

bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

bind("SUPER + G", "Toggle group", hl.dsp.group.toggle())
bind("SUPER + ALT + G", "Move window out of group", hl.dsp.window.move({ out_of_group = true }))
bind("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())
bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", hl.dsp.group.prev())
bind("SUPER + CTRL + LEFT", "Previous window in group", hl.dsp.group.prev())
bind("SUPER + CTRL + RIGHT", "Next window in group", hl.dsp.group.next())
bind("SUPER + ALT + mouse_down", "Next window in group", hl.dsp.group.next())
bind("SUPER + ALT + mouse_up", "Previous window in group", hl.dsp.group.prev())
bind("SUPER + ALT + LEFT", "Move window into group left", hl.dsp.window.move({ into_group = "l" }))
bind("SUPER + ALT + RIGHT", "Move window into group right", hl.dsp.window.move({ into_group = "r" }))
bind("SUPER + ALT + UP", "Move window into group above", hl.dsp.window.move({ into_group = "u" }))
bind("SUPER + ALT + DOWN", "Move window into group below", hl.dsp.window.move({ into_group = "d" }))
-- code:10..14 are the number row keys 1..5, whatever the layout.
for index = 1, 5 do
  bind("SUPER + ALT + code:" .. tostring(index + 9), "Window " .. index .. " in group", hl.dsp.group.active({ index = index }))
end

-- --- Workspaces -----------------------------------------------------------------------------------
-- code:10..19 are the number row keys 1..0, whatever the layout.
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  bind("SUPER + " .. key, "Workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
  bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace,
    hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
bind("SUPER + CTRL + TAB", "Last workspace", hl.dsp.focus({ workspace = "previous" }))
bind("SUPER + mouse_down", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
bind("SUPER + mouse_up", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))

bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
bind("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
-- code:49 is the ` key left of 1, whatever the layout.
bind("SUPER + code:49", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
bind("SUPER + SHIFT + code:49", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

-- --- Monitors -------------------------------------------------------------------------------------
-- Move the workspace, or the window, to the monitor in that direction (u and d for monitors stacked
-- above one another). With no monitor that way the key does nothing, rather than hand Hyprland a
-- move it can only fail. Hyprland 0.56 moves a window by workspace, not by monitor, so the window
-- goes to the workspace the other monitor shows, and focus follows it.
local function workspace_to_monitor(direction)
  return function()
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.workspace.move({ monitor = target.name }))
    end
  end
end

local function window_to_monitor(direction)
  return function()
    local target = hl.get_monitor(direction)
    if target and target.active_workspace then
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(target.active_workspace.id) }))
    end
  end
end

for _, side in ipairs({ { "LEFT", "l", "left" }, { "RIGHT", "r", "right" }, { "UP", "u", "upper" }, { "DOWN", "d", "lower" } }) do
  local key, direction, name = side[1], side[2], side[3]
  bind("SUPER + SHIFT + ALT + " .. key, "Move workspace to " .. name .. " monitor", workspace_to_monitor(direction))
  bind("SUPER + SHIFT + CTRL + " .. key, "Move window to " .. name .. " monitor", window_to_monitor(direction))
end
bind("CTRL + ALT + TAB", "Focus next monitor", hl.dsp.focus({ monitor = "+1" }))
bind("CTRL + ALT + SHIFT + TAB", "Focus previous monitor", hl.dsp.focus({ monitor = "-1" }))

-- --- Zoom -----------------------------------------------------------------------------------------
-- Magnify around the cursor, one step per press; a config reload also resets it.
bind("SUPER + CTRL + Z", "Zoom in", function()
  hl.config({ cursor = { zoom_factor = (hl.get_config("cursor.zoom_factor") or 1) + 1 } })
end)
bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)
