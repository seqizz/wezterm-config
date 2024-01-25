local wezterm = require('wezterm')
local utils = require('utils')

local CONFIG = {
  padding = 1,
  use_icons = true,
  use_icon_colors = true,
}

local function numberStyle(number, script)
  local scripts = {
    superscript = {
      '⁰',
      '¹',
      '²',
      '³',
      '⁴',
      '⁵',
      '⁶',
      '⁷',
      '⁸',
      '⁹',
    },
    subscript = {
      '₀',
      '₁',
      '₂',
      '₃',
      '₄',
      '₅',
      '₆',
      '₇',
      '₈',
      '₉',
    },
  }
  local numbers = scripts[script]
  local number_string = tostring(number)
  local result = ''
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

--- @type table<number, string>
local tab_icons = {}

local function ansi(c) return { AnsiColor = c } end

local function css(c) return { Color = c } end

--- @type string
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
  {'linux_nixos', css('#7095F7')},
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
  return string.sub(tab_info.active_pane.title, 1, 18)
end

wezterm.on('format-tab-title', function(tab)
  -- start indexing tabs from 1
  local index = tab.tab_index + 1
  local id = tab.tab_id
  local pad = string.rep(' ', CONFIG.padding)

  if CONFIG.use_icons then
    if tab_icons[id] == nil then
      tab_icons[id] = icon_variants[math.random(#icon_variants)]
    end

    local icon = tab_icons[id]
    if tab.active_pane.is_zoomed then
      icon = wezterm.format({
        { Background = { Color = 'DarkOrange' } },
        { Foreground = { Color = 'White' } },
        { Text = string.format('%s ', wezterm.nerdfonts['md_magnify_plus']) },
      })
    end

    return string.format('%s%s  %s%s%s', numberStyle(index, 'superscript'), icon, tab_title(tab), pad, sep)
  end

  return string.format('%s %d %s', pad, index, pad)
end)

return {
  enable_tab_bar = true,
  use_fancy_tab_bar = false,
  tab_bar_at_bottom = true,
  show_new_tab_button_in_tab_bar = false,
  tab_max_width = 25,
}
