-- Key bindings. Shell surfaces (launcher, control center, notifications, OSD, lock, screenshots)
-- are Noctalia's and are driven over its IPC; window management is Hyprland's.
--
-- Apple keyboards: the top row sends media keys first (hid_apple fnmode=1, F1-F12 behind Fn) and
-- there is no Print key, so the capture bindings live on SUPER + the top-row keys too.

local f = require("fenoa.helpers")
local bind, launch, noctalia = f.bind, f.launch, f.noctalia

-- --- Apps -----------------------------------------------------------------------------------------
bind("SUPER + RETURN", "Terminal", launch("xdg-terminal-exec"))
bind("SUPER + SHIFT + RETURN", "Browser", launch("com.brave.Browser.desktop"))
bind("SUPER + SHIFT + B", "Browser", launch("com.brave.Browser.desktop"))
bind("SUPER + SHIFT + F", "File manager", launch("nautilus --new-window"))
bind("SUPER + SHIFT + N", "Editor", launch("xdg-terminal-exec nvim"))

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

-- The Mac top row has no keyboard-backlight keys (it only ever sends KEY_BRIGHTNESSUP/DOWN), so
-- the keyboard backlight lives on Shift + brightness. The dedicated keys stay bound for external
-- keyboards that have them.
bind("SHIFT + XF86MonBrightnessUp", "Keyboard backlight up", "fenoa-kbd-backlight up", { locked = true, repeating = true })
bind("SHIFT + XF86MonBrightnessDown", "Keyboard backlight down", "fenoa-kbd-backlight down", { locked = true, repeating = true })
bind("XF86KbdBrightnessUp", "Keyboard backlight up", "fenoa-kbd-backlight up", { locked = true, repeating = true })
bind("XF86KbdBrightnessDown", "Keyboard backlight down", "fenoa-kbd-backlight down", { locked = true, repeating = true })

bind("XF86AudioPlay", "Play/pause", noctalia("media toggle"), { locked = true })
bind("XF86AudioPause", "Play/pause", noctalia("media toggle"), { locked = true })
bind("XF86AudioNext", "Next track", noctalia("media next"), { locked = true })
bind("XF86AudioPrev", "Previous track", noctalia("media previous"), { locked = true })

-- --- Capture --------------------------------------------------------------------------------------
bind("PRINT", "Screenshot region", noctalia("screenshot-region"))
bind("SHIFT + PRINT", "Screenshot display", noctalia("screenshot-fullscreen pick"))
bind("SUPER + F11", "Screenshot region", noctalia("screenshot-region"))
bind("SUPER + F12", "Screenshot display", noctalia("screenshot-fullscreen pick"))
bind("SUPER + XF86AudioLowerVolume", "Screenshot region (Apple top row)", noctalia("screenshot-region"))
bind("SUPER + XF86AudioRaiseVolume", "Screenshot display (Apple top row)", noctalia("screenshot-fullscreen pick"))

-- --- Lid ------------------------------------------------------------------------------------------
-- Apple Silicon reports the lid as "Apple SMC power/lid events", not the generic "Lid Switch".
-- With an external display attached, closing the lid turns the internal panel off instead of
-- leaving workspaces on a dark screen; with none, logind suspends as usual.
bind("switch:on:Apple SMC power/lid events", nil, "fenoa-hypr-clamshell close", { locked = true })
bind("switch:off:Apple SMC power/lid events", nil, "fenoa-hypr-clamshell open", { locked = true })

-- --- Windows --------------------------------------------------------------------------------------
bind("SUPER + W", "Close window", hl.dsp.window.close())
bind("SUPER + Q", "Close window", hl.dsp.window.close())
bind("SUPER + J", "Toggle split", hl.dsp.layout("togglesplit"))
bind("SUPER + P", "Pseudo-tile window", hl.dsp.window.pseudo())
bind("SUPER + T", "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
bind("SUPER + F", "Fullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind("SUPER + ALT + F", "Maximize", hl.dsp.window.fullscreen({ mode = "maximized" }))

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

bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

bind("SUPER + G", "Toggle group", hl.dsp.group.toggle())
bind("SUPER + ALT + G", "Move window out of group", hl.dsp.window.move({ out_of_group = true }))
bind("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())
bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", hl.dsp.group.prev())

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

bind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
bind("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))
bind("CTRL + ALT + TAB", "Focus next monitor", hl.dsp.focus({ monitor = "+1" }))
