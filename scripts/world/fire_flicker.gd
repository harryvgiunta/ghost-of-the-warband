extends OmniLight3D
class_name FireFlicker
## A hearth lamp that breathes with the flame under it.
##
## A steady point light is the loudest tell that a fire is faked: real flame light
## rises and falls several times a second and never repeats. `base_energy` is the
## light the scene asked for, and the flicker is a sum of three incommensurate
## sines around it, so the fire never settles into a visible cycle. Two fires are
## offset from each other by their own position.

## Fraction of the base energy the lamp wanders by.
@export var flicker: float = 0.18

var base_energy := 1.0
var _clock := 0.0
var _phase := 0.0


func _ready() -> void:
	base_energy = light_energy
	_phase = fmod(absf(float(hash(position))), 628.0) * 0.01


func _process(delta: float) -> void:
	_clock += delta
	var wobble := sin(_clock * 7.3 + _phase) * 0.55 \
		+ sin(_clock * 11.9 + _phase * 1.7) * 0.28 \
		+ sin(_clock * 19.7 + _phase * 2.3) * 0.17
	light_energy = base_energy * (1.0 + flicker * wobble)
