local wezterm = require('wezterm')
local common = require('keys-common')

local close_copy_mode = wezterm.action.Multiple({
  wezterm.action.CopyMode('Close'),
  wezterm.action.ScrollToBottom,
})

local mux_keys = {
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
  { key = 'k', mods = 'ALT', action = wezterm.action.CloseCurrentTab({ confirm = true }) },
  { key = 'z', mods = 'ALT', action = 'TogglePaneZoomState' },
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
for i = 1, 9 do
  table.insert(mux_keys, { key = tostring(i), mods = 'ALT', action = wezterm.action.ActivateTab(i - 1) })
end

return {
  keys = common.concat(mux_keys, common.keys),

  key_tables = {
    copy_mode = {
      {
        key = 'LeftArrow',
        mods = 'CTRL',
        action = wezterm.action({ CopyMode = 'MoveBackwardWord' }),
      },
      {
        key = 'RightArrow',
        mods = 'CTRL',
        action = wezterm.action({ CopyMode = 'MoveForwardWord' }),
      },
      {
        key = 'v',
        mods = 'NONE',
        action = wezterm.action.CopyMode({ SetSelectionMode = 'Cell' }),
      },
      {
        key = 'v',
        mods = 'SHIFT',
        action = wezterm.action.CopyMode({ SetSelectionMode = 'Line' }),
      },
      { key = 'Escape', mods = 'NONE', action = close_copy_mode },
      {
        key = '?',
        mods = 'SHIFT',
        action = wezterm.action.Search('CurrentSelectionOrEmptyString'),
      },
      { key = 'c', mods = 'CTRL', action = close_copy_mode },
      { key = 'Enter', mods = 'NONE', action = close_copy_mode },
      { key = 'Escape', mods = 'ALT', action = close_copy_mode },
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
          wezterm.action.ScrollToBottom,
        }),
      },
      { key = 'PageDown', mods = 'NONE', action = wezterm.action.CopyMode('PageDown') },
      { key = 'PageUp', mods = 'NONE', action = wezterm.action.CopyMode('PageUp') },
    },
    search_mode = {
      { key = 'Enter', mods = 'NONE', action = wezterm.action.CopyMode('PriorMatch') },
      { key = 'Enter', mods = 'SHIFT', action = wezterm.action.CopyMode('NextMatch') },
      { key = 'Escape', mods = 'NONE', action = wezterm.action.Multiple({
        wezterm.action({ CopyMode = 'ClearPattern' }),
        wezterm.action({ CopyMode = 'Close' }),
        wezterm.action.ScrollToBottom,
      })},
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
