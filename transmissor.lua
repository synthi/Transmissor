-- Transmissor v1.0
-- Shortwave SSB transmission simulator
-- Audio input → SSB modulation → RF effects → SSB demodulation → output
-- Based on concepts from EdgeField but completely rewritten for norns

engine.name = 'Transmissor'

-- =========================================================
-- SHARED STATE (globals accessible by all lib modules)
-- =========================================================

current_page = 1
current_fidelity = 1
current_interference = 1
distance_mode = false
shift_active = false

-- =========================================================
-- MODULE LOADER
-- =========================================================

local function load_module(name)
  local path = _path.code .. "Transmissor/lib/" .. name .. ".lua"
  local ok, result = pcall(dofile, path)
  if not ok then
    print("[Transmissor] Error loading " .. name .. ": " .. tostring(result))
    return {}
  end
  if type(result) == "table" then
    for k, v in pairs(result) do
      _G[k] = v
    end
  end
  return result or {}
end

-- =========================================================
-- LFO STATE (inherited concept from EdgeField)
-- =========================================================

local carrier_phase = 0.0
local static_phase = 0.0
local carrier_lfo_rate = 0.005
local static_lfo_rate = 0.005
local carrier_depth_col = 8
local static_depth_col = 4
local LFO_SPEED_MIN = 0.005
local LFO_SPEED_MAX = 0.084
local CARRIER_FREQ_DEPTH = 400.0
local STATIC_DEPTH = 0.50

-- =========================================================
-- UPDATE LFOS — called from metro (25fps)
-- Modulates carrier freq and noise floor via LFO
-- =========================================================

local function update_lfos()
  carrier_phase = (carrier_phase + carrier_lfo_rate) % 1.0
  static_phase  = (static_phase  + static_lfo_rate)  % 1.0

  local carrier_depth = (carrier_depth_col / 15.0) * CARRIER_FREQ_DEPTH
  local carrier_sine  = math.sin(carrier_phase * math.pi * 2)
  local carrier_val   = params:get("tx_freq") + (carrier_sine * carrier_depth)
  engine.set_tx_freq(math.max(100, carrier_val))

  local static_depth = (static_depth_col / 15.0) * STATIC_DEPTH
  local static_sine  = math.sin(static_phase * math.pi * 2) +
                       math.sin(static_phase * math.pi * 5.7) * 0.3
  static_sine = static_sine / 1.3
  local static_base = params:get("floor")
  local static_val = static_base + (static_sine * static_depth * static_base)
  engine.set_floor(math.max(0, static_val))
end

-- =========================================================
-- ADJUST PARAM — helper for encoders
-- =========================================================

local function adjust_param(name, delta)
  if not name then return end

  local minv = param_min(name)
  local maxv = param_max(name)
  local cur = params:get(name)
  local range = maxv - minv

  if range < 0.0001 then return end

  local step = range / 128.0
  local new_val = cur + (delta * step)
  new_val = util.clamp(new_val, minv, maxv)

  if step > 0.001 then
    new_val = math.floor(new_val / step + 0.5) * step
  end

  params:set(name, new_val)
end

-- =========================================================
-- ENCODERS
-- E1 = param 1 (or shift param 4) / distance mode
-- E2 = param 2 (or shift param 5) / distance mode
-- E3 = param 3 (or shift param 6) / distance mode
-- =========================================================

function enc(n, d)
  if d == 0 then return end

  if distance_mode then
    local v = params:get("distance") + (d * 0.02)
    params:set("distance", util.clamp(v, 0.0, 1.0))
    return
  end

  local page = pages[current_page]
  if not page then return end

  local param_name
  if shift_active then
    param_name = page.shift[n]
  else
    param_name = page.main[n]
  end

  if param_name then
    adjust_param(param_name, d)
  end
end

-- =========================================================
-- KEY HANDLER (norns keys)
-- =========================================================

function key(n, z)
  if z == 0 then return end

  if n == 2 then
    engine.kill_trail(3.0)
  elseif n == 3 then
    distance_mode = not distance_mode
  end
end

-- =========================================================
-- INIT
-- =========================================================

function init()
  print("[Transmissor] Loading modules...")

  load_module("parameters")
  load_module("grid")
  load_module("ui")

  -- Setup all parameters
  if setup_parameters then setup_parameters() end

  -- Wire params to engine commands
  if setup_param_actions then setup_param_actions() end

  -- Initialize grid
  if init_grid then init_grid() end

  -- Apply default presets
  if apply_fidelity_preset then apply_fidelity_preset(1) end
  if apply_interference_preset then apply_interference_preset(1) end

  -- LFO update at 25fps
  metro.init(function()
    update_lfos()
    if grid_redraw then grid_redraw() end
  end, 1/25):start()

  -- Screen redraw at 15fps
  metro.init(function()
    if redraw then redraw() end
  end, 1/15):start()

  params:bang()
  print("[Transmissor] Ready")
end

-- =========================================================
-- CLEANUP
-- =========================================================

function cleanup()
  if grid_cleanup then grid_cleanup() end
  engine.trail_clear(0.0)
  print("[Transmissor] Cleaned up")
end