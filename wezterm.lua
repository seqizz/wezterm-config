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
}, utils.req)

return utils.merge(table.unpack(modules))
