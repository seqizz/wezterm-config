local wezterm = require 'wezterm';
return {
  keys = {
    -- mux start
    { key = '-', mods = 'ALT', action = wezterm.action({ SplitVertical = { domain = 'CurrentPaneDomain' } }) },
    { key = '|', mods = 'ALT', action = wezterm.action({ SplitHorizontal = { domain = 'CurrentPaneDomain' } }) },
    { key = 'z', mods = 'ALT', action = 'TogglePaneZoomState' },
    { key = 'n', mods = 'ALT', action = wezterm.action({ SpawnTab = 'CurrentPaneDomain' }) },
    { key = 'LeftArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Left' }) },
    { key = 'DownArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Down' }) },
    { key = 'UpArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Up' }) },
    { key = 'RightArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Right' }) },
    { key = 'a', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Left', 5 } }) },
    { key = 's', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Down', 5 } }) },
    { key = 'w', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Up', 5 } }) },
    { key = 'd', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Right', 5 } }) },
    { key = '1', mods = 'ALT', action = wezterm.action.ActivateTab(0) },
    { key = '2', mods = 'ALT', action = wezterm.action.ActivateTab(1) },
    { key = '3', mods = 'ALT', action = wezterm.action.ActivateTab(2) },
    { key = '4', mods = 'ALT', action = wezterm.action.ActivateTab(3) },
    { key = '5', mods = 'ALT', action = wezterm.action.ActivateTab(4) },
    { key = '6', mods = 'ALT', action = wezterm.action.ActivateTab(5) },
    { key = '7', mods = 'ALT', action = wezterm.action.ActivateTab(6) },
    { key = '8', mods = 'ALT', action = wezterm.action.ActivateTab(7) },
    { key = '9', mods = 'ALT', action = wezterm.action.ActivateTab(8) },
    { key = 'k', mods = 'ALT', action = wezterm.action.CloseCurrentTab({ confirm = true }) },
    -- mux end

    -- Turn off the defaults
    { key = '=', mods = 'CTRL', action = 'DisableDefaultAssignment' },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'Tab', mods = 'CTRL', action = 'DisableDefaultAssignment' },
    { key = 'Tab', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'Tab', mods = 'SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'F', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'P', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    -- mux start
    { key = ' ', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'Enter', mods = 'ALT', action = 'DisableDefaultAssignment' },
    -- mux end
    { key = 'Return', mods = 'ALT', action = 'DisableDefaultAssignment' },
    { key = 'n', mods = 'SUPER', action = 'DisableDefaultAssignment' },

    -- standalone start
    -- {key="1", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="2", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="3", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="4", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="5", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="6", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="7", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="8", mods="ALT", action="DisableDefaultAssignment"},
    -- {key="9", mods="ALT", action="DisableDefaultAssignment"},
    --standalone end

    -- Assign new
    -- @Reference see above
    -- {key="A", mods="ALT", action=wezterm.action_callback(
    -- function(window, pane)
    -- send_signal(pane, '-USR1')
    -- end
    -- )},
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
          'https?://[A-Za-z0-9$_+:/?@&,;%=.-]+',
        },
        action = wezterm.action_callback(function(window, pane)
          local url = window:get_selection_text_for_pane(pane)
          wezterm.log_info('opening: ' .. url)
          wezterm.open_with(url)
        end),
      }),
    },
    -- mux reference start
    -- {key="RightArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-right"}},
    -- {key="LeftArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-left"}},
    -- {key="UpArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-up"}},
    -- {key="DownArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-down"}},
    -- mux reference end
  },

  mouse_bindings = {
    -- Change the default click behavior so that it only selects
    -- text and doesn't open hyperlinks
    {
      event={Up={streak=1, button="Left"}},
      mods="NONE",
      action=wezterm.action{CompleteSelection="PrimarySelection"},
    },

    -- and make CTRL-Click open hyperlinks
    {
      event={Up={streak=1, button="Left"}},
      mods="CTRL",
      action="OpenLinkAtMouseCursor",
    },
  },
}
