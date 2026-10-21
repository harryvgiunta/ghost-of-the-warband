extends Node3D

const Geo = preload("res://scripts/geo.gd")
var blade_length := 0.8
var sword_kind := 0

func _ready() -> void:
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
