-- if we get 'wezterm_disabletabs' user variable set to anything:
-- - hide tab bar
-- - disable keys which would conflict with tmux

local wezterm = require('wezterm')
dofile('/devel/wezterm-config/keys-common.lua') -- brings "common_keys" into scope
tmux_keys = {
  { key = 'LeftArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'DownArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'UpArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'RightArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'a', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 's', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'w', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'd', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '1', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '2', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '3', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '4', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '5', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '6', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '7', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '8', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '9', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'k', mods = 'ALT', action = 'DisableDefaultAssignment' },
}
return {
  wezterm.on('user-var-changed', function(window, pane, name, value)
    wezterm.log_info('var', name, value)
    if name == 'wezterm_disabletabs' then
      window:set_config_overrides({
        hide_tab_bar_if_only_one_tab = true,
        keys = concat_table(tmux_keys, common_keys),
      })
    end
  end),
}
