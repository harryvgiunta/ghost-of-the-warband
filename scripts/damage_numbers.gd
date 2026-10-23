extends RefCounted
## Scrolling world-space damage numbers shared by the frontier and arena.
## The host applies real damage; arena replicas spawn the same presenter from
## the health delta in a snapshot, so every peer sees feedback without a new
## network message.

const HIT_COLOR := Color("f4d89b")
const HEAD_COLOR := Color("ffd36b")
const PLAYER_COLOR := Color("ff7668")
const LETHAL_COLOR := Color("ff9a5c")
const DRIFT := 0.32

static var _sequence := 0

static func spawn(parent: Node, at: Vector3, amount: float, kind: String = "hit", headshot: bool = false, lethal: bool = false) -> void:
	if not is_instance_valid(parent) or amount <= 0.0:
		return
	var label := Label3D.new()
	label.name = "DamageNumber"
	label.text = ("-%d" if kind == "self" else "%d") % int(ceil(amount))
	label.font_size = 74 if headshot else 60
	label.pixel_size = 0.0062
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 14
	label.outline_modulate = Color(0.035,0.055,0.06,0.96)
	label.modulate = LETHAL_COLOR if lethal else (PLAYER_COLOR if kind == "self" else (HEAD_COLOR if headshot else HIT_COLOR))
	label.scale = Vector3.ONE*0.55
	parent.add_child(label)
	var side := -1.0 if (_sequence & 1) == 0 else 1.0
	var drift := Vector3(DRIFT*side,0.0,DRIFT*0.35*side)
	_sequence += 1
	label.global_position = at + Vector3(0,1.35,0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label,"global_position",label.global_position+Vector3(0,1.15,0)+drift,0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"scale",Vector3.ONE*1.12,0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"modulate:a",0.0,0.9).set_delay(0.22)
	tween.chain().tween_callback(label.queue_free)
