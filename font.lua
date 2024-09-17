local wezterm = require('wezterm')
return {
  font_size = 14,

  -- @Reference: single font
  -- font = wezterm.font "FiraCode Nerd Font",
  font = wezterm.font_with_fallback {
      { family = "Operator Mono Lig", weight="Book" },
      { family = "FiraCode Nerd Font", weight="Regular" },
  },
}
