local padding = 0
local window_padding = {
  left = padding,
  right = padding,
  top = padding,
  bottom = padding,
}

local M = {
  window_decorations = "NONE",
  window_close_confirmation = "NeverPrompt",
  window_padding = window_padding,
  window_background_image_hsb = {
    brightness = 0.3,
  },
  window_background_opacity = 0.95,
  text_background_opacity = 1.0,
  adjust_window_size_when_changing_font_size = false,
}

return M
