class_name LessonArrow
extends Node3D
## GHOST OF THE WARBAND: the pointing hand for a thing the lesson wants walked to.
##
## The first fight's shiv lies in the dirt seven metres up the pocket, and "walk to
## your shiv" is not a place: a body standing at the cage line is looking at a dark
## pocket, two sleepers and a card. This is a big warm gold arrow - unshaded, so it
## reads at any distance and in the camp's night - hanging above the item with a
## slow roll and a bob. It carries no text: the pickup already floats its own name.
##
## The scene owns where it points (`anchor_at`) and when it is shown; the bob and
## the roll are this node's own clock, so a marker never fights a physics step.

const GOLD := Color(1.0, 0.76, 0.24)
## Overall size. It is the only thing marking the spot from the cage line, so it is
## deliberately out of scale with everything around it.
const SIZE := 1.35
const HOVER := 1.7       ## metres above the point being marked
const BOB := 0.16        ## how far the arrow swings up and down
const BOB_RATE := 2.6    ## radians/second of the bob
const SPIN_RATE := 1.1   ## radians/second of the slow roll
const SCALE_PULSE := 0.06

var _base := Vector3.ZERO
var _clock := 0.0


func _ready() -> void:
	_build()
	_place()


## Point at a spot in the world. Safe to call every frame: the arrow reads its
## anchor back on its own clock.
func anchor_at(point: Vector3) -> void:
	_base = point
	_place()


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
