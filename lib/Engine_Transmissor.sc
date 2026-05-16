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
    // ALLOC — EXECUTED SEQUENTIALLY TOP TO BOTTOM
    // =====================================================

    alloc {

        // -------------------------------------------------
        // BUSSES
        // -------------------------------------------------

        voiceBus   = Bus.audio(context.server, 2);
        ambientBus = Bus.audio(context.server, 2);
        distanceVal = 0.3;

        // =====================================================
        // CARRIER SYNTH — Ionospheric carrier
        // SinOsc with slow pitch + amplitude flutter
        // =====================================================

        carrierSynth = {

            arg
                vol      = 0.0,
                freq     = 4800,
                pitchLFO = 0.08,
                ampLFO   = 0.15;

            var freqSmooth;
            var volSmooth;
            var pitchMod;
            var ampMod;
            var sig;

            freqSmooth = freq.lag(0.08);
            volSmooth  = vol.lag(0.05);

            pitchMod = LFNoise1.kr(pitchLFO).range(
                freqSmooth * 0.998,
                freqSmooth * 1.002
            );

            ampMod = LFNoise1.kr(ampLFO).range(0.3, 1.0);

            sig = SinOsc.ar(pitchMod) * ampMod * volSmooth;
            sig = BPF.ar(sig, freqSmooth, 0.02);

            Out.ar(ambientBus, sig ! 2);

        }.play(context.server, addAction: \addToHead);

        // =====================================================
        // NOISE SYNTH — Shortwave static
        // WhiteNoise BPF + sparse impulse pops
        // =====================================================

        noiseSynth = {

            arg
                vol     = 0.0,
                popRate = 1.2,
                center  = 2400;

            var volSmooth;
            var band;
            var pops;
            var sig;

            volSmooth = vol.lag(0.08);

            band = BPF.ar(WhiteNoise.ar(1.0), center, 0.8) * 0.6;

            pops = Dust.ar(popRate) * 0.4;
            pops = HPF.ar(pops, 1200);

            sig = (band + pops) * volSmooth;

            Out.ar(ambientBus, sig ! 2);

        }.play(context.server, addAction: \addToHead);

        // =====================================================
        // MASTER FX — Voice bandpass + phaser + echo trail
        // =====================================================

        masterSynth = {

            arg
                bandwidth     = 2400,
                locut         = 300,
                phaserFreq    = 0.15,
                ambientVol    = 0.4,
                trailWet      = 0.0,
                trailTime     = 0.45,
                trailFeedback = 0.0,
                volume        = 0.7;

            var voiceIn;
            var ambientIn;
            var sig;
            var trail;
            var wetSmooth;
            var fbSmooth;

            voiceIn   = In.ar(voiceBus,   2);
            ambientIn = In.ar(ambientBus, 2);

            // radio bandpass
            sig = HPF.ar(voiceIn, locut);
            sig = LPF.ar(sig, bandwidth);

            // mild phaser
            sig = AllpassN.ar(
                sig,
                0.02,
                SinOsc.kr(phaserFreq).range(0.001, 0.009),
                0.08
            );

            // echo trail
            wetSmooth = trailWet.lag(0.1);
            fbSmooth  = trailFeedback.lag(0.1);

            trail = CombL.ar(
                sig,
                2.0,
                trailTime,
                fbSmooth * 8.0
            );

            sig = sig + (trail * wetSmooth);
            sig = sig + (ambientIn * ambientVol);

            Out.ar(0, Limiter.ar(sig * volume, 0.95));

        }.play(context.server, addAction: \addToTail);

        // =====================================================
        // INPUT SSB CHAIN — Full modulator/demodulator
        // Captures audio from norns inputs, processes through
        // SSB modulation, RF effects, then demodulation
        // =====================================================

        inputSynth = {

            arg
                // TX section
                tx_freq      = 4800,
                osc_jitter   = 0.2,
                pilot_leak   = 0.0,
                saturation   = 0.0,
                harmonic_drive = 0.0,
                key_click    = 0.0,

                // AIR section
                multipath    = 0.3,
                doppler      = 3.0,
                fade_rate    = 0.3,
                fade_depth   = 0.5,
                smear        = 0.2,
                link_quality = 0.8,

                // NOISE section
                atmos        = 0.2,
                space_hum    = 0.05,
                whistle      = 0.0,
                hum          = 0.0,
                e_skip       = 0.0,
                borealis     = 0.0,

                // RX section
                detune       = 0.0,
                rx_drift     = 0.1,
                agc_rate     = 0.4,
                agc_breath   = 0.1,
                rx_bw        = 2400,
                adc_depth    = 16,

                // MIX section
                input_trim   = 0.8,
                blend        = 1.0,
                floor        = 0.3,
                hum_level    = 0.05,
                distance     = 0.3,

                // RF FX — SPACE
                rev_wet      = 0.0,
                rev_decay    = 0.3,
                rev_damp     = 0.5,
                ech_wet      = 0.0,
                ech_time     = 0.3,
                ech_fb       = 0.3,

                // RF FX — TEXTURE
                cho_wet      = 0.0,
                cho_rate     = 0.5,
                cho_depth    = 0.005,
                com_wet      = 0.0,
                com_freq     = 100,
                com_fb       = 0.3,

                // RF FX — DESTROY
                dst_wet      = 0.0,
                dst_drive    = 3.0,
                dst_tone     = 4000,
                fbn_wet      = 0.0,
                fbn_spread   = 0.5,
                fbn_rate     = 0.3;

            var input, hilbert, rf, rfMultipath, rfEffects;
            var demod, sig, compSig, agcKey;
            var driftLFO, tapDelay, tapGain;
            var harmonicSig;
            var rfReverb, rfEcho, rfChorus, rfComb, rfDist, rfFBank;

            // 1. INPUT STAGE
            input = In.ar(0, 1) * input_trim;

            // 2. KEY CLICK — transient on signal onset
            input = input * (1 + (key_click *
                EnvGen.kr(Env.perc(0.001, 0.05),
                Trig1.kr(A2K.kr(input.abs > 0.001), 0.01))));

            // 3. PRE-MOD SATURATION (overmod)
            input = (input * (1 + saturation * 4)).tanh *
                (1 / (1 + saturation * 4).max(0.001));

            // 4. SSB MODULATOR (USB via Hilbert)
            hilbert = Hilbert.ar(input);

            rf = (hilbert[0] * CosOsc.ar(
                    tx_freq * (1 + osc_jitter * 0.001 * LFNoise1.kr(3)))) -
                 (hilbert[1] * SinOsc.ar(tx_freq));

            // 5. CARRIER LEAK (pilot tone)
            rf = rf + (SinOsc.ar(tx_freq, mul: pilot_leak * 0.001));

            // 6. HARMONIC DISTORTION (amplifier harmonics)
            harmonicSig = 0;
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 2) * 0.5);
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 3) * 0.3);
            harmonicSig = harmonicSig + (SinOsc.ar(tx_freq * 4) * 0.1);
            rf = rf + (harmonic_drive * harmonicSig);

            // 7. MULTIPATH (5 tapped delay lines)
            rfMultipath = rf * 0.5;

            // tap 1: direct path (always present, gain 0.3)
            // tap 2: first reflection
            tapDelay = LFNoise1.kr(0.5 + (multipath * 0.5))
                .range(0.002, 0.002 + multipath * 0.015);
            tapGain = 0.35 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            // tap 3: second reflection
            tapDelay = LFNoise1.kr(0.7 + (multipath * 0.3))
                .range(0.003, 0.003 + multipath * 0.020);
            tapGain = 0.25 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            // tap 4: third reflection
            tapDelay = LFNoise1.kr(0.3 + (multipath * 0.7))
                .range(0.001, 0.001 + multipath * 0.025);
            tapGain = 0.15 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            // tap 5: fourth reflection
            tapDelay = LFNoise1.kr(0.9 + (multipath * 0.1))
                .range(0.004, 0.004 + multipath * 0.018);
            tapGain = 0.08 * multipath.max(0.1);
            rfMultipath = rfMultipath + (DelayC.ar(rf, 0.05, tapDelay) * tapGain);

            rf = rfMultipath;

            // 8. DOPPLER SPREAD — frequency shift
            rfEffects = FreShift.ar(rf,
                LFNoise1.kr(0.3).range(-doppler, doppler));
            // secondary spread tap (lower gain)
            rfEffects = rfEffects + (FreShift.ar(rf,
                LFNoise1.kr(0.7).range(-doppler * 0.5, doppler * 0.5)) * 0.3);

            rf = rfEffects;

            // 9. SELECTIVE FADING — modulated bandpass
            rf = BPF.ar(rf,
                tx_freq + (fade_depth *
                    LFNoise1.kr(fade_rate * 2).range(
                        -tx_freq * 0.3, tx_freq * 0.3)),
                LFNoise1.kr(fade_rate).range(
                    0.2, 1.0 - (fade_depth * 0.5))
            );

            // 10. DISPERSION — allpass chain (group delay variation)
            rf = AllpassC.ar(rf, 0.01,
                LFNoise1.kr(0.2).range(
                    0.0005, 0.0005 + smear * 0.005), 0.5);
            rf = AllpassC.ar(rf, 0.01,
                LFNoise1.kr(0.3).range(
                    0.0003, 0.0003 + smear * 0.004), 0.4);

            // 11. ATMOSPHERIC NOISE (QRN — storm crackle, brown noise)
            rf = rf + (atmos * 0.08 *
                LPF.ar(Dust.ar(LFNoise1.kr(0.1).range(5, 40)), 200));

            // 12. GALACTIC NOISE (space background hum)
            rf = rf + (space_hum * 0.02 * BrownNoise.ar(1.0));

            // 13. HETERODYNE WHISTLE (interference tone)
            rf = rf + (whistle * 0.06 *
                SinOsc.ar(LFNoise1.kr(0.1).range(300, 3000)));

            // 14. POWER LINE HUM (50/60 Hz + harmonics)
            rf = rf + (hum * 0.04 * (
                SinOsc.ar(60) * 0.5 +
                SinOsc.ar(120) * 0.3 +
                SinOsc.ar(180) * 0.15));

            // 15. SPORADIC E — sudden SNR improvement + timbre shift
            rf = rf * (1 + (e_skip *
                Dust.kr(LFNoise1.kr(0.05).range(0.05, 0.2)) *
                LFNoise1.kr(0.2).range(0.5, 1.5)));

            // 16. AURORAL — aggressive FM modulation
            rf = rf * (1 + (borealis * 0.3 *
                LFNoise1.kr(8).range(-1, 1)));

            // =====================================================
            // RF FX SECTION — Effects applied in RF domain
            // Each effect is wet/dry selectable via param
            // =====================================================

            // 17a. RF REVERB (FreeVerb in RF domain)
            rfReverb = Select.ar(rev_wet > 0.001, [
                rf,
                FreeVerb.ar(rf, rev_wet, rev_decay, rev_damp)
            ]);

            // 17b. RF ECHO (delay line in RF)
            rfEcho = rfReverb +
                (DelayL.ar(rfReverb, 2.0, ech_time, ech_fb * 6.0) * ech_wet);
            rf = Select.ar(ech_wet > 0.001, [ rfReverb, rfEcho ]);

            // 17c. RF CHORUS (3 modulated delays in RF)
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
            rfComb = Select.ar(com_wet > 0.001, [
                rf,
                CombL.ar(rf, 0.5,
                    1.0 / com_freq.max(20),
                    com_fb * 8.0)
            ]);
            rf = rfComb;

            // 17e. RF DISTORTION (intermodulation via saturation)
            rfDist = Select.ar(dst_wet > 0.001, [
                rf,
                (rf * (1 + dst_drive * 2)).tanh /
                    (1 + dst_drive * 2).tanh
            ]);
            rf = rfDist;

            // 17f. RF FILTERBANK (3 bandpass filters with modulation)
            rfFBank = Select.ar(fbn_wet > 0.001, [
                rf,
                (BPF.ar(rf,
                    tx_freq * (1.0 - fbn_spread * 0.15) *
                        (1 + fbn_wet * 0.05 * LFNoise1.kr(fbn_rate).range(-1, 1)),
                    0.3) * (1.0 - fbn_spread * 0.3)) +
                (BPF.ar(rf,
                    tx_freq * (1.0 + fbn_spread * 0.0),
                    0.3) * 1.0) +
                (BPF.ar(rf,
                    tx_freq * (1.0 + fbn_spread * 0.15) *
                        (1 + fbn_wet * 0.05 * LFNoise1.kr(fbn_rate * 0.7).range(-1, 1)),
                    0.3) * (1.0 - fbn_spread * 0.3))
            ]);
            rf = rfFBank;

            // 18. SNR — master noise floor
            rf = (rf * link_quality) +
                (WhiteNoise.ar(1.0) * (1 - link_quality) * 0.1);

            // 18. SSB DEMODULATOR
            demod = rf * CosOsc.ar(
                tx_freq + detune +
                (rx_drift * LFNoise1.kr(0.05).range(-5, 5))
            );
            demod = LPF.ar(demod, 4000);

            // 19. ADC QUANTIZATION (SDR bit depth)
            sig = demod.round(2.0 / (2 ** adc_depth));

            // 20. AGC WITH PUMPING
            agcKey = sig.abs.max(0.001);
            compSig = Compander.ar(sig, agcKey,
                0.05,          // threshold
                1,             // slope below
                1 + agc_breath, // slope above (pumping)
                agc_rate * 0.1, // attack
                agc_rate * 0.01 // release
            );

            // prevent DC buildup
            sig = LeakDC.ar(compSig);

            // 21. RX BANDWIDTH (IF filter)
            sig = HPF.ar(sig, 100);
            sig = LPF.ar(sig, rx_bw);

            // 22. BLEND (dry/wet)
            sig = (input * (1 - blend)) + (sig * blend);

            // 23. OUTPUT to voiceBus
            Out.ar(voiceBus, sig ! 2);

        }.play(context.server, addAction: \addToHead);

        // =====================================================
        // COMMANDS — one per parameter
        // =====================================================

        // TX section
        this.addCommand("set_tx_freq", "f", { arg msg;
            inputSynth.set(\tx_freq, msg[1]);
        });
        this.addCommand("set_osc_jitter", "f", { arg msg;
            inputSynth.set(\osc_jitter, msg[1]);
        });
        this.addCommand("set_pilot_leak", "f", { arg msg;
            inputSynth.set(\pilot_leak, msg[1]);
        });
        this.addCommand("set_saturation", "f", { arg msg;
            inputSynth.set(\saturation, msg[1]);
        });
        this.addCommand("set_harmonic_drive", "f", { arg msg;
            inputSynth.set(\harmonic_drive, msg[1]);
        });
        this.addCommand("set_key_click", "f", { arg msg;
            inputSynth.set(\key_click, msg[1]);
        });

        // AIR section
        this.addCommand("set_multipath", "f", { arg msg;
            inputSynth.set(\multipath, msg[1]);
        });
        this.addCommand("set_doppler", "f", { arg msg;
            inputSynth.set(\doppler, msg[1]);
        });
        this.addCommand("set_fade_rate", "f", { arg msg;
            inputSynth.set(\fade_rate, msg[1]);
        });
        this.addCommand("set_fade_depth", "f", { arg msg;
            inputSynth.set(\fade_depth, msg[1]);
        });
        this.addCommand("set_smear", "f", { arg msg;
            inputSynth.set(\smear, msg[1]);
        });
        this.addCommand("set_link_quality", "f", { arg msg;
            inputSynth.set(\link_quality, msg[1]);
        });

        // NOISE section
        this.addCommand("set_atmos", "f", { arg msg;
            inputSynth.set(\atmos, msg[1]);
        });
        this.addCommand("set_space_hum", "f", { arg msg;
            inputSynth.set(\space_hum, msg[1]);
        });
        this.addCommand("set_whistle", "f", { arg msg;
            inputSynth.set(\whistle, msg[1]);
        });
        this.addCommand("set_hum", "f", { arg msg;
            inputSynth.set(\hum, msg[1]);
        });
        this.addCommand("set_e_skip", "f", { arg msg;
            inputSynth.set(\e_skip, msg[1]);
        });
        this.addCommand("set_borealis", "f", { arg msg;
            inputSynth.set(\borealis, msg[1]);
        });

        // RX section
        this.addCommand("set_detune", "f", { arg msg;
            inputSynth.set(\detune, msg[1]);
        });
        this.addCommand("set_rx_drift", "f", { arg msg;
            inputSynth.set(\rx_drift, msg[1]);
        });
        this.addCommand("set_agc_rate", "f", { arg msg;
            inputSynth.set(\agc_rate, msg[1]);
        });
        this.addCommand("set_agc_breath", "f", { arg msg;
            inputSynth.set(\agc_breath, msg[1]);
        });
        this.addCommand("set_rx_bw", "f", { arg msg;
            inputSynth.set(\rx_bw, msg[1]);
        });
        this.addCommand("set_adc_depth", "f", { arg msg;
            inputSynth.set(\adc_depth, msg[1]);
        });

        // MIX section
        this.addCommand("set_input_trim", "f", { arg msg;
            inputSynth.set(\input_trim, msg[1]);
        });
        this.addCommand("set_blend", "f", { arg msg;
            inputSynth.set(\blend, msg[1]);
        });
        this.addCommand("set_floor", "f", { arg msg;
            inputSynth.set(\floor, msg[1]);
        });
        this.addCommand("set_hum_level", "f", { arg msg;
            inputSynth.set(\hum_level, msg[1]);
        });

        // RF FX — SPACE
        this.addCommand("set_rev_wet", "f", { arg msg;
            inputSynth.set(\rev_wet, msg[1]);
        });
        this.addCommand("set_rev_decay", "f", { arg msg;
            inputSynth.set(\rev_decay, msg[1]);
        });
        this.addCommand("set_rev_damp", "f", { arg msg;
            inputSynth.set(\rev_damp, msg[1]);
        });
        this.addCommand("set_ech_wet", "f", { arg msg;
            inputSynth.set(\ech_wet, msg[1]);
        });
        this.addCommand("set_ech_time", "f", { arg msg;
            inputSynth.set(\ech_time, msg[1]);
        });
        this.addCommand("set_ech_fb", "f", { arg msg;
            inputSynth.set(\ech_fb, msg[1]);
        });

        // RF FX — TEXTURE
        this.addCommand("set_cho_wet", "f", { arg msg;
            inputSynth.set(\cho_wet, msg[1]);
        });
        this.addCommand("set_cho_rate", "f", { arg msg;
            inputSynth.set(\cho_rate, msg[1]);
        });
        this.addCommand("set_cho_depth", "f", { arg msg;
            inputSynth.set(\cho_depth, msg[1]);
        });
        this.addCommand("set_com_wet", "f", { arg msg;
            inputSynth.set(\com_wet, msg[1]);
        });
        this.addCommand("set_com_freq", "f", { arg msg;
            inputSynth.set(\com_freq, msg[1]);
        });
        this.addCommand("set_com_fb", "f", { arg msg;
            inputSynth.set(\com_fb, msg[1]);
        });

        // RF FX — DESTROY
        this.addCommand("set_dst_wet", "f", { arg msg;
            inputSynth.set(\dst_wet, msg[1]);
        });
        this.addCommand("set_dst_drive", "f", { arg msg;
            inputSynth.set(\dst_drive, msg[1]);
        });
        this.addCommand("set_dst_tone", "f", { arg msg;
            inputSynth.set(\dst_tone, msg[1]);
        });
        this.addCommand("set_fbn_wet", "f", { arg msg;
            inputSynth.set(\fbn_wet, msg[1]);
        });
        this.addCommand("set_fbn_spread", "f", { arg msg;
            inputSynth.set(\fbn_spread, msg[1]);
        });
        this.addCommand("set_fbn_rate", "f", { arg msg;
            inputSynth.set(\fbn_rate, msg[1]);
        });

        // Carrier commands
        this.addCommand("set_carrier_vol", "f", { arg msg;
            carrierSynth.set(\vol, msg[1]);
        });
        this.addCommand("set_carrier_freq", "f", { arg msg;
            carrierSynth.set(\freq, msg[1]);
        });
        this.addCommand("set_carrier_drift", "f", { arg msg;
            carrierSynth.set(\pitchLFO, msg[1]);
            carrierSynth.set(\ampLFO, msg[1] * 1.8);
        });

        // Noise commands
        this.addCommand("set_noise_vol", "f", { arg msg;
            noiseSynth.set(\vol, msg[1]);
        });
        this.addCommand("set_noise_pops", "f", { arg msg;
            noiseSynth.set(\popRate, msg[1]);
        });

        // Master commands
        this.addCommand("set_master_bw", "f", { arg msg;
            masterSynth.set(\bandwidth, msg[1]);
        });
        this.addCommand("set_master_ambient", "f", { arg msg;
            masterSynth.set(\ambientVol, msg[1]);
        });

        // =====================================================
        // DISTANCE — meta-control
        // Drives: noise up, carrier up, bandwidth down,
        // ambient mix up, blend towards processed
        // =====================================================

        this.addCommand("set_distance", "f", { arg msg;

            var d = msg[1].clip(0.0, 1.0);

            distanceVal = d;

            carrierSynth.set(\vol,      d * 0.18);
            noiseSynth.set(\vol,        d * 0.22);
            noiseSynth.set(\popRate,    d * 4.0 + 0.3);
            masterSynth.set(\bandwidth, 4000 - (d * 2800));
            masterSynth.set(\ambientVol, d * 0.55);
            inputSynth.set(\blend,      1.0 - (d * 0.2));
        });

        // =====================================================
        // KILL TRAIL — spike echo wet+feedback, then fade
        // =====================================================

        this.addCommand("kill_trail", "f", { arg msg;

            var dur = msg[1];

            masterSynth.set(\trailWet,      0.9);
            masterSynth.set(\trailFeedback, 0.85);

            SystemClock.sched(dur, {
                masterSynth.set(\trailWet,      0.0);
                masterSynth.set(\trailFeedback, 0.0);
                masterSynth.set(\ambientVol,    distanceVal * 0.55);
                nil
            });
        });

        // =====================================================
        // TRAIL CLEAR — immediate fade
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