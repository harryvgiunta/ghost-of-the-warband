class_name QuestMarker
extends "res://scripts/warband/lesson_arrow.gd"
## The "talk to him" arrow over a keeper's head.
##
## `LessonArrow` already is the campaign's pointing hand - unshaded gold, a slow
## roll and a bob - so this adds the one thing an NPC marker needs: it follows a
## body instead of a spot on the dirt. The keeper is a standing figure, so the
## arrow rides at head height and a step clear of it, and the owner decides which
## keeper wears it (`QuestGiver.marker_service()`); this node never chooses.
##
## The arrow is unparented from the keeper on purpose: a marker under a rig would
## inherit the rig's scale (the band's bodies are 0.86-1.14 of the authored
## skeleton), and a gold arrow that comes out different sizes over two heads
## reads as two different markers.

## Where the arrow hangs over a standing body: the rig is 1.8-2.0 m to the crown
## and the arrow's own `HOVER` sits it another 1.7 m up.
const HEAD_HEIGHT := 2.05
## The word over a keeper's head is read from three or four metres, not from the
## cage line, so it is scaled for that: the shared constant is sized for a marker
## twenty metres away and at a conversation distance it fills half the screen.
const NPC_LABEL_PIXEL := 0.0042
const NPC_LABEL_FONT := 40

var _target: Node3D = null
var _height := HEAD_HEIGHT


## Hang the arrow over `target`'s head. Safe to call before the target is in the
## tree: the arrow re-reads the position on its own clock.
func attach_to(target: Node3D, height: float = HEAD_HEIGHT) -> void:
	_target = target
	_height = height
	_tick()

func detach() -> void:
	_target = null

## Whether the arrow is currently riding a live body.
func attached() -> bool:
	return _target != null and is_instance_valid(_target)

## The body the arrow points at (or null).
func target() -> Node3D:
	return _target if attached() else null

## The word over the arrow, at a keeper's scale. The parent builds the label with
## the lesson's own measurements; this re-sizes it at the size a body standing at
## the counter reads it.
func set_label(text: String) -> void:
	super.set_label(text)
	if _label != null:
		_label.pixel_size = NPC_LABEL_PIXEL
		_label.font_size = NPC_LABEL_FONT


func _process(delta: float) -> void:
	_tick()
	super._process(delta)

func _tick() -> void:
	if not attached():
		return
	anchor_at(_target.global_position + Vector3(0.0, _height, 0.0))
