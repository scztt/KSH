
s.options.numOutputBusChannels = 12;

State(\ksh).clear;
State(\ksh).initActions.add({

	DistCurve(\hard,
		[-1, 0, 1],
		Env([-1, -0.00001, 0.96, 1], [1, 0.01, 1], [4, 'lin', 'lin'])
	);

	SynthDef(\kshDriver, {
		| buffer, t_trigger, contTrigger = 0, amp=1, attack=0.1, decay=1.5, offset=0, trigLPF=1000, baseRate=1 |
		var sig, rateMult, outs, outAmps;

		rateMult = \rateMult.kr([1, 1.001, 1.3333, 1.334]);
		outs = \outs.kr([1, 1, 1, 1]);
		outAmps = \outAmps.kr([1, 1, 1, 1]);

		sig = Mix(PlayBuf.ar(1, buffer,
			rate:baseRate * rateMult,
			trigger: contTrigger + t_trigger,
			startPos: offset * BufSamples.kr(buffer),
			loop:1
		));

		sig = sig * LPF.ar(
			Decay2.ar(Trig.ar(t_trigger + contTrigger, 0.0001), attack, decay),
			trigLPF
		);

		DetectSilence.ar(sig, doneAction:2);
		sig = sig * outAmps * amp;

		Out.ar(outs, sig);
	}).addReplace;

	SynthDef(\kshDistA, {
		| distBus, inFeed, outFeed, pan = 0, amp = 1, moogFreq = 200, moogRes = 0.7, hpfFreq = 1000, fuzzAmt = 0, fuzzFreq = 200, feedAmt = 0.1 |
		var sig, sigPos, sigNeg, distSig, feed;

		// sig = Mix(PlayBuf.ar(1, ~buf, rate:0.8 * [1, 1.01, 2, 2.01], loop:1));
		// sig = sig * LPF.ar(Decay2.ar(Impulse.ar(1 / 8), 0.1, 1, 0.8), 1000);

		feed = LocalIn.ar(1);
		feed = feed + (FreeVerb1.ar(feed, 4, hfDamping:0.9) * 0.07).tanh.tanh;
		feed = LeakDC.ar(LPF.ar(DelayC.ar(feed, 0.06, 0.06), 1000, feedAmt));
		feed = FreqShift.ar(feed, SinOsc.kr(0.04, 0, 3)).neg;

		sig = In.ar(distBus, 1) + (FreqShift.ar(SoundIn.ar(0), -400) * 6);

		sig = sig + feed;
		sigPos = sig.clip(0, 10);
		sigNeg = sig.clip(-10, 0);
		distSig = sig.sign * Mix([sigPos, sigNeg.abs].collect {
			|x|
			var ds;
			x = (x.abs > 0.00001) * x;
			ds = (64 * x.pow(7)) - (112 * x.pow(5)) + (56 * x.pow(3)) - (7 * x);
		});

		// Supplemental filtering / per-freq fuzz
		distSig = distSig + MoogVCF.ar(distSig, 200, 0.7) + HPF.ar(distSig, hpfFreq);
		distSig = distSig + (
			DistCurve(\hard).ar(
				BPF.ar(distSig, fuzzFreq * [1, 1.0231, 0.9942], 10, fuzzAmt),
				12, -24
			) * fuzzAmt
		).sum;
		distSig = SoftClipAmp4.ar(distSig, 1, amp);

		LocalOut.ar(distSig);
		ReplaceOut.ar(distBus, distSig);
	}).addReplace;

	SynthDef(\kshDistNull, {
		| distBus, inFeed, outFeed, pan = 0, amp = 1, moogFreq = 200, moogRes = 0.7, hpfFreq = 1000, fuzzAmt = 0, fuzzFreq = 200, feedAmt = 0.1 |
		ReplaceOut.ar(distBus, DC.ar(0));
	}).addReplace;

	SynthDef(\kshFeedback, {
		| in, out, amount=0.05 |
		var feed;

		feed = InFeedback.ar(in);
		feed = feed + (FreeVerb1.ar(feed, 7, hfDamping:0.5) * 0.05).tanh.tanh;
		feed = LeakDC.ar(LPF.ar(DelayC.ar(feed, 0.06, 0.06), 1000, amount));
		feed = FreqShift.ar(feed, SinOsc.kr(0.04, 0, 3)).neg;

		Out.ar(out, feed);
		//Out.ar(2, feed);
	}).addReplace;


	SynthDef(\kshWhispers, {
		| in, out, outFeed |
		var sig, decays, formant, noise, amp;
		// Whispers

		sig = In.ar(in);
		amp = Amplitude.kr(sig, 0.01, 3).min(1);
		noise = FormantTable.at(\counterTenorO).flop.sum {
			|form|
			var f, a, q;
			#f, a, q = form;
			BBandPass.ar(WhiteNoise.ar(1), f, q, a);
		};

		decays = ([43, 80, 140, 91, 85, 51] * 3).sum {
			|f, i|
			var pwidth, pfreq, pan, decay;

			decay = BPF.ar(sig, f, 25 / f);
			pfreq = LFDNoise3.kr(LFDNoise3.kr(4, 0.3, 0.6), 4, 20);
			pwidth = LFDNoise3.kr(LFDNoise3.kr(0.1, 0.2, 0.3), 0.25, 0.25);
			pan = LFDNoise3.kr(LFDNoise3.kr(0.1, 0.2, 0.3), 0.9, 0.0);
			decay = decay * LPF.ar(LFPulse.ar(pfreq, 0, pwidth), amp.linexp(0, 1, 100, 2000));

			decay = decay * (1 + LPF.ar(noise, amp.linlin(0, 1, 6000, 20000)));
			decay = AllpassC.ar(decay, 0.25, 0.25, 1.9);
			decay = Pan2.ar(decay, pan, 2);
		};

		Out.ar(outFeed, decays);
		Out.ar(out, decays);
	}).addReplace;

	~resources.addAll([
		// Samples
		~samples = [
			Buffer.read(s, "/Users/fsc/Documents/_sounds/cello/C-string/C-str-7_mono-261.aif"),
			Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_E1_phrase_forte_con-sord.wav"),
			Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_A1_phrase_piano_arco-normal.wav"),
			Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_F1_phrase_mezzo-forte_arco-glissando.wav"),
			Buffer.read(s, "/Users/fsc/Documents/_sounds/phil-samples/double bass/double-bass_E1_phrase_mezzo-forte_arco-legato.wav")
		],

		~buses = (
			distA: Bus.audio(s, 1),
			distB: Bus.audio(s, 1),
			distC: Bus.audio(s, 1),
			distD: Bus.audio(s, 1),

			preFeed: Bus.audio(s, 2),
			postFeed: Bus.audio(s, 2),
		),

		~groups = ().make({
			~feedback = Group(s);
			~driver = Group(~feedback, 'addAfter');
			~dist = Group(~driver, 'addAfter');
			~whisper = Group(~dist, 'addAfter');
			~mixer = Group(~whisper, 'addAfter');
		})

	]);

	~distBusNums = ~buses.atAll([\distA, \distB, \distC, \distD]).collect(_.index);

	~kshDriverEvent = (
		\instrument: \kshDriver,
		\group: ~groups.driver,
		\latency: 0,
		\buffer: ~samples[0].bufnum,
		\outs: [~distBusNums],
		\trigger: 1,
		\contTrigger: 0,
		\amp: 1,
		\attack: 0.1,
		\decay: 1.5,
		\trigLPF: 1000,
		\baseRate: 0.5,
		\outAmps: [[1, 1, 1, 1]],
		\rateMult: [[1, 2, 3, 4]]
	);

});

State(\ksh).startActions.add({
	~distA = (
		instrument: \kshDistA,
		group: ~groups.dist,
		distBus: ~buses.distA,
		inFeed: ~buses.postFeed,
		outFeed: ~buses.preFeed,
		pan: 0,
		amp: 0.3,
		moogFreq: 200,
		moogRes: 0.7,
		hpfFreq: 1000,
		fuzzAmt: 0,
		fuzzFreq: 200
	).play;

	~distB = (
		instrument: \kshDistNull,
		group: ~groups.dist,
		distBus: ~buses.distB,
	).play;

	~distC = (
		instrument: \kshDistNull,
		group: ~groups.dist,
		distBus: ~buses.distC,
	).play;

	~distD = (
		instrument: \kshDistNull,
		group: ~groups.dist,
		distBus: ~buses.distD,
	).play;

	~whispersA = (
		instrument: \kshWhispers,
		group: ~groups.whisper,
		in: ~buses.distA,
		out: 0,
		outFeed: ~buses.preFeed
	).play;

	~feedback = (
		instrument: \kshFeedback,
		in: ~buses.preFeed,
		out: ~buses.postFeed
	).play;

	~short1 = (~kshDriverEvent << (
		\attack: 0.001,
		\decay: 6.3,
		//\offset: { rrand(0.2, 0.8) },
		\offset: { rrand(0.3, 0.36) },
		\baseRate: 0.59,
		\amp: 0.1,
		\buffer: ~samples[0].bufnum,
		\outAmps: [[1, 1, 1, 1]],
		\rateMult: [[1, 1.01, 5/3, 7/3]]
	)).play;


	~buses.preFeed.scope;

	~short1.set(\t_trigger, 1);

	~mixer = {
		var sigs = ~distBusNums.collect(In.ar(_, 1));
		Out.ar(0, Splay.ar(sigs, 0.5));
	}.play(target:~groups.mixer);

});

State(\ksh).stopActions.add({
	~distA.free;
	~short1.free;

})


~d = NodeProxy.audio(s, 2);
~d.play;
~d.stop

(
~buf = ~samples[2];

~d.source = {
	| a=1, b=1.3333, c=2.3333, d=1.01 |
	var sig, distSig, feed, sigPos, sigNeg, decays;

	sig = Mix(PlayBuf.ar(1, ~buf, rate:0.8 * [a, b, c, d], loop:1));
	sig = sig * LPF.ar(Decay2.ar(Impulse.ar(1 / 4), 0.1, 1, 0.8), 1000);
	//	sig = sig + (WhiteNoise.ar(0.01) * Trig.ar(Dust.ar(0.05), 0.4));

	feed = LocalIn.ar(1);
	feed = feed + (FreeVerb1.ar(feed, 7, hfDamping:0.5) * 0.05).tanh.tanh;
	feed = LeakDC.ar(LPF.ar(DelayC.ar(feed, 0.06, 0.06), 1000, 0.1));
	feed = LeakDC.ar(feed);
	feed = FreqShift.ar(feed, SinOsc.kr(0.04, 0, 3)).neg;

	sig = (sig * 4.5) + feed;
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

	decays = [43, 80, 140, 91, 85, 51].collect {
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