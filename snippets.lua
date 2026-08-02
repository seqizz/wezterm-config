-- Terminal snippet capture & paste.
--
-- Local/remote zsh sessions emit a selected command via OSC 1337 SetUserVar
-- (WEZ_SNIPPET_ADD, base64 JSON). This module receives the decoded JSON in the
-- 'user-var-changed' event, stores it in a local SQLite database (WAL mode),
-- and offers a picker (M.picker, bound in keys-common.lua) that pastes a chosen
-- snippet into the active pane WITHOUT a trailing newline.
--
-- WezTerm's embedded Lua has no SQLite C binding (package.cpath is a dead end
-- on NixOS), so all operations shell out to the sqlite3 CLI via
-- wezterm.run_child_process. The overhead (~5-10 ms per call) is negligible for
-- user-triggered actions (explicit capture, picker open).

local wezterm = require('wezterm')

local M = {}

local DB_DIR = wezterm.home_dir .. '/syncfolder/dotfiles/snippetstore'
local DB = DB_DIR .. '/snippets.db'

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

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- SQLite does not exist during config eval; run_child_process yields a
-- coroutine, which is illegal outside event/callback contexts. Lazily create
-- the database on first use.
local db_ready = false

local function ensure_db()
  if db_ready then
    return true
  end
  local ok, _, err = wezterm.run_child_process({ 'mkdir', '-p', DB_DIR })
  if not ok then
    wezterm.log_error('wez-snippets: mkdir failed: ' .. tostring(err))
    return false
  end
  -- Schema is split into separate calls because PRAGMA output mixed with DDL
  -- in a single sqlite3 CLI invocation can cause unexpected stdout.
  ok, _, err = wezterm.run_child_process({ 'sqlite3', DB, 'PRAGMA journal_mode=WAL;' })
  if not ok then
    wezterm.log_error('wez-snippets: WAL pragma failed: ' .. tostring(err))
    return false
  end
  ok, _, err = wezterm.run_child_process({ 'sqlite3', DB, [[
    CREATE TABLE IF NOT EXISTS snippets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text TEXT NOT NULL,
      comment TEXT,
      source TEXT,
      host TEXT,
      user TEXT,
      cwd TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      use_count INTEGER NOT NULL DEFAULT 0,
      last_used_at INTEGER
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_text ON snippets(text);
  ]] })
  if not ok then
    wezterm.log_error('wez-snippets: schema creation failed: ' .. tostring(err))
    return false
  end
  -- Migrate databases created before the comment feature: add the column if
  -- absent. ADD COLUMN on an existing column errors, so gate on pragma lookup.
  local ok2, out = wezterm.run_child_process({
    'sqlite3', DB, "SELECT COUNT(*) FROM pragma_table_info('snippets') WHERE name = 'comment';",
  })
  if ok2 and out and trim(out) == '0' then
    wezterm.run_child_process({ 'sqlite3', DB, 'ALTER TABLE snippets ADD COLUMN comment TEXT;' })
  end
  db_ready = true
  return true
end

-- run_child_process returns (success_bool, stdout, stderr).
-- Execute a SQL statement (INSERT/UPDATE/DELETE/DDL). Returns true on success,
-- false on failure. Errors are logged.
local function sql_exec(sql)
  local ok, stdout, stderr = wezterm.run_child_process({ 'sqlite3', DB, sql })
  if not ok then
    wezterm.log_error('wez-snippets: sql exec failed: ' .. tostring(stderr))
    return false
  end
  return true
end

-- Execute a SELECT query with -json output. Returns parsed Lua table on
-- success, empty table on failure.
local function sql_query(sql)
  local ok, stdout, stderr =
    wezterm.run_child_process({ 'sqlite3', DB, '-json', sql })
  if not ok then
    wezterm.log_error('wez-snippets: sql query failed: ' .. tostring(stderr))
    return {}
  end
  if not stdout or stdout == '' then
    return {}
  end
  local ok2, parsed = pcall(wezterm.json_parse, stdout)
  if not ok2 or type(parsed) ~= 'table' then
    wezterm.log_error('wez-snippets: bad json from sqlite3')
    return {}
  end
  return parsed
end

-- Escape a string for safe use as a SQLite string literal.
local function sql_str(s)
  if s == nil then
    return 'NULL'
  end
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

local function now()
  return os.time()
end

local function looks_like_secret(text)
  for _, p in ipairs(SECRET_PATTERNS) do
    if text:find(p, 1, true) then
      return true
    end
  end
  return false
end

-- Id of the last snippet inserted/updated this session. Used to attach a
-- comment-only capture ('# ...') to the snippet just saved. Reset on config
-- reload, in which case attach_comment falls back to the newest DB row.
local last_snippet_id = nil

-- Split a captured line into (command, comment). A trailing note must be set
-- off by whitespace before the '#' (' # ...'), so a '#' glued to command text
-- (URL fragment, printf '%H#') is NOT mistaken for a comment. A line that
-- starts with '#' is a comment-only capture. Returns:
--   command, comment  -> normal capture with a note
--   command, nil      -> plain command, no note
--   nil, comment      -> comment only (no command before the '#')
local function split_comment(raw)
  local s = trim(raw)
  -- Comment-only capture: the whole line is a '# ...' note.
  if s:sub(1, 1) == '#' then
    local comment = trim(s:sub(2))
    return nil, (#comment > 0 and comment or nil)
  end
  -- Command + note: split on the LAST ' #' (whitespace immediately before '#').
  local ws, hash
  local i = 1
  while true do
    local a, b = s:find('%s#', i)
    if not a then
      break
    end
    ws, hash = a, b
    i = b + 1
  end
  if not hash then
    return s, nil
  end
  local cmd = trim(s:sub(1, ws - 1))
  local comment = trim(s:sub(hash + 1))
  if #comment == 0 then
    comment = nil
  end
  if #cmd == 0 then
    return nil, comment
  end
  return cmd, comment
end

-- Attach a comment-only capture to the last saved snippet (or the newest row
-- after a reload). Returns record, nil or nil, reason.
local function attach_comment(comment)
  local id = last_snippet_id
  if not id then
    local rows = sql_query('SELECT id FROM snippets ORDER BY created_at DESC, id DESC LIMIT 1')
    if #rows == 0 then
      return nil, 'no snippet to comment'
    end
    id = rows[1].id
  end
  if not sql_exec(string.format(
    'UPDATE snippets SET comment = %s, updated_at = %d WHERE id = %s',
    sql_str(comment), now(), sql_str(id)
  )) then
    return nil, 'db error'
  end
  local rows = sql_query(
    string.format('SELECT * FROM snippets WHERE id = %s LIMIT 1', sql_str(id))
  )
  if #rows > 0 then
    last_snippet_id = rows[1].id
    return rows[1], nil
  end
  return { text = comment, use_count = 0 }, nil
end

-- Store a validated payload. Returns record, nil on success or nil, reason on
-- rejection. Deduplication is handled by the UNIQUE index on text: an identical
-- snippet gets its use_count bumped via ON CONFLICT instead of a duplicate row.
local function add(payload)
  local raw = payload.command
  if type(raw) ~= 'string' or #raw == 0 then
    return nil, 'empty command'
  end
  if #raw > MAX_COMMAND then
    return nil, 'command too large'
  end

  local text, comment = split_comment(raw)

  -- No command part: a lone '# ...' capture updates the last snippet's comment.
  if text == nil then
    if not comment then
      return nil, 'empty comment'
    end
    return attach_comment(comment)
  end

  if looks_like_secret(text) then
    return nil, 'looks like secret'
  end

  local t = now()
  local sql = string.format(
    [[INSERT INTO snippets (text, comment, source, host, user, cwd, created_at, updated_at)
      VALUES (%s, %s, %s, %s, %s, %s, %d, %d)
      ON CONFLICT(text) DO UPDATE SET
        use_count = use_count + 1,
        updated_at = excluded.updated_at,
        comment = COALESCE(excluded.comment, snippets.comment)]],
    sql_str(text),
    sql_str(comment),
    sql_str(payload.source),
    sql_str(payload.host),
    sql_str(payload.user),
    sql_str(payload.cwd),
    t,
    t
  )
  if not sql_exec(sql) then
    return nil, 'db error'
  end

  -- Fetch the row back (either newly inserted or the conflicted one) for the
  -- toast notification and to remember it as the comment-attach target.
  local rows = sql_query(
    string.format('SELECT * FROM snippets WHERE text = %s LIMIT 1', sql_str(text))
  )
  if #rows > 0 then
    last_snippet_id = rows[1].id
    return rows[1], nil
  end
  -- Should not happen, but return a minimal record rather than nil.
  return { text = text, use_count = 0 }, nil
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

  if not ensure_db() then
    window:toast_notification('wez-snippets', 'rejected: db init failed', nil, 4000)
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
  if not ensure_db() then
    window:toast_notification('wez-snippets', 'db init failed', nil, 3000)
    return
  end
  local rows = sql_query(
    'SELECT * FROM snippets ORDER BY last_used_at DESC, use_count DESC'
  )
  if #rows == 0 then
    window:toast_notification('wez-snippets', 'no snippets saved', nil, 3000)
    return
  end

  local choices = {}
  for _, s in ipairs(rows) do
    local preview = (s.text or ''):gsub('%s+', ' ')
    if #preview > 80 then
      preview = preview:sub(1, 77) .. '...'
    end
    local origin = s.host and ('[' .. s.host .. '] ') or ''
    -- Comment is appended to the label so InputSelector's fuzzy match hits it.
    local note = (s.comment and #s.comment > 0) and ('  # ' .. s.comment) or ''
    table.insert(choices, { id = tostring(s.id), label = origin .. preview .. note })
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
        local t = now()
        sql_exec(string.format(
          'UPDATE snippets SET use_count = use_count + 1, last_used_at = %d WHERE id = %s',
          t,
          sql_str(id)
        ))
        -- Fetch the text to paste. The id came from our own query so integer
        -- coercion is safe; sql_str wraps it in quotes for SQLite.
        local rows = sql_query(
          string.format('SELECT text FROM snippets WHERE id = %s', sql_str(id))
        )
        if #rows > 0 then
          -- strip trailing newline: insert without executing
          inner_pane:send_text((rows[1].text or ''):gsub('\n+$', ''))
        end
      end),
    }),
    pane
  )
end)

return M
