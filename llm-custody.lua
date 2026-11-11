-- llm-custody jail integration: mid-session sync, toolbox provisioning,
-- answering package requests, and the jail tab badge.
--
-- The runner (and, for requests, the session's broker) publishes session
-- facts as OSC 1337 user vars, tmux DCS passthrough handled on its side,
-- cleared when the session ends:
--   llm_custody_state        key=value lines: state/tool/pid/workspace/git/
--                            overlay, plus sync when a tree is isolated
--   llm_custody_toolbox      directory of the session's package profile
--   llm_custody_toolbox_cmd  store path of the host-side CLI (a `nix run`
--                            jail puts nothing on the host's PATH)
--   llm_custody_jail         set for the whole session
--   llm_custody_dirty        unsynced path count, empty while there are none
--   llm_custody_requests     packages the agent is blocked waiting on, empty
--                            while there are none

local wezterm = require('wezterm')
local M = {}

-- Where the panes this file spawns go.
local SPLIT_DIRECTION = 'Down'

-- These commands prompt and report (sync asks y/N per tree, toolbox prints a
-- nix build log), so the pane has to outlive them; `exit 0` stops a failed
-- command from making WezTerm hold the pane a second time with its own
-- message. Caller values are passed as positional arguments, never
-- concatenated into cmd, so `$SHELL -c` cannot re-parse them as shell syntax.
local function hold_open(cmd, label, ...)
  local args = {
    os.getenv('SHELL') or '/bin/sh',
    '-c',
    cmd .. '; printf "\\n[' .. label .. ' finished, press enter to close]"; read -r _; exit 0',
    -- $0 for the -c script; the caller's values start at $1.
    'llm-custody',
  }
  for _, v in ipairs({ ... }) do
    args[#args + 1] = v
  end
  return args
end

-- Splits on the first '=' only, since values are paths. Unknown keys are kept
-- and never read, so the runner can grow the record without a change here.
local function parse_state(raw)
  if not raw or raw == '' then
    return nil
  end
  local state = {}
  for line in raw:gmatch('[^\n]+') do
    local k, v = line:match('^([^=]+)=(.*)$')
    if k then
      state[k] = v
    end
  end
  return state
end

M.sync = wezterm.action_callback(function(window, pane)
  local vars = pane:get_user_vars()
  local st = parse_state(vars.llm_custody_state)
  if not st then
    -- A runner predating the state record publishes only the bare sync path,
    -- and its session outlives the rebuild that replaced it.
    local legacy = vars.llm_custody_sync
    if not legacy or legacy == '' then
      window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
      return
    end
    st = { sync = legacy }
  end
  local sync = st.sync
  if not sync or sync == '' then
    -- Live jail with nothing isolated from the host: the changes are already
    -- in the real tree, there is no sync-back to run.
    window:toast_notification(
      'llm-custody',
      ('nothing to sync - --git %s writes straight to %s'):format(st.git or '?', st.workspace or 'the host tree'),
      nil,
      5000
    )
    return
  end
  -- The user var survives ssh, the runtime dir it points at does not.
  local f = io.open(sync, 'r')
  if not f then
    window:toast_notification('llm-custody', 'sync command is not on this host: ' .. sync, nil, 5000)
    return
  end
  f:close()
  -- SplitPane rather than SplitVertical: only the former takes a size.
  window:perform_action(
    wezterm.action.SplitPane({
      direction = SPLIT_DIRECTION,
      command = { args = hold_open('"$1"', 'llm-custody sync', sync) },
      size = { Percent = 35 },
    }),
    pane
  )
end)

-- Provision a package into the running jail's PATH. The sandbox cannot
-- install anything itself (/nix/store read-only, no binary cache whitelisted),
-- so the agent asks by ending a reply with `required packages: <attrs>`; that
-- whole line can be pasted here, llm-custody-toolbox strips labels and commas.
-- The toolbox is a live bind, so the next PATH lookup inside the jail finds
-- the new binary and nothing restarts.
M.toolbox = wezterm.action_callback(function(window, pane)
  local vars = pane:get_user_vars()
  local dir = vars.llm_custody_toolbox
  if not dir or dir == '' then
    window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
    return
  end
  -- Bare name is only a fallback for a runner predating the _cmd var.
  local cmd = vars.llm_custody_toolbox_cmd
  if not cmd or cmd == '' then
    cmd = 'llm-custody-toolbox'
  end
  -- Same ssh reason as M.sync; without the probe a remote jail would have
  -- llm-custody-toolbox mkdir a stray local toolbox and build into it.
  -- io.open works as an existence test because the C fopen underneath opens a
  -- directory in read mode and only returns nil when the path is absent.
  local d = io.open(dir, 'r')
  if not d then
    window:toast_notification('llm-custody', 'toolbox is not on this host: ' .. dir, nil, 5000)
    return
  end
  d:close()
  window:perform_action(
    wezterm.action.PromptInputLine({
      description = 'nixpkgs attributes to add to the jail toolbox (lua5_4, shellcheck, ...):',
      action = wezterm.action_callback(function(inner_window, inner_pane, line)
        -- nil when the prompt was cancelled; blank when it was just confirmed.
        if not line or line:match('^%s*$') then
          return
        end
        inner_window:perform_action(
          wezterm.action.SplitPane({
            direction = SPLIT_DIRECTION,
            command = {
              args = hold_open(
                '"$1" --dir "$2" add "$3"',
                'llm-custody toolbox',
                cmd,
                dir,
                line
              ),
            },
            size = { Percent = 35 },
          }),
          inner_pane
        )
      end),
    }),
    pane
  )
end)

-- Answer the package requests a jailed agent is blocked on. The picker lives
-- in llm-custody-toolbox (`answer`), so this only finds the session's CLI.
M.requests = wezterm.action_callback(function(window, pane)
  local vars = pane:get_user_vars()
  local cmd = vars.llm_custody_toolbox_cmd
  if not cmd or cmd == '' then
    -- No jail in this pane at all, as opposed to a runner too old to publish
    -- the store path.
    if not vars.llm_custody_jail or vars.llm_custody_jail == '' then
      window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
      return
    end
    cmd = 'llm-custody-toolbox'
  end
  window:perform_action(
    wezterm.action.SplitPane({
      direction = SPLIT_DIRECTION,
      command = { args = hold_open('"$1" answer', 'llm-custody requests', cmd) },
      size = { Percent = 35 },
    }),
    pane
  )
end)

-- Tab badge: marks a tab as jailed and whether work is waiting there.
--
-- Only the glyph is taken from 'llm_custody_jail', not the whole value
-- ('▥ pi'): the tool name is already in the pane title.
--
-- Constant width, state in the color rather than the count in the text. A
-- badge that gains a cell when the count crosses 9 reflows every tab in the
-- bar (tab.lua's grow-to-need sizing) each time the agent writes a file, and
-- a wider badge hits the point where titles can no longer shrink sooner. The
-- exact number is in the sync pane and `llm-custody-sync --list`.
--
-- U+25A5 rather than a CJK glyph: it is East Asian Ambiguous, so WezTerm
-- gives it one column instead of the two a fullwidth character claims.
-- badge_width() measures instead of assuming, so this survives
-- treat_east_asian_ambiguous_width_as_wide.
local MARK = '▥'

-- Same palette as tab.lua's ALERT_STATES.
local DIRTY_COLOR = '#03fc52'
local REQUEST_COLOR = '#fe8019'

-- Active pane only - PaneInformation carries no tab_id and format-tab-title
-- hands over the active tab's panes, so a jail in a background split of
-- another tab does not badge it (same limitation as alert_state).
function M.tab_badge(tab_info)
  local pane = tab_info.active_pane
  if not pane then
    return nil
  end
  local vars = pane.user_vars or {}
  local jail = vars.llm_custody_jail
  if not jail or jail == '' then
    return nil
  end
  local function pending(v)
    return v ~= nil and v ~= '' and v ~= '0'
  end
  if pending(vars.llm_custody_requests) then
    return MARK, REQUEST_COLOR
  end
  if pending(vars.llm_custody_dirty) then
    return MARK, DIRTY_COLOR
  end
  return MARK, nil
end

-- Includes the separating space: tab.lua budgets title width from every tab's
-- decoration width, so an uncounted badge pushes the last title off the bar.
function M.badge_width(tab_info)
  local badge = M.tab_badge(tab_info)
  if not badge then
    return 0
  end
  return wezterm.column_width(badge) + 1
end

return M
