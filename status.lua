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
  return wezterm.format({
    { Foreground = { AnsiColor = color } },
    { Text = icons[icon_name] },
    { Foreground = { Color = fg_color } },
    { Text = string.format(' %.0f%%', battery.state_of_charge * 100) },
  })
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
end

local function update_right_status(window, pane)
  -- "Wed Mar 3 08:14"
  local date = wezterm.strftime('%a %b %-d %H:%M')

  local tilde = wezterm.format({
    { Foreground = { AnsiColor = 'Fuchsia' } },
    { Text = '~' },
  })

  local hostname = wezterm.format({
    { Text = string.format(' %s ', pane:get_domain_name()) },
  })

  local battery

  for _, b in ipairs(wezterm.battery_info()) do
    battery = render_battery(b, '#1c1b19')
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
end

function M.enable()
  wezterm.on('update-right-status', function(window, pane)
    update_left_status(window, pane)
    update_right_status(window, pane)
  end)
end

return M
