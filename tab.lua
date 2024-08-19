local wezterm = require('wezterm')
local utils = require('utils')

local MAX_TAB_WIDTH = 30
local MAX_TEXT_LENGTH = math.max(18, MAX_TAB_WIDTH - 7)

local CONFIG = {
  padding = 1,
  use_icons = true,
  use_icon_colors = false,  -- TODO: fucks up foreground color of the text
}

local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

local tab_icons = {}

local function ansi(c) return { AnsiColor = c } end

local function css(c) return { Color = c } end

local sep = wezterm.format({
  { Foreground = { AnsiColor = 'Fuchsia' } },
  { Text = '┊' },
})

local icon_variants = utils.map({
  { 'dev_coda', css('#3A5F0B') },
  'dev_onedrive',
  { 'linux_awesome', ansi('Teal') },
  'fa_bath',
  'fa_bug',
  'fa_eye',
  'fae_floppy',
  { 'fa_eur', ansi('Yellow') },
  'fa_flask',
  'fa_fort_awesome',
  { 'fa_magic', css('#7fcedc') },
  { 'fa_magnet', ansi('Purple') },
  'fa_microchip',
  { 'fa_plane', ansi('Blue') },
  { 'fa_snowflake_o', css('#002553') },
  'fa_subway',
  { 'fa_usd', css('#118C4F') },
  { 'fae_apple_fruit', css('#4CBB17') },
  { 'fae_biohazard', css('#EADF0C') },
  { 'fae_carot', css('#F88017') },
  { 'fae_cherry', ansi('Red') },
  { 'md_hammer_sickle', ansi('Red') },
  { 'fae_comet', css('#61667D') },
  { 'fae_dna', css('#F88017') },
  { 'fae_donut', css('#FAAFBE') },
  'fae_popcorn',
  'fae_poison',
  { 'linux_nixos', css('#7095F7') },
  'linux_gentoo',
  { 'fae_radioactive', css('#A49B72') },
  { 'fae_ruby', css('#E0115F') },
  { 'fae_tooth', ansi('White') },
  'linux_tux',
  { 'md_basketball', css('#F88158') },
  { 'md_clover', css('#3EA055') },
  { 'md_currency_eth', css('#7095F7') },
  { 'md_ghost', ansi('White') },
}, function(i)
  if type(i) == 'string' then
    return wezterm.nerdfonts[i]
  end

  if type(i) == 'table' then
    if CONFIG.use_icon_colors then
      return wezterm.format({
        { Foreground = i[2] },
        { Text = wezterm.nerdfonts[i[1]] },
      })
    else
      return wezterm.nerdfonts[i[1]]
    end
  end

  error('unexpected type')
end)

function tab_title(tab_info)
  local title = tab_info.tab_title
  -- if the tab title is explicitly set, take that
  if title and #title > 0 then
    return title
  end
  -- Otherwise, use the title from the active pane
  -- in that tab
  return string.sub(tab_info.active_pane.title, 1, MAX_TEXT_LENGTH)
end

local SOLID_LEFT_ARROW = utf8.char(0xe0ba)
local SOLID_LEFT_MOST = utf8.char(0x2588)
local SOLID_RIGHT_ARROW = utf8.char(0xe0bc)

local SUP_IDX = {
  '¹',
  '²',
  '³',
  '⁴',
  '⁵',
  '⁶',
  '⁷',
  '⁸',
  '⁹',
  '¹⁰',
  '¹¹',
  '¹²',
  '¹³',
  '¹⁴',
  '¹⁵',
  '¹⁶',
  '¹⁷',
  '¹⁸',
  '¹⁹',
  '²⁰',
}
local SUB_IDX = {
  '₁',
  '₂',
  '₃',
  '₄',
  '₅',
  '₆',
  '₇',
  '₈',
  '₉',
  '₁₀',
  '₁₁',
  '₁₂',
  '₁₃',
  '₁₄',
  '₁₅',
  '₁₆',
  '₁₇',
  '₁₈',
  '₁₉',
  '₂₀',
}

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover)
  local edge_background = '#1c1b19'
  local background = '#4e4e4e'
  local foreground = '#1c1b19'
  local dim_foreground = '#3A3A3A'

  if tab.is_active then
    background = '#d79921'
    -- background = '#d65d0e'
    foreground = '#1c1b19'
  elseif hover then
    background = '#ff7800'
    -- background = '#d79921'
    foreground = '#1c1b19'
  end

  if tab_icons[tab.tab_id] == nil then
    tab_icons[tab.tab_id] = icon_variants[math.random(#icon_variants)]
  end

  local icon = tab_icons[tab.tab_id]
  -- print(dump(icon))
  if tab.active_pane.is_zoomed then
    icon = wezterm.format({
      { Text = wezterm.nerdfonts['md_magnify_plus'] },
    })
  end

  local left_arrow = SOLID_LEFT_ARROW
  if tab.tab_index == 0 then
    left_arrow = SOLID_LEFT_MOST
  end
  local id = SUB_IDX[tab.tab_index + 1]

  return {
    { Attribute = { Intensity = 'Bold' } },
    { Background = { Color = edge_background } },
    { Foreground = { Color = background } },
    { Text = left_arrow },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = id },
    { Text = icon },
    { Text = ' ' },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = tab_title(tab) .. ' ' },
    { Background = { Color = edge_background } },
    { Foreground = { Color = background } },
    { Text = SOLID_RIGHT_ARROW },
    { Attribute = { Intensity = 'Normal' } },
  }
end)

return {
  enable_tab_bar = true,
  use_fancy_tab_bar = false,
  tab_bar_at_bottom = true,
  show_new_tab_button_in_tab_bar = false,
  tab_max_width = MAX_TAB_WIDTH,
}
