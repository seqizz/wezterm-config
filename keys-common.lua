local wezterm = require('wezterm')
function concat_table(t1, t2)
  for i = 1, #t2 do
    t1[#t1 + 1] = t2[i]
  end
  return t1
end
common_keys = {
  -- Turn off the defaults
  { key = ' ', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
  { key = 'Enter', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = '=', mods = 'CTRL', action = 'DisableDefaultAssignment' },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
  { key = 'Tab', mods = 'CTRL', action = 'DisableDefaultAssignment' },
  { key = 'Tab', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
  { key = 'Tab', mods = 'SHIFT', action = 'DisableDefaultAssignment' },
  { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
  { key = 'F', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
  { key = 'P', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },

  { key = 'Return', mods = 'ALT', action = 'DisableDefaultAssignment' },
  { key = 'n', mods = 'SUPER', action = 'DisableDefaultAssignment' },
  { key = 'z', mods = 'ALT', action = 'TogglePaneZoomState' },
  { key = 'x', mods = 'ALT', action = 'QuickSelect' },
  { key = '+', mods = 'CTRL', action = 'IncreaseFontSize' },
  { key = '4', mods = 'CTRL', action = 'IncreaseFontSize' },
  { key = '-', mods = 'CTRL', action = 'DecreaseFontSize' },
  { key = '0', mods = 'CTRL', action = 'ResetFontSize' },
  { key = 'Delete', mods = 'SHIFT', action = wezterm.action({ PasteFrom = 'PrimarySelection' }) },
  { key = 'V', mods = 'CTRL', action = wezterm.action({ PasteFrom = 'Clipboard' }) },
  -- Alt-c to "click" links without mouse
  {
    key = 'c',
    mods = 'ALT',
    action = wezterm.action.QuickSelectArgs({
      label = 'open url',
      patterns = {
        -- A bit more proper regex for URLs, at least to clickable ones
        'https?://[A-Za-z0-9$_+:/?#@&,;%=.-]+',
      },
      action = wezterm.action_callback(function(window, pane)
        local url = window:get_selection_text_for_pane(pane)
        wezterm.log_info('opening: ' .. url)
        wezterm.open_with(url)
      end),
    }),
  },
}
