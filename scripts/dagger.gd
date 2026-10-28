extends Node3D
## Slim close-range dagger. Same socket axis as the swords: blade along -Z.
## ``dagger_kind`` picks the object: forged iron at index 0, the whittled
## ironwood shiv of the makeshift tier at index 1.

const Geo = preload("res://scripts/geo.gd")
var blade_length := 0.34
var dagger_kind := 0


func _ready() -> void:
	_build()


func set_dagger_kind(kind: int) -> void:
	if kind == dagger_kind and get_child_count() > 0:
		return
	dagger_kind = kind
	_build()


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _build() -> void:
	_clear()
	if dagger_kind >= 1:
		_build_ironwood()
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

## A split ironwood stave whittled to a point: the makeshift tier's shank. Dark,
## dense, fire-hardened at the tip, bound in gut over a rag grip, and crooked
## because nothing in the wood was straight to begin with. The shaft runs from
## the grip's far end to the shoulder of the point with no seam between them.
func _build_ironwood() -> void:
	var wood := Geo.material(Color("33251a"), 0.0, 0.92)
	var wood_light := Geo.material(Color("6a4c30"), 0.0, 0.88)
	var char := Geo.material(Color("171310"), 0.0, 0.98)
	var gut := Geo.material(Color("a89066"), 0.0, 0.86)
	var rag := Geo.material(Color("4a3c2c"), 0.0, 0.94)
	var tip := -maxf(blade_length, 0.22)
	var shoulder := tip * 0.62
	# The shank: one tapered, slightly bent length of ironwood.
	var shaft := Geo.cylinder(self, 0.0165, 0.0090, absf(shoulder) + 0.055,
		Vector3(0.003, 0.002, (shoulder + 0.055) * 0.5), wood, 7)
	shaft.name = "Blade"
	shaft.rotation.x = PI / 2.0
	shaft.rotation.z = 0.05
	# The point: fire-blackened, tapered off the same crooked line.
	var point := Geo.cylinder(self, 0.0090, 0.0, absf(tip - shoulder),
		Vector3(0.005, 0.003, (tip + shoulder) * 0.5 - 0.004), char, 5)
	point.rotation.x = PI / 2.0
	point.rotation.z = 0.07
	point.scale.z = 0.45
	# Whittle scars down one face, and the pale wood they expose.
	for index in 3:
		var scar := Geo.box(self, Vector3(0.005, 0.003, 0.048),
			Vector3(-0.0075, 0.0012, shoulder * (0.22 + 0.26 * float(index))), wood_light)
		scar.rotation.x = 0.18 - index * 0.12
		scar.rotation.y = 0.2 - index * 0.15
	# Rag grip, gut wraps over it, and a swollen butt knot.
	var grip := Geo.cylinder(self, 0.019, 0.021, 0.115, Vector3(0.0, 0.0, 0.010), rag, 9)
	grip.rotation.x = PI / 2.0
	for index in 3:
		var coil := Geo.cylinder(self, 0.022, 0.022, 0.006,
			Vector3(0.0, 0.0, -0.034 + index * 0.038), gut, 9)
		coil.rotation.x = PI / 2.0
	Geo.sphere(self, 0.023, Vector3(0.004, 0.0, 0.072), wood_light,
		Vector3(1.0, 0.85, 1.0))
	var toggle := Geo.cylinder(self, 0.006, 0.004, 0.052, Vector3(0.016, 0.004, 0.050), gut, 5)
	toggle.rotation.z = 1.35
