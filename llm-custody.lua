-- llm-custody jail integration: mid-session sync, live mounts, toolbox
-- provisioning, answering package requests, and the jail tab badge.
--
-- Host side is one command, `llm-custody`, with a subcommand per feature;
-- sync and mount are reached through the session's own launchers instead,
-- which is what the runner publishes as user vars.
--
-- The runner (and, for requests, the session's broker) publishes session
-- facts as OSC 1337 user vars, tmux DCS passthrough handled on its side,
-- cleared when the session ends:
--   llm_custody_state        key=value lines: state/tool/pid/workspace/git/
--                            overlay, plus sync when a tree is isolated
--   llm_custody_toolbox      directory of the session's package profile
--   llm_custody_toolbox_cmd  store path of the host-side `llm-custody` CLI,
--                            whose subcommands cover the toolbox and the
--                            request queue (a `nix run` jail puts nothing on
--                            the host's PATH). The var keeps its original
--                            name because every consumer keys on it
--   llm_custody_jail         set for the whole session
--   llm_custody_dirty        unsynced path count, empty while there are none
--   llm_custody_requests     packages the agent is blocked waiting on, empty
--                            while there are none
--   llm_custody_mount        the session's mount launcher (add/remove/list),
--                            also the `mount` key of the state record

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
      ('nothing to sync - --git %s writes straight to %s'):format(
        st.git or '?',
        st.workspace or 'the host tree'
      ),
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

-- Fallback for list_packages below: package names and their lease state
-- read from files, for a session whose CLI predates `lease list --json`. It
-- cannot tell how old a lease is. current/manifest.json is the profile nix
-- built, with `elements` keyed by element name (an older manifest's
-- unnamed array yields no string keys and so no rows, the CLI refuses such a
-- profile too). leases/ holds one file per leased element, so an element
-- without one is permanent and a lease without an element is left over from
-- a hand-run `nix profile remove`.
local function read_packages(dir)
  local state = {}
  local f = io.open(dir .. '/current/manifest.json', 'r')
  if f then
    local raw = f:read('*a')
    f:close()
    local ok, manifest = pcall(wezterm.json_parse, raw)
    if ok and type(manifest) == 'table' and type(manifest.elements) == 'table' then
      for name in pairs(manifest.elements) do
        if type(name) == 'string' then
          state[name] = 'permanent'
        end
      end
    end
  end
  for _, path in ipairs(wezterm.glob(dir .. '/leases/*')) do
    local name = path:match('([^/]+)$')
    -- Dotted names are a concurrent writer's in-flight temp files.
    if name and name:sub(1, 1) ~= '.' then
      state[name] = state[name] and 'leased' or 'orphan'
    end
  end
  local out = {}
  for name, st in pairs(state) do
    out[#out + 1] = { name = name, state = st }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- What each lease state offers, first row being the one enter picks. Remove
-- leads only for an orphan, where dropping the lease is all there is to do.
local PACKAGE_ACTIONS = {
  leased = {
    { id = 'pin', label = 'make permanent  (drop the lease, never pruned)' },
    { id = 'renew', label = 'renew lease' },
    { id = 'remove', label = 'remove  (gone from every jail PATH immediately)' },
  },
  permanent = {
    { id = 'renew', label = 'put under a lease  (pruned when it goes unrenewed)' },
    { id = 'remove', label = 'remove  (gone from every jail PATH immediately)' },
  },
  orphan = {
    { id = 'remove', label = 'drop the lease  (the package is already gone)' },
  },
}

local PACKAGE_STATE_LABEL = {
  leased = 'leased',
  permanent = 'permanent',
  orphan = 'lease only, not installed',
}

-- Seconds as the largest unit that fits, for a picker label.
local function short_duration(secs)
  if secs >= 86400 then
    return ('%dd'):format(secs // 86400)
  elseif secs >= 3600 then
    return ('%dh'):format(secs // 3600)
  elseif secs >= 60 then
    return ('%dm'):format(secs // 60)
  end
  return ('%ds'):format(secs)
end

-- The toolbox as the CLI reports it: `lease list --json` gives each package
-- its state plus the lease age and time left, which the files alone do not.
-- It runs nix once, so this picker opens a moment later than the file-backed
-- ones; that is the price of showing when a lease runs out. Each entry gets
-- a `detail` string for its label. An older CLI rejects --json, and then
-- the file reader answers instead.
local function list_packages(dir, cmd)
  local ok, stdout = wezterm.run_child_process({ cmd, '--dir', dir, 'lease', 'list', '--json' })
  local parsed = nil
  if ok then
    local good, v = pcall(wezterm.json_parse, stdout)
    if good and type(v) == 'table' and type(v.packages) == 'table' then
      parsed = v.packages
    end
  end
  local out = {}
  if not parsed then
    for _, pkg in ipairs(read_packages(dir)) do
      pkg.detail = PACKAGE_STATE_LABEL[pkg.state]
      out[#out + 1] = pkg
    end
    return out
  end
  for _, p in ipairs(parsed) do
    if type(p.name) == 'string' then
      local state, detail = p.state, nil
      if state == 'leased' and type(p.left) == 'number' then
        detail = 'leased, expires in ' .. short_duration(math.floor(p.left))
      elseif state == 'expired' then
        -- Still installed until the next prune, and still renewable, so it
        -- gets the leased actions.
        state, detail = 'leased', 'lease EXPIRED, goes at the next prune'
      end
      if PACKAGE_ACTIONS[state] then
        out[#out + 1] = { name = p.name, state = state, detail = detail or PACKAGE_STATE_LABEL[state] }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Package operations on the running jail's toolbox: add, remove, pin, renew.
-- The sandbox cannot install anything itself (/nix/store read-only, no binary
-- cache whitelisted), so the agent asks by ending a reply with
-- `required packages: <attrs>`; that whole line can be pasted into the add
-- prompt, `llm-custody toolbox add` strips labels and commas.
-- The toolbox is a live bind, so the next PATH lookup inside the jail finds
-- an added binary (and misses a removed one) without a restart.
--
-- The picker comes back after every action that finishes in place (pin,
-- renew, remove), re-read from disk, so several packages can be handled from
-- one keypress; escape on the list leaves, escape on a package's actions
-- goes back to the list. Add is the exception: it prints a nix build log
-- into a split of its own, and the picker ends there.
local function show_packages(window, pane, dir, cmd)
  -- Runs to completion before the list is drawn again, and reports through
  -- a toast. The CLI writes its notes to stderr.
  local function in_place(w, group, verb, name)
    local ok, stdout, stderr = wezterm.run_child_process({ cmd, '--dir', dir, group, verb, name })
    local msg = ((stderr or '') .. (stdout or '')):gsub('%s+$', '')
    if msg == '' then
      msg = ('%s %s'):format(verb, name)
    end
    w:toast_notification('llm-custody', (ok and '' or 'failed: ') .. msg, nil, 5000)
  end

  local choices = { { id = 'add', label = '+ add packages' } }
  local by_name = {}
  for _, pkg in ipairs(list_packages(dir, cmd)) do
    by_name[pkg.name] = pkg
    choices[#choices + 1] = {
      id = 'pkg:' .. pkg.name,
      label = ('%s  (%s)'):format(pkg.name, pkg.detail),
    }
  end

  window:perform_action(
    wezterm.action.InputSelector({
      title = 'llm-custody packages  (esc to close)',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id)
        if not id then
          return
        end

        if id == 'add' then
          inner_window:perform_action(
            wezterm.action.PromptInputLine({
              description = 'nixpkgs attributes to add to the jail toolbox (lua5_4, shellcheck, ...):',
              action = wezterm.action_callback(function(w2, p2, line)
                -- nil when the prompt was cancelled; blank when it was just
                -- confirmed. Either way nothing was asked for, so back to
                -- the list.
                if not line or line:match('^%s*$') then
                  show_packages(w2, p2, dir, cmd)
                  return
                end
                w2:perform_action(
                  wezterm.action.SplitPane({
                    direction = SPLIT_DIRECTION,
                    command = {
                      args = hold_open(
                        '"$1" --dir "$2" toolbox add "$3"',
                        'llm-custody toolbox add',
                        cmd,
                        dir,
                        line
                      ),
                    },
                    size = { Percent = 35 },
                  }),
                  p2
                )
              end),
            }),
            inner_pane
          )
          return
        end

        local pkg = by_name[id:sub(#'pkg:' + 1)]
        if not pkg then
          return
        end
        inner_window:perform_action(
          wezterm.action.InputSelector({
            title = ('%s  (%s)  - esc to go back'):format(pkg.name, pkg.detail),
            choices = PACKAGE_ACTIONS[pkg.state],
            action = wezterm.action_callback(function(w2, p2, action)
              if action == 'remove' or action == 'pin' or action == 'renew' then
                in_place(w2, 'lease', action, pkg.name)
              end
              show_packages(w2, p2, dir, cmd)
            end),
          }),
          inner_pane
        )
      end),
    }),
    pane
  )
end

M.packages = wezterm.action_callback(function(window, pane)
  local vars = pane:get_user_vars()
  local dir = vars.llm_custody_toolbox
  if not dir or dir == '' then
    window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
    return
  end
  -- Bare name is only a fallback for a runner predating the _cmd var.
  local cmd = vars.llm_custody_toolbox_cmd
  if not cmd or cmd == '' then
    cmd = 'llm-custody'
  end
  -- Same ssh reason as M.sync; without the probe a remote jail would have
  -- llm-custody mkdir a stray local toolbox and build into it.
  -- io.open works as an existence test because the C fopen underneath opens a
  -- directory in read mode and only returns nil when the path is absent.
  local d = io.open(dir, 'r')
  if not d then
    window:toast_notification('llm-custody', 'toolbox is not on this host: ' .. dir, nil, 5000)
    return
  end
  d:close()
  show_packages(window, pane, dir, cmd)
end)

-- The modes a live mount can be attached in, in the order the picker shows
-- them: safest first, so the default (top row, enter) is read-only.
local MOUNT_MODES = {
  { id = 'ro', label = 'ro       read-only bind' },
  { id = 'limited', label = 'limited  copy with a baseline repo, synced back on request and at exit' },
  { id = 'none', label = 'none     same copy without a repo' },
  { id = 'overlay', label = 'overlay  copy-on-write over the real tree, synced only on confirmation' },
  { id = 'full', label = 'full     the real tree read-write - writes hit the host immediately' },
}

-- The session's current mounts, read straight from the controller's record
-- files under the runtime dir rather than by spawning `list`: a picker is
-- built on every keypress and must not wait on a process. The launcher path
-- is RUNDIR/mount, so the rundir is its parent.
local function read_mounts(launcher)
  local rundir = launcher:match('^(.*)/mount$')
  local mounts = {}
  if not rundir then
    return mounts
  end
  for _, path in ipairs(wezterm.glob(rundir .. '/mounts/*/record')) do
    local f = io.open(path, 'r')
    if f then
      local rec = parse_state(f:read('*a')) or {}
      f:close()
      if rec.name then
        mounts[#mounts + 1] = rec
      end
    end
  end
  table.sort(mounts, function(a, b) return a.name < b.name end)
  return mounts
end

-- Runs the launcher with the given arguments in a held-open split, so the
-- controller's own output (and remove's sync prompt) has a terminal.
local function mount_pane(window, pane, launcher, ...)
  window:perform_action(
    wezterm.action.SplitPane({
      direction = SPLIT_DIRECTION,
      -- $1 is the launcher, the rest its arguments: shifted off one by one
      -- rather than spliced into the command string, so a path with shell
      -- syntax in it stays one argument.
      command = { args = hold_open('l="$1"; shift; "$l" "$@"', 'llm-custody mount', launcher, ...) },
      size = { Percent = 35 },
    }),
    pane
  )
end

-- The last non-blank line of a launcher's stderr: its own statement of what
-- went wrong, short enough for a toast.
local function last_line(text)
  local last = nil
  for line in (text or ''):gmatch('[^\n]+') do
    if not line:match('^%s*$') then
      last = line
    end
  end
  return last
end

-- Modes whose removal has nothing to sync back, so it cannot prompt and can
-- run in place. Every other mode is a copy or an overlay, and removing one
-- asks about its unsynced changes, which needs a terminal.
local MOUNT_DIRECT_MODES = { ro = true, full = true }

-- Attach a host tree to the running jail, or detach one. One picker: the
-- session's current mounts (pick one to remove it) plus an "add" row that
-- asks for the path and then the mode. The mode is asked rather than typed
-- on the same line because read-only has to be the answer of least effort,
-- and `full` deserves to be read before it is chosen.
--
-- The picker comes back after every action that finishes in place (any add,
-- and removing a direct bind), re-read from disk, so several mounts can be
-- handled from one keypress; escape on the list leaves, escape below it goes
-- back to the list. Removing a copy or an overlay is the exception: it
-- prompts for the sync-back in a split of its own, and the picker ends
-- there.
local function show_mounts(window, pane, launcher)
  local function back(w, p) show_mounts(w, p, launcher) end

  -- Runs to completion and reports through a toast. The controller prints
  -- `GUEST<TAB>POINT<TAB>FIXED` on stdout for an add and its diagnostics on
  -- stderr. The arguments are an argv array, so a path never meets a shell.
  local function in_place(w, what, ...)
    local ok, stdout, stderr = wezterm.run_child_process({ launcher, ... })
    local msg
    if ok then
      local guest = (stdout or ''):match('^([^\t\n]+)')
      msg = guest and ('%s at %s'):format(what, guest) or what
    else
      msg = ('%s failed: %s'):format(what, last_line(stderr) or 'no reason given')
    end
    w:toast_notification('llm-custody', msg, nil, 5000)
  end

  local mounts = read_mounts(launcher)
  local by_name = {}
  local choices = { { id = 'add', label = '+ mount a host path' } }
  for _, m in ipairs(mounts) do
    by_name[m.name] = m
    local tail = m.fixed == '1' and ', fixed' or ''
    choices[#choices + 1] = {
      id = 'rm:' .. m.name,
      label = ('- remove %s  (%s %s <- %s%s)'):format(
        m.name,
        m.mode or '?',
        m.guest or '?',
        m.host or '?',
        tail
      ),
    }
  end

  window:perform_action(
    wezterm.action.InputSelector({
      title = 'llm-custody mounts  (esc to close)',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id)
        if not id then
          return
        end
        if id:sub(1, 3) == 'rm:' then
          local name = id:sub(4)
          local m = by_name[name]
          if m and MOUNT_DIRECT_MODES[m.mode or ''] then
            in_place(inner_window, 'removed ' .. name, 'remove', name)
            back(inner_window, inner_pane)
          else
            mount_pane(inner_window, inner_pane, launcher, 'remove', name)
          end
          return
        end
        inner_window:perform_action(
          wezterm.action.PromptInputLine({
            description = 'host path to mount (lands under /workspace, named after its last component):',
            action = wezterm.action_callback(function(w2, p2, line)
              if not line or line:match('^%s*$') then
                back(w2, p2)
                return
              end
              -- extra parens: drop gsub's 2nd return (count), same trap as
              -- snippets.lua
              local path = (line:gsub('^%s+', ''):gsub('%s+$', ''))
              w2:perform_action(
                wezterm.action.InputSelector({
                  title = 'mode for ' .. path .. '  - esc to go back',
                  choices = MOUNT_MODES,
                  action = wezterm.action_callback(function(w3, p3, mode)
                    if mode then
                      if not MOUNT_DIRECT_MODES[mode] then
                        -- A copy of a large tree takes a while and prints
                        -- nothing until it is done.
                        w3:toast_notification('llm-custody', 'copying ' .. path .. ' ...', nil, 3000)
                      end
                      in_place(w3, ('mounted %s (%s)'):format(path, mode), 'add', '--mode', mode, '--', path)
                    end
                    back(w3, p3)
                  end),
                }),
                p2
              )
            end),
          }),
          inner_pane
        )
      end),
    }),
    pane
  )
end

M.mount = wezterm.action_callback(function(window, pane)
  local vars = pane:get_user_vars()
  local launcher = vars.llm_custody_mount
  if not launcher or launcher == '' then
    local st = parse_state(vars.llm_custody_state)
    launcher = st and st.mount or nil
  end
  if not launcher or launcher == '' then
    if not vars.llm_custody_jail or vars.llm_custody_jail == '' then
      window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
    else
      window:toast_notification(
        'llm-custody',
        'this session was started by a runner without live mounts',
        nil,
        5000
      )
    end
    return
  end
  -- Same ssh reason as M.sync.
  local f = io.open(launcher, 'r')
  if not f then
    window:toast_notification('llm-custody', 'mount launcher is not on this host: ' .. launcher, nil, 5000)
    return
  end
  f:close()
  show_mounts(window, pane, launcher)
end)

-- How long an approved domain lasts. Session first: the jail is gone in an
-- hour, the domains file is forever, so the cheaper answer is the default.
local DOMAIN_ADD_SCOPES = {
  { id = 'session', label = 'session  this jail run only' },
  { id = 'persist', label = 'persist  also append it to the state root domains file' },
}

local DOMAIN_RM_SCOPES = {
  { id = 'session', label = 'session  stop allowing it in this jail run' },
  { id = 'persist', label = 'persist  also drop it from the state root domains file' },
}

-- The whitelist as the controller currently sees it, read from its own
-- source-of-truth file for the same reason read_mounts avoids `list`: this
-- builds on every keypress. Lines are NAME<TAB>SOURCE; the launcher path is
-- RUNDIR/domain, so the rundir is its parent.
local function read_domains(launcher)
  local rundir = launcher:match('^(.*)/domain$')
  local domains = {}
  if not rundir then
    return domains
  end
  local f = io.open(rundir .. '/domains.active', 'r')
  if not f then
    return domains
  end
  for line in f:lines() do
    local name, source = line:match('^([^\t]+)\t(.*)$')
    if name then
      domains[#domains + 1] = { name = name, source = source }
    end
  end
  f:close()
  table.sort(domains, function(a, b) return a.name < b.name end)
  return domains
end

-- One whitelist change, run to completion through the session's launcher
-- and reported through a toast, so the picker can come back with the result
-- already in domains.active. The arguments are an argv array, so a domain
-- never meets a shell. On failure the launcher's last stderr line is its own
-- statement of what went wrong.
local function domain_change(window, launcher, verb, persist, name)
  local argv = { launcher, verb }
  if persist then
    argv[#argv + 1] = '--persist'
  end
  argv[#argv + 1] = '--'
  argv[#argv + 1] = name
  local ok, _, stderr = wezterm.run_child_process(argv)
  local msg
  if ok then
    msg = ('%s %s%s'):format(verb == 'add' and 'allowed' or 'removed', name, persist and ' (persisted)' or '')
  else
    msg = ('%s %s failed: %s'):format(verb, name, last_line(stderr) or 'no reason given')
  end
  window:toast_notification('llm-custody', msg, nil, 5000)
end

-- Manage what the jail may reach, from the pane the agent runs in. The rows
-- that come from a file are built inline; the blocked list is the one thing
-- that needs the controller (it parses the dnsmasq log), so it is spawned
-- only once that row is chosen, never while the first picker is drawn.
--
-- The picker comes back after every change, re-read from disk, so several
-- domains can be handled from one keypress; escape on the list leaves,
-- escape anywhere below it goes back to the list. `» full menu` is the
-- exception: it hands over to the CLI's own menu in a split.
local function show_domains(window, pane, launcher, cmd)
  local function back(w, p) show_domains(w, p, launcher, cmd) end

  -- Second step of both add paths (typed name and promoted blocked name),
  -- so the scope question is asked once in one place.
  local function ask_add_scope(w, p, name)
    w:perform_action(
      wezterm.action.InputSelector({
        title = 'allow ' .. name .. '  - esc to go back',
        choices = DOMAIN_ADD_SCOPES,
        action = wezterm.action_callback(function(w2, p2, scope)
          if scope then
            domain_change(w2, launcher, 'add', scope == 'persist', name)
          end
          back(w2, p2)
        end),
      }),
      p
    )
  end

  local choices = {
    { id = 'add', label = '+ allow a domain' },
    { id = 'blocked', label = '? blocked requests  (what the filter refused, pick one to allow it)' },
    { id = 'menu', label = '» full menu  (pending agent requests, allowed, blocked)' },
  }
  local active = read_domains(launcher)
  for _, d in ipairs(active) do
    choices[#choices + 1] = {
      id = 'rm:' .. d.name,
      label = ('- remove %s  (%s)'):format(d.name, d.source or '?'),
    }
  end

  window:perform_action(
    wezterm.action.InputSelector({
      title = 'llm-custody domains  (esc to close)',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id)
        if not id then
          return
        end

        if id == 'menu' then
          -- `llm-custody domain` with no subcommand is the only place a
          -- pending agent request can be approved, and it prompts, so it
          -- gets a terminal of its own. It finds the session through the
          -- runtime registry, so it takes no argument naming one.
          inner_window:perform_action(
            wezterm.action.SplitPane({
              direction = SPLIT_DIRECTION,
              command = { args = hold_open('"$1" domain', 'llm-custody domain', cmd) },
              size = { Percent = 35 },
            }),
            inner_pane
          )
          return
        end

        if id == 'add' then
          inner_window:perform_action(
            wezterm.action.PromptInputLine({
              description = 'domain to allow (hostname only, subdomains included):',
              action = wezterm.action_callback(function(w2, p2, line)
                if not line or line:match('^%s*$') then
                  back(w2, p2)
                  return
                end
                -- extra parens: drop gsub's 2nd return (count), same trap as
                -- snippets.lua
                local name = (line:gsub('^%s+', ''):gsub('%s+$', ''))
                ask_add_scope(w2, p2, name)
              end),
            }),
            inner_pane
          )
          return
        end

        if id == 'blocked' then
          local ok, stdout = wezterm.run_child_process({ launcher, 'blocked' })
          local blocked = {}
          if ok then
            for line in stdout:gmatch('[^\n]+') do
              local count, name = line:match('^(%d+)\t(.+)$')
              if name then
                blocked[#blocked + 1] = {
                  id = name,
                  label = ('%s  (%s lookup%s)'):format(name, count, count == '1' and '' or 's'),
                }
              end
            end
          end
          if #blocked == 0 then
            inner_window:toast_notification(
              'llm-custody',
              ok and 'nothing has been blocked in this session yet' or 'could not read the blocked names',
              nil,
              3000
            )
            back(inner_window, inner_pane)
            return
          end
          inner_window:perform_action(
            wezterm.action.InputSelector({
              title = 'blocked in this session - pick one to allow it, esc to go back',
              choices = blocked,
              fuzzy = true,
              action = wezterm.action_callback(function(w2, p2, name)
                if not name then
                  back(w2, p2)
                  return
                end
                ask_add_scope(w2, p2, name)
              end),
            }),
            inner_pane
          )
          return
        end

        local name = id:sub(4)
        local source = nil
        for _, d in ipairs(active) do
          if d.name == name then
            source = d.source
          end
        end
        -- A default comes from tools.nix, so there is no file line to drop
        -- and the controller refuses --persist for it: don't offer it.
        local scopes = DOMAIN_RM_SCOPES
        if source == 'default' then
          scopes = { DOMAIN_RM_SCOPES[1] }
        end
        inner_window:perform_action(
          wezterm.action.InputSelector({
            title = 'stop allowing ' .. name .. '  - esc to go back',
            choices = scopes,
            action = wezterm.action_callback(function(w2, p2, scope)
              if scope then
                domain_change(w2, launcher, 'remove', scope == 'persist', name)
              end
              back(w2, p2)
            end),
          }),
          inner_pane
        )
      end),
    }),
    pane
  )
end

M.domain = wezterm.action_callback(function(window, pane)
  local vars = pane:get_user_vars()
  local launcher = vars.llm_custody_domain
  if not launcher or launcher == '' then
    local st = parse_state(vars.llm_custody_state)
    launcher = st and st.domain or nil
  end
  if not launcher or launcher == '' then
    if not vars.llm_custody_jail or vars.llm_custody_jail == '' then
      window:toast_notification('llm-custody', 'no live jail session in this pane', nil, 3000)
    else
      -- The runner only writes the launcher when it filters the network, so
      -- an empty one is --no-net-filter rather than an old runner.
      window:toast_notification('llm-custody', 'this session runs without a network filter', nil, 5000)
    end
    return
  end
  -- Same ssh reason as M.sync.
  local f = io.open(launcher, 'r')
  if not f then
    window:toast_notification('llm-custody', 'domain launcher is not on this host: ' .. launcher, nil, 5000)
    return
  end
  f:close()
  -- Bare name is only a fallback for a runner predating the _cmd var, same
  -- as M.packages.
  local cmd = vars.llm_custody_toolbox_cmd
  if not cmd or cmd == '' then
    cmd = 'llm-custody'
  end
  show_domains(window, pane, launcher, cmd)
end)

-- Answer the package requests a jailed agent is blocked on. The picker lives
-- in the CLI (`llm-custody request answer`), so this only finds the session's
-- copy of it.
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
    cmd = 'llm-custody'
  end
  window:perform_action(
    wezterm.action.SplitPane({
      direction = SPLIT_DIRECTION,
      command = { args = hold_open('"$1" request answer', 'llm-custody requests', cmd) },
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
-- exact number is in the sync pane and `llm-custody session list`.
--
-- U+25A5 rather than a CJK glyph: it is East Asian Ambiguous, so WezTerm
-- gives it one column instead of the two a fullwidth character claims.
-- badge_width() measures instead of assuming, so this survives
-- treat_east_asian_ambiguous_width_as_wide.
local MARK = '▥'

-- Same palette as tab.lua's ALERT_STATES.
local DIRTY_COLOR = '#03fc52'
-- Background of a tab whose agent is blocked on a request: the red of
-- ALERT_STATES.waiting, since both mean "nothing moves until you answer".
M.REQUEST_BACKGROUND = '#fb4934'

local function pending(v) return v ~= nil and v ~= '' and v ~= '0' end

-- User vars of the tab's jail, or nil for a tab that is not one.
--
-- Active pane only - PaneInformation carries no tab_id and format-tab-title
-- hands over the active tab's panes, so a jail in a background split of
-- another tab does not badge it (same limitation as alert_state).
local function jail_vars(tab_info)
  local pane = tab_info.active_pane
  if not pane then
    return nil
  end
  local vars = pane.user_vars or {}
  local jail = vars.llm_custody_jail
  if not jail or jail == '' then
    return nil
  end
  return vars
end

-- True while the agent in this tab waits on a package, mount or domain
-- request. tab.lua paints the whole tab for it rather than just the badge: a
-- blocked agent wastes the session until somebody notices, and one recolored
-- cell is easy to miss in a full tab bar.
function M.request_pending(tab_info)
  local vars = jail_vars(tab_info)
  return vars ~= nil and pending(vars.llm_custody_requests)
end

function M.tab_badge(tab_info)
  local vars = jail_vars(tab_info)
  if not vars then
    return nil
  end
  -- Not while a request is pending: the tab background is REQUEST_BACKGROUND
  -- then, and green on that red is unreadable.
  if pending(vars.llm_custody_dirty) and not pending(vars.llm_custody_requests) then
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
