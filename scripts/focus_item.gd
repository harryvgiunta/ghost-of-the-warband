extends Node3D
## Held off-hand focus: a closed grimoire or a small skull. Cosmetic only; the
## rig shows it in the left hand when the main hand is one-handed and nothing
## else owns the off slot. Geometry faces down the weapon's -Z axis.

const Geo = preload("res://scripts/geo.gd")
var focus_kind := "tome"

func _ready() -> void:
	if focus_kind == "skull":
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

func _build_skull() -> void:
	var bone := Geo.material(Color("d9cdb0"),0.05,0.55)
	var dark := Geo.material(Color("1d1915"))
	Geo.sphere(self,0.080,Vector3(0,0.01,-0.19),bone,Vector3(0.95,1.0,1.0))
	Geo.box(self,Vector3(0.085,0.050,0.070),Vector3(0,0.06,-0.16),bone)
	Geo.box(self,Vector3(0.070,0.055,0.060),Vector3(0,0.02,-0.12),bone)
	for side in [-1,1]:
		Geo.sphere(self,0.020,Vector3(0.030*side,0.015,-0.255),dark)
	Geo.box(self,Vector3(0.075,0.018,0.030),Vector3(0,0.075,-0.245),dark)
	Geo.cylinder(self,0.022,0.022,0.09,Vector3(0,0.10,-0.19),bone,8).rotation.x = PI*0.5
