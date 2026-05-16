-- =========================================================
-- STORAGE — Transmissor v1.3.0
-- Pset save/load: user presets + sequencer data
-- =========================================================

local Storage = {}

function Storage.save_data(pset_id)
  if not pset_id then return end

  -- Ensure data directory exists
  if not util.file_exists(_path.data .. "Transmissor") then
    util.make_dir(_path.data .. "Transmissor")
  end

  local filename = _path.data .. "Transmissor/" .. pset_id .. ".data"

  -- Serialize user presets (strip playback_clock which is not serializable)
  local presets_clean = {}
  for i = 1, 10 do
    local p = _G.user_presets[i]
    if p then
      presets_clean[i] = { data = p.data, status = p.status or 0 }
    else
      presets_clean[i] = { data = nil, status = 0 }
    end
  end

  -- Serialize sequencers (strip playback_clock, store stopped state)
  local seq_clean = {}
  for i = 1, 4 do
    local s = _G.seq_slots[i]
    if s then
      seq_clean[i] = {
        data = s.data or {},
        duration = s.duration or 0,
        has_content = (s.data and #s.data > 0 and s.duration and s.duration > 0)
      }
    else
      seq_clean[i] = { data = {}, duration = 0, has_content = false }
    end
  end

  local pack = {
    user_presets = presets_clean,
    user_preset_selected = _G.user_preset_selected or 0,
    seq_slots = seq_clean,
    current_fidelity = _G.current_fidelity,
    current_interference = _G.current_interference,
    current_page = _G.current_page
  }

  tab.save(pack, filename)
  print("[Transmissor] Saved PSET " .. pset_id)
end

function Storage.load_data(pset_id)
  if not pset_id then return end
  local filename = _path.data .. "Transmissor/" .. pset_id .. ".data"

  if not util.file_exists(filename) then return end

  local pack = tab.load(filename)
  if not pack then
    print("[Transmissor] No data file for PSET " .. pset_id)
    return
  end

  -- Restore user presets
  if pack.user_presets then
    for i = 1, 10 do
      if pack.user_presets[i] then
        _G.user_presets[i] = {
          data = pack.user_presets[i].data,
          status = pack.user_presets[i].status or 0
        }
      end
    end
  end
  _G.user_preset_selected = pack.user_preset_selected or 0

  -- Restore sequencers (in stopped state, ready to play)
  if pack.seq_slots then
    for i = 1, 4 do
      if pack.seq_slots[i] then
        local s = pack.seq_slots[i]
        if s.has_content and s.data and #s.data > 0 and s.duration > 0 then
          _G.seq_slots[i] = {
            data = s.data,
            state = 3,  -- Stopped (ready to play)
            press_time = 0,
            start_time = 0,
            step = 1,
            duration = s.duration,
            playback_clock = nil
          }
        else
          _G.seq_slots[i] = {
            data = {}, state = 0, press_time = 0,
            start_time = 0, step = 1, duration = 0,
            playback_clock = nil
          }
        end
      end
    end
  end

  -- Restore UI state
  if pack.current_fidelity then
    _G.current_fidelity = pack.current_fidelity
    apply_fidelity_preset(pack.current_fidelity)
  end
  if pack.current_interference then
    _G.current_interference = pack.current_interference
    apply_interference_preset(pack.current_interference)
  end
  if pack.current_page then
    _G.current_page = pack.current_page
  end

  print("[Transmissor] Loaded PSET " .. pset_id)
end

return Storage