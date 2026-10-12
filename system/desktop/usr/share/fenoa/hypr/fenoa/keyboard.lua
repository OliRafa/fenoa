-- Fenoa's keyboard layout, resolved from the system setting. Pure Lua with no hl.* calls, so the
-- same code serves Hyprland (fenoa/input.lua) and the login screen (/usr/libexec/fenoa-greeter-session
-- runs it with the lua interpreter): the greeter starts in the layout the session will use.
--
-- The setting is XKBLAYOUT/XKBVARIANT/XKBOPTIONS in /etc/vconsole.conf. `localectl set-x11-keymap`
-- writes them, and so do systemd-firstboot and `localectl set-keymap` when they can convert the
-- console keymap. A file that carries only the console KEYMAP is mapped here through systemd's
-- table, /usr/share/systemd/kbd-model-map. Nothing set → us.

local M = {}

local function read_vconsole(path)
  local values = {}
  local file = io.open(path, "r")
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
local function xkb_from_console_keymap(map_path, keymap)
  local file = keymap and io.open(map_path, "r")
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

-- Hyprland matches key bindings against the FIRST layout in kb_layout, so with a non-Latin layout
-- first, SUPER + W and every other letter binding would stop working.
local non_latin_layouts =
  " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "
local function is_latin(layout)
  return not non_latin_layouts:find(" " .. layout .. " ", 1, true)
end

-- Returns { layout = ..., variant = ..., options = ... }: comma-separated XKB values, ready for
-- Hyprland's kb_layout/kb_variant/kb_options and libxkbcommon's XKB_DEFAULT_LAYOUT/VARIANT/OPTIONS.
function M.resolve()
  local vconsole = read_vconsole(os.getenv("FENOA_VCONSOLE_CONF") or "/etc/vconsole.conf")
  local kb_layout, kb_variant, kb_options = vconsole.XKBLAYOUT, vconsole.XKBVARIANT, vconsole.XKBOPTIONS
  if not kb_layout or kb_layout == "" then
    local map_path = os.getenv("FENOA_KBD_MODEL_MAP") or "/usr/share/systemd/kbd-model-map"
    kb_layout, kb_variant, kb_options = xkb_from_console_keymap(map_path, vconsole.KEYMAP)
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

  -- Lead with a Latin layout: move one forward if the list already has it (systemd maps e.g. ru to
  -- "ru,us"), else add us, and give the user a way to switch (Left Alt + Right Alt) unless a group
  -- toggle is already configured.
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

  return {
    layout = table.concat(layouts, ","),
    variant = table.concat(variants, ",", 1, #layouts),
    options = kb_options,
  }
end

return M
