extends Node

var voices: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var voice_index := 0
var muted := false

func _ready() -> void:
	for index in 4:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -13.0
		add_child(voice)
		voices.append(voice)
	sounds["release"] = _synthesize(0.24, 155.0, 0.5, 54.0)
	sounds["hit"] = _synthesize(0.20, 95.0, 0.65, 70.0)
	sounds["bullseye"] = _synthesize(0.55, 620.0, 0.02, 920.0)
	sounds["equip"] = _synthesize(0.09, 440.0, 0.08, 600.0)
	sounds["clang"] = _synthesize(0.48, 230.0, 0.52, 74.0)
	sounds["parry"] = _synthesize(0.36, 1480.0, 0.14, 2350.0)
	sounds["block"] = _synthesize(0.22, 170.0, 0.5, 82.0)
	sounds["heal"] = _synthesize(0.42, 660.0, 0.03, 990.0)
	sounds["charge"] = _synthesize(0.55, 118.0, 0.62, 640.0)
	# Item skills: a short library so each weapon reads with its own voice.
	sounds["barrage"] = _synthesize(0.16, 260.0, 0.55, 120.0)
	sounds["volley"] = _synthesize(0.24, 220.0, 0.50, 92.0)
	sounds["pierce"] = _synthesize(0.34, 320.0, 0.40, 74.0)
	sounds["slash"] = _synthesize(0.20, 420.0, 0.58, 130.0)
	sounds["lunge"] = _synthesize(0.26, 190.0, 0.52, 82.0)
	sounds["spin"] = _synthesize(0.52, 124.0, 0.48, 380.0)
	sounds["dash"] = _synthesize(0.16, 380.0, 0.72, 840.0)
	sounds["fire"] = _synthesize(0.62, 96.0, 0.78, 46.0)
	sounds["bone"] = _synthesize(0.36, 540.0, 0.30, 180.0)
	sounds["bash"] = _synthesize(0.30, 160.0, 0.44, 88.0)
	sounds["slam"] = _synthesize(0.58, 74.0, 0.70, 34.0)

func play_sound(sound: String) -> void:
	if muted:
		return
	var voice := voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	voice.stream = sounds[sound]
	voice.volume_db = -5.0 if sound == "clang" else -9.0 if sound in ["parry","charge"] else -13.0
	voice.play()

func _synthesize(duration: float, frequency: float, noise: float, end_frequency: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	var oscillator := 0.0
	for index in count:
		var time := float(index) / rate
		var progress := time / duration
		oscillator += TAU * lerpf(frequency, end_frequency, progress) / rate
		var envelope := exp(-progress * 7.0) * minf(time * 350.0, 1.0)
		var sample := (sin(oscillator) * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise) * envelope * 0.65
		bytes.encode_s16(index * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
