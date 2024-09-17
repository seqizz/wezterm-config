-- if we get 'wezterm_disabletabs' user variable set to anything:
-- - hide tab bar
-- - disable keys which would conflict with tmux

local wezterm = require('wezterm')
dofile('/home/gurkan/.config/wezterm/keys-common.lua') -- brings "common_keys" into scope
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
  { key = 'z', mods = 'ALT', action = 'DisableDefaultAssignment' },
}
return {
  wezterm.on('user-var-changed', function(window, pane, name, value)
    wezterm.log_info('var', name, value)
    if name == 'wezterm_disabletabs' then
      window:set_config_overrides({
        hide_tab_bar_if_only_one_tab = true,
        keys = concat_table(tmux_keys, common_keys),
        background = {
          { source = { Color = '#282828' }, opacity = 0.95, width = '100%', height = '100%' },
          {
            source = {
              File = wezterm.home_dir .. '/.config/wezterm/assets/plane.png',
            },
            width = '3cell',
            height = '15cell',
            repeat_x = 'NoRepeat',
            repeat_y = 'NoRepeat',
            hsb = dimmer,
            opacity = 0.4,
            horizontal_align = 'Right',
            vertical_align = 'Bottom',
            horizontal_offset = -30,
          },
        },
      })
    end
  end),
}
