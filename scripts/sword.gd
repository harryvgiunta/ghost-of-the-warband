extends Node3D

## Held sword. ``skin`` selects the model family: forged steel, or the salvage
## "Makeshift" cleaver the forest creatures' own gear is built from. The socket
## axis is shared: blade along -Z, grip at the origin.

const Geo = preload("res://scripts/geo.gd")
var blade_length := 0.8
var sword_kind := 0
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
		_build_steel()


func _build_steel() -> void:
	var steel := Geo.material(Color("b9cbd0"),0.75,0.28)
	var edge := Geo.material(Color("e1e9e8"),0.85,0.18)
	var gold := Geo.material(Color("c59b5a"),0.65,0.35)
	var leather := Geo.material(Color("41332b"))
	var width := 0.09 + sword_kind * 0.022
	var blade := Geo.box(self,Vector3(width,0.035,blade_length-0.18),Vector3(0,0,-0.09-(blade_length-0.18)*0.5),steel)
	blade.name = "Blade"
	Geo.box(self,Vector3(width*0.20,0.045,blade_length-0.21),Vector3(0,0,-0.09-(blade_length-0.21)*0.5),edge)
	var point := Geo.cylinder(self,width*0.65,0,0.20,Vector3(0,0,-blade_length+0.01),steel,4)
	point.rotation.x = -PI/2
	point.scale.z = 0.28
	Geo.box(self,Vector3(0.32+sword_kind*0.07,0.06,0.065),Vector3(0,0,-0.075),gold)
	var grip_length := 0.31 if sword_kind == 2 else 0.19
	var handle := Geo.cylinder(self,0.028,0.028,grip_length,Vector3(0,0,-0.04+grip_length*0.5),leather,10)
	handle.rotation.x = PI/2
	for index in 6:
		var binding := Geo.cylinder(self,0.030,0.030,0.008,Vector3(0,0,-0.025+index*(grip_length-0.03)/5.0),gold,10)
		binding.rotation.x=PI/2
	Geo.sphere(self,0.043,Vector3(0,0,grip_length-0.02),gold)


## A split branch hafted with a knapped flint edge, lashed in sinew. Every part
## is deliberately crooked: nothing here was cut square.
func _build_makeshift() -> void:
	var bark := Geo.material(Color("2e2019"),0.0,0.92)
	var bark_light := Geo.material(Color("4a352a"),0.0,0.88)
	var flint := Geo.material(Color("6d6f70"),0.18,0.55)
	var flint_edge := Geo.material(Color("9aa0a0"),0.22,0.42)
	var sinew := Geo.material(Color("8d7852"),0.0,0.86)
	var hide := Geo.material(Color("4c3a2c"),0.0,0.9)
	var span := maxf(blade_length - 0.16, 0.22)
	# Haft: two overlapping crooked lengths of branch, not one straight shaft.
	var haft := Geo.cylinder(self,0.024,0.030,span*0.62,Vector3(0.004,0.002,-0.02),bark,7)
	haft.rotation.x = PI/2.0
	haft.rotation.z = 0.06
	var haft_tip := Geo.cylinder(self,0.030,0.022,0.10,Vector3(0.012,0.004,-0.04-span*0.31),bark,7)
	haft_tip.rotation.x = PI/2.0
	haft_tip.rotation.z = 0.10
	# Flint head: a wide knapped wedge with a chipped edge and a broken shoulder.
	var head_span := span * 0.52
	var head := Geo.box(self,Vector3(0.088,0.020,head_span),Vector3(0.012,0.004,-0.10-head_span*0.5),flint)
	head.name = "Blade"
	head.rotation.y = 0.03
	Geo.box(self,Vector3(0.020,0.024,head_span*0.92),Vector3(-0.032,0.004,-0.11-head_span*0.46),flint_edge)
	for index in 3:
		var facet := Geo.box(self,Vector3(0.030,0.006,0.045),
			Vector3(0.030 - index * 0.022,0.012,-0.13 - index * head_span * 0.16),flint_edge)
		facet.rotation.y = 0.18 - index * 0.16
		facet.rotation.z = 0.10
	var point := Geo.cylinder(self,0.042,0.0,0.16,Vector3(0.012,0.004,-0.10-head_span),flint,4)
	point.rotation.x = -PI/2.0
	point.scale.z = 0.34
	# Sinew lashing where the head is bound onto the haft.
	for index in 4:
		var wrap := Geo.cylinder(self,0.034,0.034,0.012,
			Vector3(0.010,0.003,-0.085 - index * 0.017),sinew,8)
		wrap.rotation.x = PI/2.0
		wrap.rotation.z = 0.14 * (index % 2) - 0.07
	# Hide grip, thicker than a forged one, with a bone knuckle pommel.
	var grip := Geo.cylinder(self,0.030,0.034,0.185,Vector3(0.0,0.0,0.055),hide,9)
	grip.rotation.x = PI/2.0
	grip.rotation.z = 0.05
	Geo.sphere(self,0.036,Vector3(0.004,0.0,0.150),bark_light,Vector3(1.0,0.8,1.0))
	Geo.sphere(self,0.028,Vector3(0.004,0.0,0.178),sinew)
	# Splinters and a dangling cord at the guard.
	for index in 2:
		var splinter := Geo.box(self,Vector3(0.008,0.008,0.055),
			Vector3(-0.030 + index * 0.055,0.014,-0.055),bark_light)
		splinter.rotation.x = 0.5 - index * 0.9
		splinter.rotation.y = 0.4 + index * 0.5
