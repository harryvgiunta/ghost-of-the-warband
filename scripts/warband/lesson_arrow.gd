class_name LessonArrow
extends Node3D
## GHOST OF THE WARBAND: the pointing hand for a thing the lesson wants walked to.
##
## The first fight's shiv lies on the dirt at the foot of the cold altar, a few
## paces behind where Corvin stops, and "walk to your shiv" is not a place: a body
## that has just taken his hands is looking at a dark yard, two sleepers and a card. This is a big warm gold arrow - unshaded, so it
## reads at any distance and in the camp's night - hanging above the item with a
## slow roll and a bob. Over the shiv it carries no text, because the pickup
## already floats its own name; `set_label()` puts a word over it for the markers
## that need one (`PRESS G` at the bars, `RUN HERE` at the gap in the trees), and
## that word always billboards to the camera.
##
## The scene owns where it points (`anchor_at`) and when it is shown; the bob and
## the roll are this node's own clock, so a marker never fights a physics step.

const GOLD := Color(1.0, 0.76, 0.24)
## The label is the same gold, with a burnt outline so it reads over a torch, a
## cage and the wood's black night alike.
const LABEL_OUTLINE := Color(0.20, 0.08, 0.01, 0.95)
## Overall size. It is the only thing marking the spot from the cage line, so it is
## deliberately out of scale with everything around it.
const SIZE := 1.35
const HOVER := 1.7       ## metres above the point being marked
const LABEL_HEIGHT := 1.3 ## arrow-local metres above the head the label floats
## A word has to read from the cage line, not from the bars: 48 px at 22 mm a
## pixel is a metre-high line of gold, wider than the arrow under it on purpose.
const LABEL_PIXEL := 0.022
const LABEL_FONT := 48
const BOB := 0.16        ## how far the arrow swings up and down
const BOB_RATE := 2.6    ## radians/second of the bob
const SPIN_RATE := 1.1   ## radians/second of the slow roll
const SCALE_PULSE := 0.06

var _base := Vector3.ZERO
var _clock := 0.0
## An optional word over the arrow ("PRESS G", "RUN HERE"). The marker carries no
## text by default: the shiv floats its own name, so an arrow over it needs none.
var _label: Label3D = null
var _label_text := ""


func _ready() -> void:
	_build()
	_place()


## Point at a spot in the world. Safe to call every frame: the arrow reads its
## anchor back on its own clock.
func anchor_at(point: Vector3) -> void:
	_base = point
	_place()


## Put one word over the arrow, or take it away with "". The text billboards
## towards the camera, so the arrow's own slow roll never turns it edge-on.
func set_label(text: String) -> void:
	if text == _label_text and (_label != null or text.is_empty()):
		return
	_label_text = text
	if text.is_empty():
		if _label != null:
			_label.visible = false
		return
	if _label == null:
		_label = Label3D.new()
		_label.name = "Label"
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.pixel_size = LABEL_PIXEL
		_label.font_size = LABEL_FONT
		_label.outline_size = 16
		_label.modulate = GOLD
		_label.outline_modulate = LABEL_OUTLINE
		_label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
		# The arrow is a marker, not a body: its word must not sit in the shadow
		# of the thing it is pointing at.
		_label.render_priority = 1
		add_child(_label)
	_label.text = text
	_label.visible = true


## The word over the arrow, or "" (read by the scene that owns the marker).
func label_text() -> String:
	return _label_text


func _process(delta: float) -> void:
	_clock += delta
	_place()


func _place() -> void:
	var swing := sin(_clock * BOB_RATE)
	global_position = _base + Vector3(0.0, HOVER + swing * BOB, 0.0)
	rotation.y = _clock * SPIN_RATE
	scale = Vector3.ONE * (SIZE * (1.0 + swing * SCALE_PULSE))


# --- the body --------------------------------------------------------------

## One unshaded material for the whole arrow: a marker that takes the camp's night
## lighting turns black, and a marker nobody can see is not a marker.
func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GOLD
	return material


func _piece(mesh: Mesh, at: Vector3, tilt: Vector3, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = at
	piece.rotation = tilt
	# A marker has no business casting a shadow across the thing it points at.
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	return piece


func _build() -> void:
	var material := _material()
	# Head: a wide cone on its point. It is the whole read at twenty metres, so it
	# carries the silhouette and nothing else competes with it.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.42
	cone.height = 0.70
	cone.radial_segments = 12
	_piece(cone, Vector3(0.0, 0.0, 0.0), Vector3(PI, 0.0, 0.0), material)
	# Shaft: short and square above the head. No fletching - a gold cross on a stick
	# reads as a little man at this size, and the point is the only shape that says
	# "this spot, here".
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.15, 0.46, 0.15)
	_piece(shaft, Vector3(0.0, 0.55, 0.0), Vector3.ZERO, material)
