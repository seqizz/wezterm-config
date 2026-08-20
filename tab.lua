local wezterm = require('wezterm')
local utils = require('utils')

local MAX_TAB_WIDTH = 9999   -- no hard cap, let wezterm distribute available space across tabs
local MAX_TEXT_LENGTH = 60   -- upstream substring guard, real sizing done in format-tab-title
local MAX_TITLE_CAP = 24     -- most title cells a single tab will ever claim
local MIN_TITLE = 2          -- floor for the title text budget when tabs must shrink to fit

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

math.randomseed(os.time())
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

-- App-agnostic tab alerting. Any process in a pane can publish its state with the
-- `alert_state` user var (OSC 1337 SetUserVar); the tab then swaps its icon and,
-- when inactive, its background color. Icon is replaced rather than appended so
-- the grow-to-need width math below stays untouched.
local ALERT_STATES = {
  waiting = { icon = wezterm.nerdfonts.fa_question_circle, color = '#fb4934' },
  done    = { icon = wezterm.nerdfonts.fa_check_circle,    color = '#b8bb26' },
  busy    = { icon = wezterm.nerdfonts.fa_hourglass_half,  color = '#83a598' },
  failed  = { icon = wezterm.nerdfonts.fa_times_circle,    color = '#cc241d' },
}

-- tab_id -> state value the user already saw in the foreground. An alert is an
-- *unread* marker: rendering a tab while it is active counts as reading it, so the
-- tab falls back to normal colors until the publisher sends a different state.
local alert_ack = {}

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

-- Cells taken by everything except the title text: left arrow, index, icon,
-- the space after the icon, the trailing space, and the right arrow.
local function tab_fixed_width(t)
  local id_w = wezterm.column_width(SUB_IDX[t.tab_index + 1] or '?')
  local icon = tab_icons[t.tab_id]
  local icon_w = icon and wezterm.column_width(icon) or 1
  -- 1 left arrow + id + icon + 2 spaces + 1 right arrow
  return 1 + id_w + icon_w + 2 + 1
end

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
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

  -- Only the active pane of the tab is inspectable here: format-tab-title's `panes`
  -- argument holds the *active* tab's panes and PaneInformation carries no tab_id.
  local state = (tab.active_pane.user_vars or {}).alert_state or ''
  local alert = ALERT_STATES[state]
  if not alert then
    alert_ack[tab.tab_id] = nil   -- publisher cleared the var, forget the ack too
  elseif tab.is_active then
    alert_ack[tab.tab_id] = state
  end
  if alert and alert_ack[tab.tab_id] ~= state then
    icon = alert.icon or icon   -- keep the random icon if the glyph name is missing
    background = alert.color
    foreground = '#1c1b19'
  end

  local left_arrow = SOLID_LEFT_ARROW
  if tab.tab_index == 0 then
    left_arrow = SOLID_LEFT_MOST
  end
  local id = SUB_IDX[tab.tab_index + 1]

  -- Grow-to-need sizing. Give every tab the width its own title wants (capped at
  -- MAX_TITLE_CAP) and only shrink when the sum of all titles overflows the bar.
  -- That way a new short tab uses the free space on the right instead of squeezing
  -- the existing long tabs. Widths come from status.lua via wezterm.GLOBAL (1 frame
  -- stale, imperceptible).
  local cols = wezterm.GLOBAL.tabbar_cols or 80
  local reserved = (wezterm.GLOBAL.rstatus_w or 0) + (wezterm.GLOBAL.lstatus_w or 0) + 1
  local avail = math.max(0, cols - reserved)

  local sum_fixed = 0     -- decoration cells across all tabs
  local sum_desired = 0   -- title cells all tabs would like
  local this_desired = 0  -- title cells this tab would like
  for _, t in ipairs(tabs) do
    local desired = math.min(wezterm.column_width(tab_title(t)), MAX_TITLE_CAP)
    sum_fixed = sum_fixed + tab_fixed_width(t)
    sum_desired = sum_desired + desired
    if t.tab_id == tab.tab_id then this_desired = desired end
  end

  local avail_titles = math.max(0, avail - sum_fixed)
  local title_budget
  if sum_desired <= avail_titles or sum_desired == 0 then
    -- Everything fits: each tab keeps its natural width, no squeezing.
    title_budget = this_desired
  else
    -- Overflow: shrink titles proportionally to how much each wanted.
    local factor = avail_titles / sum_desired
    title_budget = math.max(MIN_TITLE, math.floor(this_desired * factor))
  end

  local title = wezterm.truncate_right(tab_title(tab), title_budget)

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
    { Text = title },
    { Text = ' ' },
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
