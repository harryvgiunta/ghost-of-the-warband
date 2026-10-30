extends RefCounted
## The trophies a warband body hangs on its own armour: skulls, jaws, finger
## bones, vertebrae, teeth and claws on thongs, feathers, horns, a plume, rags in
## its livery, bone beads and ankle rattles.
##
## Each builder merges its pieces into one `CampKit.Merged` (one draw call per
## material) in the trophy's own frame, which `ArmorFlair` places on a bone:
##   origin  the point on the garment it is fixed to (a ring trophy: the centre
##           of the limb or neck it circles)
##   +Y      up (a ring trophy: along the limb it circles)
##   +Z      away from the body
## Sizes are metres at the authored rig; the rig's own height scales them with
## the body. Presentation only: no collider, no gameplay.

const CampKit = preload("res://scripts/world/camp_kit.gd")
const Geo = preload("res://scripts/geo.gd")

## Every kind a builder answers, for the profile's tables and the regression.
const KINDS := ["skull", "beast_skull", "bird_skull", "jaw", "bones", "vertebrae", "teeth",
	"claws", "feathers", "rag", "spikes", "ribs", "long_bone", "beads", "rattles", "plume", "horns"]

static var _materials: Dictionary = {}


## The palette one body's trophies are made of.
static func materials(flair: Dictionary) -> Dictionary:
	return {
		"bone": _material(str(flair.get("bone", "#d9cdb0")), 0.0, 0.62),
		"ash": _material("#1b1714", 0.0, 0.95),
		"cord": _material(str(flair.get("leather", "#4a2a1a")), 0.0, 0.88),
		"horn": _material("#3a3029", 0.0, 0.42),
		"feather": _material(str(flair.get("feather", "#262220")), 0.0, 0.78),
		"field": _material(str(flair.get("field", "#7d2a20")), 0.0, 0.9),
		"charge": _material(str(flair.get("charge", "#d9cfb6")), 0.0, 0.9),
		"metal": _material(str(flair.get("fittings", "#d1b576")), 0.85, 0.32),
	}


## Shared per colour: a band of eight shares one bone white with nobody, but a
## tone is a tone, and the material cache keeps the draw state small.
static func _material(tone: String, metallic: float, roughness: float) -> StandardMaterial3D:
	var key := "%s:%.2f:%.2f" % [tone, metallic, roughness]
	if not _materials.has(key):
		_materials[key] = Geo.material(Color(tone), metallic, roughness)
	return _materials[key]


## One trophy as a merged mesh, in its own frame (origin on the garment, +Y up,
## +Z away from the body). `size` is the measured cross-section a ring trophy
## (necklace, bracelet, rattles) goes round - half width along X and half depth
## along Z - and is ignored by a hanging trophy. `side` is +1 for the body's left.
static func build(kind: String, mats: Dictionary, size: Vector2 = Vector2.ZERO,
		side: float = 1.0) -> CampKit.Merged:
	var m := CampKit.Merged.new()
	match kind:
		"skull":
			_hanger(m, mats, 0.035)
			_skull(m, mats, Vector3(0.0, -0.085, 0.034), 1.15)
		"beast_skull":
			_hanger(m, mats, 0.03)
			_beast_skull(m, mats, Vector3(0.0, -0.05, 0.036), 0.26, side > 0.0)
		"bird_skull":
			_hanger(m, mats, 0.04)
			_bird_skull(m, mats, Vector3(0.0, -0.06, 0.03))
		"jaw":
			_hanger(m, mats, 0.03)
			_jaw(m, mats, Vector3(0.0, -0.06, 0.03))
		"bones":
			_hanger(m, mats, 0.02)
			for i in 3:
				var top := Vector3(0.012 * (i - 1), -0.03 - 0.008 * absf(i - 1), 0.022)
				CampKit.add_beam(m, Vector3.ZERO, top, 0.0022, mats["cord"], 3)
				_phalanx(m, mats, top, 0.032 + 0.006 * i)
		"vertebrae":
			_hanger(m, mats, 0.02)
			for i in 4:
				_vertebra(m, mats, Vector3(0.0, -0.035 - 0.026 * i, 0.03), 1.0 - 0.08 * i)
		"teeth":
			_hanger(m, mats, 0.015)
			CampKit.add_beam(m, Vector3(-0.04, -0.03, 0.022), Vector3(0.04, -0.03, 0.022), 0.003, mats["cord"], 4)
			for i in 6:
				var x := -0.035 + 0.014 * i
				_fang(m, mats, Vector3(x, -0.032, 0.024), Vector3(0.0, -1.0, 0.12), 0.026 + 0.006 * float(i % 2))
		"claws":
			for i in 5:
				var x := -0.03 + 0.015 * i
				_claw(m, mats, Vector3(x, -0.004, 0.02), 0.034)
		"feathers":
			_hanger(m, mats, 0.015)
			for i in 3:
				var lean := (float(i) - 1.0) * 0.28
				_feather(m, mats, Vector3(0.0, -0.02, 0.026),
					Vector3(sin(lean), -cos(lean), 0.12).normalized(), 0.15 - 0.02 * absf(i - 1))
		"rag":
			_hanger(m, mats, 0.012)
			for i in 3:
				var tone := "field" if i % 2 == 0 else "charge"
				CampKit.add_box(m, Vector3(0.026, 0.17 - 0.03 * i, 0.004),
					Vector3(-0.022 + 0.022 * i, -0.095 + 0.015 * i, 0.022 + 0.004 * i), mats[tone],
					0.0, 0.05 * i, (float(i) - 1.0) * 0.16)
		"spikes":
			CampKit.add_box(m, Vector3(0.07, 0.012, 0.09), Vector3(0.0, 0.004, 0.0), mats["cord"])
			for i in 3:
				var at := Vector3(0.0, 0.008, -0.03 + 0.03 * i)
				CampKit.add_beam(m, at, at + Vector3(0.0, 0.075 - 0.012 * absf(i - 1), 0.035), 0.011,
					mats["bone"], 5, 0.0015)
		"ribs":
			for i in 3:
				var z := -0.035 + 0.035 * i
				var root := Vector3(-0.06, 0.0, z)
				var crest := Vector3(0.0, 0.03, z + 0.01)
				var tip := Vector3(0.06, 0.004, z + 0.02)
				CampKit.add_beam(m, root, crest, 0.0065, mats["bone"], 4, 0.0055)
				CampKit.add_beam(m, crest, tip, 0.0055, mats["bone"], 4, 0.003)
			CampKit.add_beam(m, Vector3(0.0, 0.032, -0.05), Vector3(0.0, 0.032, 0.06), 0.004, mats["cord"], 4)
		"long_bone":
			CampKit.add_beam(m, Vector3(0.0, 0.07, 0.022), Vector3(0.0, -0.09, 0.022), 0.0085, mats["bone"], 6)
			for end in [Vector3(0.0, 0.075, 0.022), Vector3(0.0, -0.095, 0.022)]:
				CampKit.add_ball(m, 0.0105, end + Vector3(0.006, 0.0, 0.0), mats["bone"], Vector3.ONE, 6, 4)
				CampKit.add_ball(m, 0.0105, end - Vector3(0.006, 0.0, 0.0), mats["bone"], Vector3.ONE, 6, 4)
			for y in [0.04, -0.05]:
				CampKit.add_box(m, Vector3(0.05, 0.008, 0.026), Vector3(0.0, y, 0.008), mats["cord"])
		"beads":
			_cord_ring(m, mats, size)
			for i in 9:
				var angle := TAU * float(i) / 9.0
				CampKit.add_ball(m, 0.0085, _on_ring(size, angle, 0.004),
					mats["bone"] if i % 3 else mats["metal"], Vector3.ONE, 6, 4)
		"rattles":
			_cord_ring(m, mats, size)
			for i in 7:
				_phalanx(m, mats, _on_ring(size, TAU * float(i) / 7.0 + 0.3, 0.006), 0.026)
		"plume":
			CampKit.add_beam(m, Vector3(0.0, -0.005, 0.0), Vector3(0.0, 0.035, -0.006), 0.011, mats["metal"], 6, 0.008)
			for i in 7:
				var spread := (float(i) - 3.0) * 0.07
				var lift := 0.13 + 0.02 * float(3 - absi(i - 3))
				var tip := Vector3(spread * 0.6, lift, -0.10 - 0.02 * float(3 - absi(i - 3)))
				_tuft(m, mats["field"] if i != 3 else mats["charge"], Vector3(0.0, 0.03, -0.006), tip)
		"horns":
			for s in [-1.0, 1.0]:
				var root := Vector3(0.055 * s, -0.01, -0.005)
				var mid := root + Vector3(0.06 * s, 0.035, -0.01)
				var bend := mid + Vector3(0.035 * s, 0.06, -0.035)
				var tip := bend + Vector3(-0.01 * s, 0.045, -0.05)
				CampKit.add_beam(m, root, mid, 0.017, mats["horn"], 6, 0.014)
				CampKit.add_beam(m, mid, bend, 0.014, mats["horn"], 6, 0.009)
				CampKit.add_beam(m, bend, tip, 0.009, mats["horn"], 5, 0.0015)
	return m


## Necklaces circle a measured neck; what hangs on them hangs at the front.
static func build_necklace(kind: String, mats: Dictionary, size: Vector2) -> CampKit.Merged:
	var m := CampKit.Merged.new()
	_cord_ring(m, mats, size)
	var count := 7 if kind == "teeth" else 5
	for i in count:
		var angle := PI * 0.5 + (float(i) - float(count - 1) * 0.5) * 0.24
		var at := _on_ring(size, angle, 0.004)
		var outward := _on_ring(size, angle, 0.0).normalized()
		match kind:
			"teeth":
				_fang(m, mats, at, (Vector3(0.0, -1.0, 0.0) + outward * 0.25).normalized(),
					0.024 + 0.008 * float(i % 2))
			"claws":
				_claw(m, mats, at, 0.03)
			_:
				if i == count / 2:
					_skull(m, mats, at + Vector3(0.0, -0.04, 0.0) + outward * 0.012, 0.62)
					CampKit.add_beam(m, at, at + Vector3(0.0, -0.016, 0.0), 0.0022, mats["cord"], 3)
				else:
					_phalanx(m, mats, at, 0.024)
	return m


# --- pieces -----------------------------------------------------------------

## The thong a hanging trophy is tied on with: a knot at the belt and a cord
## down and out to the trophy.
static func _hanger(m: CampKit.Merged, mats: Dictionary, length: float) -> void:
	CampKit.add_ball(m, 0.009, Vector3.ZERO, mats["cord"], Vector3(1.2, 0.8, 1.0), 6, 4)
	CampKit.add_beam(m, Vector3.ZERO, Vector3(0.0, -length, 0.026), 0.0026, mats["cord"], 4)


## A small human skull, face along +Z.
static func _skull(m: CampKit.Merged, mats: Dictionary, at: Vector3, s: float) -> void:
	var saved := m.push(Transform3D(Basis().scaled(Vector3.ONE * s), at))
	CampKit.add_ball(m, 0.042, Vector3(0.0, 0.018, -0.008), mats["bone"], Vector3(0.86, 0.94, 1.0), 10, 7)
	CampKit.add_box(m, Vector3(0.050, 0.026, 0.028), Vector3(0.0, -0.012, 0.020), mats["bone"])
	for x in [-0.022, 0.022]:
		CampKit.add_ball(m, 0.012, Vector3(x, -0.004, 0.022), mats["bone"], Vector3.ONE, 6, 4)
		CampKit.add_ball(m, 0.0115, Vector3(x * 0.7, 0.004, 0.032), mats["ash"], Vector3(1.0, 0.9, 0.55), 7, 4)
	CampKit.add_box(m, Vector3(0.009, 0.011, 0.006), Vector3(0.0, -0.011, 0.035), mats["ash"])
	CampKit.add_box(m, Vector3(0.042, 0.014, 0.026), Vector3(0.0, -0.034, 0.016), mats["bone"])
	for i in 5:
		CampKit.add_box(m, Vector3(0.0055, 0.008, 0.004), Vector3(-0.012 + 0.006 * i, -0.0255, 0.0315),
			mats["bone"])
	m.group = saved


## A beast's skull hung muzzle-down with its brow outward (the camp's own skull,
## turned so -Z points at the ground and +Y at the viewer).
static func _beast_skull(m: CampKit.Merged, mats: Dictionary, at: Vector3, s: float, horns: bool) -> void:
	var turned := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0))
	var saved := m.push(Transform3D(turned, at))
	CampKit.add_skull(m, mats, Vector3.ZERO, 0.0, s, horns)
	m.group = saved


static func _bird_skull(m: CampKit.Merged, mats: Dictionary, at: Vector3) -> void:
	CampKit.add_ball(m, 0.021, at, mats["bone"], Vector3(0.9, 1.0, 1.05), 8, 5)
	CampKit.add_beam(m, at + Vector3(0.0, -0.012, 0.012), at + Vector3(0.0, -0.075, 0.03), 0.009,
		mats["bone"], 5, 0.0012)
	for x in [-0.011, 0.011]:
		CampKit.add_ball(m, 0.007, at + Vector3(x, 0.002, 0.016), mats["ash"], Vector3.ONE, 5, 3)


## A lower jaw, chin down, teeth up.
static func _jaw(m: CampKit.Merged, mats: Dictionary, at: Vector3) -> void:
	var chin := at + Vector3(0.0, -0.025, 0.008)
	for s in [-1.0, 1.0]:
		var corner := at + Vector3(0.034 * s, -0.008, -0.004)
		var ramus := corner + Vector3(0.004 * s, 0.03, -0.006)
		CampKit.add_beam(m, chin, corner, 0.0075, mats["bone"], 5, 0.0065)
		CampKit.add_beam(m, corner, ramus, 0.0065, mats["bone"], 4, 0.004)
		for i in 3:
			var tooth := chin.lerp(corner, 0.25 + 0.25 * i) + Vector3(0.0, 0.007, 0.0)
			CampKit.add_beam(m, tooth, tooth + Vector3(0.0, 0.009, 0.0), 0.0028, mats["bone"], 4, 0.0012)
	CampKit.add_ball(m, 0.008, chin, mats["bone"], Vector3(1.4, 0.9, 1.0), 6, 4)


## One finger bone hanging from `top`: a shaft between two knuckles.
static func _phalanx(m: CampKit.Merged, mats: Dictionary, top: Vector3, length: float) -> void:
	var foot := top + Vector3(0.0, -length, 0.0)
	CampKit.add_beam(m, top, foot, 0.0042, mats["bone"], 5, 0.0036)
	CampKit.add_ball(m, 0.0058, top, mats["bone"], Vector3.ONE, 5, 3)
	CampKit.add_ball(m, 0.0052, foot, mats["bone"], Vector3.ONE, 5, 3)


static func _vertebra(m: CampKit.Merged, mats: Dictionary, at: Vector3, s: float) -> void:
	CampKit.add_beam(m, at + Vector3(0.0, 0.007 * s, 0.0), at - Vector3(0.0, 0.007 * s, 0.0), 0.016 * s,
		mats["bone"], 7)
	CampKit.add_box(m, Vector3(0.008, 0.01, 0.022) * s, at + Vector3(0.0, 0.0, 0.02 * s), mats["bone"])
	CampKit.add_box(m, Vector3(0.044, 0.006, 0.008) * s, at + Vector3(0.0, 0.0, 0.004), mats["bone"])


## A fang along `toward` from `root`.
static func _fang(m: CampKit.Merged, mats: Dictionary, root: Vector3, toward: Vector3, length: float) -> void:
	CampKit.add_beam(m, root, root + toward * length, 0.0045, mats["bone"], 5, 0.0006)


## A curved claw hanging from `root`, hooking outward.
static func _claw(m: CampKit.Merged, mats: Dictionary, root: Vector3, length: float) -> void:
	var bend := root + Vector3(0.0, -length * 0.6, 0.004)
	var tip := bend + Vector3(0.0, -length * 0.25, length * 0.35)
	CampKit.add_beam(m, root, bend, 0.0048, mats["horn"], 5, 0.0036)
	CampKit.add_beam(m, bend, tip, 0.0036, mats["horn"], 4, 0.0006)


## A feather from `root` along `toward`: a quill and a vane.
static func _feather(m: CampKit.Merged, mats: Dictionary, root: Vector3, toward: Vector3, length: float) -> void:
	var tip := root + toward * length
	CampKit.add_beam(m, root, tip, 0.0018, mats["bone"], 3)
	_oval(m, mats["feather"], root.lerp(tip, 0.58), toward, Vector3(0.016, length * 0.42, 0.0035))


## One tuft of a plume from `root` to `tip`.
static func _tuft(m: CampKit.Merged, material: Material, root: Vector3, tip: Vector3) -> void:
	var span := tip - root
	_oval(m, material, root + span * 0.55, span, Vector3(0.022, span.length() * 0.55, 0.012))


## A flattened ellipsoid centred on `at`, its long axis along `along` and its
## flat face toward +Z: a feather's vane, a tuft of horsehair.
static func _oval(m: CampKit.Merged, material: Material, at: Vector3, along: Vector3, size: Vector3) -> void:
	var up := along.normalized()
	var side := up.cross(Vector3(0.0, 0.0, 1.0))
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var saved := m.push(Transform3D(Basis(side, up, side.cross(up).normalized()), at))
	CampKit.add_ball(m, 1.0, Vector3.ZERO, material, size, 8, 5)
	m.group = saved


## One point on a ring's measured cross-section, `out` metres outside it, `angle`
## round the local +Y axis.
static func _on_ring(size: Vector2, angle: float, out: float) -> Vector3:
	return Vector3(cos(angle) * (size.x + out), 0.0, sin(angle) * (size.y + out))


## A thin cord circling the local +Y axis, following the cross-section it ties
## round: a neck is wider across than deep, and a wrist more so still, so a ring
## drawn as a circle through the body stood off it like a hoop.
static func _cord_ring(m: CampKit.Merged, mats: Dictionary, size: Vector2) -> void:
	const SEGMENTS := 20
	var previous := _on_ring(size, 0.0, 0.0015)
	for i in range(1, SEGMENTS + 1):
		var point := _on_ring(size, TAU * float(i) / float(SEGMENTS), 0.0015)
		CampKit.add_beam(m, previous, point, 0.0026, mats["cord"], 4)
		previous = point
