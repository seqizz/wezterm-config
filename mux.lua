return {
  unix_domains = {
    {
      name = 'default',
      socket_path = '/home/gurkan/.wezterm.sock',
      connect_automatically = false,
    },
  },
  -- Needed to pass all env vars
  mux_env_remove = { },
}
