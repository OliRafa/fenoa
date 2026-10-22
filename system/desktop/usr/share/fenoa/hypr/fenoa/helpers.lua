-- Small helpers shared by the Fenoa defaults.

local M = {}

-- Launch an app through uwsm so it lands in its own scope under app.slice: systemd-oomd may kill it
-- under memory pressure (never the compositor or the shell), and it outlives a shell restart.
function M.launch(command)
  return "uwsm-app -- " .. command
end

-- Focus the window whose class is `class` if one is open (on whatever workspace), else launch
-- `command`: for an app kept in one window, such as a chat webapp, where pressing its key again should
-- bring that window back rather than open a second. A webapp's class is its StartupWMClass.
function M.launch_or_focus(command, class)
  return function()
    for _, window in ipairs(hl.get_windows()) do
      if window.class == class then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
        return
      end
    end
    hl.exec_cmd(M.launch(command))
  end
end

-- Ask the running Noctalia shell to do something (see `noctalia msg --help`).
function M.noctalia(command)
  return "noctalia msg " .. command
end

-- bind(keys, description, action, options): action is a dispatcher or a shell command string.
function M.bind(keys, description, action, options)
  local opts = options or {}
  if description then
    opts.description = description
  end
  if type(action) == "string" then
    action = hl.dsp.exec_cmd(action)
  end
  hl.bind(keys, action, opts)
end

return M
