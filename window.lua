local wezterm = require('wezterm')
local padding = 4

wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local zoomed = ''

  local active_pane = wezterm.mux.get_pane(tab.active_pane.pane_id)
  local domain_name = active_pane:get_domain_name()

  local index = ''
  if #tabs > 1 or domain_name == 'default' then
    index = string.format('[%s][%d] ', active_pane:get_domain_name(), #tabs)
  end

  return index .. tab.active_pane.title
end)

return {
  window_decorations = 'NONE',
  window_close_confirmation = 'NeverPrompt',
  window_padding = {
    left = padding,
    right = padding,
    top = padding,
    bottom = 1, -- 4 is too much
  },
  window_background_image_hsb = {
    brightness = 0.3,
  },
  window_background_opacity = 0.95,
  text_background_opacity = 1.0,
  adjust_window_size_when_changing_font_size = false,
  background = {
    { source = { Color = '#282828' }, opacity = 0.95, width = '100%', height = '100%' },
    -- {
    --   source = {
    --     File = wezterm.home_dir .. "/.config/wezterm/assets/layer0.jpg"
    --   },
    --   opacity = 0.6,
    --   repeat_x = 'Mirror',
    --   hsb = dimmer,
    --   attachment = { Parallax = 0.01 },
    -- },
    -- {
    --   source = {
    --     File = wezterm.home_dir .. "/.config/wezterm/assets/layer1.png",
    --   },
    --   width = '50%',
    --   repeat_x = 'Repeat',
    --   attachment = { Parallax = 0.3 },
    -- },
    -- {
    --   source = {
    --     File = wezterm.home_dir .. "/.config/wezterm/assets/layer2.png",
    --   },
    --   width = '50%',
    --   repeat_x = 'Repeat',
    --   repeat_y_size = '300%',
    --   attachment = { Parallax = 0.5 },
    -- },
    -- {
    --   source = {
    --     File = wezterm.home_dir .. "/.config/wezterm/assets/plane.png",
    --   },
    --   width = '3cell',
    --   height = '15cell',
    --   repeat_x = 'NoRepeat',
    --   repeat_y = 'NoRepeat',
    --   hsb = dimmer,
    --   opacity = 0.4,
    --   horizontal_align = 'Right',
    --   horizontal_offset = -30,
    --   vertical_offset = 1000,
    --   repeat_y_size = '500%',
    --   attachment = { Parallax = 0.8 },
    -- },
  },
}
