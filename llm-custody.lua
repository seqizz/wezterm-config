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
-- 'llm_custody_state' carries the whole session as a record of key=value
-- lines (state/tool/pid/workspace/git/overlay, plus sync when there is a
-- sync command). That is what M.sync reads, because the absence of a sync
-- command has two very different causes: no jail here at all, or a jail
-- whose trees are bound straight through (--git full without
-- --overlay-workspace), where the host already has everything the agent
-- wrote. The record also makes a key the runner adds later a non-event
-- here: parse_state keeps unknown keys and nothing reads them.
--
-- Two further vars drive M.toolbox below, which prompts for nixpkgs
-- attributes and provisions them into the session's PATH:
-- 'llm_custody_toolbox' (the directory holding that package profile) and
-- 'llm_custody_toolbox_cmd' (the store path of the host-side CLI that fills
-- it, since a `nix run` jail puts nothing on the host's PATH).
--
-- Two further vars drive the tab badge at the bottom of this file:
-- 'llm_custody_jail' (set for the whole session) and 'llm_custody_dirty'
-- (the count of unsynced paths, empty while there are none).

local wezterm = require('wezterm')
local M = {}

-- Both actions below run a command that talks back: the sync prompts y/N per
-- changed tree and reports what it applied, the toolbox install prints a nix
-- build log and the list of commands it added. A bare spawn closes the pane
-- the moment the script exits, taking that report (including a declined sync
-- or a failed build) with it.
--
-- Anything derived from user input is passed as a *positional argument*,
-- never concatenated into `cmd`: `$SHELL -c` would otherwise re-parse a
-- pasted package line as shell syntax.
local function hold_open(cmd, label, ...)
  local args = {
    os.getenv('SHELL') or '/bin/sh',
    '-c',
    cmd .. '; printf "\\n[' .. label .. ' finished, press enter to close]"; read -r _',
    -- $0 for the -c script; the caller's values start at $1.
    'llm-custody',
  }
  for _, v in ipairs({ ... }) do
    args[#args + 1] = v
  end
  return args
end

-- 'llm_custody_state' into a table. Splits on the first '=' only, so a value
-- may contain any number of them (paths legitimately do). Unknown keys are
-- kept and simply never read, which is what lets the runner grow the record
-- without a matching change here.
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
    -- A session started by a runner from before the record existed still
    -- publishes the bare sync path, and outlives the rebuild that replaced
    -- its runner. Treat that path as a one-key record.
    local legacy = vars.llm_custody_sync
    if not legacy or legacy == '' then
      window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
      return
    end
    st = { sync = legacy }
  end
  local sync = st.sync
  if not sync or sync == '' then
    -- Live jail, nothing isolated from the host: there is no sync-back to
    -- run because the changes are already in the real tree.
    window:toast_notification(
      'llm-custody',
      ('nothing to sync - --git %s writes straight to %s'):format(st.git or '?', st.workspace or 'the host tree'),
      nil,
      5000
    )
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
      command = { args = hold_open('"$1"', 'llm-custody sync', sync) },
      size = { Percent = 35 },
    }),
    pane
  )
end)

-- Provision a package into the jail's PATH, mid-session.
--
-- Inside the sandbox /nix/store is read-only and no binary cache is in the
-- domain whitelist, so the agent cannot install anything - `nix build`,
-- `nix-shell` and comma all fail there. It is told to ask instead, ending a
-- reply with `required packages: <nixpkgs attrs>`. This is the other half of
-- that exchange: prompt, build on the host, done.
--
-- The whole request line can be pasted verbatim - llm-custody-toolbox strips
-- the labels and commas - so answering is a copy, a paste and a return.
--
-- The install lands in the session's profile while it keeps running: the
-- toolbox is a live bind, so the next PATH lookup inside the jail finds the
-- new binary. Nothing restarts, which is the point - the agent asked for a
-- tool mid-task and can carry on with it.
M.toolbox = wezterm.action_callback(function(window, pane)
  local vars = pane:get_user_vars()
  local dir = vars.llm_custody_toolbox
  if not dir or dir == '' then
    window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
    return
  end
  -- The runner publishes the provisioning CLI's own store path, because the
  -- documented way to start a jail is `nix run .#pi`, which installs nothing
  -- on the host - there is no llm-custody-toolbox on PATH to call. The bare
  -- name is only a fallback for a runner predating that var.
  local cmd = vars.llm_custody_toolbox_cmd
  if not cmd or cmd == '' then
    cmd = 'llm-custody-toolbox'
  end
  -- Same reason the sync action probes its path: the user var survives ssh,
  -- the directory it names does not, so a jail on a remote host would
  -- otherwise have llm-custody-toolbox mkdir a stray local copy and build
  -- into it. io.open works as an existence test here because the C fopen
  -- underneath it opens a directory in read mode and only returns nil when
  -- the path is absent.
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
            direction = 'Down',
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

-- Gruvbox bright green to be seen, same palette as tab.lua's ALERT_STATES.
local DIRTY_COLOR = '#03fc52'

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
