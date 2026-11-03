extends RefCounted
## What the altar leaves on a piece of steel.
##
## An annointment is welded to one copy, and a player has to be able to *see* it
## from the far side of the field: a plain blade is plain, and every rung after
## that adds another inlaid mark and another step of glow. So the count drives
## both the drawing and the light - `glyph_count` marks burn at `energy`, and the
## colour walks from the altar's own ember to a hot bone-white as the piece fills
## up. Six is `AnnointCatalog.MAX_PER_PIECE`.
##
## Every caller builds these before its own bake, so a worked blade is still one
## draw call per material: the marks share a single emissive material.

const Geo = preload("res://scripts/geo.gd")

const TIERS := 6
## One annointment burns altar-orange; a full piece is nearly white.
const COLD := Color("ff8a2a")
const HOT := Color("ffd9a8")
## The ink the inlay sits on, so a lit mark reads as a line cut into the metal
## rather than a painted stripe.
const INK := Color("1b1310")
## Emission energy per tier. The compatibility renderer has no bloom, so the
## numbers climb further than a glow pass would need: this is brightness, drawn.
## They stop short of white-out, or the top rung would read as bare metal.
const ENERGY := [0.0, 0.45, 0.55, 0.66, 0.79, 0.94, 1.10]


static func tier_of(value: int) -> int:
	return clampi(value, 0, TIERS)


## The marks a piece at this rung carries: one per annointment, and never none
## once it has been to the altar.
static func glyph_count(tier: int) -> int:
	return tier_of(tier)


static func color_for(tier: int) -> Color:
	var step := float(tier_of(tier)) / float(TIERS)
	return COLD.lerp(HOT, step)


static func energy_for(tier: int) -> float:
	return float(ENERGY[tier_of(tier)])


## The one material a piece's marks share. A plain piece answers null: nothing is
## drawn and no surface is added.
static func material_for(tier: int) -> StandardMaterial3D:
	if tier_of(tier) <= 0:
		return null
	var result := StandardMaterial3D.new()
	# The inlay is not black ink lit from inside: it is the altar's colour sitting
	# in the metal, so the hue survives when the piece is in the shade.
	result.albedo_color = INK.lerp(color_for(tier),0.55)
	result.metallic = 0.35
	result.roughness = 0.42
	result.emission_enabled = true
	result.emission = color_for(tier)
	result.emission_energy_multiplier = energy_for(tier)
	return result


## Runes on a blade's two faces: one chevron per annointment marching down the
## fuller over a lit channel, plus edge lines once the piece is worked past half.
## `guard` is where the blade starts in the weapon's own frame, `span` how much
## steel there is to work, `width` the blade's face and `thickness` its
## half-thickness. Returns the number of separate marks, which is what a caller
## can assert on.
static func blade(host: Node3D, guard: Vector3, span: float, width: float,
		thickness: float, tier: int) -> int:
	var material := material_for(tier)
	if material == null or span <= 0.02:
		return 0
	var count := glyph_count(tier)
	var marks := 0
	# Fixed spacing, so a higher rung reaches further down the steel instead of
	# clamping the whole inscription into the first hand's width.
	var spacing := minf(span*0.09,0.075)
	var channel := 0.05+spacing*float(count)
	var edge := width*0.40
	for face in [-1.0, 1.0]:
		var y: float = guard.y+face*(thickness+0.0006)
		Geo.box(host,Vector3(maxf(width*0.10,0.004),0.0022,channel),
			Vector3(guard.x,y,guard.z-channel*0.5-0.010),material)
		marks += 1
		if count >= 4:
			# A full piece is lit along both edges as well: at a stride the runes
			# are two pixels wide and the edges are what carry the read.
			for side in [-1.0, 1.0]:
				Geo.box(host,Vector3(0.0028,0.0020,span*0.86),
					Vector3(guard.x+side*edge,y,guard.z-span*0.45),material)
			marks += 1
	for index in count:
		var z := guard.z-0.055-spacing*(float(index)+0.5)
		for face in [-1.0, 1.0]:
			var y: float = guard.y+face*(thickness+0.0009)
			for side in [-1.0, 1.0]:
				var bar := Geo.box(host,
					Vector3(maxf(width*0.07,0.004),0.0024,minf(spacing*0.58,0.026)),
					Vector3(guard.x+side*width*0.10,y,z),material)
				bar.rotation.y = side*0.58
			marks += 1
	return marks


## Bands around a haft, shaft or limb: one ring per annointment. `start` is the
## first point along the piece and `direction` its axis, so a crooked branch only
## has to state where its workable length begins and which way it runs.
static func rings(host: Node3D, start: Vector3, direction: Vector3, span: float,
		radius: float, tier: int) -> int:
	var material := material_for(tier)
	if material == null or span <= 0.02 or direction.length_squared() < 0.000001:
		return 0
	var axis := direction.normalized()
	var count := glyph_count(tier)
	# The rings start near the hand and march up the piece, closing ranks as the
	# count rises so the work stays on the object at every rung.
	var from := span*0.16
	var to := span*0.86
	var step := (to-from)/maxf(float(count),1.0)
	# A band that only matches the shaft is a hairline of light seen edge-on. It
	# stands a little proud of the wood or the steel, like a collar hammered on.
	var band_radius := radius*1.14
	for index in count:
		var at := start+axis*(from+step*(float(index)+0.5))
		var band := Geo.cylinder(host,band_radius,band_radius,0.016,Vector3.ZERO,material,10)
		Geo.place_beam(band,at-axis*0.008,at+axis*0.008)
	return count


## Marks burnt onto a round boss or a skull: one per annointment, walked over the
## front of the sphere on the golden angle so they sit on the bone instead of
## floating in front of it.
static func sphere_marks(host: Node3D, centre: Vector3, radius: float, tier: int,
		front: Vector3 = Vector3.BACK) -> int:
	var material := material_for(tier)
	if material == null or radius <= 0.01:
		return 0
	var axis := front.normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var count := glyph_count(tier)
	for index in count:
		var spread := sqrt((float(index)+0.5)/float(count))*0.95
		var turn := float(index)*2.39996
		var direction := (axis*cos(spread)+side*sin(spread)*cos(turn)
			+up*sin(spread)*sin(turn)).normalized()
		Geo.sphere(host,minf(0.011,radius*0.14),centre+direction*radius*1.03,material,
			Vector3(1.0,1.0,0.45))
	return count


## Studs around a face - a shield's rim or a skull's socket ring: one per
## annointment, set on a ring, with a lit band once the piece is worked past half.
static func studs(host: Node3D, radius: float, face_z: float, tier: int) -> int:
	var material := material_for(tier)
	if material == null or radius <= 0.01:
		return 0
	var count := glyph_count(tier)
	var ring_radius := radius*0.66
	for index in count:
		var angle := TAU*float(index)/float(count)-PI*0.5
		Geo.sphere(host,minf(0.018,radius*0.05),
			Vector3(cos(angle)*ring_radius,sin(angle)*ring_radius,face_z),material,
			Vector3(1.0,1.0,0.55))
	if count >= 4:
		# A worked piece is ringed: the ward runs right round the face instead of
		# stopping at the studs.
		var ring := TorusMesh.new()
		ring.inner_radius = radius*0.94
		ring.outer_radius = radius*1.0
		ring.rings = 24
		ring.ring_segments = 6
		var hoop := Geo.mesh_node(host,ring,material,Vector3(0.0,0.0,face_z))
		hoop.rotation.x = PI*0.5
		hoop.scale.z = 0.45
	return count
