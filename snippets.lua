-- Terminal snippet capture & paste.
--
-- Local/remote zsh sessions emit a selected command via OSC 1337 SetUserVar
-- (WEZ_SNIPPET_ADD, base64 JSON). This module receives the decoded JSON in the
-- 'user-var-changed' event, stores it in a local JSON file, and offers a picker
-- (M.picker, bound in keys-common.lua) that pastes a chosen snippet into the
-- active pane WITHOUT a trailing newline, so it is inserted but not executed.
--
-- No external helper binary and no run_child_process on the hot path: WezTerm's
-- own wezterm.json_parse/json_encode plus stock Lua io/os are enough. Storage is
-- a JSON file rather than SQLite because WezTerm's Lua has no SQLite binding;
-- fine for the expected volume (hundreds to low thousands of snippets).

local wezterm = require('wezterm')

local M = {}

local STATE_DIR = wezterm.home_dir .. '/.local/state/wezterm'
local STORE = STATE_DIR .. '/snippets.json'
local TMP = STORE .. '.tmp'

local MAX_PAYLOAD = 64 * 1024 -- reject decoded JSON larger than this
local MAX_COMMAND = 16 * 1024 -- reject command text larger than this

-- OSC events are untrusted: any process on the terminal can emit SetUserVar.
-- Reject captures whose command matches an obvious secret marker. Plain-text
-- match (string.find 4th arg = true), case-sensitive on purpose.
local SECRET_PATTERNS = {
  'password=',
  'passwd=',
  'token=',
  'secret=',
  'apikey=',
  'api_key=',
  'Authorization:',
  'AWS_SECRET_ACCESS_KEY',
  'BEGIN PRIVATE KEY',
}

-- Pure Lua has no mkdir. Create the state dir lazily on first save; done here
-- and not at load time because run_child_process yields a coroutine, which is
-- illegal during config eval (only valid inside event/callback contexts).
local dir_ready = false
local function ensure_dir()
  if dir_ready then
    return
  end
  wezterm.run_child_process({ 'mkdir', '-p', STATE_DIR })
  dir_ready = true
end

local function now()
  return os.time()
end

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function load()
  local f = io.open(STORE, 'r')
  if not f then
    return {}
  end
  local data = f:read('*a')
  f:close()
  if not data or data == '' then
    return {}
  end
  local ok, parsed = pcall(wezterm.json_parse, data)
  if not ok or type(parsed) ~= 'table' then
    -- corrupt/partial file: start fresh rather than crash the handler
    return {}
  end
  return parsed
end

local function save(list)
  ensure_dir()
  local f = io.open(TMP, 'w')
  if not f then
    wezterm.log_error('wez-snippets: cannot write ' .. TMP)
    return false
  end
  f:write(wezterm.json_encode(list))
  f:close()
  -- rename is atomic on the same filesystem; guards against a torn file if two
  -- WezTerm processes write concurrently (last writer wins, no partial reads).
  local ok, err = os.rename(TMP, STORE)
  if not ok then
    wezterm.log_error('wez-snippets: rename failed: ' .. tostring(err))
    return false
  end
  return true
end

local function next_id(list)
  local m = 0
  for _, s in ipairs(list) do
    if s.id and s.id > m then
      m = s.id
    end
  end
  return m + 1
end

local function looks_like_secret(text)
  for _, p in ipairs(SECRET_PATTERNS) do
    if text:find(p, 1, true) then
      return true
    end
  end
  return false
end

-- Store a validated payload. Returns record, nil on success or nil, reason on
-- rejection. Dedups by trimmed text: an existing identical snippet gets its
-- use_count bumped instead of a duplicate row.
local function add(payload)
  local text = payload.command
  if type(text) ~= 'string' or #text == 0 then
    return nil, 'empty command'
  end
  if #text > MAX_COMMAND then
    return nil, 'command too large'
  end
  if looks_like_secret(text) then
    return nil, 'looks like secret'
  end

  local list = load()
  local norm = trim(text)
  local t = now()

  for _, s in ipairs(list) do
    if trim(s.text or '') == norm then
      s.use_count = (s.use_count or 0) + 1
      s.updated_at = t
      save(list)
      return s, nil
    end
  end

  local rec = {
    id = next_id(list),
    text = text,
    source = payload.source,
    host = payload.host,
    user = payload.user,
    cwd = payload.cwd,
    created_at = t,
    updated_at = t,
    use_count = 0,
  }
  table.insert(list, rec)
  save(list)
  return rec, nil
end

wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'WEZ_SNIPPET_ADD' then
    return
  end
  -- value arrives already base64-decoded from WezTerm: raw JSON string.
  if type(value) ~= 'string' or #value == 0 or #value > MAX_PAYLOAD then
    return
  end
  local ok, payload = pcall(wezterm.json_parse, value)
  if not ok or type(payload) ~= 'table' then
    wezterm.log_error('wez-snippets: bad JSON payload')
    return
  end
  if payload.kind ~= 'snippet' then
    return
  end

  local rec, err = add(payload)
  if rec then
    local short = rec.text:gsub('%s+', ' ')
    if #short > 60 then
      short = short:sub(1, 57) .. '...'
    end
    window:toast_notification('wez-snippets', 'saved: ' .. short, nil, 3000)
  else
    window:toast_notification('wez-snippets', 'rejected: ' .. tostring(err), nil, 4000)
  end
end)

-- Picker action, bound to a key in keys-common.lua. Lists snippets
-- most-recently-used first and pastes the selection into the active pane.
M.picker = wezterm.action_callback(function(window, pane)
  local list = load()
  if #list == 0 then
    window:toast_notification('wez-snippets', 'no snippets saved', nil, 3000)
    return
  end

  table.sort(list, function(a, b)
    local la, lb = a.last_used_at or 0, b.last_used_at or 0
    if la ~= lb then
      return la > lb
    end
    return (a.use_count or 0) > (b.use_count or 0)
  end)

  local choices = {}
  for _, s in ipairs(list) do
    local preview = (s.text or ''):gsub('%s+', ' ')
    if #preview > 80 then
      preview = preview:sub(1, 77) .. '...'
    end
    local origin = s.host and ('[' .. s.host .. '] ') or ''
    table.insert(choices, { id = tostring(s.id), label = origin .. preview })
  end

  window:perform_action(
    wezterm.action.InputSelector({
      title = 'Snippets',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
        if not id then
          return
        end
        -- reload fresh state so a concurrent capture is not clobbered
        local cur = load()
        for _, s in ipairs(cur) do
          if tostring(s.id) == id then
            s.use_count = (s.use_count or 0) + 1
            s.last_used_at = now()
            save(cur)
            -- strip trailing newline: insert without executing
            inner_pane:send_text((s.text or ''):gsub('\n+$', ''))
            return
          end
        end
      end),
    }),
    pane
  )
end)

return M
