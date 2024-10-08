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

function M.enable() wezterm.on('update-right-status', update_right_status) end

return M
