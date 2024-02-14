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
    { source = { Color = '#282828' }, opacity = 1, width = '100%', height = '100%' },
    {
      source = {
        File = wezterm.home_dir .. "/.config/wezterm/assets/layer0.jpg"
      },
      opacity = 0.5,
      repeat_x = 'Mirror',
      hsb = dimmer,
      attachment = { Parallax = 0.01 },
    },
    {
      source = {
        File = wezterm.home_dir .. "/.config/wezterm/assets/layer1.png",
      },
      width = '100%',
      repeat_x = 'NoRepeat',
      hsb = dimmer,
      attachment = { Parallax = 0.3 },
    },
    {
      source = {
        File = wezterm.home_dir .. "/.config/wezterm/assets/layer2.png",
      },
      width = '100%',
      repeat_x = 'NoRepeat',
      opacity = 0.6,
      vertical_offset = 500,
      repeat_y_size = '300%',
      hsb = dimmer,
      attachment = { Parallax = 0.8 },
    },
  },
}
