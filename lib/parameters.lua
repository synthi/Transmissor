-- =========================================================
-- PARAMETERS — Transmissor v1.3.0
-- Defines all params, pages, presets (16+16)
-- =========================================================

-- =========================================================
-- FIDELITY NAMES
-- =========================================================

local fidelity_names = {
  [1]="PRISTINE", [2]="CLEAN", [3]="GOOD", [4]="FAIR",
  [5]="AVERAGE", [6]="POOR", [7]="BAD", [8]="DEGRADED",
  [9]="FRINGE", [10]="VOID", [11]="XTINA", [12]="XBAJA",
  [13]="XFRINGE", [14]="XVOID", [15]="EDGE", [16]="VOIDMAX"
}

-- =========================================================
-- INTERFERENCE NAMES
-- =========================================================

local interference_names = {
  [1]="DEAD AIR", [2]="BACKGROUND", [3]="QUIET", [4]="TYPICAL",
  [5]="ACTIVE", [6]="NOISY", [7]="STORM", [8]="CHAOTIC",
  [9]="APOCALYPSE", [10]="VOID", [11]="XSTORM", [12]="XCHAOS",
  [13]="XAPOC", [14]="XVOID", [15]="EDGE", [16]="VOIDMAX"
}

-- =========================================================
-- PAGES (8 pages, 3+3 params via shift)
-- Pages 4-5-6 are RF FX (Space, Texture, Destroy)
-- =========================================================

local pages = {
  [1] = { name = "TX",
    main = { "tx_freq", "osc_jitter", "pilot_leak" },
    shift = { "saturation", "harmonic_drive", "key_click" }
  },
  [2] = { name = "AIR",
    main = { "multipath", "fade_rate", "fade_depth" },
    shift = { "doppler", "smear", "link_quality" }
  },
  [3] = { name = "NOISE",
    main = { "atmos", "space_hum", "whistle" },
    shift = { "hum", "e_skip", "borealis" }
  },
  [4] = { name = "SPACE",
    main = { "rev_wet", "rev_decay", "rev_damp" },
    shift = { "ech_wet", "ech_time", "ech_fb" }
  },
  [5] = { name = "TEXTURE",
    main = { "cho_wet", "cho_rate", "cho_depth" },
    shift = { "com_wet", "com_freq", "com_fb" }
  },
  [6] = { name = "DESTROY",
    main = { "dst_wet", "dst_drive", "dst_tone" },
    shift = { "fbn_wet", "fbn_spread", "fbn_rate" }
  },
  [7] = { name = "RX",
    main = { "detune", "rx_drift", "rx_bw" },
    shift = { "agc_rate", "agc_breath", "adc_depth" }
  },
  [8] = { name = "MIX",
    main = { "input_trim", "blend", "floor" },
    shift = { "hum_level", "distance", nil }
  },
  [9] = { name = "EQ",
    main = { "locut", "hicut", "rx_hpf" },
    shift = { nil, nil, nil }
  }
}

-- =========================================================
-- FULL PARAMETER DEFINITIONS
-- =========================================================

-- Helper to build controlspec quickly
local function cs(minv, maxv, warp, step, default)
  return controlspec.new(minv, maxv, warp or 'lin', step or 0, default or 0)
end

function setup_parameters()
  params:add_separator("STATION")

  params:add_control("tx_freq", "TX Freq",
    cs(1000, 9000, 'exp', 0, 4800))
  params:add_control("osc_jitter", "Phase Noise",
    cs(0, 1, 'lin', 0, 0.2))
  params:add_control("pilot_leak", "Carrier Leak",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("saturation", "Overmod",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("harmonic_drive", "Harmonics",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("key_click", "PTT Click",
    cs(0, 1, 'lin', 0, 0.5))

  params:add_separator("PROPAGATION")

  params:add_control("multipath", "Multipath",
    cs(0, 1, 'lin', 0, 0.3))
  params:add_control("doppler", "Doppler",
    cs(0, 20, 'lin', 0, 3))
  params:add_control("fade_rate", "Fade Rate",
    cs(0, 1, 'lin', 0, 0.3))
  params:add_control("fade_depth", "Fade Depth",
    cs(0, 1, 'lin', 0, 0.5))
  params:add_control("smear", "Dispersion",
    cs(0, 1, 'lin', 0, 0.2))
  params:add_control("link_quality", "Link SNR",
    cs(0, 1, 'lin', 0, 1.0))

  params:add_separator("INTERFERENCE")

  params:add_control("atmos", "Atmospherics",
    cs(0, 1, 'lin', 0, 0.2))
  params:add_control("space_hum", "Galactic",
    cs(0, 1, 'lin', 0, 0.05))
  params:add_control("whistle", "Heterodyne",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("hum", "Power Hum",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("e_skip", "Sporadic E",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("borealis", "Auroral",
    cs(0, 1, 'lin', 0, 0))

  params:add_separator("RECEIVER")

  params:add_control("detune", "Dial Detune",
    cs(-50, 50, 'lin', 0, 0))
  params:add_control("rx_drift", "Osc Drift",
    cs(0, 1, 'lin', 0, 0.1))
  params:add_control("agc_rate", "AGC Speed",
    cs(0, 1, 'lin', 0, 0.4))
  params:add_control("agc_breath", "AGC Pump",
    cs(0, 1, 'lin', 0, 0.1))
  params:add_control("rx_bw", "RX Bandwidth",
    cs(400, 6000, 'exp', 0, 2400))
  params:add_control("adc_depth", "ADC Bits",
    cs(1, 16, 'lin', 0, 16))

  params:add_separator("MIX")

  params:add_control("input_trim", "Input Gain",
    cs(0, 2, 'lin', 0, 1.0))
  params:add_control("blend", "Dry/Wet",
    cs(0, 1, 'lin', 0, 1))
  params:add_control("floor", "Noise Floor",
    cs(0, 1, 'lin', 0, 0.02))
  params:add_control("hum_level", "Carrier Vol",
    cs(0, 0.2, 'lin', 0, 0.05))
  params:add_control("distance", "Distance",
    cs(0, 1, 'lin', 0, 0.0))

  params:add_separator("EQ")

  params:add_control("locut", "TX LoCut",
    cs(20, 500, 'exp', 0, 80))
  params:add_control("hicut", "TX HiCut",
    cs(500, 10000, 'exp', 0, 4000))
  params:add_control("rx_hpf", "RX LoCut",
    cs(20, 300, 'exp', 0, 60))

  params:add_separator("RF FX")

  params:add_control("rev_wet", "Reverb Wet",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("rev_decay", "Reverb Decay",
    cs(0, 1, 'lin', 0, 0.3))
  params:add_control("rev_damp", "Reverb Damp",
    cs(0, 1, 'lin', 0, 0.5))

  params:add_control("ech_wet", "Echo Wet",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("ech_time", "Echo Time",
    cs(0.01, 2.0, 'lin', 0, 0.3))
  params:add_control("ech_fb", "Echo FB",
    cs(0, 0.95, 'lin', 0, 0.3))

  params:add_control("cho_wet", "Chorus Wet",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("cho_rate", "Chorus Rate",
    cs(0.1, 5.0, 'lin', 0, 0.5))
  params:add_control("cho_depth", "Chorus Depth",
    cs(0.001, 0.020, 'lin', 0, 0.005))

  params:add_control("com_wet", "Comb Wet",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("com_freq", "Comb Freq",
    cs(20, 500, 'exp', 0, 100))
  params:add_control("com_fb", "Comb FB",
    cs(0, 0.9, 'lin', 0, 0.3))

  params:add_control("dst_wet", "Dist Wet",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("dst_drive", "Dist Drive",
    cs(1, 50, 'exp', 0, 3))
  params:add_control("dst_tone", "Dist Tone",
    cs(500, 8000, 'exp', 0, 4000))

  params:add_control("fbn_wet", "FBank Wet",
    cs(0, 1, 'lin', 0, 0))
  params:add_control("fbn_spread", "FBank Spread",
    cs(0, 1, 'lin', 0, 0.5))
  params:add_control("fbn_rate", "FBank Rate",
    cs(0.1, 3.0, 'lin', 0, 0.3))
end

-- =========================================================
-- PARAM HELPERS
-- =========================================================

function param_min(name)
  local cspec = params:lookup_param(name)
  if cspec and cspec.controlspec then
    return cspec.controlspec.minval
  end
  return 0
end

function param_max(name)
  local cspec = params:lookup_param(name)
  if cspec and cspec.controlspec then
    return cspec.controlspec.maxval
  end
  return 1
end

-- =========================================================
-- WIRE PARAMS TO ENGINE
-- =========================================================

function setup_param_actions()
  -- TX
  params:set_action("tx_freq", function(x) engine.set_tx_freq(x) end)
  params:set_action("osc_jitter", function(x) engine.set_osc_jitter(x) end)
  params:set_action("pilot_leak", function(x) engine.set_pilot_leak(x) end)
  params:set_action("saturation", function(x) engine.set_saturation(x) end)
  params:set_action("harmonic_drive", function(x) engine.set_harmonic_drive(x) end)
  params:set_action("key_click", function(x) engine.set_key_click(x) end)

  -- AIR
  params:set_action("multipath", function(x) engine.set_multipath(x) end)
  params:set_action("doppler", function(x) engine.set_doppler(x) end)
  params:set_action("fade_rate", function(x) engine.set_fade_rate(x) end)
  params:set_action("fade_depth", function(x) engine.set_fade_depth(x) end)
  params:set_action("smear", function(x) engine.set_smear(x) end)
  params:set_action("link_quality", function(x) engine.set_link_quality(x) end)

  -- NOISE
  params:set_action("atmos", function(x) engine.set_atmos(x) end)
  params:set_action("space_hum", function(x) engine.set_space_hum(x) end)
  params:set_action("whistle", function(x) engine.set_whistle(x) end)
  params:set_action("hum", function(x) engine.set_hum(x) end)
  params:set_action("e_skip", function(x) engine.set_e_skip(x) end)
  params:set_action("borealis", function(x) engine.set_borealis(x) end)

  -- RX
  params:set_action("detune", function(x) engine.set_detune(x) end)
  params:set_action("rx_drift", function(x) engine.set_rx_drift(x) end)
  params:set_action("agc_rate", function(x) engine.set_agc_rate(x) end)
  params:set_action("agc_breath", function(x) engine.set_agc_breath(x) end)
  params:set_action("rx_bw", function(x) engine.set_rx_bw(x) end)
  params:set_action("adc_depth", function(x) engine.set_adc_depth(x) end)

  -- MIX
  params:set_action("input_trim", function(x) engine.set_input_trim(x) end)
  params:set_action("blend", function(x) engine.set_blend(x) end)
  params:set_action("floor", function(x) engine.set_floor(x) end)
  params:set_action("hum_level", function(x) engine.set_hum_level(x) end)
  params:set_action("distance", function(x) engine.set_distance(x) end)

  -- EQ
  params:set_action("locut", function(x) engine.set_locut(x) end)
  params:set_action("hicut", function(x) engine.set_hicut(x) end)
  params:set_action("rx_hpf", function(x) engine.set_rx_hpf(x) end)

  -- RF FX — SPACE
  params:set_action("rev_wet", function(x) engine.set_rev_wet(x) end)
  params:set_action("rev_decay", function(x) engine.set_rev_decay(x) end)
  params:set_action("rev_damp", function(x) engine.set_rev_damp(x) end)
  params:set_action("ech_wet", function(x) engine.set_ech_wet(x) end)
  params:set_action("ech_time", function(x) engine.set_ech_time(x) end)
  params:set_action("ech_fb", function(x) engine.set_ech_fb(x) end)

  -- RF FX — TEXTURE
  params:set_action("cho_wet", function(x) engine.set_cho_wet(x) end)
  params:set_action("cho_rate", function(x) engine.set_cho_rate(x) end)
  params:set_action("cho_depth", function(x) engine.set_cho_depth(x) end)
  params:set_action("com_wet", function(x) engine.set_com_wet(x) end)
  params:set_action("com_freq", function(x) engine.set_com_freq(x) end)
  params:set_action("com_fb", function(x) engine.set_com_fb(x) end)

  -- RF FX — DESTROY
  params:set_action("dst_wet", function(x) engine.set_dst_wet(x) end)
  params:set_action("dst_drive", function(x) engine.set_dst_drive(x) end)
  params:set_action("dst_tone", function(x) engine.set_dst_tone(x) end)
  params:set_action("fbn_wet", function(x) engine.set_fbn_wet(x) end)
  params:set_action("fbn_spread", function(x) engine.set_fbn_spread(x) end)
  params:set_action("fbn_rate", function(x) engine.set_fbn_rate(x) end)
end

-- =========================================================
-- APPLY PRESET
-- =========================================================

function apply_fidelity_preset(index)
  local preset = fidelity_presets[index]
  if not preset then return end

  for _, kv in ipairs(preset) do
    params:set(kv[1], kv[2])
  end
  print("[Transmissor] Fidelity preset " .. index .. ": " ..
    (fidelity_names[index] or "MANUAL"))
end

function apply_interference_preset(index)
  local preset = interference_presets[index]
  if not preset then return end

  for _, kv in ipairs(preset) do
    params:set(kv[1], kv[2])
  end
  print("[Transmissor] Interference preset " .. index .. ": " ..
    (interference_names[index] or "MANUAL"))
end

-- =========================================================
-- FIDELITY PRESETS (16)
-- Affects: STATION + PROPAGATION + RECEIVER
-- =========================================================

local fidelity_presets = {
  [1] = { name = "PRISTINE",
    { "tx_freq", 8800 }, { "osc_jitter", 0.0 }, { "pilot_leak", 0 },
    { "saturation", 0 }, { "harmonic_drive", 0 }, { "key_click", 0.1 },
    { "multipath", 0.0 }, { "doppler", 0.0 }, { "fade_rate", 0.0 },
    { "fade_depth", 0.0 }, { "smear", 0.0 }, { "link_quality", 1.0 },
    { "detune", 0 }, { "rx_drift", 0 }, { "agc_rate", 0.3 },
    { "agc_breath", 0.05 }, { "rx_bw", 4000 }, { "adc_depth", 16 },
    { "floor", 0.02 }, { "locut", 80 }, { "hicut", 4000 }, { "rx_hpf", 60 }
  },
  [2] = { name = "CLEAN",
    { "tx_freq", 7800 }, { "osc_jitter", 0.02 }, { "pilot_leak", 0.01 },
    { "saturation", 0.01 }, { "harmonic_drive", 0.01 }, { "key_click", 0.15 },
    { "multipath", 0.02 }, { "doppler", 0.1 }, { "fade_rate", 0.05 },
    { "fade_depth", 0.05 }, { "smear", 0.02 }, { "link_quality", 0.98 },
    { "detune", 0 }, { "rx_drift", 0.01 }, { "agc_rate", 0.35 },
    { "agc_breath", 0.06 }, { "rx_bw", 3500 }, { "adc_depth", 16 },
    { "floor", 0.02 }, { "locut", 130 }, { "hicut", 3800 }, { "rx_hpf", 70 }
  },
  [3] = { name = "GOOD",
    { "tx_freq", 6800 }, { "osc_jitter", 0.05 }, { "pilot_leak", 0.02 },
    { "saturation", 0.02 }, { "harmonic_drive", 0.02 }, { "key_click", 0.2 },
    { "multipath", 0.05 }, { "doppler", 0.3 }, { "fade_rate", 0.1 },
    { "fade_depth", 0.1 }, { "smear", 0.05 }, { "link_quality", 0.95 },
    { "detune", 0 }, { "rx_drift", 0.02 }, { "agc_rate", 0.4 },
    { "agc_breath", 0.08 }, { "rx_bw", 3000 }, { "adc_depth", 16 },
    { "floor", 0.02 }, { "locut", 180 }, { "hicut", 3500 }, { "rx_hpf", 85 }
  },
  [4] = { name = "FAIR",
    { "tx_freq", 6000 }, { "osc_jitter", 0.08 }, { "pilot_leak", 0.03 },
    { "saturation", 0.03 }, { "harmonic_drive", 0.04 }, { "key_click", 0.25 },
    { "multipath", 0.1 }, { "doppler", 0.6 }, { "fade_rate", 0.15 },
    { "fade_depth", 0.2 }, { "smear", 0.08 }, { "link_quality", 0.90 },
    { "detune", 0 }, { "rx_drift", 0.04 }, { "agc_rate", 0.45 },
    { "agc_breath", 0.1 }, { "rx_bw", 2600 }, { "adc_depth", 15 },
    { "floor", 0.03 }, { "locut", 230 }, { "hicut", 3200 }, { "rx_hpf", 100 }
  },
  [5] = { name = "AVERAGE",
    { "tx_freq", 5400 }, { "osc_jitter", 0.12 }, { "pilot_leak", 0.05 },
    { "saturation", 0.05 }, { "harmonic_drive", 0.06 }, { "key_click", 0.3 },
    { "multipath", 0.15 }, { "doppler", 1.0 }, { "fade_rate", 0.2 },
    { "fade_depth", 0.3 }, { "smear", 0.12 }, { "link_quality", 0.85 },
    { "detune", 0.5 }, { "rx_drift", 0.06 }, { "agc_rate", 0.5 },
    { "agc_breath", 0.12 }, { "rx_bw", 2400 }, { "adc_depth", 14 },
    { "floor", 0.05 }, { "locut", 280 }, { "hicut", 3000 }, { "rx_hpf", 120 }
  },
  [6] = { name = "POOR",
    { "tx_freq", 4800 }, { "osc_jitter", 0.18 }, { "pilot_leak", 0.07 },
    { "saturation", 0.07 }, { "harmonic_drive", 0.08 }, { "key_click", 0.35 },
    { "multipath", 0.25 }, { "doppler", 1.8 }, { "fade_rate", 0.3 },
    { "fade_depth", 0.45 }, { "smear", 0.18 }, { "link_quality", 0.75 },
    { "detune", 1.0 }, { "rx_drift", 0.1 }, { "agc_rate", 0.55 },
    { "agc_breath", 0.15 }, { "rx_bw", 2200 }, { "adc_depth", 12 },
    { "floor", 0.08 }, { "locut", 330 }, { "hicut", 2500 }, { "rx_hpf", 145 }
  },
  [7] = { name = "BAD",
    { "tx_freq", 4500 }, { "osc_jitter", 0.25 }, { "pilot_leak", 0.1 },
    { "saturation", 0.1 }, { "harmonic_drive", 0.12 }, { "key_click", 0.4 },
    { "multipath", 0.35 }, { "doppler", 3.0 }, { "fade_rate", 0.4 },
    { "fade_depth", 0.6 }, { "smear", 0.25 }, { "link_quality", 0.65 },
    { "detune", 2.0 }, { "rx_drift", 0.15 }, { "agc_rate", 0.6 },
    { "agc_breath", 0.18 }, { "rx_bw", 1800 }, { "adc_depth", 10 },
    { "floor", 0.12 }, { "locut", 380 }, { "hicut", 2200 }, { "rx_hpf", 170 }
  },
  [8] = { name = "DEGRADED",
    { "tx_freq", 4300 }, { "osc_jitter", 0.35 }, { "pilot_leak", 0.15 },
    { "saturation", 0.15 }, { "harmonic_drive", 0.18 }, { "key_click", 0.5 },
    { "multipath", 0.5 }, { "doppler", 5.0 }, { "fade_rate", 0.5 },
    { "fade_depth", 0.75 }, { "smear", 0.35 }, { "link_quality", 0.50 },
    { "detune", 4.0 }, { "rx_drift", 0.25 }, { "agc_rate", 0.65 },
    { "agc_breath", 0.2 }, { "rx_bw", 1500 }, { "adc_depth", 8 },
    { "floor", 0.18 }, { "locut", 430 }, { "hicut", 2000 }, { "rx_hpf", 195 }
  },
  [9] = { name = "FRINGE",
    { "tx_freq", 4100 }, { "osc_jitter", 0.5 }, { "pilot_leak", 0.2 },
    { "saturation", 0.2 }, { "harmonic_drive", 0.25 }, { "key_click", 0.2 },
    { "multipath", 0.75 }, { "doppler", 12.0 }, { "fade_rate", 0.75 },
    { "fade_depth", 0.85 }, { "smear", 0.5 }, { "link_quality", 0.2 },
    { "detune", 18 }, { "rx_drift", 0.5 }, { "agc_rate", 0.7 },
    { "agc_breath", 0.25 }, { "rx_bw", 1300 }, { "adc_depth", 8 },
    { "floor", 0.3 }, { "locut", 480 }, { "hicut", 1800 }, { "rx_hpf", 215 }
  },
  [10] = { name = "VOID",
    { "tx_freq", 3950 }, { "osc_jitter", 0.6 }, { "pilot_leak", 0.3 },
    { "saturation", 0.3 }, { "harmonic_drive", 0.35 }, { "key_click", 0.3 },
    { "multipath", 0.85 }, { "doppler", 16.0 }, { "fade_rate", 0.85 },
    { "fade_depth", 0.95 }, { "smear", 0.6 }, { "link_quality", 0.1 },
    { "detune", 25 }, { "rx_drift", 0.6 }, { "agc_rate", 0.75 },
    { "agc_breath", 0.3 }, { "rx_bw", 1100 }, { "adc_depth", 7 },
    { "floor", 0.35 }, { "locut", 530 }, { "hicut", 1600 }, { "rx_hpf", 230 }
  },
  [11] = { name = "XTINA",
    { "tx_freq", 3800 }, { "osc_jitter", 0.7 }, { "pilot_leak", 0.4 },
    { "saturation", 0.4 }, { "harmonic_drive", 0.4 }, { "key_click", 0.35 },
    { "multipath", 0.9 }, { "doppler", 18.0 }, { "fade_rate", 0.9 },
    { "fade_depth", 0.95 }, { "smear", 0.65 }, { "link_quality", 0.08 },
    { "detune", 30 }, { "rx_drift", 0.7 }, { "agc_rate", 0.8 },
    { "agc_breath", 0.35 }, { "rx_bw", 1200 }, { "adc_depth", 6 },
    { "floor", 0.4 }, { "locut", 580 }, { "hicut", 1400 }, { "rx_hpf", 240 }
  },
  [12] = { name = "XBAJA",
    { "tx_freq", 3650 }, { "osc_jitter", 0.8 }, { "pilot_leak", 0.5 },
    { "saturation", 0.5 }, { "harmonic_drive", 0.5 }, { "key_click", 0.4 },
    { "multipath", 0.92 }, { "doppler", 19.0 }, { "fade_rate", 0.92 },
    { "fade_depth", 0.98 }, { "smear", 0.7 }, { "link_quality", 0.05 },
    { "detune", 35 }, { "rx_drift", 0.8 }, { "agc_rate", 0.85 },
    { "agc_breath", 0.4 }, { "rx_bw", 1400 }, { "adc_depth", 6 },
    { "floor", 0.45 }, { "locut", 630 }, { "hicut", 1200 }, { "rx_hpf", 250 }
  },
  [13] = { name = "XFRINGE",
    { "tx_freq", 3500 }, { "osc_jitter", 0.85 }, { "pilot_leak", 0.6 },
    { "saturation", 0.6 }, { "harmonic_drive", 0.6 }, { "key_click", 0.45 },
    { "multipath", 0.95 }, { "doppler", 19.5 }, { "fade_rate", 0.95 },
    { "fade_depth", 0.99 }, { "smear", 0.75 }, { "link_quality", 0.03 },
    { "detune", 40 }, { "rx_drift", 0.85 }, { "agc_rate", 0.88 },
    { "agc_breath", 0.45 }, { "rx_bw", 1600 }, { "adc_depth", 6 },
    { "floor", 0.5 }, { "locut", 680 }, { "hicut", 1000 }, { "rx_hpf", 260 }
  },
  [14] = { name = "XVOID",
    { "tx_freq", 3400 }, { "osc_jitter", 0.9 }, { "pilot_leak", 0.7 },
    { "saturation", 0.7 }, { "harmonic_drive", 0.7 }, { "key_click", 0.5 },
    { "multipath", 0.97 }, { "doppler", 20.0 }, { "fade_rate", 0.97 },
    { "fade_depth", 0.99 }, { "smear", 0.8 }, { "link_quality", 0.02 },
    { "detune", 45 }, { "rx_drift", 0.9 }, { "agc_rate", 0.9 },
    { "agc_breath", 0.48 }, { "rx_bw", 1800 }, { "adc_depth", 6 },
    { "floor", 0.55 }, { "locut", 730 }, { "hicut", 900 }, { "rx_hpf", 275 }
  },
  [15] = { name = "EDGE",
    { "tx_freq", 3300 }, { "osc_jitter", 0.95 }, { "pilot_leak", 0.8 },
    { "saturation", 0.8 }, { "harmonic_drive", 0.8 }, { "key_click", 0.55 },
    { "multipath", 0.98 }, { "doppler", 20.0 }, { "fade_rate", 0.98 },
    { "fade_depth", 1.0 }, { "smear", 0.85 }, { "link_quality", 0.01 },
    { "detune", 48 }, { "rx_drift", 0.95 }, { "agc_rate", 0.92 },
    { "agc_breath", 0.5 }, { "rx_bw", 2000 }, { "adc_depth", 6 },
    { "floor", 0.6 }, { "locut", 776 }, { "hicut", 750 }, { "rx_hpf", 285 }
  },
  [16] = { name = "VOIDMAX",
    { "tx_freq", 3200 }, { "osc_jitter", 1.0 }, { "pilot_leak", 1.0 },
    { "saturation", 1.0 }, { "harmonic_drive", 1.0 }, { "key_click", 0.6 },
    { "multipath", 1.0 }, { "doppler", 20.0 }, { "fade_rate", 1.0 },
    { "fade_depth", 1.0 }, { "smear", 1.0 }, { "link_quality", 0.0 },
    { "detune", 50 }, { "rx_drift", 1.0 }, { "agc_rate", 1.0 },
    { "agc_breath", 0.6 }, { "rx_bw", 2100 }, { "adc_depth", 6 },
    { "floor", 0.65 }, { "locut", 826 }, { "hicut", 600 }, { "rx_hpf", 295 }
  }
}

-- =========================================================
-- INTERFERENCE PRESETS (16)
-- Affects: NOISE section
-- =========================================================

local interference_presets = {
  [1] = { name = "DEAD AIR",
    { "atmos", 0 }, { "space_hum", 0 }, { "whistle", 0 },
    { "hum", 0 }, { "e_skip", 0 }, { "borealis", 0 }
  },
  [2] = { name = "BACKGROUND",
    { "atmos", 0.01 }, { "space_hum", 0.02 }, { "whistle", 0 },
    { "hum", 0 }, { "e_skip", 0 }, { "borealis", 0 }
  },
  [3] = { name = "QUIET",
    { "atmos", 0.03 }, { "space_hum", 0.05 }, { "whistle", 0.001 },
    { "hum", 0 }, { "e_skip", 0 }, { "borealis", 0 }
  },
  [4] = { name = "TYPICAL",
    { "atmos", 0.08 }, { "space_hum", 0.10 }, { "whistle", 0.002 },
    { "hum", 0.001 }, { "e_skip", 0 }, { "borealis", 0 }
  },
  [5] = { name = "ACTIVE",
    { "atmos", 0.15 }, { "space_hum", 0.15 }, { "whistle", 0.003 },
    { "hum", 0.003 }, { "e_skip", 0.001 }, { "borealis", 0 }
  },
  [6] = { name = "NOISY",
    { "atmos", 0.25 }, { "space_hum", 0.25 }, { "whistle", 0.005 },
    { "hum", 0.02 }, { "e_skip", 0.003 }, { "borealis", 0.001 }
  },
  [7] = { name = "STORM",
    { "atmos", 0.45 }, { "space_hum", 0.35 }, { "whistle", 0.02 },
    { "hum", 0.05 }, { "e_skip", 0.05 }, { "borealis", 0 }
  },
  [8] = { name = "CHAOTIC",
    { "atmos", 0.65 }, { "space_hum", 0.50 }, { "whistle", 0.08 },
    { "hum", 0.10 }, { "e_skip", 0.15 }, { "borealis", 0.05 }
  },
  [9] = { name = "APOCALYPSE",
    { "atmos", 0.85 }, { "space_hum", 0.70 }, { "whistle", 0.15 },
    { "hum", 0.15 }, { "e_skip", 0.25 }, { "borealis", 0.15 }
  },
  [10] = { name = "VOID",
    { "atmos", 1.0 }, { "space_hum", 0.85 }, { "whistle", 0.25 },
    { "hum", 0.25 }, { "e_skip", 0.40 }, { "borealis", 0.30 }
  },
  [11] = { name = "XSTORM",
    { "atmos", 1.0 }, { "space_hum", 0.6 }, { "whistle", 0.3 },
    { "hum", 0.25 }, { "e_skip", 0.3 }, { "borealis", 0.35 }
  },
  [12] = { name = "XCHAOS",
    { "atmos", 1.0 }, { "space_hum", 0.7 }, { "whistle", 0.35 },
    { "hum", 0.3 }, { "e_skip", 0.35 }, { "borealis", 0.45 }
  },
  [13] = { name = "XAPOC",
    { "atmos", 1.0 }, { "space_hum", 0.8 }, { "whistle", 0.4 },
    { "hum", 0.35 }, { "e_skip", 0.4 }, { "borealis", 0.5 }
  },
  [14] = { name = "XVOID",
    { "atmos", 1.0 }, { "space_hum", 0.9 }, { "whistle", 0.45 },
    { "hum", 0.4 }, { "e_skip", 0.45 }, { "borealis", 0.55 }
  },
  [15] = { name = "EDGE",
    { "atmos", 1.0 }, { "space_hum", 0.95 }, { "whistle", 0.5 },
    { "hum", 0.45 }, { "e_skip", 0.5 }, { "borealis", 0.6 }
  },
  [16] = { name = "VOIDMAX",
    { "atmos", 1.0 }, { "space_hum", 1.0 }, { "whistle", 0.6 },
    { "hum", 0.5 }, { "e_skip", 0.6 }, { "borealis", 0.7 }
  }
}

-- =========================================================
-- FORCE CRITICAL GLOBALS
-- (belt-and-suspenders: load_module does _G[k]=v but
--  let's guarantee these are accessible everywhere)
-- =========================================================

_G.pages = pages
_G.fidelity_names = fidelity_names
_G.interference_names = interference_names
_G.fidelity_presets = fidelity_presets
_G.interference_presets = interference_presets

-- =========================================================
-- RETURN ALL DATA
-- =========================================================

return {
  pages = pages,
  fidelity_names = fidelity_names,
  interference_names = interference_names,
  fidelity_presets = fidelity_presets,
  interference_presets = interference_presets,
  setup_parameters = setup_parameters,
  setup_param_actions = setup_param_actions,
  apply_fidelity_preset = apply_fidelity_preset,
  apply_interference_preset = apply_interference_preset,
  param_min = param_min,
  param_max = param_max
}