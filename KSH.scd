
s.options.numOutputBusChannels = 12;

State(\ksh).clear;
State(\ksh).initActions.add({
	Log(\ksh).level = 'info';

	Event.parentEvents[\cvSynth] = CVEvent.synthEvent;

	DistCurve(\hard,
		[-1, 0, 1],
		Env([-1, -0.00001, 0.96, 1], [1, 0.01, 1], [4, 'lin', 'lin'])
	);

	///////////////////////////////////////////////////////////////////////////////////////////////
	// SYNTHDEFS
	///////////////////////////////////////////////////////////////////////////////////////////////
	Log(\ksh).info("Initializing synthdefs.");
	SynthDef(\kshDriver, {
		| buffer, t_trigger, contTrigger = 0, amp=1, attack=0.1, decay=1.5, offset=0, trigLPF=1000, baseRate=1 |
		var sig, rateMult, outs, outAmps;

		rateMult = \rateMult.kr([1, 1.001, 1.3333, 1.334]);
		outs = \outs.kr([1, 1, 1, 1]);
		outAmps = \outAmps.kr([1, 1, 1, 1]);
		amp = amp.dbamp;

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

		feed = LocalIn.ar(1, 0);
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
				fuzzAmt,
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
		noise = FormantTable.at(\altoA).flop.sum {
			|form|
			var f, a, q;
			#f, a, q = form;
			BBandPass.ar(WhiteNoise.ar(1), f, q, a);
		};

		decays = ([43, 80, 140, 91, 85, 51] * 3).sum {
			|f, i|
			var pwidth, pfreq, pan, decay;

			decay = BPF.ar(sig, f, 25 / f);
			pfreq = LFDNoise3.kr(LFDNoise3.kr(4, 0.3, 0.6), 4, 16);
			pwidth = LFDNoise3.kr(LFDNoise3.kr(0.1, 0.2, 0.3), 0.2, 0.5);
			pan = LFDNoise3.kr(LFDNoise3.kr(0.1, 0.2, 0.3), 0.9, 0.0);
			noise = noise * LPF.ar(LFPulse.ar(pfreq, 0, pwidth), amp.linexp(0, 1, 100, 2000));

			decay = decay * (1 + LPF.ar(noise, amp.linlin(0, 1, 10000, 20000)));
			decay = AllpassC.ar(decay, 0.25, 0.25, 1.9);
			decay = Pan2.ar(decay, pan, 2);
		};

		Out.ar(outFeed, decays);
		Out.ar(out, decays);
	}).addReplace;

	///////////////////////////////////////////////////////////////////////////////////////////////
	// RESOURCES
	///////////////////////////////////////////////////////////////////////////////////////////////
	Log(\ksh).info("Initializing resources.");
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
			distA:		Bus.audio(s, 1),
			distB:		Bus.audio(s, 1),
			distC:		Bus.audio(s, 1),
			distD:		Bus.audio(s, 1),

			preFeed:	Bus.audio(s, 2),
			postFeed:	Bus.audio(s, 2),
		),

		~groups = ().make({
			~feedback 	= Group(s);
			~driver 	= Group(~feedback, 'addAfter');
			~dist 		= Group(~driver, 'addAfter');
			~whisper 	= Group(~dist, 'addAfter');
			~mixer 		= Group(~whisper, 'addAfter');
		}),

		~lc = LCDevice()
	]);

	~distBusNums = ~buses.atAll([\distA, \distB, \distC, \distD]).collect(_.index);

	///////////////////////////////////////////////////////////////////////////////////////////////
	// CVS
	///////////////////////////////////////////////////////////////////////////////////////////////
	Log(\ksh).info("Initializing controls.");
	~ctrl = (
		driver: (
			amp: 		CV(\db, 						0	),
			attack: 	CV(ControlSpec(0, 6, 4), 		0.1	),
			decay: 		CV(ControlSpec(0, 6, 4), 		2	),
		),
		distA: (
			amp: 		CV(ControlSpec(0, 1, 4),		1	),
			pan: 		CV(\pan, 						0	),
			moogFreq: 	CV(ControlSpec(20, 400, 'exp'),	0	),
			moogRes: 	CV(ControlSpec(0.1, 3),			0.7 ),
			hpfFreq: 	CV(ControlSpec(100, 4000),		1000 ),
			fuzzAmt: 	CV(ControlSpec(0, 1, 4),		0	),
			fuzzFreq: 	CV(ControlSpec(20, 400),		200	),
		)
	);

	~lc.connect;

	~ctrl.driver.atAll([\amp, \attack, \decay]).do {
		|cv, i|
		~lc.knobRows[0][i].connect.cv_(cv)
	};

	~ctrl.distA.atAll([\amp, \pan, \moogFreq, \moogRes, \hpfFreq, \fuzzAmt, \fuzzFreq]).do {
		|cv, i|
		~lc.knobRows[1][i].connect.cv_(cv)
	};

	~kshDriverEvent = (
		\instrument: 	\kshDriver,
		\group:			~groups.driver,
		\latency: 		false,
		\buffer: 		~samples[1].bufnum,
		\outs:			[~distBusNums],
		\trigger: 		1,
		\contTrigger: 	0,
		\trigLPF: 		1000,
		\baseRate: 		0.02,
		\outAmps: 		[[1, 1, 1, 1]],
		\rateMult: 		[[1, 2, 3, 4]]
	) << ~ctrl.driver;


});

State(\ksh).startActions.add({
	~distA = (
		(
			instrument: 	\kshDistA,
			type:			\cvEvent,
			group: 			~groups.dist,
			distBus: 		~buses.distA,
			inFeed: 		~buses.postFeed,
			outFeed: 		~buses.preFeed,
			// pan: 			~ctrl.distA.pan,
			// amp: 			~ctrl.distA.amp,
			// moogFreq: 		~ctrl.distA.moogFreq,
			// moogRes: 		~ctrl.distA.moogRes,
			// hpfFreq: 		~ctrl.distA.hpfFreq,
			// fuzzAmt: 		0,
			// fuzzFreq: 		200
		) << ~ctrl.distA
	).cvSynth.play;

	~distB = (
		instrument: 	\kshDistNull,
		group: 			~groups.dist,
		distBus: 		~buses.distB,
	).play;

	~distC = (
		instrument: 	\kshDistNull,
		group: 			~groups.dist,
		distBus: 		~buses.distC,
	).play;

	~distD = (
		instrument: 	\kshDistNull,
		group: 			~groups.dist,
		distBus: 		~buses.distD,
	).play;

	~whispersA = (
		instrument: 	\kshWhispers,
		group: 			~groups.whisper,
		in: 			~buses.distA,
		out: 			0,
		outFeed: 		~buses.preFeed
	).play;

	~feedback = (
		instrument: 	\kshFeedback,
		in: 			~buses.preFeed,
		out: 			~buses.postFeed
	).play;

	~lc.buttons[0].buttonOnActions.clear();
	~lc.buttons[0].default.toggle_(false).connect.buttonOnActions.add({
		~short1 = (~kshDriverEvent << (
			// \attack: 		0.001,
			// \decay: 		6.3,
			//\offset: { rrand(0.2, 0.8) },
			\offset: 		{ rrand(0.1, 0.86) },
			\baseRate: 		0.39,
//			\amp: 			0.1,
			\buffer: 		~samples[1].bufnum,
			\outAmps: 		[[1, 1, 1, 1]],
			\rateMult: 		[[1, 1.01, 5/3, 7/3]]
		) << ~ctrl.driver).play;
	});

	~mixer = {
		var sigs = ~distBusNums.collect(In.ar(_, 1));
		Out.ar(0, Splay.ar(sigs, 0.5));
	}.play(target:~groups.mixer);

});

State(\ksh).stopActions.add({
	~distA.free;
	~mixer.free;
});

State(\ksh).push;
State(\ksh).doInit();

// CVGrid(\ksh).rows = [
// 	~ctrl.driver.collect { |cv| CVGridCell(, cv)}
// ]

MultiStateManager().activate(nil);
MultiStateManager().activate(\ksh);
