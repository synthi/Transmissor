-- =========================================================
-- GRID — Transmissor v1.2.0
-- Differential grid state management + key handler
-- Rows 1-3: interactive param bars (tap/hold ramp)
-- Rows 4-5: Fidelity/Interference presets
-- Row 8: Controls
-- Shift params inherit from main when nil
-- =========================================================

local grid_state = {}
for y = 1, 8 do
  grid_state[y] = {}
  for x = 1, 16 do
    grid_state[y][x] = -1
  end
end

local _grid = nil

-- Page button column → page mapping
local page_cols = {
  [4] = 4,   -- SPACE
  [5] = 5,   -- TEXTURE
  [6] = 6,   -- DESTROY
  [9] = 9,   -- EQ
  [10] = 1,  -- TX
  [11] = 2,  -- AIR
  [12] = 3,  -- NOISE
  [13] = 7,  -- RX
  [14] = 8   -- MIX
}

-- Is this column a page button?
local function is_page_col(x)
  return page_cols[x] ~= nil
end

-- =========================================================
-- RAMP SYSTEM (for grid hold interaction)
-- =========================================================

-- Track press times for rows 1-3
local press_time = {}  -- [y] = clock time

-- Ramp state per param row
local ramp_state = {
  [1] = { active = false, param = nil, start_val = 0, target_val = 0,
          start_time = 0, duration = 0 },
  [2] = { active = false, param = nil, start_val = 0, target_val = 0,
          start_time = 0, duration = 0 },
  [3] = { active = false, param = nil, start_val = 0, target_val = 0,
          start_time = 0, duration = 0 },
}

local ramp_metro = nil

-- Get param name for a row (shift inherits from main when nil)
local function get_param_for_row(page, row)
  local sa = _G.shift_active or false
  if sa and page.shift then
    return page.shift[row] or page.main[row]
  else
    return page.main[row]
  end
end

-- Start a ramp for a param row
local function start_ramp(row, param_name, target_norm, hold_time)
  local minv = param_min(param_name)
  local maxv = param_max(param_name)
  local target_val = minv + target_norm * (maxv - minv)
  local current_val = params:get(param_name) or minv

  ramp_state[row] = {
    active = true,
    param = param_name,
    start_val = current_val,
    target_val = target_val,
    start_time = clock.time(),
    duration = math.max(0.1, hold_time * 2.0)  -- ramp = 2x hold time
  }
end

-- Process ramps (called at 25fps)
local function process_ramps()
  local now = clock.time()
  for row = 1, 3 do
    local rs = ramp_state[row]
    if rs.active then
      local elapsed = now - rs.start_time
      local progress = math.min(1.0, elapsed / rs.duration)
      -- Ease-in-out curve
      local eased = progress < 0.5
        and (2 * progress * progress)
        or (1 - ((-2 * progress + 2) ^ 2) / 2)
      local val = rs.start_val + (rs.target_val - rs.start_val) * eased
      params:set(rs.param, val)
      if progress >= 1.0 then
        rs.active = false
      end
    end
  end
end

-- =========================================================
-- GRID LED SET (differential)
-- =========================================================

local function grid_set_led(x, y, val)
  val = util.clamp(math.floor(val + 0.5), 0, 15)
  if grid_state[y][x] ~= val then
    grid_state[y][x] = val
    _grid:led(x, y, val)
  end
end

-- =========================================================
-- GRID KEY HANDLER
-- =========================================================

function grid_key(x, y, z)
  -- ROW 8: Controls
  if y == 8 then

    -- SHIFT BUTTON (col 16) — momentáneo
    if x == 16 then
      _G.shift_active = (z == 1)
      return
    end

    -- PAGE BUTTONS — press = change page + shift, release = shift off
    if is_page_col(x) then
      if z == 1 then
        _G.current_page = page_cols[x]
        _G.distance_mode = false
        _G.shift_active = true
      else
        _G.shift_active = false
      end
      return
    end

    -- PTT (col 1) — toggle
    if x == 1 and z == 1 then
      _G.ptt_active = not _G.ptt_active
      params:set("key_click", _G.ptt_active and 1 or 0)
      return
    end

    -- DISTANCE (col 8) — toggle
    if x == 8 and z == 1 then
      _G.distance_mode = not _G.distance_mode
      return
    end

    return
  end

  -- ROWS 1-3: Interactive param bars
  if y >= 1 and y <= 3 then
    local page = pages[_G.current_page]
    if not page then return end
    if _G.distance_mode then return end

    local param_name = get_param_for_row(page, y)
    if not param_name then return end

    if z == 1 then
      -- Record press time
      press_time[y] = clock.time()
    else
      -- Release: calculate hold duration
      if press_time[y] then
        local hold_time = clock.time() - press_time[y]
        local target_norm = x / 16.0

        if hold_time < 0.15 then
          -- Tap: instant set
          local minv = param_min(param_name)
          local maxv = param_max(param_name)
          params:set(param_name, minv + target_norm * (maxv - minv))
        else
          -- Hold: start ramp
          start_ramp(y, param_name, target_norm, hold_time)
        end
        press_time[y] = nil
      end
    end
    return
  end

  -- ROW 4: FIDELITY PRESET
  if y == 4 and z == 1 then
    _G.current_fidelity = x
    apply_fidelity_preset(x)
    return
  end

  -- ROW 5: INTERFERENCE PRESET
  if y == 5 and z == 1 then
    _G.current_interference = x
    apply_interference_preset(x)
    return
  end
end

-- =========================================================
-- RENDER PRESET ROW
-- =========================================================

local function render_preset_row(row, current_val)
  for x = 1, 16 do
    local b
    if x == current_val then
      b = 11
    elseif x <= 2 then b = 9
    elseif x <= 4 then b = 8
    elseif x <= 6 then b = 7
    elseif x <= 8 then b = 6
    elseif x <= 10 then b = 5
    elseif x <= 12 then b = 4
    elseif x <= 14 then b = 3
    else b = 2
    end
    grid_set_led(x, row, b)
  end
end

-- =========================================================
-- RENDER PAGE VISUALS (rows 1-3 = active params)
-- =========================================================

function render_page_visuals()
  if _G.distance_mode then
    local dist = params:get("distance") or 0
    local vu_cols = math.floor(dist * 16)
    for x = 1, 16 do
      for y = 1, 3 do
        grid_set_led(x, y, (x <= vu_cols) and
          math.floor(4 + (x / 16) * 6) or 0)
      end
    end
    return
  end

  local page = pages[_G.current_page]
  if not page then
    for y = 1, 3 do
      for x = 1, 16 do grid_set_led(x, y, 0) end
    end
    return
  end

  for row = 1, 3 do
    local p = get_param_for_row(page, row)
    if p then
      local norm = (params:get(p) - param_min(p)) /
        (param_max(p) - param_min(p) + 0.0001)
      norm = util.clamp(norm, 0, 1)
      local filled = math.floor(norm * 16)
      for x = 1, 16 do
        grid_set_led(x, row, (x <= filled) and math.floor(5 + norm * 10) or 0)
      end
    else
      for x = 1, 16 do grid_set_led(x, row, 0) end
    end
  end
end

-- =========================================================
-- GRID REDRAW
-- =========================================================

function grid_redraw()
  if not _grid then return end

  local ok, err = pcall(function()
    -- Process any active ramps
    process_ramps()

    -- ROWS 1-3: Page visuals (interactive param bars)
    render_page_visuals()

    -- ROW 4: FIDELITY presets (moved from row 6)
    render_preset_row(4, _G.current_fidelity)

    -- ROW 5: INTERFERENCE presets (moved from row 7)
    render_preset_row(5, _G.current_interference)

    -- ROW 6-7: empty (freed by preset move)
    for x = 1, 16 do
      grid_set_led(x, 6, 0)
      grid_set_led(x, 7, 0)
    end

    -- ROW 8: Controls
    -- Col 1: PTT toggle (2=off, 11=on)
    grid_set_led(1, 8, _G.ptt_active and 11 or 2)
    -- Cols 2-3: empty
    grid_set_led(2, 8, 0); grid_set_led(3, 8, 0)
    -- Col 4-6: FX pages (SPACE=4, TEXTURE=5, DESTROY=6)
    grid_set_led(4, 8, (_G.current_page == 4) and 11 or 1)
    grid_set_led(5, 8, (_G.current_page == 5) and 11 or 1)
    grid_set_led(6, 8, (_G.current_page == 6) and 11 or 1)
    -- Col 7: empty
    grid_set_led(7, 8, 0)
    -- Col 8: DISTANCE
    grid_set_led(8, 8, _G.distance_mode and 11 or 1)
    -- Col 9: EQ page
    grid_set_led(9, 8, (_G.current_page == 9) and 11 or 1)
    -- Cols 10-14: Pages (TX=10, AIR=11, NOISE=12, RX=13, MIX=14)
    grid_set_led(10, 8, (_G.current_page == 1) and 11 or 1)
    grid_set_led(11, 8, (_G.current_page == 2) and 11 or 1)
    grid_set_led(12, 8, (_G.current_page == 3) and 11 or 1)
    grid_set_led(13, 8, (_G.current_page == 7) and 11 or 1)
    grid_set_led(14, 8, (_G.current_page == 8) and 11 or 1)
    -- Col 15: empty
    grid_set_led(15, 8, 0)
    -- Col 16: SHIFT (4=inactive, 15=active)
    grid_set_led(16, 8, _G.shift_active and 15 or 4)

    _grid:refresh()
  end)

  if not ok then
    print("[Transmissor] grid_redraw error:", err)
  end
end

-- =========================================================
-- INIT / CLEANUP
-- =========================================================

function init_grid()
  _grid = grid.connect()
  if _grid then
    _grid.key = grid_key
    _grid:all(0)
    _grid:refresh()
    for y = 1, 8 do
      for x = 1, 16 do
        grid_state[y][x] = 0
      end
    end
    print("[Transmissor] Grid connected")
  end
end

function grid_cleanup()
  if _grid then
    pcall(function()
      _grid:all(0)
      _grid:refresh()
    end)
  end
end

return {
  grid_redraw = grid_redraw,
  grid_key = grid_key,
  init_grid = init_grid,
  grid_cleanup = grid_cleanup,
  render_page_visuals = render_page_visuals
}