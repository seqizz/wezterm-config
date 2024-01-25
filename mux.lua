return {
  unix_domains = {
    {
      name = 'default',
      socket_path = os.getenv('HOME') .. '/.wezterm.sock',
      connect_automatically = false,
    },
  },
  mux_env_remove = {
    'SSH_CLIENT',
    'SSH_CONNECTION',
  },
}
