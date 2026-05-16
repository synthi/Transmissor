-- =========================================================
-- GRID — Transmissor
-- Differential grid state management + key handler
-- =========================================================

-- =========================================================
-- GRID STATE (16x8 matrix, brightness 0-15, -1 = unknown)
-- =========================================================

local grid_state = {}
for y = 1, 8 do
  grid_state[y] = {}
  for x = 1, 16 do
    grid_state[y][x] = -1
  end
end

-- =========================================================
-- GLOBALS (shared with transmissor.lua)
-- These are set as _G globals by transmissor.lua
-- =========================================================

local _grid = nil
-- current_page, current_fidelity, current_interference,
-- distance_mode, shift_active are read from _G

-- =========================================================
-- CONSTANTS
-- =========================================================

local KEY_DEBOUNCE_MS = 0.05
local last_key_time = 0

-- =========================================================
-- GRID LED SET (differential — only sends if changed)
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
  -- DEBOUNCE
  local now = util.time()
  if (now - last_key_time) < KEY_DEBOUNCE_MS then return end
  last_key_time = now

  -- ANY PRESS → illuminate that button at level 15 momentarily
  if z == 1 then
    grid_state[y][x] = 15
    _grid:led(x, y, 15)
    _grid:refresh()
  end

  -- SHIFT BUTTON (col 16, row 8) — momentáneo mientras se sostiene
  if y == 8 and x == 16 then
    _G.shift_active = (z == 1)
    return
  end

  -- Only respond to press (not release) for the rest
  if z ~= 1 then return end

  -- ROW 6: FIDELITY PRESET (cols 1-16)
  if y == 6 then
    _G.current_fidelity = x
    apply_fidelity_preset(x)
    return
  end

  -- ROW 7: INTERFERENCE PRESET (cols 1-16)
  if y == 7 then
    _G.current_interference = x
    apply_interference_preset(x)
    return
  end

  -- ROW 8
  if y == 8 then
    if x == 8 then
      -- DISTANCE MODE TOGGLE (col 8)
      _G.distance_mode = not _G.distance_mode
      return
    elseif x >= 10 and x <= 14 then
      -- PAGE SELECTOR (cols 10-14 = 5 pages)
      _G.current_page = x - 9  -- 10→1, 11→2, 12→3, 13→4, 14→5
      _G.distance_mode = false  -- exit distance mode on page change
      return
    end
  end
end

-- =========================================================
-- RENDER PRESET ROW (brightness gradient from 9 down to 2,
-- selection = 11)
-- =========================================================

local function render_preset_row(row, current_val)
  for x = 1, 16 do
    local b
    if x == current_val then
      b = 11  -- selected
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
-- RENDER PAGE VISUALS (grid rows 1-4)
-- Called from grid_redraw
-- =========================================================

function render_page_visuals()
  if _G.distance_mode then
    -- Show distance level as VU bar across rows 1-4
    local dist = params:get("distance")
    local vu_cols = math.floor(dist * 16)
    for x = 1, 16 do
      for y = 1, 4 do
        local b = (x <= vu_cols) and
          math.floor(4 + (x / 16) * 6) or 0
        grid_set_led(x, y, b)
      end
    end
    return
  end

  -- Page-specific VU for main 3 params
  local page = pages[_G.current_page]
  if not page then
    for x = 1, 16 do
      for y = 1, 4 do grid_set_led(x, y, 0) end
    end
    return
  end

  -- Row 1: VU for param main[1]
  local p1 = page.main[1]
  if p1 then
    local norm = (params:get(p1) - param_min(p1)) /
      (param_max(p1) - param_min(p1) + 0.0001)
    norm = util.clamp(norm, 0, 1)
    local filled = math.floor(norm * 16)
    for x = 1, 16 do
      grid_set_led(x, 1, (x <= filled) and
        math.floor(5 + norm * 10) or 0)
    end
  end

  -- Row 2: VU for param main[2]
  local p2 = page.main[2]
  if p2 then
    local norm = (params:get(p2) - param_min(p2)) /
      (param_max(p2) - param_min(p2) + 0.0001)
    norm = util.clamp(norm, 0, 1)
    local filled = math.floor(norm * 16)
    for x = 1, 16 do
      grid_set_led(x, 2, (x <= filled) and
        math.floor(5 + norm * 10) or 0)
    end
  end

  -- Row 3: VU for param main[3]
  local p3 = page.main[3]
  if p3 then
    local norm = (params:get(p3) - param_min(p3)) /
      (param_max(p3) - param_min(p3) + 0.0001)
    norm = util.clamp(norm, 0, 1)
    local filled = math.floor(norm * 16)
    for x = 1, 16 do
      grid_set_led(x, 3, (x <= filled) and
        math.floor(5 + norm * 10) or 0)
    end
  end

  -- Row 4: combined / phase visualization (simple)
  -- Show a pattern based on shift params
  local s1 = page.shift[1]
  if s1 then
    local norm = (params:get(s1) - param_min(s1)) /
      (param_max(s1) - param_min(s1) + 0.0001)
    norm = util.clamp(norm, 0, 1)
    local filled = math.floor(norm * 16)
    for x = 1, 16 do
      grid_set_led(x, 4, (x <= filled) and
        math.floor(3 + norm * 5) or 0)
    end
  else
    for x = 1, 16 do
      grid_set_led(x, 4, 0)
    end
  end
end

-- =========================================================
-- GRID REDRAW (differential)
-- =========================================================

function grid_redraw()
  if not _grid then return end

  local ok, err = pcall(function()
    -- ROW 6: FIDELITY presets
    render_preset_row(6, _G.current_fidelity)

    -- ROW 7: INTERFERENCE presets
    render_preset_row(7, _G.current_interference)

    -- ROW 8:
    -- Col 8: DISTANCE button
    grid_set_led(8, 8, _G.distance_mode and 11 or 1)
    -- Col 9: VACÍA
    grid_set_led(9, 8, 0)
    -- Cols 10-14: PAGE buttons (1=page active, 11=selected)
    for x = 10, 14 do
      grid_set_led(x, 8, (x - 9 == _G.current_page) and 11 or 1)
    end
    -- Col 15: VACÍA
    grid_set_led(15, 8, 0)
    -- Col 16: SHIFT button (4=inactive, 15=active)
    grid_set_led(16, 8, _G.shift_active and 15 or 4)

    -- ROWS 1-4: Page visuals (VU / waveform)
    render_page_visuals()

    -- ROW 5: VACÍA (separator, always off)
    for x = 1, 16 do
      grid_set_led(x, 5, 0)
    end

    _grid:refresh()
  end)

  if not ok then
    print("[Transmissor] grid_redraw error:", err)
  end
end

-- =========================================================
-- INIT GRID
-- =========================================================

function init_grid()
  _grid = grid.connect()
  if _grid then
    _grid.key = grid_key
    -- initial full clear
    _grid:all(0)
    _grid:refresh()
    -- reset state tracker
    for y = 1, 8 do
      for x = 1, 16 do
        grid_state[y][x] = 0
      end
    end
    print("[Transmissor] Grid connected")
  end
end

-- =========================================================
-- CLEANUP
-- =========================================================

function grid_cleanup()
  if _grid then
    pcall(function()
      _grid:all(0)
      _grid:refresh()
    end)
  end
end

-- =========================================================
-- EXPORT
-- =========================================================

return {
  grid_redraw = grid_redraw,
  grid_key = grid_key,
  init_grid = init_grid,
  grid_cleanup = grid_cleanup,
  render_page_visuals = render_page_visuals
}
