-- =========================================================
-- GRID — Transmissor v1.4.0
-- Rows 1-3: interactive param bars (tap/hold ramp) + seq recording
-- Rows 4-5: Fidelity/Interference presets + seq recording
-- Row 6: empty
-- Row 7: User Presets (1-10) + Gap (11) + Sequencers (12-15)
-- Row 8: Controls
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

local function is_page_col(x)
  return page_cols[x] ~= nil
end

-- All params for user preset save/restore
local ALL_PARAMS = {
  "tx_freq", "osc_jitter", "pilot_leak", "saturation", "harmonic_drive", "key_click",
  "multipath", "doppler", "fade_rate", "fade_depth", "smear", "link_quality",
  "atmos", "space_hum", "whistle", "hum", "e_skip", "borealis",
  "detune", "rx_drift", "agc_rate", "agc_breath", "rx_bw", "adc_depth",
  "input_trim", "blend", "floor", "hum_level", "distance",
  "locut", "hicut", "rx_hpf",
  "rev_wet", "rev_decay", "rev_damp",
  "ech_wet", "ech_time", "ech_fb",
  "cho_wet", "cho_rate", "cho_depth",
  "com_wet", "com_freq", "com_fb",
  "dst_wet", "dst_drive", "dst_tone",
  "fbn_wet", "fbn_spread", "fbn_rate"
}

-- =========================================================
-- RAMP SYSTEM (for grid hold interaction)
-- =========================================================

local press_time = {}  -- [y] = clock time
local page_press_time = 0

local ramp_state = {
  [1] = { active = false, param = nil, start_val = 0, target_val = 0,
          start_time = 0, duration = 0 },
  [2] = { active = false, param = nil, start_val = 0, target_val = 0,
          start_time = 0, duration = 0 },
  [3] = { active = false, param = nil, start_val = 0, target_val = 0,
          start_time = 0, duration = 0 },
}

local function get_param_for_row(page, row)
  local sa = _G.shift_active or false
  if sa and page.shift then
    return page.shift[row] or page.main[row]
  else
    return page.main[row]
  end
end

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
    start_time = util.time(),
    duration = math.max(0.1, hold_time * 2.6)
  }
end

local function process_ramps()
  local now = util.time()
  for row = 1, 3 do
    local rs = ramp_state[row]
    if rs.active then
      local elapsed = now - rs.start_time
      local progress = math.min(1.0, elapsed / rs.duration)
      -- cubic ease-out: starts fast, decelerates smoothly
      local eased = 1 - ((1 - progress) ^ 3)
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
-- USER PRESETS — save / recall / clear
-- =========================================================

local user_preset_press_time = {}

local function save_user_preset(slot)
  local data = {}
  for _, p in ipairs(ALL_PARAMS) do
    data[p] = params:get(p)
  end
  data.current_fidelity = _G.current_fidelity
  data.current_interference = _G.current_interference
  data.current_page = _G.current_page
  _G.user_presets[slot] = { data = data, status = 1 }
  _G.user_preset_selected = slot
end

local function recall_user_preset(slot)
  local preset = _G.user_presets[slot]
  if not preset or not preset.data then return end
  local d = preset.data
  for _, p in ipairs(ALL_PARAMS) do
    if d[p] ~= nil then
      params:set(p, d[p])
    end
  end
  if d.current_fidelity then _G.current_fidelity = d.current_fidelity end
  if d.current_interference then _G.current_interference = d.current_interference end
  if d.current_page then _G.current_page = d.current_page end
  _G.user_preset_selected = slot
end

local function clear_user_preset(slot)
  _G.user_presets[slot] = { data = nil, status = 0 }
  if _G.user_preset_selected == slot then
    _G.user_preset_selected = 0
  end
end

-- =========================================================
-- SEQUENCER — record / playback / state machine
-- =========================================================
-- States: 0=Empty, 1=Recording, 2=Playing, 3=Stopped, 4=Overdub

-- Flag to prevent re-recording during playback
local seq_replaying = false

-- Track press time for long-hold detection on seq buttons
local seq_press_time = {}

local function is_recordable(x, y)
  -- Don't record: row 8 (controls)
  if y == 8 then return false end
  -- Don't record: row 7 cols 12-15 (sequencer buttons themselves)
  if y == 7 and x >= 12 and x <= 15 then return false end
  -- Don't record: row 7 col 11 (gap)
  if y == 7 and x == 11 then return false end
  -- Don't record: row 6 (empty)
  if y == 6 then return false end
  -- YES: rows 1-3 (params, page-aware), row 4 (fidelity), row 5 (interference),
  --       row 7 cols 1-10 (user presets)
  return true
end

local function record_event(x, y, z)
  if seq_replaying then return end
  local now = util.time()
  for i = 1, 4 do
    local seq = _G.seq_slots[i]
    if seq and (seq.state == 1 or seq.state == 4) then
      local dt
      if seq.state == 1 then
        dt = now - seq.start_time
      else
        -- Overdub: wrap into loop duration
        dt = (now - seq.start_time) % (seq.duration > 0 and seq.duration or 1)
      end
      local page = 0
      if y >= 1 and y <= 3 then
        page = _G.current_page
      end
      table.insert(seq.data, { dt = dt, x = x, y = y, z = z, page = page })
      table.sort(seq.data, function(a, b) return a.dt < b.dt end)
    end
  end
end

local function stop_seq_playback(slot)
  local seq = _G.seq_slots[slot]
  if seq and seq.playback_clock then
    clock.cancel(seq.playback_clock)
    seq.playback_clock = nil
  end
end

local function start_seq_playback(slot)
  local seq = _G.seq_slots[slot]
  if not seq or not seq.data or #seq.data == 0 then return end

  -- Cancel any existing playback
  stop_seq_playback(slot)

  seq.start_time = util.time()
  seq.playback_clock = clock.run(function()
    while seq.state == 2 or seq.state == 4 do
      local cycle_start = util.time()

      for i = 1, #seq.data do
        if seq.state ~= 2 and seq.state ~= 4 then break end

        local ev = seq.data[i]
        local elapsed = util.time() - cycle_start

        -- Wait until event time
        if ev.dt > elapsed then
          clock.sleep(ev.dt - elapsed)
        end

        -- Re-check state after sleep
        if seq.state ~= 2 and seq.state ~= 4 then break end

        -- Execute event
        seq_replaying = true
        if ev.y >= 1 and ev.y <= 3 then
          -- Page-aware: only execute if page matches
          if ev.page == _G.current_page then
            grid_key(ev.x, ev.y, ev.z)
          end
        else
          grid_key(ev.x, ev.y, ev.z)
        end
        seq_replaying = false
      end

      -- Wait for remaining cycle duration
      if seq.state == 2 or seq.state == 4 then
        local remaining = seq.duration - (util.time() - cycle_start)
        if remaining > 0.01 then
          clock.sleep(remaining)
        end
      end
    end
  end)
end

local function clear_seq(slot)
  stop_seq_playback(slot)
  _G.seq_slots[slot] = {
    data = {}, state = 0, press_time = 0,
    start_time = 0, step = 1, duration = 0,
    playback_clock = nil
  }
end

local function update_seq_active()
  local any = false
  for i = 1, 4 do
    local s = _G.seq_slots[i]
    if s and (s.state == 2 or s.state == 4) then any = true end
  end
  _G.seq_active = any
end

-- =========================================================
-- GRID KEY HANDLER
-- =========================================================

function grid_key(x, y, z)
  -- ROW 8: Controls
  if y == 8 then

    -- SHIFT BUTTON (col 16) — momentary
    if x == 16 then
      _G.shift_active = (z == 1)
      return
    end

    -- PAGE BUTTONS — same page = instant shift toggle, different page = change + hold for shift
    if is_page_col(x) then
      if z == 1 then
        local target_page = page_cols[x]
        if target_page == _G.current_page then
          -- Same page: instant shift toggle
          _G.shift_active = not _G.shift_active
          page_press_time = 0
        else
          -- Different page: change page + start timer
          _G.current_page = target_page
          _G.distance_mode = false
          page_press_time = util.time()
        end
      else
        -- Release: toggle shift only if we changed pages + held >150ms
        if page_press_time > 0 then
          local hold = util.time() - page_press_time
          if hold > 0.15 then
            _G.shift_active = not _G.shift_active
          end
          page_press_time = 0
        end
      end
      return
    end

    -- PTT (col 1) — momentary: press=click on, release=click off+squelch
    if x == 1 then
      _G.ptt_active = (z == 1)
      if z == 1 then
        engine.trigger_ptt_on()
      else
        engine.trigger_ptt_off()
      end
      return
    end

    -- DISTANCE (col 8) — toggle
    if x == 8 and z == 1 then
      _G.distance_mode = not _G.distance_mode
      return
    end

    return
  end

  -- ROW 7: USER PRESETS (1-10) + GAP (11) + SEQUENCERS (12-15)
  if y == 7 then
    local now = util.time()

    -- USER PRESETS (cols 1-10)
    if x >= 1 and x <= 10 then
      local slot = x
      local sa = _G.shift_active or false

      -- Record for sequencers
      record_event(x, y, z)

      if sa then
        -- Shift + button = clear preset
        if z == 1 then
          clear_user_preset(slot)
        end
        return
      end

      if z == 1 then
        user_preset_press_time[slot] = now
        local preset = _G.user_presets[slot]
        local status = preset and preset.status or 0

        if status == 0 then
          -- Empty: save current params
          save_user_preset(slot)
        else
          -- Has content: recall
          recall_user_preset(slot)
        end
      else
        -- Release: check for long hold (>1s) to overwrite
        local hold_time = user_preset_press_time[slot]
          and (now - user_preset_press_time[slot]) or 0
        local preset = _G.user_presets[slot]
        local status = preset and preset.status or 0

        if status == 1 and hold_time > 1.0 then
          -- Overwrite with current params
          save_user_preset(slot)
        end
        user_preset_press_time[slot] = nil
      end
      return
    end

    -- GAP (col 11)
    if x == 11 then return end

    -- SEQUENCERS (cols 12-15)
    if x >= 12 and x <= 15 then
      local slot = x - 11  -- 1-4
      local sa = _G.shift_active or false

      if sa then
        -- Shift + seq = clear
        if z == 1 then
          clear_seq(slot)
          update_seq_active()
        end
        return
      end

      if z == 1 then
        seq_press_time[slot] = now
        local seq = _G.seq_slots[slot]
        local ss = seq.state

        if ss == 0 then
          -- Empty → Record
          seq.state = 1
          seq.start_time = now
          seq.data = {}
          seq.step = 1
          seq.duration = 0
        elseif ss == 1 then
          -- Recording → Playing
          seq.duration = now - seq.start_time
          if seq.duration < 0.05 then seq.duration = 0.5 end
          seq.state = 2
          seq.start_time = now
          seq.step = 1
          start_seq_playback(slot)
        elseif ss == 2 then
          -- Playing → Overdub
          seq.state = 4
          seq.start_time = now
        elseif ss == 4 then
          -- Overdub → Playing
          seq.state = 2
        elseif ss == 3 then
          -- Stopped → Playing
          seq.state = 2
          seq.start_time = now
          seq.step = 1
          start_seq_playback(slot)
        end
      else
        -- Release: long hold >0.6s = stop
        local hold_time = seq_press_time[slot]
          and (now - seq_press_time[slot]) or 0
        local seq = _G.seq_slots[slot]

        if hold_time > 0.6 and (seq.state == 2 or seq.state == 4) then
          seq.state = 3  -- Stop
          stop_seq_playback(slot)
        end
        seq_press_time[slot] = nil
      end

      update_seq_active()
      return
    end

    return
  end

  -- ROW 6: empty (ignore)
  if y == 6 then return end

  -- ROWS 4-5: FIDELITY / INTERFERENCE presets + recording
  if y == 4 and z == 1 then
    -- Record for sequencers
    record_event(x, y, z)
    _G.current_fidelity = x
    apply_fidelity_preset(x)
    return
  end

  if y == 5 and z == 1 then
    -- Record for sequencers
    record_event(x, y, z)
    _G.current_interference = x
    apply_interference_preset(x)
    return
  end

  -- ROWS 1-3: Interactive param bars + recording
  if y >= 1 and y <= 3 then
    local page = pages[_G.current_page]
    if not page then return end
    if _G.distance_mode then return end

    local param_name = get_param_for_row(page, y)
    if not param_name then return end

    -- Record for sequencers
    record_event(x, y, z)

    if z == 1 then
      press_time[y] = util.time()
    else
      if press_time[y] then
        local hold_time = util.time() - press_time[y]
        local target_norm = x / 16.0

        if hold_time < 0.15 then
          local minv = param_min(param_name)
          local maxv = param_max(param_name)
          params:set(param_name, minv + target_norm * (maxv - minv))
        else
          start_ramp(y, param_name, target_norm, hold_time)
        end
        press_time[y] = nil
      end
    end
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
-- RENDER ROW 7: User Presets + Gap + Sequencers
-- =========================================================

local function render_row7()
  local now = util.time()

  -- User Presets (cols 1-10)
  for x = 1, 10 do
    local preset = _G.user_presets[x]
    local status = preset and preset.status or 0
    local b = 1  -- Empty
    if status == 1 then
      b = 3  -- Has content
    end
    if _G.user_preset_selected == x and status == 1 then
      b = 12  -- Selected
    end
    grid_set_led(x, 7, b)
  end

  -- Gap (col 11)
  grid_set_led(11, 7, 0)

  -- Sequencers (cols 12-15)
  for i = 1, 4 do
    local x = i + 11
    local seq = _G.seq_slots[i]
    local ss = seq and seq.state or 0
    local b = 1  -- Empty

    if ss == 1 then
      -- Recording: pulse 2-11 (fast)
      b = math.floor(util.linlin(-1, 1, 2, 11, math.sin(now * 8)))
    elseif ss == 2 then
      -- Playing: brightness 12
      b = 12
    elseif ss == 3 then
      -- Stopped: brightness 4
      b = 4
    elseif ss == 4 then
      -- Overdub: pulse 5-10 (slower)
      b = math.floor(util.linlin(-1, 1, 5, 10, math.sin(now * 4)))
    end

    grid_set_led(x, 7, b)
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

    -- ROW 4: FIDELITY presets
    render_preset_row(4, _G.current_fidelity)

    -- ROW 5: INTERFERENCE presets
    render_preset_row(5, _G.current_interference)

    -- ROW 6: empty
    for x = 1, 16 do grid_set_led(x, 6, 0) end

    -- ROW 7: User Presets + Gap + Sequencers
    render_row7()

    -- ROW 8: Controls
    -- Col 1: PTT momentary (2=off, 11=on)
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
  end

  -- Init user presets
  _G.user_presets = {}
  for i = 1, 10 do
    _G.user_presets[i] = { data = nil, status = 0 }
  end
  _G.user_preset_selected = 0

  -- Init sequencers
  _G.seq_slots = {}
  for i = 1, 4 do
    _G.seq_slots[i] = {
      data = {}, state = 0, press_time = 0,
      start_time = 0, step = 1, duration = 0,
      playback_clock = nil
    }
  end
  _G.seq_active = false

  print("[Transmissor] Grid connected (v1.4.0)")
end

function grid_cleanup()
  -- Stop all sequencer playbacks
  for i = 1, 4 do
    if _G.seq_slots and _G.seq_slots[i] then
      stop_seq_playback(i)
    end
  end

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