local M = {}

local wezterm = require('wezterm')

-- window_id -> right status as last handed to wezterm, and its form without
-- the repaint marker
local right_sent = {}
local right_base = {}

-- One left-status block: its drawn form plus the plain text tab.lua's width
-- math is measured from (wezterm.column_width would count escape bytes in the
-- formatted string).
local function indicator(bg, text)
  return {
    text = wezterm.format({
      { Attribute = { Intensity = 'Bold' } },
      { Background = { AnsiColor = bg } },
      { Foreground = { AnsiColor = 'White' } },
      { Text = text },
    }),
    plain = text,
  }
end

local function update_left_status(window, pane)
  local key_table = window:active_key_table()
  local indicators = {}

  if key_table == 'copy_mode' then
    table.insert(indicators, indicator('Red', ' ' .. wezterm.nerdfonts['md_content_copy'] .. ' COPY '))
  elseif key_table == 'search_mode' then
    table.insert(indicators, indicator('Blue', ' SEARCH '))
  end

  -- zoom state lives on PaneInformation, not Pane userdata
  for _, p in ipairs(window:active_tab():panes_with_info()) do
    if p.is_zoomed then
      table.insert(indicators, indicator('Blue', ' ' .. wezterm.nerdfonts['md_magnify_plus'] .. ' ZOOM '))
      break
    end
  end

  local drawn = {}
  local lw = 0
  for _, ind in ipairs(indicators) do
    drawn[#drawn + 1] = ind.text
    lw = lw + wezterm.column_width(ind.plain)
  end
  window:set_left_status(table.concat(drawn, ''))
  -- Visible width of left status for the grow-to-fill tab sizing (tab.lua)
  wezterm.GLOBAL.lstatus_w = lw
end

local function update_right_status(window, pane)
  -- "Wed Mar 3 08:14"
  local date = wezterm.strftime('%a %b %-d %H:%M')
  local host = string.format(' %s ', wezterm.hostname())

  local SOLID_LEFT_ARROW = utf8.char(0xe0ba)
  local background = '#d79921'
  local foreground = '#1c1b19'

  -- Segments in display order, each carrying both its drawn form and the plain
  -- text the published width is measured from, so the two cannot drift apart.
  -- `arrow_fg` colors the arrow drawn *after* the segment.
  local segments = {}
  segments[#segments + 1] = { text = date, plain = date, arrow_fg = foreground }
  segments[#segments + 1] = { text = host, plain = host }

  local elements = {}
  local function push(e) elements[#elements + 1] = e end

  for i, seg in ipairs(segments) do
    -- Arrow into the segment, drawn in the segment color over the dark edge.
    push({ Background = { Color = foreground } })
    push({ Foreground = { Color = background } })
    push({ Text = SOLID_LEFT_ARROW })
    push({ Background = { Color = background } })
    push({ Foreground = { Color = foreground } })
    push({ Text = seg.text })
    -- The last segment runs to the edge of the bar, so it gets no closing
    -- arrow and no separating space.
    if i < #segments then
      push({ Background = { Color = background } })
      push({ Foreground = { Color = seg.arrow_fg } })
      push({ Text = SOLID_LEFT_ARROW })
      push({ Background = { Color = foreground } })
      push({ Text = ' ' })
    end
  end

  local formatted = wezterm.format(elements)
  local id = window:window_id()
  right_base[id] = formatted
  right_sent[id] = formatted
  window:set_right_status(formatted)

  -- Publish widths + total terminal columns so tab.lua can size tabs to fill.
  -- Two powerline arrows per segment bar the trailing one, plus a space between
  -- each pair: 3 arrows and 1 space for the date/host pair.
  local rw = (2 * #segments - 1) + (#segments - 1)
  for _, seg in ipairs(segments) do
    rw = rw + wezterm.column_width(seg.plain)
  end
  wezterm.GLOBAL.rstatus_w = rw

  -- MuxTab:get_size() gives the whole tab grid (full width, ignores splits),
  -- which equals the tab bar width in columns.
  local ok, size = pcall(function() return window:active_tab():get_size() end)
  if ok and size then
    wezterm.GLOBAL.tabbar_cols = size.cols
  end
end

-- Makes wezterm call format-tab-title again right away, for tab.lua's switch
-- animation. wezterm rebuilds the tab bar whenever the status text changes, so
-- the stored right status is set again with a trailing SGR reset toggled on or
-- off: a different string that draws the same cells.
function M.repaint()
  if not wezterm.gui then
    return
  end
  for _, window in ipairs(wezterm.gui.gui_windows()) do
    local id = window:window_id()
    local base = right_base[id]
    if base then
      local text = base
      if right_sent[id] == text then
        text = text .. '\x1b[0m'
      end
      right_sent[id] = text
      window:set_right_status(text)
    end
  end
end

function M.enable()
  wezterm.on('update-status', function(window, pane)
    update_left_status(window, pane)
    update_right_status(window, pane)
  end)
end

return M
