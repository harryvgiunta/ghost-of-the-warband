extends Node3D

const Geo = preload("res://scripts/geo.gd")
const LIMIT := 32.0
var spawn_points: Array[Vector3] = [Vector3(-22, 0, -22), Vector3(22, 0, 22), Vector3(-22, 0, 22), Vector3(22, 0, -22)]

func _ready() -> void:
	var grass := Geo.material(Color("7b8b60"))
	var wood := Geo.material(Color("68533e"))
	var stone := Geo.material(Color("7d8982"))
	_solid_box(Vector3(66, 0.6, 66), Vector3(0, -0.3, 0), grass)
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(66, 1.4, 0.7), Vector3(0, 0.7, side * 32.5), stone)
		_solid_box(Vector3(0.7, 1.4, 64), Vector3(side * 32.5, 0.7, 0), stone)
		for index in 17:
			Geo.box(self, Vector3(0.3, 2.1, 0.3), Vector3(-32 + index * 4, 1.05, side * 32.5), wood)
	var colors := [Color("70c4cb"), Color("e4a75f"), Color("bfa1dc"), Color("86c48a")]
	for index in 4:
		Geo.cylinder(self, 2, 2, 0.025, spawn_points[index] + Vector3(0, 0.012, 0), Geo.material(colors[index].darkened(0.3)), 32)
		var label := Label3D.new()
		label.text = str(index + 1)
		label.position = spawn_points[index] + Vector3(0, 0.04, 0)
		label.rotation.x = -PI / 2
		label.font_size = 90
		label.pixel_size = 0.014
		add_child(label)
	# Existing centre cover stays where the combat regressions expect it; the
	# expanded flanks add new sight lines, trees and stone islands.
	var tree_locations := [
		Vector3(-9,0,-7), Vector3(9,0,7), Vector3(-8,0,9), Vector3(8,0,-9), Vector3(-18,0,1), Vector3(18,0,-1),
		Vector3(-24,0,8), Vector3(24,0,-8), Vector3(-12,0,-24), Vector3(12,0,24),
		Vector3(-28,0,-4), Vector3(28,0,4), Vector3(0,0,27), Vector3(0,0,-27),
	]
	for location: Vector3 in tree_locations:
		var trunk := StaticBody3D.new()
		trunk.position = location
		trunk.collision_layer = 1
		trunk.collision_mask = 0
		add_child(trunk)
		Geo.cylinder(trunk, 0.55, 0.35, 5.5, Vector3(0,2.75,0), wood)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.55
		shape.height = 5.5
		collision.shape = shape
		collision.position.y = 2.75
		trunk.add_child(collision)
		for tier in 3:
			Geo.cylinder(trunk, 2.3 - tier * 0.45, 0.05, 3.1, Vector3(0,4.6 + tier * 1.2,0), Geo.material(Color("4d735c").lightened(tier * 0.07)), 7)
	var cover_boxes := [
		Vector3(-11,0,2), Vector3(11,0,-2), Vector3(0,0,-13), Vector3(0,0,13),
		Vector3(-20,0,-6), Vector3(20,0,6), Vector3(-6,0,20), Vector3(6,0,-20),
		Vector3(-26,0,18), Vector3(26,0,-18),
	]
	for location: Vector3 in cover_boxes:
		_solid_box(Vector3(3.2, 1.4, 1.5), location + Vector3(0,0.7,0), stone)
		Geo.box(self, Vector3(3.35,0.12,1.65), location + Vector3(0,1.42,0), wood)
	# Bound the expanded field visually without adding a second floor collider.
	Geo.box(self,Vector3(180,0.3,180),Vector3(0,-0.65,0),grass)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("789fab")
	sky_material.sky_horizon_color = Color("dbd7bd")
	sky_material.ground_bottom_color = Color("637057")
	sky_material.ground_horizon_color = Color("c5cbb2")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bdcbd0")
	environment.ambient_light_energy = 0.45
	var lighting := WorldEnvironment.new()
	lighting.environment = environment
	add_child(lighting)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.light_color = Color("ffe4bf")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

func _solid_box(dimensions: Vector3, point: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	Geo.box(body, dimensions, Vector3.ZERO, material)
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
