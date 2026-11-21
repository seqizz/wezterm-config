local wezterm = require('wezterm')

return {
  unix_domains = {
    {
      name = 'default',
      socket_path = wezterm.home_dir .. '/.wezterm.sock',
      connect_automatically = false,
    },
  },
  -- Needed to pass all env vars
  mux_env_remove = { },
}
