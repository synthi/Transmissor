-- Transmissor v1.3.3
-- Shortwave SSB transmission simulator
-- Audio input → SSB modulation → RF effects → SSB demodulation → output
--
-- Changelog:
--   v1.3.3  Fix crash: load_module uses include() (norns native path resolve)
--   v1.3.2  Fix crash: pcall guards on params:get
--   v1.3.1  Click sounds reworked (no BPF), key_click gradient, page shift fix

engine.name = 'Transmissor'

-- =========================================================
-- SHARED STATE (globals accessible by all lib modules)
-- =========================================================

current_page = 1
current_fidelity = 1
current_interference = 1
distance_mode = false
shift_active = false
ptt_active = false  -- Key Click crackle: OFF by default

-- =========================================================
-- MODULE LOADER
-- =========================================================

local function load_module(name)
  local ok, result = pcall(include, 'lib/' .. name)
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
-- METRO REFERENCES (prevent GC from collecting them)
-- =========================================================

local lfo_metro = nil    -- 25fps: LFO + grid
local redraw_metro = nil -- 15fps: screen redraw

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

  local ok, tx_freq_val = pcall(params.get, params, "tx_freq")
  if not ok then return end

  local carrier_depth = (carrier_depth_col / 15.0) * CARRIER_FREQ_DEPTH
  local carrier_sine  = math.sin(carrier_phase * math.pi * 2)
  local carrier_val   = tx_freq_val + (carrier_sine * carrier_depth)
  engine.set_carrier_freq(math.max(100, carrier_val))

  local static_depth = (static_depth_col / 15.0) * STATIC_DEPTH
  local static_sine  = math.sin(static_phase * math.pi * 2) +
                       math.sin(static_phase * math.pi * 5.7) * 0.3
  static_sine = static_sine / 1.3
  local _, floor_val = pcall(params.get, params, "floor")
  floor_val = floor_val or 0
  local static_val = floor_val + (static_sine * static_depth * floor_val)
  engine.set_floor(math.max(0, static_val))
end

-- =========================================================
-- ADJUST PARAM — helper for encoders
-- =========================================================

local function adjust_param(name, delta)
  if not name then return end

  local ok = pcall(params.get, params, name)
  if not ok then return end

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
    param_name = page.shift[n] or page.main[n]
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
-- MAIN REDRAW
-- =========================================================

function redraw()
  if _G.ui_redraw then
    _G.ui_redraw()
  end
end

-- =========================================================
-- INIT
-- =========================================================

function init()
  load_module("parameters")
  load_module("grid")
  load_module("ui")

  local Storage = include('lib/storage')

  if setup_parameters then setup_parameters() end
  if setup_param_actions then setup_param_actions() end
  if init_grid then init_grid() end

  if apply_fidelity_preset then apply_fidelity_preset(1) end
  if apply_interference_preset then apply_interference_preset(1) end

  lfo_metro = metro.init(function()
    update_lfos()
    if grid_redraw then grid_redraw() end
  end, 1/25)
  lfo_metro:start()

  redraw_metro = metro.init(function()
    redraw()
  end, 1/15)
  redraw_metro:start()

  params:bang()

  params.action_write = function(filename, name, id)
    if Storage then Storage.save_data(id) end
  end
  params.action_read = function(filename, silent, id)
    if Storage then Storage.load_data(id) end
  end

  print("[Transmissor] Ready v1.3.3")
end

-- =========================================================
-- CLEANUP
-- =========================================================

function cleanup()
  if lfo_metro then lfo_metro:stop() end
  if redraw_metro then redraw_metro:stop() end
  if grid_cleanup then grid_cleanup() end
  pcall(function() engine.trail_clear(0.0) end)
  print("[Transmissor] Cleaned up")
end