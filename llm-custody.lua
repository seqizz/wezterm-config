-- One-key mid-session sync for llm-custody jail sessions.
--
-- The jail runner (bubblewrap sandbox around a coding agent) hands the
-- sandbox a *copy* of the workspace and of every read-write extra mount, so
-- nothing the agent writes reaches the real tree until it is reviewed. That
-- review normally happens when the session exits; this binding runs the very
-- same sync-back mid-session, as often as wanted, so finished work can land
-- on the host while the agent keeps going.
--
-- The runner publishes this run's sync command as the 'llm_custody_sync'
-- user var (OSC 1337 SetUserVar, tmux DCS passthrough handled on its side)
-- and clears it when the session ends - same mechanism the snippet capture
-- and the alert_state tab marker use.

local wezterm = require('wezterm')
local M = {}

-- The sync prompts y/N per changed tree and prints what it applied, so it
-- needs a terminal of its own - and one that stays up afterwards. A bare
-- spawn would close the pane the moment the script exits, taking the report
-- (including a declined sync) with it.
local function hold_open(cmd)
  return {
    os.getenv('SHELL') or '/bin/sh',
    '-c',
    cmd .. '; printf "\\n[llm-custody sync finished, press enter to close]"; read -r _',
  }
end

M.sync = wezterm.action_callback(function(window, pane)
  local sync = pane:get_user_vars().llm_custody_sync
  if not sync or sync == '' then
    window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
    return
  end
  -- The user var survives ssh, the runtime dir it points at does not: a jail
  -- running on a remote host advertises a path that exists only there.
  local f = io.open(sync, 'r')
  if not f then
    window:toast_notification('llm-custody', 'sync command is not on this host: ' .. sync, nil, 5000)
    return
  end
  f:close()
  -- SplitPane rather than SplitVertical: only the former takes a size.
  window:perform_action(
    wezterm.action.SplitPane({
      direction = 'Down',
      command = { args = hold_open(sync) },
      size = { Percent = 35 },
    }),
    pane
  )
end)

return M
