-- Small helpers shared by the Fenoa defaults.

local M = {}

-- Launch an app through uwsm so it lands in its own scope under app.slice: systemd-oomd may kill it
-- under memory pressure (never the compositor or the shell), and it outlives a shell restart.
function M.launch(command)
  return "uwsm-app -- " .. command
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
