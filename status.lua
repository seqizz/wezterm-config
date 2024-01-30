--- @alias battery_state 'Charging' | 'Discharging' | 'Empty' | 'Full' | 'Unknown'
--- @alias battery { state: battery_state, state_of_charge: number }

local M = {}

local wezterm = require('wezterm')
local utils = require('utils')

--- @param battery battery state of charge, from 0.00 to 1.00
--- @return string
local function render_battery(battery)
  --- @type table<string, string>
  local icons = wezterm.nerdfonts
  local percent = battery.state_of_charge
  local formatted_percent = string.format('%.0f%%', percent * 100)

  local get_icon = function()
    local prefix = 'md_battery'
    if battery.state == 'Charging' then
      return icons[prefix .. '_charging']
    end

    --- @type string
    local icon_name

    if percent == 1 then
      icon_name = prefix
    else
      local suffix = math.max(1, math.ceil(percent * 10)) .. '0'
      icon_name = prefix .. '_' .. suffix
    end

    local color = percent <= 0.1 and 'Red' or 'Green'
    return wezterm.format({
      { Foreground = { AnsiColor = color } },
      { Text = icons[icon_name] },
    })
  end

  return string.format('%s %s', get_icon(), formatted_percent)
end

local function update_right_status(window, pane)
  -- "Wed Mar 3 08:14"
  --- @type string
  local date = wezterm.strftime('%a %b %-d %H:%M')

  --- @type string
  local tilde = wezterm.format({
    { Foreground = { AnsiColor = 'Fuchsia' } },
    { Text = '~' },
  })

  --- @type string
  local hostname = wezterm.format({
    { Background = { AnsiColor = 'Grey' } },
    { Foreground = { AnsiColor = 'White' } },
    { Text = string.format(' %s ', pane:get_domain_name()) },
  })

  --- @type string
  local battery

  for _, b in ipairs(wezterm.battery_info()) do
    battery = render_battery(b)
  end

  local status = string.format('%s %s %s %s %s ', battery, tilde, date, tilde, hostname)
  window:set_right_status(wezterm.format({
    { Text = status },
  }))
end

function M.enable() wezterm.on('update-right-status', update_right_status) end

return M
