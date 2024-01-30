local wezterm = require 'wezterm';

local SOLID_LEFT_ARROW = utf8.char(0xe0b1)
local SOLID_RIGHT_ARROW = utf8.char(0xe0b0)

-- @Reference send signal to active app
-- Not used yet (tmux is always THE active one)
-- function send_signal (pane, signal)
  -- local_process = pane:get_foreground_process_info()
  -- if local_process then
    -- success, stdout, stderr = wezterm.run_child_process { 'sudo', 'kill', signal, local_process.pid }
  -- end
-- end

-- function set_col_overrides(window, pane)
  -- local overrides = window:get_config_overrides() or {}
  -- local pane_obj = pane:get_dimensions()
  -- overrides.initial_cols = pane_obj.cols
  -- overrides.initial_rows = pane_obj.viewport_rows
  -- window:set_config_overrides(overrides)
-- end

-- local move_around = function(window, pane, direction_wez, direction_nvim)
  -- -- if pane:get_title():sub(-3) == "vim" then
  -- if string.find(pane:get_title(), ":vim ") then
    -- window:perform_action(wezterm.action{SendString="\x17"..direction_nvim}, pane)
  -- else
    -- window:perform_action(wezterm.action{ActivatePaneDirection=direction_wez}, pane)
  -- end
-- end
-- wezterm.on("move-left", function(window, pane)
  -- move_around(window, pane, "Left", "h")
-- end)

-- wezterm.on("move-right", function(window, pane)
  -- move_around(window, pane, "Right", "l")
-- end)

-- wezterm.on("move-up", function(window, pane)
  -- move_around(window, pane, "Up", "k")
-- end)

-- wezterm.on("move-down", function(window, pane)
  -- move_around(window, pane, "Down", "j")
-- end)

-- wezterm.on('mux-startup', function()
  -- local tab, pane, window = mux.spawn_window {}
  -- pane:split { direction = 'Top' }
-- end)

-- wezterm.on('gui-startup', function(cmd)
  -- local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
  -- window:gui_window():maximize()
-- end)

-- wezterm.on("window-resized", function(window, pane)
  -- set_col_overrides(window, pane)
-- end)

-- wezterm.on("window-config-reloaded", function(window, pane)
  -- set_col_overrides(window, pane)
-- end);

local function numberStyle(number, script)
	local scripts = {
		superscript = {
			"⁰",
			"¹",
			"²",
			"³",
			"⁴",
			"⁵",
			"⁶",
			"⁷",
			"⁸",
			"⁹",
		},
		subscript = {
			"₀",
			"₁",
			"₂",
			"₃",
			"₄",
			"₅",
			"₆",
			"₇",
			"₈",
			"₉",
		},
	}
	local numbers = scripts[script]
	local number_string = tostring(number)
	local result = ""
	for i = 1, #number_string do
		local char = number_string:sub(i, i)
		local num = tonumber(char)
		if num then
			result = result .. numbers[num + 1]
		else
			result = result .. char
		end
	end
	return result
end

-- custom tab bar
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local RIGHT_DIVIDER = utf8.char(0xe0bc)
	local colours = config.resolved_palette.tab_bar

	local active_tab_index = 0
	for _, t in ipairs(tabs) do
		if t.is_active == true then
			active_tab_index = t.tab_index
		end
	end

	local active_bg = colours.active_tab.bg_color
	local active_fg = colours.active_tab.fg_color
	local inactive_bg = colours.inactive_tab.bg_color
	local inactive_fg = colours.inactive_tab.fg_color
  local new_tab_bg = colours.new_tab.bg_color

	local s_bg, s_fg, e_bg, e_fg

	-- the last tab
	if tab.tab_index == #tabs - 1 then
		if tab.is_active then
			s_bg = active_bg
			s_fg = active_fg
			e_bg = new_tab_bg
			e_fg = active_bg
		else
			s_bg = inactive_bg
			s_fg = inactive_fg
			e_bg = new_tab_bg
			e_fg = inactive_bg
		end
	elseif tab.tab_index == active_tab_index - 1 then
		s_bg = inactive_bg
		s_fg = inactive_fg
		e_bg = active_bg
		e_fg = inactive_bg
	elseif tab.is_active then
		s_bg = active_bg
		s_fg = active_fg
		e_bg = inactive_bg
		e_fg = active_bg
	else
		s_bg = inactive_bg
		s_fg = inactive_fg
    e_bg = inactive_bg
		e_fg = inactive_bg
	end

	local muxpanes = wezterm.mux.get_tab(tab.tab_id):panes()
	local count = #muxpanes == 1 and "" or #muxpanes

	return {
		{ Background = { Color = s_bg } },
		{ Foreground = { Color = s_fg } },
		{ Text = " " .. tab.tab_index + 1 .. ": " .. tab.active_pane.title .. numberStyle(count, "superscript") .. " " },
		{ Background = { Color = e_bg } },
		{ Foreground = { Color = e_fg } },
		{ Text = RIGHT_DIVIDER },
	}
end)

return {
  font = wezterm.font("Operator Mono Lig", {weight="Book"}),
  font_size = 14.0,
  scrollback_lines = 20000,
  -- debug_key_events = true,
  -- enable_tab_bar = false,
  use_fancy_tab_bar = false,
  tab_bar_at_bottom = true,
  hide_tab_bar_if_only_one_tab = true,
  tab_max_width = 32,
  show_tab_index_in_tab_bar = true,
  tab_and_split_indices_are_zero_based = false,
  -- use_fancy_tab_bar = true,
  harfbuzz_features = {"ss03", "ss08"},
  enable_wayland = false,
  colors = {
    foreground = "#d0d0d0",
    background = "#212121",
    cursor_bg = "#d0d0d0",
    cursor_border = "#d0d0d0",
    cursor_fg = "#151515",
    selection_bg = "teal",
    selection_fg = "#d0d0d0",
    ansi = {"#151515","#ac4142","#7e8e50","#e5b567","#6c99bb","#9f4e85","#7dd6cf","#d0d0d0"},
    brights = {"#505050","#ac4142","#7e8e50","#e5b567","#6c99bb","#9f4e85","#7dd6cf","#f5f5f5"},
    tab_bar = {
      background = "#303446",
      new_tab = {
        bg_color = "#303446",
        fg_color = "white",
        intensity = "Normal"
      },
      active_tab = {
        bg_color = "#6c71c4",
        fg_color = "white",
        intensity = "Normal"
      },
      inactive_tab = {
        bg_color = "#51576D",
        fg_color = "#C6D0F5",
      }
      -- inactive_tab_hover = {
        -- bg_color = "#3b3052",
        -- fg_color = "#909090"
      -- }
    }
  },
  window_decorations = "NONE",
  window_close_confirmation = "NeverPrompt",
  selection_word_boundary = " \t\n{[}]()\"':;=",
  check_for_updates = false,
  warn_about_missing_glyphs = false,
  exit_behavior = "Close",
  adjust_window_size_when_changing_font_size = false,
  -- enable_csi_u_key_encoding = true,

  window_background_opacity = 0.92,
  text_background_opacity = 1.0,

  -- multiplexing stuff
  unix_domains = {
    {
      name = "default",
      socket_path = "/home/gurkan/.wezterm.sock",
      connect_automatically = false,
    }
  },
  mux_env_remove = {
    "SSH_CLIENT",
    "SSH_CONNECTION",
  },

  -- quick_select_alphabet = "" -- todo for workmen
  disable_default_quick_select_patterns = true,
  quick_select_patterns = {
    'sha256-\\S{44}', -- sha256 another
    '[0-9a-f]{7,40}', -- sha1
    'sha256:[A-Za-z0-9]{52}', -- sha256
    '[a-z0-9-]+.[a-z0-9]+.[a-z0-9]+.[a-z0-9]+ ', -- inno FQDN
    '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+.[a-zA-Z0-9.-]+',  -- simple e-mail
    "'(\\S[^']*\\S)'",  -- single quoted text
    '"(\\S[^"]*\\S)"',  -- double quoted text
    '~?/?[a-zA-Z0-9_/.-]+',  -- path
    '~> (.*)', -- stuff after ~> because that is the prompt
    '%s(.*)%s',  -- anything else covered with whitespace
  },

  mouse_bindings = {
    -- Change the default click behavior so that it only selects
    -- text and doesn't open hyperlinks
    {
      event={Up={streak=1, button="Left"}},
      mods="NONE",
      action=wezterm.action{CompleteSelection="PrimarySelection"},
    },

    -- and make CTRL-Click open hyperlinks
    {
      event={Up={streak=1, button="Left"}},
      mods="CTRL",
      action="OpenLinkAtMouseCursor",
    },
  },

  keys = {
    -- mux start
    -- { key = "-", mods = "ALT", action=wezterm.action{SplitVertical={domain="CurrentPaneDomain"}} },
    -- { key = "|", mods = "ALT", action=wezterm.action{SplitHorizontal={domain="CurrentPaneDomain"}} },
    -- { key = "z", mods = "ALT", action="TogglePaneZoomState" },
    -- { key = "n", mods = "ALT", action=wezterm.action{SpawnTab="CurrentPaneDomain"}},
    -- { key = "LeftArrow", mods = "ALT", action=wezterm.action{ActivatePaneDirection="Left"}},
    -- { key = "DownArrow", mods = "ALT", action=wezterm.action{ActivatePaneDirection="Down"}},
    -- { key = "UpArrow", mods = "ALT", action=wezterm.action{ActivatePaneDirection="Up"}},
    -- { key = "RightArrow", mods = "ALT", action=wezterm.action{ActivatePaneDirection="Right"}},
    -- { key = "a", mods = "ALT", action=wezterm.action{AdjustPaneSize={"Left", 5}}},
    -- { key = "s", mods = "ALT", action=wezterm.action{AdjustPaneSize={"Down", 5}}},
    -- { key = "w", mods = "ALT", action=wezterm.action{AdjustPaneSize={"Up", 5}}},
    -- { key = "d", mods = "ALT", action=wezterm.action{AdjustPaneSize={"Right", 5}}},
    -- { key = "1", mods = "ALT", action = wezterm.action.ActivateTab(0) },
    -- { key = "2", mods = "ALT", action = wezterm.action.ActivateTab(1) },
    -- { key = "3", mods = "ALT", action = wezterm.action.ActivateTab(2) },
    -- { key = "4", mods = "ALT", action = wezterm.action.ActivateTab(3) },
    -- { key = "5", mods = "ALT", action = wezterm.action.ActivateTab(4) },
    -- { key = "6", mods = "ALT", action = wezterm.action.ActivateTab(5) },
    -- { key = "7", mods = "ALT", action = wezterm.action.ActivateTab(6) },
    -- { key = "8", mods = "ALT", action = wezterm.action.ActivateTab(7) },
    -- { key = "9", mods = "ALT", action = wezterm.action.ActivateTab(8) },
    -- { key = "k", mods = "ALT", action = wezterm.action.CloseCurrentTab{confirm=true}},
    -- mux end

    -- Turn off the defaults
    {key="=", mods="CTRL", action="DisableDefaultAssignment"},
    {key="RightArrow", mods="CTRL|SHIFT", action="DisableDefaultAssignment"},
    {key="Tab", mods="CTRL", action="DisableDefaultAssignment"},
    {key="Tab", mods="CTRL|SHIFT", action="DisableDefaultAssignment"},
    {key="Tab", mods="SHIFT", action="DisableDefaultAssignment"},
    {key="LeftArrow", mods="CTRL|SHIFT", action="DisableDefaultAssignment"},
    {key="F", mods="CTRL|SHIFT", action="DisableDefaultAssignment"},
    {key="P", mods="CTRL|SHIFT", action="DisableDefaultAssignment"},
    -- mux start
    -- {key=" ", mods="CTRL|SHIFT", action="DisableDefaultAssignment"},
    -- {key="Enter", mods="ALT", action="DisableDefaultAssignment"},
    -- mux end
    {key="Return", mods="ALT", action="DisableDefaultAssignment"},
    {key="n", mods="SUPER", action="DisableDefaultAssignment"},

    -- standalone start
    {key="1", mods="ALT", action="DisableDefaultAssignment"},
    {key="2", mods="ALT", action="DisableDefaultAssignment"},
    {key="3", mods="ALT", action="DisableDefaultAssignment"},
    {key="4", mods="ALT", action="DisableDefaultAssignment"},
    {key="5", mods="ALT", action="DisableDefaultAssignment"},
    {key="6", mods="ALT", action="DisableDefaultAssignment"},
    {key="7", mods="ALT", action="DisableDefaultAssignment"},
    {key="8", mods="ALT", action="DisableDefaultAssignment"},
    {key="9", mods="ALT", action="DisableDefaultAssignment"},
    --standalone end

    -- Assign new
    -- @Reference see above
    -- {key="A", mods="ALT", action=wezterm.action_callback(
    -- function(window, pane)
    -- send_signal(pane, '-USR1')
    -- end
    -- )},
    {key="x", mods="ALT", action="QuickSelect"},
    {key="+", mods="CTRL", action="IncreaseFontSize"},
    {key="4", mods="CTRL", action="IncreaseFontSize"},
    {key="-", mods="CTRL", action="DecreaseFontSize"},
    {key="0", mods="CTRL", action="ResetFontSize"},
    {key="Delete", mods="SHIFT", action=wezterm.action{PasteFrom="PrimarySelection"}},
    {key="V", mods="CTRL", action=wezterm.action{PasteFrom="Clipboard"}},
    -- Alt-c to "click" links without mouse
    {
      key = 'c',
      mods = 'ALT',
      action = wezterm.action.QuickSelectArgs {
        label = 'open url',
        patterns = {
          -- A bit more proper regex for URLs, at least to clickable ones
          'https?://[A-Za-z0-9$_+:/?@&,;%=.-]+',
        },
        action = wezterm.action_callback(function(window, pane)
          local url = window:get_selection_text_for_pane(pane)
          wezterm.log_info('opening: ' .. url)
          wezterm.open_with(url)
        end),
      },
    },
    -- mux reference start
    -- {key="RightArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-right"}},
    -- {key="LeftArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-left"}},
    -- {key="UpArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-up"}},
    -- {key="DownArrow", mods="CTRL|SHIFT", action=wezterm.action{EmitEvent="move-down"}},
    -- mux reference end
  }
}

-- vim: set ts=2 sw=2 tw=0 et :
