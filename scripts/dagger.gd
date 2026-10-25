extends Node3D
## Slim close-range dagger. Same socket axis as the swords: blade along -Z.
## ``skin == "makeshift"`` swaps the iron blade for a ground bone shiv.

const Geo = preload("res://scripts/geo.gd")
var blade_length := 0.34
var skin := ""


func _ready() -> void:
	_build()


func set_skin(value: String) -> void:
	if value == skin and get_child_count() > 0:
		return
	skin = value
	_build()


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _build() -> void:
	_clear()
	if skin == "makeshift":
		_build_makeshift()
	else:
		_build_iron()


func _build_iron() -> void:
	var steel := Geo.material(Color("b6c8ce"),0.78,0.24)
	var edge := Geo.material(Color("eef3f2"),0.88,0.14)
	var brass := Geo.material(Color("c59b5a"),0.68,0.32)
	var leather := Geo.material(Color("3b2e26"))
	var span := maxf(blade_length-0.12,0.10)
	var blade := Geo.box(self,Vector3(0.032,0.011,span),Vector3(0,0,-0.09-span*0.5),steel)
	blade.name = "Blade"
	Geo.box(self,Vector3(0.009,0.015,span*0.92),Vector3(0,0,-0.09-span*0.46),edge)
	for side in [-1.0,1.0]:
		Geo.box(self,Vector3(0.006,0.0025,span*0.84),Vector3(side*0.015,0.0045,-0.09-span*0.43),edge)
	var point := Geo.cylinder(self,0.017,0.0,0.20,Vector3(0,0,-blade_length+0.01),steel,4)
	point.rotation.x = -PI/2.0
	point.scale.z = 0.20
	Geo.box(self,Vector3(0.132,0.024,0.022),Vector3(0,0,-0.073),brass)
	for side in [-1.0,1.0]:
		Geo.box(self,Vector3(0.026,0.030,0.018),Vector3(side*0.064,0,-0.066),brass)
	var handle := Geo.cylinder(self,0.017,0.019,0.115,Vector3(0,0,0.0175),leather,10)
	handle.rotation.x = PI/2.0
	for index in 4:
		var binding := Geo.cylinder(self,0.019,0.019,0.006,Vector3(0,0,-0.026+index*0.026),brass,10)
		binding.rotation.x = PI/2.0
	Geo.sphere(self,0.027,Vector3(0,0,0.086),brass)


## A snapped rib ground to a point: pale, slightly curved, wrapped in hide and
## twine, with a chipped stone tied at the guard.
func _build_makeshift() -> void:
	var bone := Geo.material(Color("bdae92"),0.0,0.62)
	var bone_dark := Geo.material(Color("8b7a60"),0.0,0.72)
	var hide := Geo.material(Color("453427"),0.0,0.9)
	var twine := Geo.material(Color("8d7852"),0.0,0.86)
	var stone := Geo.material(Color("5d6064"),0.15,0.6)
	var span := maxf(blade_length-0.11,0.10)
	var shaft := Geo.cylinder(self,0.0135,0.0085,span,Vector3(0.002,0.0,-0.075-span*0.5),bone,8)
	shaft.name = "Blade"
	shaft.rotation.x = PI/2.0
	shaft.rotation.z = 0.03
	# Ground edge: a flat facet ground down one side.
	var facet := Geo.box(self,Vector3(0.007,0.004,span*0.86),
		Vector3(-0.008,0.0,-0.082-span*0.44),bone_dark)
	facet.rotation.z = 0.06
	var point := Geo.cylinder(self,0.0085,0.0,0.15,Vector3(0.002,0.0,-0.075-span),bone,5)
	point.rotation.x = -PI/2.0
	point.scale.z = 0.35
	# Hide wrap over a knuckle-sized grip.
	var grip := Geo.cylinder(self,0.017,0.020,0.115,Vector3(0.0,0.0,0.012),hide,9)
	grip.rotation.x = PI/2.0
	for index in 3:
		var coil := Geo.cylinder(self,0.021,0.021,0.005,
			Vector3(0.0,0.0,-0.040 + index * 0.038),twine,9)
		coil.rotation.x = PI/2.0
	Geo.sphere(self,0.020,Vector3(0.0,0.0,0.074),bone,Vector3(1.0,1.0,0.8))
	# Chip of stone tied on as a counterweight.
	var chip := Geo.box(self,Vector3(0.016,0.020,0.026),Vector3(0.020,0.006,-0.052),stone)
	chip.rotation.y = 0.5
	chip.rotation.z = 0.3
	var tie := Geo.cylinder(self,0.004,0.004,0.030,Vector3(0.010,0.004,-0.052),twine,6)
	tie.rotation.x = PI/2.0
	tie.rotation.z = 1.2
