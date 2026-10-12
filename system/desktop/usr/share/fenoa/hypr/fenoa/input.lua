-- Keyboard and trackpad. https://wiki.hypr.land/Configuring/Basics/Variables/#input

-- Keyboard layout: follow the system setting instead of hardcoding one. `localectl set-x11-keymap`
-- stores XKBLAYOUT/XKBVARIANT/XKBOPTIONS in /etc/vconsole.conf; systemd-firstboot only writes the
-- console KEYMAP, so map that to XKB through systemd's own table (/usr/share/systemd/kbd-model-map),
-- as `localectl set-keymap` would. Nothing set → us. Override in ~/.config/hypr/hyprland.lua.
local vconsole_path = os.getenv("FENOA_VCONSOLE_CONF") or "/etc/vconsole.conf"
local kbd_map_path = os.getenv("FENOA_KBD_MODEL_MAP") or "/usr/share/systemd/kbd-model-map"

local function read_vconsole()
  local values = {}
  local file = io.open(vconsole_path, "r")
  if not file then
    return values
  end
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and value then
      value = value:gsub("%s+#.*$", ""):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      values[key] = value
    end
  end
  file:close()
  return values
end

-- kbd-model-map rows: console-keymap xkb-layout xkb-model xkb-variant xkb-options ("-" = empty).
local function xkb_from_console_keymap(keymap)
  local file = keymap and io.open(kbd_map_path, "r")
  if not file then
    return nil
  end
  for line in file:lines() do
    if not line:match("^%s*#") then
      local console, layout, _, variant, options = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
      if console == keymap then
        file:close()
        return layout, variant ~= "-" and variant or "", options ~= "-" and options or ""
      end
    end
  end
  file:close()
  return nil
end

local vconsole = read_vconsole()
local kb_layout, kb_variant, kb_options = vconsole.XKBLAYOUT, vconsole.XKBVARIANT, vconsole.XKBOPTIONS
if not kb_layout or kb_layout == "" then
  kb_layout, kb_variant, kb_options = xkb_from_console_keymap(vconsole.KEYMAP)
end
kb_layout = (kb_layout and kb_layout ~= "") and kb_layout or "us"
kb_variant = kb_variant or ""
-- terminate:ctrl_alt_bksp is an X server option and means nothing on Wayland.
local kept = {}
for option in (kb_options or ""):gmatch("[^,]+") do
  if not option:match("^terminate:") then
    table.insert(kept, option)
  end
end
kb_options = table.concat(kept, ",")

-- Hyprland matches key bindings against the FIRST layout in kb_layout, so with a non-Latin layout
-- first, SUPER + W and every other letter binding would stop working. Lead with a Latin layout: move
-- one forward if the list already has it (systemd maps e.g. ru to "ru,us"), else add us, and give
-- the user a way to switch (Left Alt + Right Alt) unless a group toggle is already configured.
local non_latin_layouts =
  " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "
local function is_latin(layout)
  return not non_latin_layouts:find(" " .. layout .. " ", 1, true)
end

local layouts, variants = {}, {}
for layout in kb_layout:gmatch("[^,]+") do
  table.insert(layouts, layout)
end
local index = 0
for variant in (kb_variant .. ","):gmatch("([^,]*),") do
  index = index + 1
  variants[index] = variant
end
for i = 1, #layouts do
  variants[i] = variants[i] or ""
end

if not is_latin(layouts[1]) then
  local latin
  for i = 2, #layouts do
    if is_latin(layouts[i]) then
      latin = i
      break
    end
  end
  if latin then
    table.insert(layouts, 1, table.remove(layouts, latin))
    table.insert(variants, 1, table.remove(variants, latin))
  else
    table.insert(layouts, 1, "us")
    table.insert(variants, 1, "")
  end
  if not kb_options:find("grp:", 1, true) then
    kb_options = kb_options ~= "" and (kb_options .. ",grp:alts_toggle") or "grp:alts_toggle"
  end
end

kb_layout = table.concat(layouts, ",")
kb_variant = table.concat(variants, ",", 1, #layouts)

hl.config({
  input = {
    kb_layout = kb_layout,
    kb_variant = kb_variant,
    kb_options = kb_options,
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
