~buf = Buffer.read(s, "/Users/fsc/Documents/_sounds/cello/C-string/C-str-7_mono-261.aif");
~buf = Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_E1_phrase_forte_con-sord.wav");
~buf = Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_A1_phrase_piano_arco-normal.wav");
~buf = Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_F1_phrase_mezzo-forte_arco-glissando.wav");
~buf = Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_E1_phrase_mezzo-forte_arco-legato.wav");

~d = NodeProxy.audio(s, 2);
~d.play;
~d.scope

DistCurve(\hard,
	[-1, 0, 1],
	Env([-1, -0.00001, 0.96, 1], [1, 0.01, 1], [4, 'lin', 'lin'])
);
DistCurve(\hard).plot

(
~d.source = {
	| a=1, b=1.3333, c=2.3333, d=1.01 |
	var sig, distSig, feed, sigPos, sigNeg, decays;

	sig = Mix(PlayBuf.ar(1, ~buf, rate:0.8 * [a, b, c, d], loop:1));
	sig = sig * LPF.ar(Decay2.ar(Impulse.ar(1 / 4), 1, 4, 0.8), 1000);
//	sig = sig + (WhiteNoise.ar(0.01) * Trig.ar(Dust.ar(0.05), 0.4));

	feed = LocalIn.ar(1);
	feed = feed + (FreeVerb1.ar(feed, 7, hfDamping:0.5) * 0.05).tanh.tanh;
	feed = LeakDC.ar(LPF.ar(DelayC.ar(feed, 0.06, 0.06), 1000, 0.1));
	feed = LeakDC.ar(feed);
	feed = FreqShift.ar(feed, SinOsc.kr(0.04, 0, 3)).neg;

	sig = (sig * 1.5) + feed;
	sigPos = sig.clip(0, 10);
	sigNeg = sig.clip(-10, 0);
	distSig = sig.sign * Mix([sigPos, sigNeg.abs].collect {
		|x|
		var ds;
		x = (x.abs > 0.00001) * x;
		ds = (64 * x.pow(7)) - (112 * x.pow(5)) + (56 * x.pow(3)) - (7 * x);
	});

	distSig = distSig + MoogVCF.ar(distSig, 200, 0.7) + HPF.ar(distSig, 1000);
	distSig = distSig + (DistCurve(\hard).ar(BPF.ar(distSig, MouseY.kr(200, 400) * [1, 4/3, 5/3], 1, MouseX.kr(0, 1)), 12, -24) * MouseX.kr(0, 1)).sum;
	distSig = SoftClipAmp4.ar(distSig, 1, 1);


	decays = [90, 140, 80, 43, 85].collect {
		|f|
		var pwidth, pfreq, pan, decay = BPF.ar(distSig, f, 5 / f);
		pfreq = LFDNoise3.kr(LFDNoise3.kr(4, 0.3, 0.6), 4, 20);
		pwidth = LFDNoise3.kr(LFDNoise3.kr(0.1, 0.2, 0.3), 0.25, 0.25);
		pan = LFDNoise3.kr(LFDNoise3.kr(0.1, 0.2, 0.3), 0.9, 0.0);
		decay = decay * LPF.ar(LFPulse.ar(pfreq, 0, pwidth), 300);
		decay = decay * (1 + LPF.ar(WhiteNoise.ar(0.1), 1000 + (20000 * Amplitude.kr(distSig, 0.01, 3).min(1))));
		decay = AllpassC.ar(decay, 0.25, 0.25, 1.9);
		decay = Pan2.ar(decay, pan, 4);
	};

	LocalOut.ar(distSig);

	(distSig * [1, 1]) + decays.sum;
};
)

(
~d.set(\a, 1);
~d.set(\b, 1.033);
~d.set(\c, 2.033);
~d.set(\d, 2.01);
)