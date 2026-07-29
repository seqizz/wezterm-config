local wezterm = require('wezterm')
-- requiring the module registers its 'user-var-changed' capture handler and
-- exposes the picker action bound below (Ctrl-Shift-S)
local snippets = require('snippets')
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
  { key = 'x', mods = 'ALT', action = 'QuickSelect' },
  { key = '+', mods = 'CTRL', action = 'IncreaseFontSize' },
  { key = '4', mods = 'CTRL', action = 'IncreaseFontSize' },
  { key = '-', mods = 'CTRL', action = 'DecreaseFontSize' },
  { key = '0', mods = 'CTRL', action = 'ResetFontSize' },
  {
    key = 'Backspace',
    mods = 'CTRL',
    action = wezterm.action.SendKey({ key = 'h', mods = 'CTRL' }),
  },
  { key = 'Delete', mods = 'SHIFT', action = wezterm.action({ PasteFrom = 'PrimarySelection' }) },
  { key = 'V', mods = 'CTRL', action = wezterm.action({ PasteFrom = 'Clipboard' }) },
  -- Physical launch key (X keycode 195, keysym XF86Launch8) carries no terminal
  -- escape of its own, so WezTerm handles it directly rather than the shell:
  --   plain -> inject the Shift-F5 sequence the zsh bindkey captures on
  --   Ctrl  -> open the snippet picker
  { key = 'raw:195', action = wezterm.action.SendString('\x1b[15;2~') },
  { key = 'raw:195', mods = 'CTRL', action = snippets.picker },
  -- Alt-c to "click" links without mouse
  {
    key = 'c',
    mods = 'ALT',
    action = wezterm.action.QuickSelectArgs({
      label = 'open url',
      patterns = {
        -- A bit more proper regex for URLs, at least to clickable ones
        -- last char must be alnum or '/' so trailing sentence punctuation
        -- (comma, dot, etc.) is not part of the highlighted selection
        'https?://[A-Za-z0-9$_+:/?#@&,;%=.-]*[A-Za-z0-9/]',
      },
      action = wezterm.action_callback(function(window, pane)
        local url = window:get_selection_text_for_pane(pane)
        -- Comma is valid mid-URL (query params), so keep it in the pattern
        -- but strip trailing punctuation that is usually sentence-suffix.
        url = url:gsub('[.,;:!?]+$', '')
        wezterm.log_info('opening: ' .. url)
        wezterm.open_with(url)
      end),
    }),
  },
}
