-- if we get 'wezterm_disabletabs' user variable set to anything:
-- - hide tab bar
-- - disable keys which would conflict with tmux

local wezterm = require('wezterm')
local common = require('keys-common')

local tmux_keys = {
  { key = 'LeftArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'DownArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'UpArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'RightArrow', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'a', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 's', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'w', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'd', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'k', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'z', mods = 'ALT', action = 'DisableDefaultAssignment' },
}
for i = 1, 9 do
  table.insert(tmux_keys, { key = tostring(i), mods = 'ALT', action = 'DisableDefaultAssignment' })
end

-- Built once at load, not per event: common.concat appends in place, so calling
-- it inside the handler re-appends the whole of common.keys to tmux_keys every
-- time a shell sets the var, and the key list grows without bound over a
-- session.
local tmux_mode_keys = common.concat(tmux_keys, common.keys)

wezterm.on('user-var-changed', function(window, pane, name, value)
  if name == 'wezterm_disabletabs' then
    -- Logged only for this module's own var. The same event also delivers
    -- WEZ_SNIPPET_ADD, whose value is raw captured command text, and the gui
    -- log is a plaintext file on disk that snippets.lua's secret filter never
    -- gets to see.
    wezterm.log_info('var', name, value)
    window:set_config_overrides({
      hide_tab_bar_if_only_one_tab = true,
      keys = tmux_mode_keys,
      background = {
        { source = { Color = '#282828' }, opacity = 0.95, width = '100%', height = '100%' },
        {
          source = {
            File = wezterm.config_dir .. '/assets/my-man.png',
          },
          width = '14cell',
          height = '6cell',
          repeat_x = 'NoRepeat',
          repeat_y = 'NoRepeat',
          opacity = 0.1,
          horizontal_align = 'Right',
          vertical_align = 'Bottom',
          vertical_offset = -20,
          -- horizontal_offset = -30,
        },
      },
    })
  end
end)

return {}
