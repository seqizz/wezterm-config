local wezterm = require('wezterm')
dofile('/devel/wezterm-config/keys-common.lua') -- brings "common_keys" into scope
mux_keys = {
  {
    key = '-',
    mods = 'ALT',
    action = wezterm.action({ SplitVertical = { domain = 'CurrentPaneDomain' } }),
  },
  {
    key = '|',
    mods = 'ALT',
    action = wezterm.action({ SplitHorizontal = { domain = 'CurrentPaneDomain' } }),
  },
  {
    key = 'n',
    mods = 'ALT',
    action = wezterm.action.SpawnCommandInNewTab({ cwd = wezterm.home_dir, domain = 'CurrentPaneDomain' }),
  },
  { key = 'LeftArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Left' }) },
  { key = 'DownArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Down' }) },
  { key = 'UpArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Up' }) },
  { key = 'RightArrow', mods = 'ALT', action = wezterm.action({ ActivatePaneDirection = 'Right' }) },
  { key = 'a', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Left', 2 } }) },
  { key = 's', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Down', 2 } }) },
  { key = 'w', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Up', 2 } }) },
  { key = 'd', mods = 'ALT', action = wezterm.action({ AdjustPaneSize = { 'Right', 2 } }) },
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
  {
    key = 'f',
    mods = 'ALT',
    action = wezterm.action.Search('CurrentSelectionOrEmptyString'),
  },
  {
    key = 'Escape',
    mods = 'ALT',
    action = wezterm.action.ActivateCopyMode,
  },

  -- mux @Reference start (see above)
  -- {key="RightArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-right"}},
  -- {key="LeftArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-left"}},
  -- {key="UpArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-up"}},
  -- {key="DownArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-down"}},
  -- mux reference end
}
return {

  keys = concat_table(mux_keys, common_keys),

  key_tables = {
    copy_mode = {
      {
        key = 'v',
        mods = 'SHIFT',
        action = wezterm.action.CopyMode({ SetSelectionMode = 'Line' }),
      },
      {
        key = 'Escape',
        mods = 'NONE',
        action = wezterm.action.CopyMode('Close'),
      },
      {
        key = 'Escape',
        mods = 'ALT',
        action = wezterm.action.CopyMode('Close'),
      },
      { key = 'LeftArrow', mods = 'NONE', action = wezterm.action({ CopyMode = 'MoveLeft' }) },
      { key = 'RightArrow', mods = 'NONE', action = wezterm.action({ CopyMode = 'MoveRight' }) },
      { key = 'UpArrow', mods = 'NONE', action = wezterm.action({ CopyMode = 'MoveUp' }) },
      { key = 'DownArrow', mods = 'NONE', action = wezterm.action({ CopyMode = 'MoveDown' }) },
      {
        key = 'y',
        mods = 'NONE',
        action = wezterm.action.Multiple({
          wezterm.action({ CopyTo = 'ClipboardAndPrimarySelection' }),
          wezterm.action({ CopyMode = 'Close' }),
        }),
      },
      { key = 'PageDown', mods = 'NONE', action = wezterm.action.CopyMode('PageDown') },
      { key = 'PageUp', mods = 'NONE', action = wezterm.action.CopyMode('PageUp') },
    },
  },

  mouse_bindings = {
    -- Change the default click behavior so that it only selects
    -- text and doesn't open hyperlinks
    {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'NONE',
      action = wezterm.action({ CompleteSelection = 'PrimarySelection' }),
    },

    -- and make CTRL-Click open hyperlinks
    {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'CTRL',
      action = 'OpenLinkAtMouseCursor',
    },
  },
}
