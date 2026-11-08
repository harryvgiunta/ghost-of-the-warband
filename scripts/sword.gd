extends Node3D

## Held sword. The model family comes from ``sword_kind`` - forged steel for the
## three ranked blades, a knotted club and a whole tree limb for the makeshift
## tier - and ``skin`` overrides it for the salvage cleaver, which shares the
## short blade's index but not its look. The socket axis is shared: blade along
## -Z, grip at the origin.

const Geo = preload("res://scripts/geo.gd")
const AnnointMarks = preload("res://scripts/annoint_marks.gd")
## Which kinds are not steel by default. The catalog's `index` is the key, so a
## club is a club because it is item index 3, not because a caller said so.
const NATURAL_FAMILY := {3: "club", 4: "branch", 5: "axe"}
var blade_length := 0.8
var sword_kind := 0
var skin := ""
## How many annointments the altar welded to this copy, 0..6. The blade draws one
## inlaid mark per annointment and glows harder with each, so a worked piece is
## recognisable in the hand and on the floor.
var annoint_tier := 0
var _annoint_glyphs := 0


func _ready() -> void:
	_build()


func set_skin(value: String) -> void:
	if value == skin and get_child_count() > 0:
		return
	skin = value
	_build()


## The altar's record of this copy, pushed by the rig that draws it. Only a change
## of rung rebuilds the blade.
func set_annoint_marks(value: int) -> void:
	var wanted := AnnointMarks.tier_of(value)
	if wanted == annoint_tier and get_child_count() > 0:
		return
	annoint_tier = wanted
	_build()


## The separate marks the blade is carrying right now: one per annointment, plus
## the fuller and the rune pairs that come with them.
func annoint_glyphs() -> int:
	return _annoint_glyphs


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _build() -> void:
	_clear()
	var family := skin
	if family.is_empty():
		family = str(NATURAL_FAMILY.get(sword_kind, ""))
	match family:
		"makeshift":
			_build_makeshift()
		"club":
			_build_club()
		"branch":
			_build_branch()
		"axe":
			_build_axe()
		_:
			_build_steel()
	# Thirteen primitives are thirteen draw calls: baked into one instance with a
	# surface per material, the whole blade is four or five. Nothing on a held
	# blade moves on its own, so nothing is lost but the draws.
	Geo.bake_parts(self)


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
	# The altar's work: inlaid runes down the fuller of the forged blade.
	_annoint_glyphs = AnnointMarks.blade(self,Vector3(0,0,-0.10),
		maxf(blade_length-0.24,0.10),width,0.0175,annoint_tier)


## How far up the limb a two-handed grip sits. The hand is the node's origin, so
## this is how much butt hangs behind it.
const BRANCH_GRIP_INSET := 0.20

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
	# A worked stave is branded, not decorated: the altar's marks are burnt bands
	# around the haft where a hand holds it.
	_annoint_glyphs = AnnointMarks.rings(self,Vector3(0.006,0.003,-0.12),
		Vector3(0,0,-1),span*0.46,0.033,annoint_tier)

## A knotted length of heartwood with the root still on it: one club, two hands
## of a prisoner's strength, a head that is heavier than the haft so the swing
## reads as a swing and not a stick waved about.
func _build_club() -> void:
	var bark := Geo.material(Color("3a2b20"), 0.0, 0.94)
	var bark_light := Geo.material(Color("5c4534"), 0.0, 0.9)
	var heart := Geo.material(Color("6b4a2c"), 0.0, 0.86)
	var hide := Geo.material(Color("2b2019"), 0.0, 0.92)
	var cord := Geo.material(Color("8d7852"), 0.0, 0.88)
	var span := maxf(blade_length, 0.3)
	# The haft: thick at the knot, thin at the hand, crooked all the way down.
	var haft := Geo.cylinder(self, 0.026, 0.040, span * 0.94,
		Vector3(0.0, 0.0, -0.04 - span * 0.44), heart, 8)
	haft.name = "Blade"
	haft.rotation.x = PI / 2.0
	haft.rotation.z = 0.05
	# The root ball at the striking end: two offset masses and a stub of a
	# second root still hanging off it.
	var head := Geo.sphere(self, 0.072, Vector3(0.006, 0.004, -0.06 - span * 0.9),
		heart, Vector3(1.0, 0.86, 1.25))
	head.name = "Head"
	Geo.sphere(self, 0.048, Vector3(-0.012, 0.018, -0.02 - span * 0.86), bark_light,
		Vector3(1.0, 0.8, 1.0))
	var stub := Geo.cylinder(self, 0.020, 0.010, 0.10,
		Vector3(0.052, 0.030, -0.05 - span * 0.78), bark_light, 6)
	stub.rotation.z = -0.7
	stub.rotation.x = 0.5
	# Bark still on the haft in broken plates, and the knots the wood grew.
	for index in 4:
		var plate := Geo.cylinder(self, 0.030, 0.030, 0.045,
			Vector3(0.0, 0.0, -0.10 - index * span * 0.19), bark, 7)
		plate.rotation.x = PI / 2.0
		plate.rotation.z = 0.12 * float(index % 2) - 0.06
		var knot := Geo.sphere(self, 0.016,
			Vector3(0.020 - 0.010 * float(index % 2), 0.006, -0.13 - index * span * 0.19),
			bark_light, Vector3(1.0, 0.7, 1.0))
		knot.rotation.z = 0.4 + index
	# A hide grip, bound with the cord that used to hold somebody else's cage.
	var grip := Geo.cylinder(self, 0.030, 0.033, 0.16, Vector3(0.0, 0.0, 0.03), hide, 9)
	grip.rotation.x = PI / 2.0
	for index in 4:
		var wrap := Geo.cylinder(self, 0.033, 0.033, 0.007,
			Vector3(0.0, 0.0, -0.03 + index * 0.038), cord, 9)
		wrap.rotation.x = PI / 2.0
	Geo.sphere(self, 0.030, Vector3(0.0, 0.0, 0.112), heart, Vector3(1.0, 0.8, 1.0))
	# A worked club carries the altar's bands up its haft.
	_annoint_glyphs = AnnointMarks.rings(self,Vector3(0.0,0.0,-0.12),
		Vector3(0,0,-1),span*0.62,0.036,annoint_tier)


## A hafted axe head, lashed on with wet cord and left unpolished: the makeshift
## tier's one piece with an edge. The socket axis is the sword's - the haft runs
## down -Z from the grip, the wedge drops out of the far end, and the back of the
## head carries a stub of a spike so the whole thing reads as a tool first.
func _build_axe() -> void:
	var haft_mat := Geo.material(Color("4a3524"), 0.0, 0.93)
	var haft_light := Geo.material(Color("6b4d31"), 0.0, 0.9)
	var iron := Geo.material(Color("6d7175"), 0.55, 0.42)
	var iron_edge := Geo.material(Color("a9b1b2"), 0.72, 0.24)
	var cord := Geo.material(Color("8d7852"), 0.0, 0.88)
	var hide := Geo.material(Color("2b2019"), 0.0, 0.92)
	var span := maxf(blade_length, 0.34)
	# Haft: a straight branch, thicker at the head where the weight is.
	var haft := Geo.cylinder(self, 0.024, 0.029, span * 0.96,
		Vector3(0.0, 0.0, -0.02 - span * 0.46), haft_mat, 8)
	haft.name = "Blade"
	haft.rotation.x = PI / 2.0
	haft.rotation.z = 0.03
	# The head: a wedge that grows out of the haft on the swing side (+X here,
	# which the socket turns into the leading edge) and a blunt poll behind it.
	var head_at := Vector3(0.048, 0.0, -0.08 - span * 0.82)
	var head := Geo.box(self, Vector3(0.096, 0.052, 0.150), head_at, iron)
	head.name = "Head"
	head.rotation.z = 0.06
	# The edge itself: a thinner, brighter plate standing proud of the head.
	var edge := Geo.box(self, Vector3(0.022, 0.060, 0.164),
		head_at + Vector3(0.052, 0.0, 0.0), iron_edge)
	edge.rotation.z = 0.06
	var bevel := Geo.box(self, Vector3(0.040, 0.034, 0.170),
		head_at + Vector3(0.030, 0.0, 0.0), iron_edge)
	bevel.rotation.z = 0.06
	# A stub of a poll behind the head, and the socket collar it hangs on.
	var poll := Geo.cylinder(self, 0.026, 0.020, 0.070,
		head_at + Vector3(-0.062, 0.0, 0.0), iron, 6)
	poll.rotation.z = PI / 2.0
	var collar := Geo.cylinder(self, 0.036, 0.036, 0.052,
		head_at + Vector3(-0.030, 0.0, 0.0), iron, 8)
	collar.rotation.x = PI / 2.0
	# Wet cord across the socket, still drying, and a tail of it hanging free.
	for index in 3:
		var lash := Geo.cylinder(self, 0.034, 0.034, 0.010,
			head_at + Vector3(-0.026 + index * 0.026, 0.0, -0.004), cord, 8)
		lash.rotation.x = PI / 2.0
		lash.rotation.z = 0.10 * float(index % 2) - 0.05
	var tail := Geo.beam(self, head_at + Vector3(-0.02, -0.03, 0.0),
		head_at + Vector3(-0.02, -0.11, 0.045), 0.006, cord)
	tail.rotation.z = 0.12
	# Hide grip and a knob of the haft left bare at the butt.
	var grip := Geo.cylinder(self, 0.030, 0.032, 0.175, Vector3(0.0, 0.0, 0.03), hide, 9)
	grip.rotation.x = PI / 2.0
	Geo.sphere(self, 0.030, Vector3(0.0, 0.0, 0.118), haft_light, Vector3(1.0, 0.9, 1.0))
	_annoint_glyphs = AnnointMarks.rings(self, Vector3(0.0, 0.0, -0.10),
		Vector3(0, 0, -1), span * 0.55, 0.030, annoint_tier)


## A whole limb swung with both hands: long, bent, and heavy enough that a body
## has to load the whole torso to move it. Two segments at an angle, the broken
## stubs of the branches it grew, and a split end where it came off the tree.
func _build_branch() -> void:
	var bark := Geo.material(Color("43321f"), 0.0, 0.95)
	var bark_light := Geo.material(Color("6d4f34"), 0.0, 0.9)
	var heart := Geo.material(Color("a8834f"), 0.0, 0.82)
	var leaf := Geo.material(Color("37472c"), 0.0, 0.92)
	var cord := Geo.material(Color("8d7852"), 0.0, 0.88)
	var span := maxf(blade_length, 0.5)
	# A two-handed limb is gripped a hand's width up from the butt, not at the very
	# end: the butt sticks out behind the fist the way a real branch does, and the
	# mass of the limb runs out in front of both hands.
	var holder := Node3D.new()
	holder.name = "Limb"
	holder.position = Vector3(0.0, 0.0, BRANCH_GRIP_INSET)
	add_child(holder)
	# The limb: one long crooked mass, thicker toward the far end.
	var near := Geo.cylinder(holder, 0.036, 0.050, span * 0.52,
		Vector3(0.0, 0.0, -0.02 - span * 0.24), bark, 9)
	near.name = "Blade"
	near.rotation.x = PI / 2.0
	near.rotation.z = 0.04
	var far := Geo.cylinder(holder, 0.050, 0.034, span * 0.46,
		Vector3(0.030, 0.014, -0.05 - span * 0.68), bark, 9)
	far.rotation.x = PI / 2.0
	far.rotation.z = 0.10
	# The split end where it came off the trunk.
	var split := Geo.box(holder, Vector3(0.082, 0.036, 0.080),
		Vector3(0.052, 0.020, -0.02 - span * 0.94), heart)
	split.rotation.y = 0.24
	split.rotation.z = 0.16
	# Branch stubs: the limb is not a pole, it is a limb.
	for index in 3:
		var root := Vector3(0.028 - 0.01 * float(index), 0.012,
			-0.16 - float(index) * span * 0.22)
		var stub := Geo.beam(holder, root,
			root + Vector3(0.10 * (1.0 if index % 2 == 0 else -0.8), 0.07, -0.05),
			0.022, bark_light, 6)
		stub.name = "Stub%d" % index
	# Bark plates along the whole length, and a knot the size of a fist.
	for index in 6:
		var plate := Geo.cylinder(holder, 0.046, 0.046, 0.055,
			Vector3(0.004 * float(index % 2), 0.004, -0.11 - float(index) * span * 0.14),
			bark_light, 8)
		plate.rotation.x = PI / 2.0
		plate.rotation.z = 0.1 * float(index % 3) - 0.1
	Geo.sphere(holder, 0.038, Vector3(-0.038, 0.022, -0.30 - span * 0.18), heart,
		Vector3(1.0, 0.8, 1.2))
	# Two hands: a cord wrap at each grip, and a rag tied mid-shaft.
	for at in [0.02, -0.10 - span * 0.16]:
		var wrap := Geo.cylinder(holder, 0.036, 0.036, 0.10,
			Vector3(0.0, 0.0, at), cord, 9)
		wrap.rotation.x = PI / 2.0
	var rag := Geo.box(holder, Vector3(0.010, 0.085, 0.030),
		Vector3(-0.040, -0.030, -0.44 - span * 0.10), leaf)
	rag.rotation.z = 0.5
	rag.rotation.y = 0.3
	# The altar's bands run up the limb itself, past the second hand.
	_annoint_glyphs = AnnointMarks.rings(holder,Vector3(0.006,0.004,-0.14),
		Vector3(0.0,0.02,-1),span*0.70,0.050,annoint_tier)
