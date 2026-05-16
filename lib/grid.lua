-- =========================================================
-- GRID — Transmissor v1.1.1
-- Differential grid state management + key handler
-- Hold page button = shift for that page
-- Rows 1-3: active params, Row 4: empty separator
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
    -- Momentary: tap changes page (shift blips 1 frame), hold = page+shift
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

  -- ROW 6: FIDELITY PRESET
  if y == 6 and z == 1 then
    _G.current_fidelity = x
    apply_fidelity_preset(x)
    return
  end

  -- ROW 7: INTERFERENCE PRESET
  if y == 7 and z == 1 then
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
-- RENDER PAGE VISUALS (rows 1-3 = active params, row 4 = empty)
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
    -- Row 4: empty
    for x = 1, 16 do grid_set_led(x, 4, 0) end
    return
  end

  local page = pages[_G.current_page]
  if not page then
    for y = 1, 4 do
      for x = 1, 16 do grid_set_led(x, y, 0) end
    end
    return
  end

  local sa = _G.shift_active or false

  -- Row 1: param 1
  local p1 = sa and page.shift[1] or page.main[1]
  if p1 then
    local norm = (params:get(p1) - param_min(p1)) /
      (param_max(p1) - param_min(p1) + 0.0001)
    norm = util.clamp(norm, 0, 1)
    local filled = math.floor(norm * 16)
    for x = 1, 16 do
      grid_set_led(x, 1, (x <= filled) and math.floor(5 + norm * 10) or 0)
    end
  else
    for x = 1, 16 do grid_set_led(x, 1, 0) end
  end

  -- Row 2: param 2
  local p2 = sa and page.shift[2] or page.main[2]
  if p2 then
    local norm = (params:get(p2) - param_min(p2)) /
      (param_max(p2) - param_min(p2) + 0.0001)
    norm = util.clamp(norm, 0, 1)
    local filled = math.floor(norm * 16)
    for x = 1, 16 do
      grid_set_led(x, 2, (x <= filled) and math.floor(5 + norm * 10) or 0)
    end
  else
    for x = 1, 16 do grid_set_led(x, 2, 0) end
  end

  -- Row 3: param 3
  local p3 = sa and page.shift[3] or page.main[3]
  if p3 then
    local norm = (params:get(p3) - param_min(p3)) /
      (param_max(p3) - param_min(p3) + 0.0001)
    norm = util.clamp(norm, 0, 1)
    local filled = math.floor(norm * 16)
    for x = 1, 16 do
      grid_set_led(x, 3, (x <= filled) and math.floor(5 + norm * 10) or 0)
    end
  else
    for x = 1, 16 do grid_set_led(x, 3, 0) end
  end

  -- Row 4: always empty (separator)
  for x = 1, 16 do grid_set_led(x, 4, 0) end
end

-- =========================================================
-- GRID REDRAW
-- =========================================================

function grid_redraw()
  if not _grid then return end

  local ok, err = pcall(function()
    -- ROWS 1-4: Page visuals
    render_page_visuals()

    -- ROW 5: separator (always off)
    for x = 1, 16 do grid_set_led(x, 5, 0) end

    -- ROW 6: FIDELITY presets
    render_preset_row(6, _G.current_fidelity)

    -- ROW 7: INTERFERENCE presets
    render_preset_row(7, _G.current_interference)

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