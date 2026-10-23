extends AnimatableBody3D
## Equipped round shield. The face is local -Z, so a look-at basis points the
## boss at the blocker's forward. It is a moving physical body on the shield
## layer so arrows can strike it passively, without adding a hitbox to the
## character capsule.

const Geo = preload("res://scripts/geo.gd")
const SHIELD_LAYER := 8
const RADIUS := 0.36
const THICKNESS := 0.06

func _ready() -> void:
	collision_layer = SHIELD_LAYER
	collision_mask = 0
	sync_to_physics = true
	_build()
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = THICKNESS
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.rotation.x = PI * 0.5
	add_child(collider)
	visible = false
	set_active(false)

func _build() -> void:
	var wood := Geo.material(Color("5a3b26"))
	var grain := Geo.material(Color("6f4a2e"))
	var iron := Geo.material(Color("8e9a9c"),0.7,0.38)
	var boss := Geo.material(Color("b9c4c3"),0.85,0.28)
	var disc := Geo.cylinder(self,RADIUS,RADIUS,THICKNESS,Vector3.ZERO,wood,24)
	disc.rotation.x = PI * 0.5
	var inner := Geo.cylinder(self,RADIUS*0.82,RADIUS*0.82,THICKNESS+0.006,Vector3(0,0,-0.002),grain,24)
	inner.rotation.x = PI * 0.5
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS*0.9
	ring.outer_radius = RADIUS*1.04
	ring.rings = 24
	ring.ring_segments = 8
	var rim := Geo.mesh_node(self,ring,iron,Vector3(0,0,-0.01))
	rim.rotation.x = PI * 0.5
	Geo.box(self,Vector3(0.045,RADIUS*1.55,0.022),Vector3(0,0,-0.045),iron)
	Geo.box(self,Vector3(RADIUS*1.55,0.045,0.022),Vector3(0,0,-0.046),iron)
	Geo.sphere(self,0.085,Vector3(0,0,-0.062),boss,Vector3(1.0,1.0,0.55))
	Geo.cylinder(self,0.045,0.045,0.035,Vector3(0,0,-0.095),boss,10).rotation.x = PI * 0.5
	Geo.box(self,Vector3(0.08,0.26,0.05),Vector3(0,0,0.075),grain)

func set_active(active: bool) -> void:
	visible = active
	collision_layer = SHIELD_LAYER if active else 0

func is_shield() -> bool:
	return true
