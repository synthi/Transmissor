-- =========================================================
-- UI — Transmissor
-- OLED redraw + display helpers
-- =========================================================

-- =========================================================
-- FIDELITY NAMES (imported from parameters)
-- =========================================================

-- These are set as globals by parameters.lua at load time

-- =========================================================
-- DRAW PARAM LINE WITH BAR
-- =========================================================

local function draw_param_bar(y_pos, param_name, value, minv, maxv)
  if not param_name then return end

  local norm = (value - minv) / (maxv - minv + 0.0001)
  norm = util.clamp(norm, 0, 1)

  local label_w = 45  -- pixels for label
  local bar_w = 50   -- pixels for bar
  local bar_x = label_w
  local filled = math.floor(norm * bar_w)

  -- Label
  screen.level(15)
  screen.move(0, y_pos)
  screen.text(string.sub(param_name, 1, 6))

  -- Bar: filled portion
  if filled > 0 then
    screen.level(15)
    screen.rect(bar_x, y_pos - 6, filled, 6)
    screen.fill()
  end

  -- Bar: empty portion
  if filled < bar_w then
    screen.level(2)
    screen.rect(bar_x + filled, y_pos - 6, bar_w - filled, 6)
    screen.fill()
  end

  -- Value text
  screen.level(8)
  screen.move(bar_x + bar_w + 3, y_pos)

  -- Format value nicely based on range
  local val_str
  if math.abs(maxv - minv) < 0.01 then
    val_str = string.format("%.0f", value)
  elseif math.abs(maxv - minv) < 0.1 then
    val_str = string.format("%.3f", value)
  elseif math.abs(maxv - minv) < 1 then
    val_str = string.format("%.2f", value)
  elseif math.abs(maxv - minv) < 10 then
    val_str = string.format("%.1f", value)
  else
    val_str = string.format("%.0f", value)
  end
  screen.text(val_str)
end

-- =========================================================
-- OLED REDRAW
-- =========================================================

function ui_redraw()
  screen.clear()

  local cp = _G.current_page or 1
  local dm = _G.distance_mode or false
  local sa = _G.shift_active or false
  local cf = _G.current_fidelity or 1
  local ci = _G.current_interference or 1

  local page = pages[cp]
  if not page then page = pages[1] end
  local page_str = string.format("%02d/08", cp)

  -- Determine suffix for header
  local suffix = ""
  if dm then
    suffix = " DIST"
  elseif sa then
    suffix = " SH"
  end

  -- -------------------------------------------------
  -- LINE 1: Header — logo + page + suffix
  -- -------------------------------------------------
  screen.level(15)
  screen.move(0, 8)
  screen.text("TRMS " .. page_str .. " " .. page.name .. suffix)

  -- -------------------------------------------------
  -- LINES 2-4: Parameter displays
  -- -------------------------------------------------
  if dm then
    -- DISTANCE MODE: show distance on all 3 lines
    local d = params:get("distance")

    screen.level(8)
    screen.move(0, 20)
    screen.text("DIST")

    screen.level(15)
    screen.rect(45, 14, math.floor(d * 83), 6)
    screen.fill()

    screen.level(8)
    screen.move(134, 20)
    screen.text(string.format("%.2f", d))

    -- Lines 2-3 show "DISTANCE" repeated for visual emphasis
    screen.level(3)
    screen.move(0, 30)
    screen.text("ALL ENCODERS → DISTANCE")

    screen.move(0, 40)
    screen.text("")
  else
    -- Normal mode: E1, E2, E3 display
    local idx1 = sa and page.shift[1] or page.main[1]
    local idx2 = sa and page.shift[2] or page.main[2]
    local idx3 = sa and page.shift[3] or page.main[3]

    if idx1 then
      draw_param_bar(20, idx1, params:get(idx1),
        param_min(idx1), param_max(idx1))
    end

    if idx2 then
      draw_param_bar(30, idx2, params:get(idx2),
        param_min(idx2), param_max(idx2))
    end

    if idx3 then
      draw_param_bar(40, idx3, params:get(idx3),
        param_min(idx3), param_max(idx3))
    end
  end

  -- -------------------------------------------------
  -- LINE 5: Preset info
  -- -------------------------------------------------
  local fid_name = fidelity_names[cf] or "MAN"
  local int_name = interference_names[ci] or "MAN"

  screen.level(4)
  screen.move(0, 50)
  screen.text("FID:" .. cf .. " " ..
    fid_name .. "  INT:" .. ci .. " " .. int_name)

  -- -------------------------------------------------
  -- LINE 6: Distance bar (ALWAYS)
  -- -------------------------------------------------
  local dist_val = params:get("distance")
  local bar_pixels = math.floor(dist_val * 128)

  if bar_pixels > 0 then
    screen.level(15)
    screen.rect(0, 58, bar_pixels, 5)
    screen.fill()
  end

  -- Static thin line for empty bar area
  screen.level(1)
  screen.rect(bar_pixels, 58, 128 - bar_pixels, 5)
  screen.fill()

  screen.update()
end

-- =========================================================
-- EXPORT
-- =========================================================

return {
  ui_redraw = ui_redraw,
  draw_param_bar = draw_param_bar
}
