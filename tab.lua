local wezterm = require('wezterm')
local llm_custody = require('llm-custody')
local status = require('status')

local MAX_TAB_WIDTH = 9999 -- no hard cap, let wezterm distribute available space across tabs
local MAX_TEXT_LENGTH = 60 -- upstream substring guard, real sizing done in format-tab-title
local MAX_TITLE_CAP = 24 -- most title cells a single tab will ever claim
local MIN_TITLE = 2 -- floor for the title text budget when tabs must shrink to fit

-- App-agnostic tab alerting. Any process in a pane can publish its state with the
-- `alert_state` user var (OSC 1337 SetUserVar); the tab number then takes the
-- state's color. The tab keeps its width and background, so an alert never
-- reflows the bar.
local ALERT_STATES = {
  waiting = { color = '#fb4934' },
  done = { color = '#b8bb26' },
  busy = { color = '#83a598' },
  failed = { color = '#cc241d' },
}

-- tab_id -> state value the user already saw in the foreground. An alert is an
-- *unread* marker: rendering a tab while it is active counts as reading it, so the
-- tab falls back to normal colors until the publisher sends a different state.
local alert_ack = {}

-- Unread alert of a tab, or nil.
-- Only the active pane of the tab is inspectable here: format-tab-title's `panes`
-- argument holds the *active* tab's panes and PaneInformation carries no tab_id.
local function unread_alert(tab_info)
  local state = (tab_info.active_pane.user_vars or {}).alert_state or ''
  local alert = ALERT_STATES[state]
  if not alert then
    alert_ack[tab_info.tab_id] = nil -- publisher cleared the var, forget the ack too
    return nil
  end
  if tab_info.is_active then
    alert_ack[tab_info.tab_id] = state
  end
  if alert_ack[tab_info.tab_id] ~= state then
    return alert
  end
  return nil
end

local function tab_title(tab_info)
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

-- Tab switch animation: the new active tab flashes through FLASH_COLORS
-- before it settles. Only the background changes, so no frame reflows the bar.
local FLASH_COLORS = { '#fff4d0', '#f0c868' }
local FLASH_STEP = 0.05 -- seconds per flash color
local ANIM_TIMEOUT = 2 -- seconds after which an animation is dropped unfinished

local last_active = {} -- window_id -> tab_id of the active tab at the last render
local anims = {} -- window_id -> running animation
local anim_gen = 0

-- Running animation of a window, or nil. Its timer does not survive a config
-- reload, so one that outlives ANIM_TIMEOUT is dropped here and the bar falls
-- back to its settled look.
local function current_anim(win)
  local a = anims[win]
  if a and os.time() - a.started > ANIM_TIMEOUT then
    anims[win] = nil
    return nil
  end
  return a
end

-- Advances an animation by one frame and asks for a repaint. `gen` ties the
-- timer chain to the animation it was started for, so a chain whose animation
-- got replaced by a newer switch stops by itself.
local function anim_tick(win, gen)
  local a = anims[win]
  if not a or a.gen ~= gen then
    return
  end
  a.step = a.step + 1
  if a.step > #FLASH_COLORS then
    anims[win] = nil
  end
  status.repaint()
  if anims[win] then
    wezterm.time.call_after(FLASH_STEP, function() anim_tick(win, gen) end)
  end
end

-- Compares the active tab with the one seen at the last render and starts an
-- animation when it changed. Runs at the top of every format-tab-title call,
-- so the first frame painted after a switch already belongs to the animation.
local function track_active(win, tabs)
  local prev = last_active[win]
  local active, prev_open
  for _, t in ipairs(tabs) do
    if t.is_active then
      active = t.tab_id
    end
    if t.tab_id == prev then
      prev_open = true
    end
  end
  if not active or active == prev then
    return
  end
  last_active[win] = active
  anims[win] = nil
  -- first render of the window, or the previous active tab was closed
  if not prev_open then
    return
  end

  anim_gen = anim_gen + 1
  local gen = anim_gen
  anims[win] = { gen = gen, step = 1, started = os.time() }
  wezterm.time.call_after(FLASH_STEP, function() anim_tick(win, gen) end)
end

-- The number only serves to jump to a tab, so the active tab carries none.
local function tab_id_text(t)
  if t.is_active then
    return ''
  end
  return tostring(t.tab_index + 1)
end

-- Cells taken by everything except the title text: left arrow, index, the
-- space after it, the trailing space, the right arrow, and the jail badge
-- where there is one (0 for every tab that is not a jail session).
local function tab_fixed_width(t)
  local id_w = #tab_id_text(t)
  -- 1 left arrow + id + 2 spaces + 1 right arrow
  return 1 + id_w + 2 + 1 + llm_custody.badge_width(t)
end

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local edge_background = '#1c1b19'
  local background = '#4e4e4e'
  local foreground = '#1c1b19'
  local dim_foreground = '#3A3A3A'

  local win = tab.window_id or 0
  track_active(win, tabs)
  local anim = current_anim(win)

  if tab.is_active then
    background = '#d79921'
    -- background = '#d65d0e'
    foreground = '#1c1b19'
  elseif hover then
    background = '#ff7800'
    -- background = '#d79921'
    foreground = '#1c1b19'
  end

  if anim and tab.is_active then
    background = FLASH_COLORS[anim.step] or background
  end

  local alert = unread_alert(tab)
  local id_default = '#ffffff'
  local id_foreground = alert and alert.color or id_default

  -- A pending jail request outranks alert_state and has no unread semantics:
  -- the agent stays blocked whether or not the tab was looked at, so the tab
  -- stays red, focused included, until the queue drains.
  if llm_custody.request_pending(tab) then
    background = llm_custody.REQUEST_BACKGROUND
    foreground = '#1c1b19'
    -- alert colors are unreadable on the request background
    id_foreground = id_default
  end

  local left_arrow = SOLID_LEFT_ARROW
  if tab.tab_index == 0 then
    left_arrow = SOLID_LEFT_MOST
  end
  local id = tab_id_text(tab)

  -- Grow-to-need sizing. Give every tab the width its own title wants (capped at
  -- MAX_TITLE_CAP) and only shrink when the sum of all titles overflows the bar.
  -- That way a new short tab uses the free space on the right instead of squeezing
  -- the existing long tabs. Widths come from status.lua via wezterm.GLOBAL (1 frame
  -- stale, imperceptible).
  local cols = wezterm.GLOBAL.tabbar_cols or 80
  local reserved = (wezterm.GLOBAL.rstatus_w or 0) + (wezterm.GLOBAL.lstatus_w or 0) + 1
  local avail = math.max(0, cols - reserved)

  local sum_fixed = 0 -- decoration cells across all tabs
  local sum_desired = 0 -- title cells all tabs would like
  local this_desired = 0 -- title cells this tab would like
  local live = {} -- tab ids still open, for the cache prune below
  for _, t in ipairs(tabs) do
    local desired = math.min(wezterm.column_width(tab_title(t)), MAX_TITLE_CAP)
    sum_fixed = sum_fixed + tab_fixed_width(t)
    sum_desired = sum_desired + desired
    live[t.tab_id] = true
    if t.tab_id == tab.tab_id then
      this_desired = desired
    end
  end

  -- The cache is keyed by tab_id and nothing else ever removes an entry, so
  -- closed tabs would accumulate for the lifetime of the gui process. Prune
  -- while rendering the first tab: this handler runs once per tab per repaint,
  -- and `tabs` is the authoritative live set at that moment.
  if tab.tab_index == 0 then
    for id in pairs(alert_ack) do
      if not live[id] then
        alert_ack[id] = nil
      end
    end
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

  local elements = {
    { Attribute = { Intensity = 'Bold' } },
    { Background = { Color = edge_background } },
    { Foreground = { Color = background } },
    { Text = left_arrow },
    { Background = { Color = background } },
    { Foreground = { Color = id_foreground } },
    { Text = id },
    { Foreground = { Color = foreground } },
    { Text = ' ' },
  }

  -- Jail badge sits right before the title, as its own segment
  local badge, badge_color = llm_custody.tab_badge(tab)
  if badge then
    if badge_color then
      table.insert(elements, { Foreground = { Color = badge_color } })
      table.insert(elements, { Text = badge })
      table.insert(elements, { Foreground = { Color = foreground } })
    else
      table.insert(elements, { Text = badge })
    end
    table.insert(elements, { Text = ' ' })
  end

  for _, element in ipairs({
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },
    { Text = ' ' },
    { Background = { Color = edge_background } },
    { Foreground = { Color = background } },
    { Text = SOLID_RIGHT_ARROW },
    { Attribute = { Intensity = 'Normal' } },
  }) do
    table.insert(elements, element)
  end

  return elements
end)

return {
  enable_tab_bar = true,
  use_fancy_tab_bar = false,
  tab_bar_at_bottom = true,
  show_new_tab_button_in_tab_bar = false,
  tab_max_width = MAX_TAB_WIDTH,
}
