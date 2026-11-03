extends Node3D
## Held off-hand focus: a closed grimoire or one of the three skulls.
##
## The plain skull is cosmetic; the life and death skulls carry the kill
## refills (see `TrinketStats`), so their sockets glow to say which is which.
## Geometry faces down the weapon's -Z axis.

const Geo = preload("res://scripts/geo.gd")
const AnnointMarks = preload("res://scripts/annoint_marks.gd")

const SKULLS := ["skull", "skull_life", "skull_death"]
const SOUL := {
	"skull_life": Color("79ff9e"),
	"skull_death": Color("b98bff"),
}

var focus_kind := "tome"
## The altar's work on this copy: runes on a tome's cover, brands around a skull,
## one per annointment and brighter with each.
var annoint_tier := 0
var _annoint_glyphs := 0

func _ready() -> void:
	_build()


## The altar's record of this copy. Only a change of rung rebuilds the piece.
func set_annoint_marks(value: int) -> void:
	var wanted := AnnointMarks.tier_of(value)
	if wanted == annoint_tier and get_child_count() > 0:
		return
	annoint_tier = wanted
	_build()


func annoint_glyphs() -> int:
	return _annoint_glyphs


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if focus_kind in SKULLS:
		_build_skull()
	else:
		_build_tome()

func _build_tome() -> void:
	var cover := Geo.material(Color("4a2420"))
	var pages := Geo.material(Color("e6d9ba"))
	var gold := Geo.material(Color("c19a55"),0.7,0.35)
	Geo.box(self,Vector3(0.17,0.040,0.23),Vector3(0,0.010,-0.20),cover)
	Geo.box(self,Vector3(0.150,0.030,0.205),Vector3(0,0.032,-0.20),pages)
	Geo.box(self,Vector3(0.160,0.014,0.21),Vector3(0,0.050,-0.20),cover)
	Geo.box(self,Vector3(0.022,0.062,0.235),Vector3(-0.083,0.020,-0.20),gold)
	Geo.box(self,Vector3(0.055,0.012,0.055),Vector3(0.035,0.058,-0.29),gold)
	# A worked grimoire is inscribed across its cover, not on its spine.
	_annoint_glyphs = AnnointMarks.blade(self,Vector3(0.010,0.0585,-0.115),
		0.15,0.13,0.0004,annoint_tier)

func _build_skull() -> void:
	var bone := Geo.material(Color("d9cdb0"),0.05,0.55)
	var dark := Geo.material(Color("1d1915"))
	var soul: Color = SOUL.get(focus_kind, Color(0,0,0,0))
	Geo.sphere(self,0.080,Vector3(0,0.01,-0.19),bone,Vector3(0.95,1.0,1.0))
	Geo.box(self,Vector3(0.085,0.050,0.070),Vector3(0,0.06,-0.16),bone)
	Geo.box(self,Vector3(0.070,0.055,0.060),Vector3(0,0.02,-0.12),bone)
	for side in [-1,1]:
		Geo.sphere(self,0.020,Vector3(0.030*side,0.015,-0.255),dark)
		if SOUL.has(focus_kind):
			Geo.sphere(self,0.013,Vector3(0.030*side,0.016,-0.258),_soul_material(soul))
	Geo.box(self,Vector3(0.075,0.018,0.030),Vector3(0,0.075,-0.245),dark)
	Geo.cylinder(self,0.022,0.022,0.09,Vector3(0,0.10,-0.19),bone,8).rotation.x = PI*0.5
	if SOUL.has(focus_kind):
		Geo.sphere(self,0.016,Vector3(0,0.062,-0.252),_soul_material(soul))
	# The altar's ward is set on the bone itself, walked over the front of the
	# cranium: a caged skull reads as a prop, a marked one as a relic.
	_annoint_glyphs = AnnointMarks.sphere_marks(self,Vector3(0.0,0.010,-0.190),
		0.080,annoint_tier,Vector3.FORWARD)

func _soul_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.6
	return mat
