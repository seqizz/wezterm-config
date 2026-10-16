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
--
-- Two further vars drive the tab badge at the bottom of this file:
-- 'llm_custody_jail' (set for the whole session) and 'llm_custody_dirty'
-- (the count of unsynced paths, empty while there are none).

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

-- Tab badge: marks a tab as jailed, and shows how much work is sitting in
-- the jail unsynced.
--
-- The count is the part that earns its cells. A jail copy holding finished
-- work looks exactly like one holding none, and without this the first
-- moment that difference surfaces is the sync prompt at exit - long after
-- the point where you would have wanted to land it and keep going.
--
-- Only the marker glyph is taken from 'llm_custody_jail', not the whole
-- value ('▥ pi'): the tab bar is tight and the tool name is already in the
-- pane title.
--
-- The badge is deliberately constant width, carrying the *state* in its
-- color rather than the count in its text. Two reasons, both about the
-- grow-to-need sizing in tab.lua: a badge that gains a cell when the count
-- crosses 9 reflows every tab in the bar, and it does so every time the
-- agent writes a file - and the wider the badge, the sooner the whole bar
-- hits the point where titles can no longer shrink to absorb it. The exact
-- number is a detail, available in the sync pane and from
-- `llm-custody-sync --list`; what belongs in a tab bar is whether there is
-- anything waiting at all.
-- U+25A5 rather than a CJK glyph: it is East Asian Ambiguous, so WezTerm
-- gives it one column (ambiguous defaults to narrow) instead of the two a
-- fullwidth character claims. Halves what the badge costs every jailed tab
-- in a bar that is already fighting over cells. badge_width() measures it
-- with column_width rather than assuming, so this stays correct even under
-- treat_east_asian_ambiguous_width_as_wide.
local MARK = '▥'

-- Gruvbox bright red, same palette as tab.lua's ALERT_STATES. Chosen over
-- the darker reds because the tab that most needs to catch the eye is an
-- *inactive* one, and those are drawn on mid-gray.
local DIRTY_COLOR = '#fb4934'

M.dirty_color = DIRTY_COLOR

-- Returns (badge, dirty) for a TabInformation, or nil when the tab is not a
-- jail session. `dirty` tells the caller whether to paint it.
--
-- Reads the tab's *active* pane only - same limitation as alert_state, since
-- PaneInformation carries no tab_id and format-tab-title only hands over the
-- active tab's pane list. A jail running in a background split of another
-- tab therefore does not badge that tab.
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
  local dirty = vars.llm_custody_dirty
  -- The runner clears the var rather than sending '0', but tolerate both:
  -- a consumer that writes the file-based count straight into the var would
  -- otherwise badge every clean session as dirty.
  return MARK, (dirty ~= nil and dirty ~= '' and dirty ~= '0')
end

-- Cells the badge claims, including the space separating it from the title.
-- tab.lua's grow-to-need sizing budgets title width from the decoration
-- width of every tab, so a badge that is not counted here would push the
-- last tab's title past the edge of the bar.
function M.badge_width(tab_info)
  local badge = M.tab_badge(tab_info)
  if not badge then
    return 0
  end
  return wezterm.column_width(badge) + 1
end

return M
