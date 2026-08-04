-- Terminal snippet capture & paste, backed by plain markdown (no database).
--
-- Local/remote zsh sessions emit a selected command via OSC 1337 SetUserVar
-- (WEZ_SNIPPET_ADD, base64 JSON). This module receives the decoded JSON in the
-- 'user-var-changed' event and appends it to an "inbox" file
-- (~/syncfolder/wiki/unsorted.txt) as a '## heading' + fenced code block, in the
-- exact same shape as the rest of the vimwiki cheatsheet.
--
-- The inbox is deliberately '.txt', not '.md': vimwiki releases the wiki to
-- public HTML (gurkan.in/wiki) and VimwikiAll2HTML only processes the wiki ext
-- (.md, see nvim nix.vim), so a .txt file is never published. Captured commands
-- may be half-baked or host-specific, so they stay unreleased until filed.
--
-- The picker (M.picker, bound in keys-common.lua) parses every wiki *.md file
-- plus the inbox live and pastes a chosen block WITHOUT a trailing newline.
-- M.promote moves an inbox entry into its proper topic file (turning it into
-- released content). Everything is one text format, git/sync-friendly and
-- hand-editable; parsing ~35 small files in pure Lua is well under the picker's
-- latency budget, so a SQLite layer bought nothing here.

local wezterm = require('wezterm')

local M = {}

-- vimwiki cheatsheet root: topic-per-file markdown, each entry a '##'/'###'
-- heading followed by a fenced code block. Captures land in the inbox file;
-- M.promote files them into the topic files alongside.
local WIKI_DIR = wezterm.home_dir .. '/syncfolder/wiki'
-- .txt on purpose: keeps the inbox out of the vimwiki .md HTML release.
local UNSORTED_FILE = WIKI_DIR .. '/unsorted.txt'

local MAX_PAYLOAD = 64 * 1024 -- reject decoded JSON larger than this
local MAX_COMMAND = 16 * 1024 -- reject command text larger than this

-- OSC events are untrusted: any process on the terminal can emit SetUserVar.
-- Reject captures whose command matches an obvious secret marker. Plain-text
-- match (string.find 4th arg = true), case-sensitive on purpose. Matters even
-- more now that captures are written to a plaintext, synced file.
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

local function looks_like_secret(text)
  for _, p in ipairs(SECRET_PATTERNS) do
    if text:find(p, 1, true) then
      return true
    end
  end
  return false
end

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

-- Fallback heading for a capture with no comment: the command itself, collapsed
-- to one line and truncated. Kept human-readable so it is searchable in the
-- picker and self-explanatory when sorting the inbox later.
local function placeholder_heading(text)
  local h = trim((text:gsub('%s+', ' ')))
  if #h > 60 then
    h = h:sub(1, 57) .. '...'
  end
  return h
end

-- ---------------------------------------------------------------------------
-- Markdown IO
-- ---------------------------------------------------------------------------

-- io is confirmed available in WezTerm's Lua (verified via io.open read+write).

local function read_file(path)
  local fh = io.open(path, 'r')
  if not fh then
    return nil
  end
  local c = fh:read('*a')
  fh:close()
  return c
end

local function write_file(path, content)
  local fh = io.open(path, 'w')
  if not fh then
    return false
  end
  fh:write(content)
  fh:close()
  return true
end

-- Parse markdown text into a list of {topic, heading, code} entries. Rules: a
-- '#'-prefixed line sets the current heading; a ``` line opens/closes a fenced
-- block (language hints like ```bash are handled, the fence line is not code).
-- Every closed block that has a current heading becomes an entry, so multiple
-- blocks under one heading each yield an entry.
local function parse_markdown(content, topic)
  local entries = {}
  if not content then
    return entries
  end
  local heading = nil
  local in_code = false
  local code_lines = nil
  for line in (content .. '\n'):gmatch('([^\n]*)\n') do
    if in_code then
      if line:match('^```') then
        if heading and code_lines and #code_lines > 0 then
          table.insert(entries, {
            topic = topic,
            heading = heading,
            code = table.concat(code_lines, '\n'),
          })
        end
        in_code = false
        code_lines = nil
      else
        table.insert(code_lines, line)
      end
    elseif line:match('^```') then
      in_code = true
      code_lines = {}
    else
      local h = line:match('^#+%s+(.+)$')
      if h then
        heading = trim(h)
      end
    end
  end
  return entries
end

-- Load every wiki entry across all topic files (including the inbox). Read-only,
-- run at picker open.
local function load_wiki()
  local all = {}
  for _, path in ipairs(wezterm.glob(WIKI_DIR .. '/*.md')) do
    local topic = path:match('([^/]+)%.md$') or path
    for _, e in ipairs(parse_markdown(read_file(path), topic)) do
      table.insert(all, e)
    end
  end
  -- Inbox is '.txt' so the glob above skips it (that keeps it out of the
  -- vimwiki HTML release); pull it in explicitly for the picker.
  for _, e in ipairs(parse_markdown(read_file(UNSORTED_FILE), 'unsorted')) do
    table.insert(all, e)
  end
  return all
end

-- Load the inbox entries (order preserved, newest last).
local function load_unsorted()
  return parse_markdown(read_file(UNSORTED_FILE), 'unsorted')
end

-- Rewrite the inbox file from an entries list in canonical form. The inbox is
-- machine-managed: freeform prose between entries is not preserved, but edited
-- headings/code survive (they are parsed back in). Entries keep their order.
local function save_unsorted(entries)
  local parts = {
    '# Unsorted snippets',
    '',
    '<!-- Captured from the terminal via the wezterm snippet key. Move entries',
    '     into their topic files to sort them; this inbox is machine-managed. -->',
    '',
  }
  for _, e in ipairs(entries) do
    table.insert(parts, '## ' .. e.heading)
    table.insert(parts, '')
    table.insert(parts, '```')
    -- Extra parens truncate gsub's 2nd return (substitution count); otherwise it
    -- leaks in as table.insert's value arg, turning this into the 3-arg
    -- insert(list, pos, value) form and erroring "number expected, got string".
    table.insert(parts, ((e.code or ''):gsub('\n+$', '')))
    table.insert(parts, '```')
    table.insert(parts, '')
  end
  return write_file(UNSORTED_FILE, table.concat(parts, '\n'))
end

-- Append an entry to a topic file, matching the existing wiki style (leading
-- blank line, blank line after the heading).
local function append_to_topic(path, heading, code)
  local fh = io.open(path, 'a')
  if not fh then
    return false
  end
  fh:write('\n## ' .. heading .. '\n\n```\n' .. ((code or ''):gsub('\n+$', '')) .. '\n```\n')
  fh:close()
  return true
end

local function find_entry(entries, code)
  for _, e in ipairs(entries) do
    if e.code == code then
      return e
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Capture
-- ---------------------------------------------------------------------------

-- Text of the last command captured this session. A bare '# note' capture
-- annotates that command's inbox entry (found by matching text, the same lookup
-- dedup uses). Reset on config reload, in which case we fall back to the last
-- inbox entry.
local last_captured_text = nil

-- Store a validated payload into the inbox. Returns entry, nil on success or
-- nil, reason on rejection. Dedup is by command text: an identical command is
-- not appended twice; re-capturing with a new comment updates its heading.
local function capture(payload)
  local raw = payload.command
  if type(raw) ~= 'string' or #raw == 0 then
    return nil, 'empty command'
  end
  if #raw > MAX_COMMAND then
    return nil, 'command too large'
  end

  local text, comment = split_comment(raw)
  local entries = load_unsorted()

  -- Comment-only capture: annotate the last-captured command (or, after a
  -- reload, the last inbox entry).
  if text == nil then
    if not comment then
      return nil, 'empty comment'
    end
    local target = last_captured_text and find_entry(entries, last_captured_text) or nil
    target = target or entries[#entries]
    if not target then
      return nil, 'nothing to annotate'
    end
    target.heading = comment
    if not save_unsorted(entries) then
      return nil, 'write failed'
    end
    return target
  end

  if looks_like_secret(text) then
    return nil, 'looks like secret'
  end

  last_captured_text = text
  local existing = find_entry(entries, text)
  if existing then
    -- Dedup: only touch the file when a new comment actually changes something.
    if comment and #comment > 0 and existing.heading ~= comment then
      existing.heading = comment
      if not save_unsorted(entries) then
        return nil, 'write failed'
      end
    end
    return existing
  end

  local entry = { heading = comment or placeholder_heading(text), code = text }
  table.insert(entries, entry)
  if not save_unsorted(entries) then
    return nil, 'write failed'
  end
  return entry
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

  local rec, err = capture(payload)
  if rec then
    local short = rec.heading:gsub('%s+', ' ')
    if #short > 60 then
      short = short:sub(1, 57) .. '...'
    end
    window:toast_notification('wez-snippets', 'saved: ' .. short, nil, 3000)
  else
    window:toast_notification('wez-snippets', 'rejected: ' .. tostring(err), nil, 4000)
  end
end)

-- ---------------------------------------------------------------------------
-- Picker / promote actions
-- ---------------------------------------------------------------------------

-- Picker action, bound to a key in keys-common.lua. Lists every wiki entry
-- (topic files + inbox) and pastes the selected block into the active pane.
M.picker = wezterm.action_callback(function(window, pane)
  local choices = {}
  -- Code is kept in the closure (not re-queried) and pasted verbatim; heading +
  -- topic go in the label for fuzzy search.
  local code_by_id = {}
  for i, e in ipairs(load_wiki()) do
    local id = tostring(i)
    code_by_id[id] = e.code
    -- Full command (whitespace-collapsed, NOT truncated) goes in the label:
    -- InputSelector fuzzy-matches the label string, so a truncated preview would
    -- make anything past the cut unsearchable (e.g. a var deep in a long command).
    -- The row still reads well because topic + heading lead; wezterm visually
    -- truncates the long tail while keeping the whole string matchable.
    local preview = e.code:gsub('%s+', ' ')
    table.insert(choices, {
      id = id,
      label = '[' .. e.topic .. '] ' .. e.heading .. '  » ' .. preview,
    })
  end

  if #choices == 0 then
    window:toast_notification('wez-snippets', 'no snippets saved', nil, 3000)
    return
  end

  window:perform_action(
    wezterm.action.InputSelector({
      title = 'Snippets',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
        if not id or not code_by_id[id] then
          return
        end
        -- strip trailing newline: insert without executing
        -- extra parens: drop gsub's 2nd return (count) so only the string passes
        inner_pane:send_text(((code_by_id[id]):gsub('\n+$', '')))
      end),
    }),
    pane
  )
end)

-- Promote action (bind in keys-common.lua): move an inbox entry into its proper
-- topic file. Appends there and removes it from the inbox, so unsorted.md stays
-- a shrinking to-do list.
M.promote = wezterm.action_callback(function(window, pane)
  local entries = load_unsorted()
  if #entries == 0 then
    window:toast_notification('wez-snippets', 'inbox empty, nothing to sort', nil, 3000)
    return
  end

  local choices = {}
  local by_id = {}
  for i, e in ipairs(entries) do
    local id = tostring(i)
    by_id[id] = e
    -- Full command in the label so fuzzy search reaches the tail (see picker).
    local preview = e.code:gsub('%s+', ' ')
    table.insert(choices, { id = id, label = e.heading .. '  » ' .. preview })
  end

  window:perform_action(
    wezterm.action.InputSelector({
      title = 'Promote inbox snippet',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id)
        if not id or not by_id[id] then
          return
        end
        local entry = by_id[id]

        -- Second selector: the target topic file (all wiki files except the
        -- inbox itself).
        local topics = {}
        for _, path in ipairs(wezterm.glob(WIKI_DIR .. '/*.md')) do
          if path ~= UNSORTED_FILE then
            table.insert(topics, { id = path, label = path:match('([^/]+)$') or path })
          end
        end

        inner_window:perform_action(
          wezterm.action.InputSelector({
            title = 'File "' .. entry.heading .. '" into topic',
            choices = topics,
            fuzzy = true,
            action = wezterm.action_callback(function(w, p, path)
              if not path then
                return
              end
              if not append_to_topic(path, entry.heading, entry.code) then
                w:toast_notification('wez-snippets', 'topic write failed', nil, 4000)
                return
              end
              -- Reload the inbox fresh (a capture may have landed meanwhile) and
              -- drop the promoted entry by matching command text.
              local cur = load_unsorted()
              local kept = {}
              for _, e in ipairs(cur) do
                if e.code ~= entry.code then
                  table.insert(kept, e)
                end
              end
              save_unsorted(kept)
              w:toast_notification(
                'wez-snippets',
                'filed into ' .. (path:match('([^/]+)$') or path),
                nil,
                3000
              )
            end),
          }),
          p
        )
      end),
    }),
    pane
  )
end)

return M
