local M = {}

local wezterm = require('wezterm')
local utils = require('utils')

local function render_battery(battery, fg_color)
  local icons = wezterm.nerdfonts
  local prefix = 'md_battery'
  local icon_name

  if battery.state == 'Charging' then
      icon_name = prefix .. '_charging'
  elseif battery.state_of_charge > 0.9 then
    icon_name = prefix
  else
    local suffix = math.max(1, math.ceil(battery.state_of_charge * 10)) .. '0'
    icon_name = prefix .. '_' .. suffix
  end

  local color = battery.state_of_charge<= 0.1 and 'Red' or 'Green'
  local plain = icons[icon_name] .. string.format(' %.0f%%', battery.state_of_charge * 100)
  local formatted = wezterm.format({
    { Foreground = { AnsiColor = color } },
    { Text = icons[icon_name] },
    { Foreground = { Color = fg_color } },
    { Text = string.format(' %.0f%%', battery.state_of_charge * 100) },
  })
  return formatted, plain
end

local function update_left_status(window, pane)
  local key_table = window:active_key_table()
  local indicators = {}

  if key_table == 'copy_mode' then
    table.insert(indicators, wezterm.format({
      { Attribute = { Intensity = 'Bold' } },
      { Background = { AnsiColor = 'Red' } },
      { Foreground = { AnsiColor = 'White' } },
      { Text = ' ' .. wezterm.nerdfonts['md_content_copy'] .. ' COPY ' },
    }))
  elseif key_table == 'search_mode' then
    table.insert(indicators, wezterm.format({
      { Attribute = { Intensity = 'Bold' } },
      { Background = { AnsiColor = 'Blue' } },
      { Foreground = { AnsiColor = 'White' } },
      { Text = ' SEARCH ' },
    }))
  end

  -- zoom state lives on PaneInformation, not Pane userdata
  local tab = window:active_tab()
  for _, p in ipairs(tab:panes_with_info()) do
    if p.is_zoomed then
      table.insert(indicators, wezterm.format({
        { Attribute = { Intensity = 'Bold' } },
        { Background = { AnsiColor = 'Blue' } },
        { Foreground = { AnsiColor = 'White' } },
        { Text = ' ' .. wezterm.nerdfonts['md_magnify_plus'] .. ' ZOOM ' },
      }))
      break
    end
  end

  window:set_left_status(table.concat(indicators, ''))

  -- Track visible width of left status for the grow-to-fill tab sizing (tab.lua).
  -- Each indicator block has a known plain-text form; recompute rather than
  -- storing escapes since wezterm.column_width would count the escape bytes.
  local lw = 0
  if key_table == 'copy_mode' then
    lw = lw + wezterm.column_width(' ' .. wezterm.nerdfonts['md_content_copy'] .. ' COPY ')
  elseif key_table == 'search_mode' then
    lw = lw + wezterm.column_width(' SEARCH ')
  end
  for _, p in ipairs(tab:panes_with_info()) do
    if p.is_zoomed then
      lw = lw + wezterm.column_width(' ' .. wezterm.nerdfonts['md_magnify_plus'] .. ' ZOOM ')
      break
    end
  end
  wezterm.GLOBAL.lstatus_w = lw
end

local function update_right_status(window, pane)
  -- "Wed Mar 3 08:14"
  local date = wezterm.strftime('%a %b %-d %H:%M')

  local tilde = wezterm.format({
    { Foreground = { AnsiColor = 'Fuchsia' } },
    { Text = '~' },
  })

  local hostname = wezterm.format({
    { Text = string.format(' %s ', wezterm.hostname()) },
  })

  local battery
  local battery_plain = ''

  for _, b in ipairs(wezterm.battery_info()) do
    battery, battery_plain = render_battery(b, '#1c1b19')
  end

  local SOLID_LEFT_ARROW = utf8.char(0xe0ba)
  local SOLID_RIGHT_MOST = utf8.char(0x2588)
  local SOLID_RIGHT_ARROW = utf8.char(0xe0bc)
  local background = '#d79921'
  local foreground = '#1c1b19'

  window:set_right_status(wezterm.format({
    -- { Attribute = { Intensity = 'Bold' } },
    { Background = { Color = foreground } },
    { Foreground = { Color = background } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = battery },
    { Background = { Color = background } },
    { Foreground = { Color = '#1c1b18' } }, -- NVIDIA workaround.. Most valuable company in the whole world!
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = foreground } },
    { Text = ' ' },
    { Background = { Color = foreground } },
    { Foreground = { Color = background } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = date },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = foreground } },
    { Text = ' ' },
    { Background = { Color = foreground } },
    { Foreground = { Color = background } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = hostname },
  }))

  -- Publish widths + total terminal columns so tab.lua can size tabs to fill.
  -- Right status visible parts: 5 powerline arrows + 2 spaces + battery + date + hostname.
  local rw = wezterm.column_width(battery_plain)
           + wezterm.column_width(date)
           + wezterm.column_width(string.format(' %s ', wezterm.hostname()))
           + 5  -- SOLID_LEFT_ARROW glyphs (1 cell each)
           + 2  -- literal spaces between segments
  wezterm.GLOBAL.rstatus_w = rw

  -- MuxTab:get_size() gives the whole tab grid (full width, ignores splits),
  -- which equals the tab bar width in columns.
  local ok, size = pcall(function() return window:active_tab():get_size() end)
  if ok and size then
    wezterm.GLOBAL.tabbar_cols = size.cols
  end
end

function M.enable()
  wezterm.on('update-right-status', function(window, pane)
    update_left_status(window, pane)
    update_right_status(window, pane)
  end)
end

return M
