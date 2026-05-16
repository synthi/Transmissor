// Engine_Transmissor.sc — Transmissor v1.3.0
// Shortwave SSB transmission simulator engine for norns
// Audio input → SSB modulation → RF effects → SSB demodulation → output
//
// Changelog:
//   v1.3.0  Cosmic ping (Decay.ar + .clip 0.5), Meteor scatter stable
//   v1.2.0  Dispersion hybrid (Meteor Scatter), no accidental blips
//   v1.1.2  Receiver hum 50Hz (audio domain), distance no override blend
//   v1.1.1  Whistle -20dB, SNR fix (multipath/AGC/compander),
//           Key click = crackle generator (no input gate),
//           EQ params: locut/hicut/rx_hpf (page 9),
//           Fidelity presets control EQ,
//           Demod LPF 5kHz, Graves/agudos restaurados en PRISTINE
//   v1.1.0  FIX: redraw_metro (norns 240102+ no auto-redraw)
//   v1.0.7  Phase noise fix, Auroral, PTT, AGC 2ms
//   v1.0    Initial release

Engine_Transmissor : CroneEngine {

    var <masterSynth;
    var <carrierSynth;
    var <noiseSynth;
    var <inputSynth;
    var <voiceBus;
    var <ambientBus;
    var distanceVal;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {

        voiceBus   = Bus.audio(context.server, 2);
        ambientBus = Bus.audio(context.server, 2);
        distanceVal = 0.0;

        // CARRIER SYNTH
        carrierSynth = {
            arg vol = 0.0, freq = 4800, pitchLFO = 0.08, ampLFO = 0.15;
            var freqSmooth, volSmooth, pitchMod, ampMod, sig;
            freqSmooth = freq.lag(0.08);
            volSmooth  = vol.lag(0.05);
            pitchMod = LFNoise1.kr(pitchLFO).range(freqSmooth * 0.998, freqSmooth * 1.002);
            ampMod = LFNoise1.kr(ampLFO).range(0.3, 1.0);
            sig = SinOsc.ar(pitchMod) * ampMod * volSmooth;
            sig = BPF.ar(sig, freqSmooth, 0.1);
            Out.ar(ambientBus, sig ! 2);
        }.play(context.server, addAction: \addToHead);

        // NOISE SYNTH
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

        // MASTER FX
        masterSynth = {
            arg bandwidth = 4000, locut = 80, phaserFreq = 0.15,
                ambientVol = 0.4, trailWet = 0.0, trailTime = 0.45,
                trailFeedback = 0.0, volume = 0.7;
            var voiceIn, ambientIn, sig, trail, wetSmooth, fbSmooth;
            voiceIn   = In.ar(voiceBus, 2);
            ambientIn = LPF.ar(In.ar(ambientBus, 2), bandwidth);
            sig = HPF.ar(voiceIn, locut);
            sig = LPF.ar(sig, bandwidth);
            sig = AllpassN.ar(sig, 0.02, SinOsc.kr(phaserFreq).range(0.001, 0.009), 0.08);
            wetSmooth = trailWet.lag(0.1);
            fbSmooth  = trailFeedback.lag(0.1);
            trail = CombL.ar(sig, 2.0, trailTime, fbSmooth * 8.0);
            sig = sig + (trail * wetSmooth);
            sig = sig + (ambientIn * ambientVol);
            Out.ar(0, Limiter.ar(sig * volume, 0.95));
        }.play(context.server, addAction: \addToTail);

        // INPUT SSB CHAIN
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
                input_trim = 1.0, blend = 1.0, floor = 0.02,
                hum_level = 0.05, distance = 0.0, rx_hpf = 60,
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
            var meteorTrigger, cosmicPing;
            var sigEnv, noiseFloor, eTrig, eEnv, ditherSig;

            // 1. INPUT
            input = SoundIn.ar(0) * input_trim;

            // 2. KEY CLICK (crackle generator — NOT an input gate)
            // Authentic telegraph key click: saturated noise burst
            input = input + ((WhiteNoise.ar(1.0) * Dust.ar(key_click * 80)).tanh * 0.12);

            // 3. PRE-MOD SATURATION
            input = (input * (1 + saturation * 4.0)).tanh *
                (1.0 / (1.0 + saturation * 4.0).max(0.001));

            // 4. SSB MODULATOR (USB via Hilbert)
            // Phase noise: PinkNoise filtered to 50Hz = real 1/f oscillator phase noise
            hilbert = Hilbert.ar(input);
            rf = (hilbert[0] * SinOsc.ar(
                    tx_freq + (osc_jitter * 50.0 * LPF.kr(PinkNoise.kr, 50)),
                    pi/2)) -
                 (hilbert[1] * SinOsc.ar(tx_freq));

            // 5. CARRIER LEAK
            rf = rf + (SinOsc.ar(tx_freq, pilot_leak * 0.001));

            // 6. HARMONIC DISTORTION
            harmonicSig = 0.0;
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 2.0) * 0.5);
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 3.0) * 0.3);
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 4.0) * 0.1);
            rf = rf + (harmonic_drive * harmonicSig);

            // 7. MULTIPATH (5 taps, direct path dominates like real RF)
            rfMultipath = rf * 0.85;
            tapDelay = LFNoise1.kr(0.5 + (multipath * 0.5))
                .range(0.002, 0.002 + multipath * 0.015);
            tapGain = 0.35 * multipath;
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);
            tapDelay = LFNoise1.kr(0.7 + (multipath * 0.3))
                .range(0.003, 0.003 + multipath * 0.020);
            tapGain = 0.25 * multipath;
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);
            tapDelay = LFNoise1.kr(0.3 + (multipath * 0.7))
                .range(0.001, 0.001 + multipath * 0.025);
            tapGain = 0.15 * multipath;
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);
            tapDelay = LFNoise1.kr(0.9 + (multipath * 0.1))
                .range(0.004, 0.004 + multipath * 0.018);
            tapGain = 0.08 * multipath;
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);
            rf = rfMultipath;

            // 8. DOPPLER SPREAD
            rfEffects = FreqShift.ar(rf, LFNoise1.kr(0.3).range(doppler.neg, doppler));
            rfEffects = rfEffects + (FreqShift.ar(rf,
                LFNoise1.kr(0.7).range(doppler.neg * 0.5, doppler * 0.5)) * 0.3);
            rf = rfEffects;

            // 9. SELECTIVE FADING
            rf = BPF.ar(rf,
                tx_freq + (fade_depth * LFNoise1.kr(fade_rate * 2).range(tx_freq.neg * 0.3, tx_freq * 0.3)),
                LFNoise1.kr(fade_rate).range(0.2, 1.0 - (fade_depth * 0.5)));

            // 10. DISPERSION (Ionospheric breathe + Meteor Scatter + Cosmic Pings)
            meteorTrigger = Dust.ar(0.12);
            cosmicPing = Decay.ar(meteorTrigger, 0.05)
                * BPF.ar(WhiteNoise.ar(1.0), tx_freq, 0.2)
                * 0.03 * smear;
            rf = rf + cosmicPing;
            rf = AllpassC.ar(rf, 0.01,
                LFNoise1.kr(0.2).range(0.0005, 0.0005 + smear * 0.005),
                (LFNoise1.kr(0.05).range(0.1, 0.3) * (1.0 + (smear * 2.0))).clip(0.0, 0.5)
            );
            rf = AllpassC.ar(rf, 0.01,
                LFNoise1.kr(0.3).range(0.0003, 0.0003 + smear * 0.004),
                (Decay2.ar(meteorTrigger, 0.5, 2.0).range(0.1, 0.4) * (1.0 + (smear * 2.0))).clip(0.0, 0.5)
            );

            // 11. ATMOSPHERIC NOISE
            rf = rf + (atmos * 0.08 * LPF.ar(Dust.ar(LFNoise1.kr(0.1).range(5, 40)), 200));

            // 12. GALACTIC NOISE
            rf = rf + (space_hum * 0.02 * BrownNoise.ar(1.0));

            // 13. HETERODYNE WHISTLE (-20dB: subtle, not overwhelming)
            rf = rf + (whistle * 0.006 * SinOsc.ar(tx_freq + LFNoise1.kr(0.1).range(300, 3000)));

            // 14. POWER LINE HUM
            rf = rf + (hum * 0.04 * (SinOsc.ar(60) * 0.5 + SinOsc.ar(120) * 0.3 + SinOsc.ar(180) * 0.15));

            // 15. SPORADIC E (temporary signal boost from ionospheric skip)
            eTrig = Dust.kr(LFNoise1.kr(0.05).range(0.05, 0.2));
            eEnv = EnvGen.kr(Env.perc(0.01, 0.3), eTrig);
            rf = rf * (1 + (e_skip * eEnv * LFNoise1.kr(0.2).range(0.5, 1.5)));

            // 16. AURORAL (rapid flutter 20-80Hz)
            rf = rf * (1 + (borealis * 0.3 * LFNoise0.kr(LFNoise1.kr(0.5).range(20, 80)).range(-1, 1)));

            // RF FX
            rfReverb = Select.ar(rev_wet > 0.001, [ rf, FreeVerb.ar(rf, rev_wet, rev_decay, rev_damp) ]);
            rfEcho = rfReverb + (DelayL.ar(rfReverb, 2.0, ech_time, ech_fb * 6.0) * ech_wet);
            rf = Select.ar(ech_wet > 0.001, [ rfReverb, rfEcho ]);
            rfChorus = rf;
            rfChorus = rfChorus + (DelayC.ar(rf, 0.03, SinOsc.kr(cho_rate).range(0.005, 0.005 + cho_depth)) * cho_wet * 0.4);
            rfChorus = rfChorus + (DelayC.ar(rf, 0.03, SinOsc.kr(cho_rate * 1.3).range(0.008, 0.008 + cho_depth * 0.7)) * cho_wet * 0.3);
            rfChorus = rfChorus + (DelayC.ar(rf, 0.03, SinOsc.kr(cho_rate * 0.7).range(0.003, 0.003 + cho_depth * 0.5)) * cho_wet * 0.2);
            rf = Select.ar(cho_wet > 0.001, [ rf, rfChorus ]);
            rfComb = Select.ar(com_wet > 0.001, [ rf, CombL.ar(rf, 0.5, 1.0 / com_freq.max(20), com_fb * 8.0) ]);
            rf = rfComb;
            rfDist = Select.ar(dst_wet > 0.001, [ rf, LPF.ar((rf * (1 + dst_drive * 2)).tanh / (1 + dst_drive * 2).tanh, dst_tone) ]);
            rf = rfDist;
            rfFBank = Select.ar(fbn_wet > 0.001, [ rf,
                (BPF.ar(rf, tx_freq * (1.0 - fbn_spread * 0.15) * (1 + fbn_wet * 0.05 * LFNoise1.kr(fbn_rate).range(-1, 1)), 0.3) * (1.0 - fbn_spread * 0.3)) +
                (BPF.ar(rf, tx_freq, 0.3) * 1.0) +
                (BPF.ar(rf, tx_freq * (1.0 + fbn_spread * 0.15) * (1 + fbn_wet * 0.05 * LFNoise1.kr(fbn_rate * 0.7).range(-1, 1)), 0.3) * (1.0 - fbn_spread * 0.3)) ]);
            rf = rfFBank;

            // 18. SNR (noise fills gaps between words = squelch tail)
            sigEnv = Amplitude.ar(rf, 0.01, 0.1);
            noiseFloor = WhiteNoise.ar(1.0) * (1.0 - link_quality) * 0.1 * (1.0 - sigEnv.min(1.0));
            rf = (rf * link_quality) + noiseFloor;

            // 19. SSB DEMODULATOR (LPF 5kHz for more air in PRISTINE)
            demod = rf * SinOsc.ar(tx_freq + (rx_drift * LFNoise1.kr(0.05).range(-5, 5)), pi/2);
            demod = LPF.ar(demod, 5000);

            // 19b. DETUNE
            detuneSmooth = detune.lag(0.05);
            detuneAtten = 1.0 - (detuneSmooth.abs / 50.0).min(0.9);
            demod = FreqShift.ar(demod, detuneSmooth.neg);
            demod = demod * detuneAtten;

            // 20. ADC QUANTIZATION with TPDF dither
            ditherSig = (WhiteNoise.ar(1.0) + WhiteNoise.ar(1.0)) * (0.5 / pow(2, adc_depth));
            sig = (demod + ditherSig).round(2.0 / pow(2, adc_depth));

            // 21. AGC (realistic SSB receiver: high threshold, moderate gain)
            agcKey = sig.abs;
            compSig = Compander.ar(sig, agcKey, 0.1, 1.0, 0.2, 0.002, agc_rate.max(0.05));
            sig = LeakDC.ar(compSig) * (4.0 + (agc_breath * 6.0));
            sig = sig.clip2(0.95);

            // 22. RX BANDWIDTH (HPF from param, not hardcoded)
            sig = HPF.ar(sig, rx_hpf);
            sig = LPF.ar(sig, rx_bw);

            // 22b. RECEIVER HUM (50Hz mains — receiving on different continent)
            sig = sig + (hum * 0.08 * (
                SinOsc.ar(50) * 0.5 + SinOsc.ar(100) * 0.3 + SinOsc.ar(150) * 0.15));

            // 23. BLEND
            sig = (input * (1 - blend)) + (sig * blend);

            // 24. OUTPUT
            Out.ar(voiceBus, sig ! 2);

        }.play(context.server, addAction: \addToHead);

        // COMMANDS
        this.addCommand("set_tx_freq", "f", { arg msg; inputSynth.set(\tx_freq, msg[1]); });
        this.addCommand("set_osc_jitter", "f", { arg msg; inputSynth.set(\osc_jitter, msg[1]); });
        this.addCommand("set_pilot_leak", "f", { arg msg; inputSynth.set(\pilot_leak, msg[1]); });
        this.addCommand("set_saturation", "f", { arg msg; inputSynth.set(\saturation, msg[1]); });
        this.addCommand("set_harmonic_drive", "f", { arg msg; inputSynth.set(\harmonic_drive, msg[1]); });
        this.addCommand("set_key_click", "f", { arg msg; inputSynth.set(\key_click, msg[1]); });
        this.addCommand("set_multipath", "f", { arg msg; inputSynth.set(\multipath, msg[1]); });
        this.addCommand("set_doppler", "f", { arg msg; inputSynth.set(\doppler, msg[1]); });
        this.addCommand("set_fade_rate", "f", { arg msg; inputSynth.set(\fade_rate, msg[1]); });
        this.addCommand("set_fade_depth", "f", { arg msg; inputSynth.set(\fade_depth, msg[1]); });
        this.addCommand("set_smear", "f", { arg msg; inputSynth.set(\smear, msg[1]); });
        this.addCommand("set_link_quality", "f", { arg msg; inputSynth.set(\link_quality, msg[1]); });
        this.addCommand("set_atmos", "f", { arg msg; inputSynth.set(\atmos, msg[1]); });
        this.addCommand("set_space_hum", "f", { arg msg; inputSynth.set(\space_hum, msg[1]); });
        this.addCommand("set_whistle", "f", { arg msg; inputSynth.set(\whistle, msg[1]); });
        this.addCommand("set_hum", "f", { arg msg; inputSynth.set(\hum, msg[1]); });
        this.addCommand("set_e_skip", "f", { arg msg; inputSynth.set(\e_skip, msg[1]); });
        this.addCommand("set_borealis", "f", { arg msg; inputSynth.set(\borealis, msg[1]); });
        this.addCommand("set_detune", "f", { arg msg; inputSynth.set(\detune, msg[1]); });
        this.addCommand("set_rx_drift", "f", { arg msg; inputSynth.set(\rx_drift, msg[1]); });
        this.addCommand("set_agc_rate", "f", { arg msg; inputSynth.set(\agc_rate, msg[1]); });
        this.addCommand("set_agc_breath", "f", { arg msg; inputSynth.set(\agc_breath, msg[1]); });
        this.addCommand("set_rx_bw", "f", { arg msg; inputSynth.set(\rx_bw, msg[1]); });
        this.addCommand("set_adc_depth", "f", { arg msg; inputSynth.set(\adc_depth, msg[1]); });
        this.addCommand("set_input_trim", "f", { arg msg; inputSynth.set(\input_trim, msg[1]); });
        this.addCommand("set_blend", "f", { arg msg; inputSynth.set(\blend, msg[1]); });
        this.addCommand("set_floor", "f", { arg msg; inputSynth.set(\floor, msg[1]); });
        this.addCommand("set_hum_level", "f", { arg msg; inputSynth.set(\hum_level, msg[1]); });
        this.addCommand("set_rev_wet", "f", { arg msg; inputSynth.set(\rev_wet, msg[1]); });
        this.addCommand("set_rev_decay", "f", { arg msg; inputSynth.set(\rev_decay, msg[1]); });
        this.addCommand("set_rev_damp", "f", { arg msg; inputSynth.set(\rev_damp, msg[1]); });
        this.addCommand("set_ech_wet", "f", { arg msg; inputSynth.set(\ech_wet, msg[1]); });
        this.addCommand("set_ech_time", "f", { arg msg; inputSynth.set(\ech_time, msg[1]); });
        this.addCommand("set_ech_fb", "f", { arg msg; inputSynth.set(\ech_fb, msg[1]); });
        this.addCommand("set_cho_wet", "f", { arg msg; inputSynth.set(\cho_wet, msg[1]); });
        this.addCommand("set_cho_rate", "f", { arg msg; inputSynth.set(\cho_rate, msg[1]); });
        this.addCommand("set_cho_depth", "f", { arg msg; inputSynth.set(\cho_depth, msg[1]); });
        this.addCommand("set_com_wet", "f", { arg msg; inputSynth.set(\com_wet, msg[1]); });
        this.addCommand("set_com_freq", "f", { arg msg; inputSynth.set(\com_freq, msg[1]); });
        this.addCommand("set_com_fb", "f", { arg msg; inputSynth.set(\com_fb, msg[1]); });
        this.addCommand("set_dst_wet", "f", { arg msg; inputSynth.set(\dst_wet, msg[1]); });
        this.addCommand("set_dst_drive", "f", { arg msg; inputSynth.set(\dst_drive, msg[1]); });
        this.addCommand("set_dst_tone", "f", { arg msg; inputSynth.set(\dst_tone, msg[1]); });
        this.addCommand("set_fbn_wet", "f", { arg msg; inputSynth.set(\fbn_wet, msg[1]); });
        this.addCommand("set_fbn_spread", "f", { arg msg; inputSynth.set(\fbn_spread, msg[1]); });
        this.addCommand("set_fbn_rate", "f", { arg msg; inputSynth.set(\fbn_rate, msg[1]); });
        this.addCommand("set_carrier_vol", "f", { arg msg; carrierSynth.set(\vol, msg[1]); });
        this.addCommand("set_carrier_freq", "f", { arg msg; carrierSynth.set(\freq, msg[1]); });
        this.addCommand("set_carrier_drift", "f", { arg msg;
            carrierSynth.set(\pitchLFO, msg[1]); carrierSynth.set(\ampLFO, msg[1] * 1.8); });
        this.addCommand("set_noise_vol", "f", { arg msg; noiseSynth.set(\vol, msg[1]); });
        this.addCommand("set_noise_pops", "f", { arg msg; noiseSynth.set(\popRate, msg[1]); });
        this.addCommand("set_master_bw", "f", { arg msg; masterSynth.set(\bandwidth, msg[1]); });
        this.addCommand("set_master_ambient", "f", { arg msg; masterSynth.set(\ambientVol, msg[1]); });
        this.addCommand("set_locut", "f", { arg msg; masterSynth.set(\locut, msg[1]); });
        this.addCommand("set_hicut", "f", { arg msg; masterSynth.set(\bandwidth, msg[1]); });
        this.addCommand("set_rx_hpf", "f", { arg msg; inputSynth.set(\rx_hpf, msg[1]); });

        // DISTANCE
        this.addCommand("set_distance", "f", { arg msg;
            var d = msg[1].clip(0.0, 1.0);
            distanceVal = d;
            carrierSynth.set(\vol, d * 0.06);
            noiseSynth.set(\vol, d * 0.15);
            noiseSynth.set(\popRate, d * 4.0 + 0.3);
            masterSynth.set(\bandwidth, (4000 - (d * 2500)).max(1500));
            masterSynth.set(\ambientVol, d * 0.4);
        });

        // KILL TRAIL
        this.addCommand("kill_trail", "f", { arg msg;
            var dur = msg[1];
            masterSynth.set(\trailWet, 0.9);
            masterSynth.set(\trailFeedback, 0.85);
            SystemClock.sched(dur, {
                masterSynth.set(\trailWet, 0.0);
                masterSynth.set(\trailFeedback, 0.0);
                masterSynth.set(\ambientVol, distanceVal * 0.55);
                nil;
            });
        });

        // TRAIL CLEAR
        this.addCommand("trail_clear", "f", { arg msg;
            masterSynth.set(\trailWet, 0.0);
            masterSynth.set(\trailFeedback, 0.0);
        });
    }

    free {
        masterSynth.free;
        carrierSynth.free;
        noiseSynth.free;
        inputSynth.free;
        voiceBus.free;
        ambientBus.free;
    }
}