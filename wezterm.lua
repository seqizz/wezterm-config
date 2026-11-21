local wezterm = require('wezterm')
local utils = require('utils')

require('status').enable()

local modules = utils.map({
  'generic',
  'window',
  'font',
  'theme',
  'tab',
  'mux',
  'tmux-switch',
  -- 'secret', -- no agent forwarding yet
  'keys-mouse',
  'colors',
  'quickselect',
}, require)

-- config_builder rejects unknown keys, so a typo in any module fails loudly
-- instead of being silently ignored
return utils.merge(wezterm.config_builder(), table.unpack(modules))
