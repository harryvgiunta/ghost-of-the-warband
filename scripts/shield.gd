extends AnimatableBody3D
## Equipped round shield. The face is local -Z, so a look-at basis points the
## boss at the blocker's forward. It is a moving physical body on the shield
## layer so arrows can strike it passively, without adding a hitbox to the
## character capsule.

const Geo = preload("res://scripts/geo.gd")
const SHIELD_LAYER := 8
## The kite shield is the authored default; buckler and tower keep the same
## construction and only change the silhouette and collision radius.
const RADIUS := 0.36
const THICKNESS := 0.06
const VARIANT_RADII := [0.26, 0.36, 0.48]

var variant := 1
var _visual: Node3D
var _shape: CylinderShape3D
var _kite_spine: Node3D
var _tower_bands: Array[Node3D] = []

func _ready() -> void:
	collision_layer = SHIELD_LAYER
	collision_mask = 0
	sync_to_physics = true
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_build()
	_shape = CylinderShape3D.new()
	_shape.radius = RADIUS
	_shape.height = THICKNESS
	var collider := CollisionShape3D.new()
	collider.shape = _shape
	collider.rotation.x = PI * 0.5
	add_child(collider)
	visible = false
	set_variant(variant)
	set_active(false)

func _build() -> void:
	var wood := Geo.material(Color("5a3b26"))
	var grain := Geo.material(Color("6f4a2e"))
	var iron := Geo.material(Color("8e9a9c"),0.7,0.38)
	var boss := Geo.material(Color("b9c4c3"),0.85,0.28)
	var disc := Geo.cylinder(_visual,RADIUS,RADIUS,THICKNESS,Vector3.ZERO,wood,24)
	disc.rotation.x = PI * 0.5
	var inner := Geo.cylinder(_visual,RADIUS*0.82,RADIUS*0.82,THICKNESS+0.006,Vector3(0,0,-0.002),grain,24)
	inner.rotation.x = PI * 0.5
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS*0.9
	ring.outer_radius = RADIUS*1.04
	ring.rings = 24
	ring.ring_segments = 8
	var rim := Geo.mesh_node(_visual,ring,iron,Vector3(0,0,-0.01))
	rim.rotation.x = PI * 0.5
	Geo.box(_visual,Vector3(0.045,RADIUS*1.55,0.022),Vector3(0,0,-0.045),iron)
	Geo.box(_visual,Vector3(RADIUS*1.55,0.045,0.022),Vector3(0,0,-0.046),iron)
	Geo.sphere(_visual,0.085,Vector3(0,0,-0.062),boss,Vector3(1.0,1.0,0.55))
	Geo.cylinder(_visual,0.045,0.045,0.035,Vector3(0,0,-0.095),boss,10).rotation.x = PI * 0.5
	Geo.box(_visual,Vector3(0.08,0.26,0.05),Vector3(0,0,0.075),grain)
	# The kite keeps a long central spine; the tower adds heavy horizontal
	# bands. The buckler stays a plain small boss-faced disc.
	_kite_spine = Geo.box(_visual,Vector3(0.050,RADIUS*1.24,0.030),Vector3(0,0,-0.058),iron)
	for offset in [-0.19, 0.19]:
		_tower_bands.append(Geo.box(_visual,Vector3(RADIUS*1.62,0.055,0.032),Vector3(0,float(offset),-0.056),iron))

func set_variant(index: int) -> void:
	variant = clampi(index,0,VARIANT_RADII.size()-1)
	var target := radius()
	if _shape != null:
		_shape.radius = target
		_shape.height = THICKNESS*(target/RADIUS)
	if _visual != null:
		# The shared construction scales to the variant; thickness included.
		var factor := target/RADIUS
		_visual.scale = Vector3(factor,factor,factor)
	if _kite_spine != null:
		_kite_spine.visible = variant == 1
	for band in _tower_bands:
		band.visible = variant == 2

func radius() -> float:
	return float(VARIANT_RADII[clampi(variant,0,VARIANT_RADII.size()-1)])

func set_active(active: bool) -> void:
	visible = active
	collision_layer = SHIELD_LAYER if active else 0

func is_shield() -> bool:
	return true
