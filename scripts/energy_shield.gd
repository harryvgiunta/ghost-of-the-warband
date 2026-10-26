extends Node3D
## The Energy Shield ward shell: one additive sphere around the ranger, warm
## yellow at the rim.
##
## Presentation only. The absorbing share of damage and its stamina price live
## on the actor that owns the health, so a replica showing this bubble and the
## authority applying the swap cannot disagree.

const SHADER = preload("res://scripts/world/shaders/energy_shield.gdshader")

const RADIUS := 0.78
const CENTRE_Y := 1.02
const VERTICAL_STRETCH := 1.32


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.radial_segments = 28
	mesh.rings = 14
	var shell := MeshInstance3D.new()
	shell.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = SHADER
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	position = Vector3(0.0, CENTRE_Y, 0.0)
	scale = Vector3(1.0, VERTICAL_STRETCH, 1.0)
