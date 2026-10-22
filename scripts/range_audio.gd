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

func play_sound(sound: String) -> void:
	if muted:
		return
	var voice := voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	voice.stream = sounds[sound]
	voice.volume_db = -5.0 if sound == "clang" else -9.0 if sound == "parry" else -13.0
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
