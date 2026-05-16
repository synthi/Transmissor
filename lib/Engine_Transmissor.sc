// Engine_Transmissor.sc — Transmissor v1.0.6
// Shortwave SSB transmission simulator engine for norns
// Audio input → SSB modulation → RF effects → SSB demodulation → output
//
// Changelog:
//   v1.0.2  (fix)   FreShift → FreqShift (UGen correcta en SC)
//   v1.0.1  (fix)   CosOsc → SinOsc(pi/2). Comentarios en arg eliminados.
//                     doppler.neg, pow(), K2A, header con changelog
//   v1.0    (2024-05)  Initial release
//     - Carrier synth (SinOsc + ionospheric pitch/amp LFO)
//     - Noise synth (WhiteNoise BPF + impulse pops)
//     - Master FX (bandpass + phaser + echo trail)
//     - Input SSB chain: Hilbert modulator → RF effects → demodulator
//     - 26 RF stages: multipath, doppler, fading, dispersion,
//       atmospheric noise, galactic noise, heterodyne, power hum,
//       sporadic E, auroral, SNR
//     - RF FX (6 effects in RF domain): reverb, echo, chorus,
//       comb filter, distortion, filterbank
//     - Distance meta-control, kill trail, trail clear

Engine_Transmissor : CroneEngine {

    // =====================================================
    // ALL VARIABLES DECLARED AT TOP
    // =====================================================

    var <masterSynth;
    var <carrierSynth;
    var <noiseSynth;
    var <inputSynth;
    var <voiceBus;
    var <ambientBus;
    var distanceVal;

    // =====================================================
    // CONSTRUCTOR
    // =====================================================

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    // =====================================================
    // ALLOC
    // =====================================================

    alloc {

        voiceBus   = Bus.audio(context.server, 2);
        ambientBus = Bus.audio(context.server, 2);
        distanceVal = 0.0;

        // =====================================================
        // CARRIER SYNTH
        // =====================================================

        carrierSynth = {

            arg vol = 0.0, freq = 4800, pitchLFO = 0.08, ampLFO = 0.15;

            var freqSmooth, volSmooth, pitchMod, ampMod, sig;

            freqSmooth = freq.lag(0.08);
            volSmooth  = vol.lag(0.05);

            pitchMod = LFNoise1.kr(pitchLFO).range(
                freqSmooth * 0.998,
                freqSmooth * 1.002
            );

            ampMod = LFNoise1.kr(ampLFO).range(0.3, 1.0);

            sig = SinOsc.ar(pitchMod) * ampMod * volSmooth;
            sig = BPF.ar(sig, freqSmooth, 0.1);  // rq más ancho = menos resonancia

            Out.ar(ambientBus, sig ! 2);

        }.play(context.server, addAction: \addToHead);

        // =====================================================
        // NOISE SYNTH
        // =====================================================

        noiseSynth = {

            arg vol = 0.0, popRate = 1.2, center = 2400;

            var volSmooth, band, pops, sig;

            volSmooth = vol.lag(0.08);

            band = BPF.ar(WhiteNoise.ar(1.0), center, 0.8) * 0.6;

            pops = Dust.ar(popRate) * 0.4;
            pops = HPF.ar(pops, 1200);

            sig = (band + pops) * volSmooth;

            Out.ar(ambientBus, sig ! 2);

        }.play(context.server, addAction: \addToHead);

        // =====================================================
        // MASTER FX
        // =====================================================

        masterSynth = {

            arg bandwidth = 2400, locut = 300, phaserFreq = 0.15,
                ambientVol = 0.4, trailWet = 0.0, trailTime = 0.45,
                trailFeedback = 0.0, volume = 0.7;

            var voiceIn, ambientIn, sig, trail, wetSmooth, fbSmooth;

            voiceIn   = In.ar(voiceBus, 2);
            // Filtrar ambient con mismo bandwidth para evitar pitido carrier
            ambientIn = LPF.ar(In.ar(ambientBus, 2), bandwidth);

            sig = HPF.ar(voiceIn, locut);
            sig = LPF.ar(sig, bandwidth);

            sig = AllpassN.ar(sig, 0.02,
                SinOsc.kr(phaserFreq).range(0.001, 0.009), 0.08);

            wetSmooth = trailWet.lag(0.1);
            fbSmooth  = trailFeedback.lag(0.1);

            trail = CombL.ar(sig, 2.0, trailTime, fbSmooth * 8.0);

            sig = sig + (trail * wetSmooth);
            sig = sig + (ambientIn * ambientVol);

            Out.ar(0, Limiter.ar(sig * volume, 0.95));

        }.play(context.server, addAction: \addToTail);

        // =====================================================
        // INPUT SSB CHAIN
        // =====================================================

        inputSynth = {

            arg
                tx_freq = 4800, osc_jitter = 0.2, pilot_leak = 0.0,
                saturation = 0.0, harmonic_drive = 0.0, key_click = 0.0,
                multipath = 0.3, doppler = 3.0, fade_rate = 0.3,
                fade_depth = 0.5, smear = 0.2, link_quality = 1.0,
                atmos = 0.2, space_hum = 0.05, whistle = 0.0,
                hum = 0.0, e_skip = 0.0, borealis = 0.0,
                detune = 0.0, rx_drift = 0.1, agc_rate = 0.4,
                agc_breath = 0.1, rx_bw = 2400, adc_depth = 16,
                input_trim = 1.0, blend = 1.0, floor = 0.3,
                hum_level = 0.05, distance = 0.0,
                rev_wet = 0.0, rev_decay = 0.3, rev_damp = 0.5,
                ech_wet = 0.0, ech_time = 0.3, ech_fb = 0.3,
                cho_wet = 0.0, cho_rate = 0.5, cho_depth = 0.005,
                com_wet = 0.0, com_freq = 100, com_fb = 0.3,
                dst_wet = 0.0, dst_drive = 3.0, dst_tone = 4000,
                fbn_wet = 0.0, fbn_spread = 0.5, fbn_rate = 0.3;

            var input, hilbert, rf, rfMultipath, rfEffects;
            var demod, sig, compSig, agcKey;
            var tapDelay, tapGain, harmonicSig;
            var rfReverb, rfEcho, rfChorus, rfComb, rfDist, rfFBank;
            var detuneSmooth, detuneAtten;

            // 1. INPUT — SoundIn.ar(0) lee hardware input (bus 2 interno en norns)
            // In.ar(0) seria el OUTPUT bus, no el input!
            input = SoundIn.ar(0) * input_trim;

            // 2. KEY CLICK
            input = input * (1 + (key_click *
                EnvGen.kr(Env.perc(0.001, 0.05),
                Trig1.kr(K2A.ar(input.abs > 0.001), 0.01))));

            // 3. PRE-MOD SATURATION
            input = (input * (1 + saturation * 4.0)).tanh *
                (1.0 / (1.0 + saturation * 4.0).max(0.001));

            // 4. SSB MODULATOR (USB via Hilbert)
            // USB = real*cos(ωc) - imag*sin(ωc)
            // CosOsc no existe en SC; se usa SinOsc con fase pi/2 para obtener coseno
            hilbert = Hilbert.ar(input);

            rf = (hilbert[0] * SinOsc.ar(
                    tx_freq * (1.0 + osc_jitter * 0.001 * LFNoise1.kr(3)),
                    pi/2)) -  // pi/2 phase shift = cosine
                 (hilbert[1] * SinOsc.ar(tx_freq));

            // 5. CARRIER LEAK
            rf = rf + (SinOsc.ar(tx_freq, pilot_leak * 0.001));

            // 6. HARMONIC DISTORTION
            harmonicSig = 0.0;
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 2.0) * 0.5);
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 3.0) * 0.3);
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 4.0) * 0.1);
            rf = rf + (harmonic_drive * harmonicSig);

            // 7. MULTIPATH (5 taps)
            rfMultipath = rf * 0.5;

            tapDelay = LFNoise1.kr(0.5 + (multipath * 0.5))
                .range(0.002, 0.002 + multipath * 0.015);
            tapGain = 0.35 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            tapDelay = LFNoise1.kr(0.7 + (multipath * 0.3))
                .range(0.003, 0.003 + multipath * 0.020);
            tapGain = 0.25 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            tapDelay = LFNoise1.kr(0.3 + (multipath * 0.7))
                .range(0.001, 0.001 + multipath * 0.025);
            tapGain = 0.15 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            tapDelay = LFNoise1.kr(0.9 + (multipath * 0.1))
                .range(0.004, 0.004 + multipath * 0.018);
            tapGain = 0.08 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            rf = rfMultipath;

            // 8. DOPPLER SPREAD (FreqShift simula desplazamiento Doppler ionosférico)
            rfEffects = FreqShift.ar(rf,
                LFNoise1.kr(0.3).range(doppler.neg, doppler));
            rfEffects = rfEffects + (FreqShift.ar(rf,
                LFNoise1.kr(0.7).range(doppler.neg * 0.5, doppler * 0.5)) * 0.3);
            rf = rfEffects;

            // 9. SELECTIVE FADING
            rf = BPF.ar(rf,
                tx_freq + (fade_depth *
                    LFNoise1.kr(fade_rate * 2).range(
                        tx_freq.neg * 0.3, tx_freq * 0.3)),
                LFNoise1.kr(fade_rate).range(
                    0.2, 1.0 - (fade_depth * 0.5))
            );

            // 10. DISPERSION
            rf = AllpassC.ar(rf, 0.01,
                LFNoise1.kr(0.2).range(0.0005, 0.0005 + smear * 0.005), 0.5);
            rf = AllpassC.ar(rf, 0.01,
                LFNoise1.kr(0.3).range(0.0003, 0.0003 + smear * 0.004), 0.4);

            // 11. ATMOSPHERIC NOISE
            rf = rf + (atmos * 0.08 *
                LPF.ar(Dust.ar(LFNoise1.kr(0.1).range(5, 40)), 200));

            // 12. GALACTIC NOISE
            rf = rf + (space_hum * 0.02 * BrownNoise.ar(1.0));

            // 13. HETERODYNE WHISTLE
            rf = rf + (whistle * 0.06 *
                SinOsc.ar(LFNoise1.kr(0.1).range(300, 3000)));

            // 14. POWER LINE HUM
            rf = rf + (hum * 0.04 *
                (SinOsc.ar(60) * 0.5 +
                 SinOsc.ar(120) * 0.3 +
                 SinOsc.ar(180) * 0.15));

            // 15. SPORADIC E
            rf = rf * (1 + (e_skip *
                Dust.kr(LFNoise1.kr(0.05).range(0.05, 0.2)) *
                LFNoise1.kr(0.2).range(0.5, 1.5)));

            // 16. AURORAL
            rf = rf * (1 + (borealis * 0.3 *
                LFNoise1.kr(8).range(-1, 1)));

            // =====================================================
            // RF FX — applied in RF domain, then demodulated
            // =====================================================

            // 17a. RF REVERB (FreeVerb en RF → phantoms detuned)
            // Select.ar: select = when selector > 0, pick second input
            rfReverb = Select.ar(rev_wet > 0.001, [ rf,
                FreeVerb.ar(rf, rev_wet, rev_decay, rev_damp) ]);

            // 17b. RF ECHO
            rfEcho = rfReverb +
                (DelayL.ar(rfReverb, 2.0, ech_time, ech_fb * 6.0) * ech_wet);
            rf = Select.ar(ech_wet > 0.001, [ rfReverb, rfEcho ]);

            // 17c. RF CHORUS
            rfChorus = rf;
            rfChorus = rfChorus + (DelayC.ar(rf, 0.03,
                SinOsc.kr(cho_rate).range(0.005, 0.005 + cho_depth))
                * cho_wet * 0.4);
            rfChorus = rfChorus + (DelayC.ar(rf, 0.03,
                SinOsc.kr(cho_rate * 1.3).range(0.008, 0.008 + cho_depth * 0.7))
                * cho_wet * 0.3);
            rfChorus = rfChorus + (DelayC.ar(rf, 0.03,
                SinOsc.kr(cho_rate * 0.7).range(0.003, 0.003 + cho_depth * 0.5))
                * cho_wet * 0.2);
            rf = Select.ar(cho_wet > 0.001, [ rf, rfChorus ]);

            // 17d. RF COMB FILTER
            rfComb = Select.ar(com_wet > 0.001, [ rf,
                CombL.ar(rf, 0.5, 1.0 / com_freq.max(20), com_fb * 8.0) ]);
            rf = rfComb;

            // 17e. RF DISTORTION
            rfDist = Select.ar(dst_wet > 0.001, [ rf,
                (rf * (1 + dst_drive * 2)).tanh /
                    (1 + dst_drive * 2).tanh ]);
            rf = rfDist;

            // 17f. RF FILTERBANK
            rfFBank = Select.ar(fbn_wet > 0.001, [ rf,
                (BPF.ar(rf,
                    tx_freq * (1.0 - fbn_spread * 0.15) *
                        (1 + fbn_wet * 0.05 *
                            LFNoise1.kr(fbn_rate).range(-1, 1)),
                    0.3) * (1.0 - fbn_spread * 0.3)) +
                (BPF.ar(rf, tx_freq, 0.3) * 1.0) +
                (BPF.ar(rf,
                    tx_freq * (1.0 + fbn_spread * 0.15) *
                        (1 + fbn_wet * 0.05 *
                            LFNoise1.kr(fbn_rate * 0.7).range(-1, 1)),
                    0.3) * (1.0 - fbn_spread * 0.3)) ]);
            rf = rfFBank;

            // 18. SNR
            rf = (rf * link_quality) +
                (WhiteNoise.ar(1.0) * (1.0 - link_quality) * 0.1);

            // 19. SSB DEMODULATOR
            // Demodular con portadora local (solo rx_drift, NO detune)
            // Makeup gain ×3 compensa la pérdida de 6dB del producto-demod
            demod = rf * SinOsc.ar(
                tx_freq +
                (rx_drift * LFNoise1.kr(0.05).range(-5, 5)),
                pi/2
            );
            demod = LPF.ar(demod, 4000);  // Clean IF, no makeup gain here to prevent ADC clipping

            // 19b. DETUNE = pitch shift en audio demodulado (no tremolo)
            // En SSB real, un offset de portadora desplaza el pitch del audio
            detuneSmooth = detune.lag(0.05);
            detuneAtten = 1.0 - (detuneSmooth.abs / 50.0).min(0.9);
            demod = FreqShift.ar(demod, detuneSmooth.neg);
            demod = demod * detuneAtten;

            // 20. ADC QUANTIZATION
            sig = demod.round(2.0 / pow(2, adc_depth));

            // 21. AGC — True Shortwave Downward Compressor + Makeup Gain
            agcKey = sig.abs;
            compSig = Compander.ar(sig, agcKey,
                0.02,                              // Low threshold (reacts to almost everything)
                1.0,                               // Linear below threshold
                0.2,                               // 5:1 Compression above threshold (ducking/pumping)
                0.01,                              // Fast attack (instant duck on static pops)
                agc_rate.max(0.05)                 // Variable release (pumping recovery speed)
            );

            // Massive makeup gain to bring compressed noise floor up to nominal level.
            // agc_breath increases makeup gain, making pumping effect more violent.
            sig = LeakDC.ar(compSig) * (10.0 + (agc_breath * 15.0));

            // Analog saturation to prevent digital clipping from massive makeup gain
            sig = sig.tanh;

            // 22. RX BANDWIDTH
            sig = HPF.ar(sig, 100);
            sig = LPF.ar(sig, rx_bw);

            // 23. BLEND
            sig = (input * (1 - blend)) + (sig * blend);

            // 24. OUTPUT
            Out.ar(voiceBus, sig ! 2);

        }.play(context.server, addAction: \addToHead);

        // =====================================================
        // COMMANDS
        // =====================================================

        this.addCommand("set_tx_freq", "f", { arg msg;
            inputSynth.set(\tx_freq, msg[1]); });
        this.addCommand("set_osc_jitter", "f", { arg msg;
            inputSynth.set(\osc_jitter, msg[1]); });
        this.addCommand("set_pilot_leak", "f", { arg msg;
            inputSynth.set(\pilot_leak, msg[1]); });
        this.addCommand("set_saturation", "f", { arg msg;
            inputSynth.set(\saturation, msg[1]); });
        this.addCommand("set_harmonic_drive", "f", { arg msg;
            inputSynth.set(\harmonic_drive, msg[1]); });
        this.addCommand("set_key_click", "f", { arg msg;
            inputSynth.set(\key_click, msg[1]); });

        this.addCommand("set_multipath", "f", { arg msg;
            inputSynth.set(\multipath, msg[1]); });
        this.addCommand("set_doppler", "f", { arg msg;
            inputSynth.set(\doppler, msg[1]); });
        this.addCommand("set_fade_rate", "f", { arg msg;
            inputSynth.set(\fade_rate, msg[1]); });
        this.addCommand("set_fade_depth", "f", { arg msg;
            inputSynth.set(\fade_depth, msg[1]); });
        this.addCommand("set_smear", "f", { arg msg;
            inputSynth.set(\smear, msg[1]); });
        this.addCommand("set_link_quality", "f", { arg msg;
            inputSynth.set(\link_quality, msg[1]); });

        this.addCommand("set_atmos", "f", { arg msg;
            inputSynth.set(\atmos, msg[1]); });
        this.addCommand("set_space_hum", "f", { arg msg;
            inputSynth.set(\space_hum, msg[1]); });
        this.addCommand("set_whistle", "f", { arg msg;
            inputSynth.set(\whistle, msg[1]); });
        this.addCommand("set_hum", "f", { arg msg;
            inputSynth.set(\hum, msg[1]); });
        this.addCommand("set_e_skip", "f", { arg msg;
            inputSynth.set(\e_skip, msg[1]); });
        this.addCommand("set_borealis", "f", { arg msg;
            inputSynth.set(\borealis, msg[1]); });

        this.addCommand("set_detune", "f", { arg msg;
            inputSynth.set(\detune, msg[1]); });
        this.addCommand("set_rx_drift", "f", { arg msg;
            inputSynth.set(\rx_drift, msg[1]); });
        this.addCommand("set_agc_rate", "f", { arg msg;
            inputSynth.set(\agc_rate, msg[1]); });
        this.addCommand("set_agc_breath", "f", { arg msg;
            inputSynth.set(\agc_breath, msg[1]); });
        this.addCommand("set_rx_bw", "f", { arg msg;
            inputSynth.set(\rx_bw, msg[1]); });
        this.addCommand("set_adc_depth", "f", { arg msg;
            inputSynth.set(\adc_depth, msg[1]); });

        this.addCommand("set_input_trim", "f", { arg msg;
            inputSynth.set(\input_trim, msg[1]); });
        this.addCommand("set_blend", "f", { arg msg;
            inputSynth.set(\blend, msg[1]); });
        this.addCommand("set_floor", "f", { arg msg;
            inputSynth.set(\floor, msg[1]); });
        this.addCommand("set_hum_level", "f", { arg msg;
            inputSynth.set(\hum_level, msg[1]); });

        this.addCommand("set_rev_wet", "f", { arg msg;
            inputSynth.set(\rev_wet, msg[1]); });
        this.addCommand("set_rev_decay", "f", { arg msg;
            inputSynth.set(\rev_decay, msg[1]); });
        this.addCommand("set_rev_damp", "f", { arg msg;
            inputSynth.set(\rev_damp, msg[1]); });
        this.addCommand("set_ech_wet", "f", { arg msg;
            inputSynth.set(\ech_wet, msg[1]); });
        this.addCommand("set_ech_time", "f", { arg msg;
            inputSynth.set(\ech_time, msg[1]); });
        this.addCommand("set_ech_fb", "f", { arg msg;
            inputSynth.set(\ech_fb, msg[1]); });

        this.addCommand("set_cho_wet", "f", { arg msg;
            inputSynth.set(\cho_wet, msg[1]); });
        this.addCommand("set_cho_rate", "f", { arg msg;
            inputSynth.set(\cho_rate, msg[1]); });
        this.addCommand("set_cho_depth", "f", { arg msg;
            inputSynth.set(\cho_depth, msg[1]); });
        this.addCommand("set_com_wet", "f", { arg msg;
            inputSynth.set(\com_wet, msg[1]); });
        this.addCommand("set_com_freq", "f", { arg msg;
            inputSynth.set(\com_freq, msg[1]); });
        this.addCommand("set_com_fb", "f", { arg msg;
            inputSynth.set(\com_fb, msg[1]); });

        this.addCommand("set_dst_wet", "f", { arg msg;
            inputSynth.set(\dst_wet, msg[1]); });
        this.addCommand("set_dst_drive", "f", { arg msg;
            inputSynth.set(\dst_drive, msg[1]); });
        this.addCommand("set_dst_tone", "f", { arg msg;
            inputSynth.set(\dst_tone, msg[1]); });
        this.addCommand("set_fbn_wet", "f", { arg msg;
            inputSynth.set(\fbn_wet, msg[1]); });
        this.addCommand("set_fbn_spread", "f", { arg msg;
            inputSynth.set(\fbn_spread, msg[1]); });
        this.addCommand("set_fbn_rate", "f", { arg msg;
            inputSynth.set(\fbn_rate, msg[1]); });

        this.addCommand("set_carrier_vol", "f", { arg msg;
            carrierSynth.set(\vol, msg[1]); });
        this.addCommand("set_carrier_freq", "f", { arg msg;
            carrierSynth.set(\freq, msg[1]); });
        this.addCommand("set_carrier_drift", "f", { arg msg;
            carrierSynth.set(\pitchLFO, msg[1]);
            carrierSynth.set(\ampLFO, msg[1] * 1.8); });

        this.addCommand("set_noise_vol", "f", { arg msg;
            noiseSynth.set(\vol, msg[1]); });
        this.addCommand("set_noise_pops", "f", { arg msg;
            noiseSynth.set(\popRate, msg[1]); });

        this.addCommand("set_master_bw", "f", { arg msg;
            masterSynth.set(\bandwidth, msg[1]); });
        this.addCommand("set_master_ambient", "f", { arg msg;
            masterSynth.set(\ambientVol, msg[1]); });

        // =====================================================
        // DISTANCE
        // =====================================================

        this.addCommand("set_distance", "f", { arg msg;
            var d = msg[1].clip(0.0, 1.0);
            distanceVal = d;
            carrierSynth.set(\vol,      d * 0.06);  // reducido para evitar pitido
            noiseSynth.set(\vol,        d * 0.15);
            noiseSynth.set(\popRate,    d * 4.0 + 0.3);
            masterSynth.set(\bandwidth, (4000 - (d * 2500)).max(1500));  // min 1500Hz
            masterSynth.set(\ambientVol, d * 0.4);
            inputSynth.set(\blend,      1.0 - (d * 0.15));
        });

        // =====================================================
        // KILL TRAIL
        // =====================================================

        this.addCommand("kill_trail", "f", { arg msg;
            var dur = msg[1];
            masterSynth.set(\trailWet,      0.9);
            masterSynth.set(\trailFeedback, 0.85);
            SystemClock.sched(dur, {
                masterSynth.set(\trailWet,      0.0);
                masterSynth.set(\trailFeedback, 0.0);
                masterSynth.set(\ambientVol,    distanceVal * 0.55);
                nil;
            });
        });

        // =====================================================
        // TRAIL CLEAR
        // =====================================================

        this.addCommand("trail_clear", "f", { arg msg;
            masterSynth.set(\trailWet,      0.0);
            masterSynth.set(\trailFeedback, 0.0);
        });
    }

    // =====================================================
    // FREE
    // =====================================================

    free {
        masterSynth.free;
        carrierSynth.free;
        noiseSynth.free;
        inputSynth.free;
        voiceBus.free;
        ambientBus.free;
    }
}