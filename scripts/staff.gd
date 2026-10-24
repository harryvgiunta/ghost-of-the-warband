extends Node3D
## Procedural two-handed staff. Geometry runs down the weapon's -Z axis from
## the grip origin so the sword grip transform and blade endpoints apply
## unchanged. Kind 0 is the ember staff, kind 1 the bone staff.

const Geo = preload("res://scripts/geo.gd")
var staff_kind := 0
var blade_length := 1.75

func _ready() -> void:
	var top := -0.09
	var bottom := top-blade_length
	var middle := (top+bottom)*0.5
	if staff_kind == 0:
		var wood := Geo.material(Color("4b3524"))
		var iron := Geo.material(Color("7d7164"),0.6,0.42)
		var ember := Geo.material(Color("ff8a3c"),0.15,0.45)
		var core := Geo.material(Color("ffd27a"),0.1,0.3)
		Geo.cylinder(self,0.030,0.024,blade_length,Vector3(0,0,middle),wood,10).rotation.x = PI*0.5
		for height in [top-0.12, middle+0.34, bottom+0.20]:
			Geo.cylinder(self,0.036,0.036,0.045,Vector3(0,0,float(height)),iron,10).rotation.x = PI*0.5
		for side in [-1,1]:
			Geo.beam(self,Vector3(0,0,bottom+0.12),Vector3(0.075*side,0,bottom-0.12),0.011,iron,6)
		Geo.sphere(self,0.068,Vector3(0,0,bottom-0.03),ember,Vector3(1.0,1.0,1.35))
		Geo.sphere(self,0.040,Vector3(0,0,bottom-0.03),core)
	else:
		var bone := Geo.material(Color("d6c9a8"),0.05,0.6)
		var dark := Geo.material(Color("2a241d"))
		var wrap := Geo.material(Color("5a3b26"))
		Geo.cylinder(self,0.030,0.022,blade_length,Vector3(0,0,middle),bone,10).rotation.x = PI*0.5
		Geo.cylinder(self,0.035,0.035,0.20,Vector3(0,0,top-0.12),wrap,10).rotation.x = PI*0.5
		Geo.cylinder(self,0.033,0.033,0.05,Vector3(0,0,bottom+0.30),dark,10).rotation.x = PI*0.5
		Geo.sphere(self,0.072,Vector3(0,0,bottom-0.02),bone,Vector3(1.0,1.1,0.95))
		Geo.box(self,Vector3(0.075,0.045,0.055),Vector3(0,0.0,bottom-0.09),bone)
		for side in [-1,1]:
			Geo.sphere(self,0.018,Vector3(0.030*side,0.012,bottom-0.075),dark)
