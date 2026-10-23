class_name GrassField
extends RefCounted
## Deterministic grass, flower and fern fields.
##
## Clumps are three cross-fanned alpha cards from the ground-cover atlases and
## are batched through WorldScatter (one MultiMesh per chunk, per clump variant),
## so there is no per-frame script and camera-distance chunk culling is free.
## Shader fade ends exactly at the chunk visibility range to avoid pops.
##
## `ground(Vector2) -> Vector3` samples the terrain; `reserved(Vector2) -> bool`
## rejects roads, water, buildings and gameplay clearings. Placement is centred
## on the parent's XZ position, so a scene can build a local meadow by moving the
## parent, or one world-wide field by leaving it at the origin.

const MAX_ATTEMPTS_PER_INSTANCE := 8
const SLOPE_SAMPLE := 0.65


static func build(parent: Node3D, style: WorldStyle, ground: Callable, reserved: Callable, seed: int) -> Dictionary:
	var counts := {"grass": 0, "flowers": 0, "ferns": 0, "chunks": 0}
	if parent == null or style == null or not ground.is_valid():
		return counts
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Support building before the parent enters the tree (headless tests, tools).
	var origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var center := Vector2(origin.x, origin.z)

	var grass_cfg: Dictionary = style.grass
	var grass_instances := _collect(rng, grass_cfg, center, ground, reserved)
	if not grass_instances.is_empty():
		var variant_count := maxi(1, int(grass_cfg.get("clump_variants", 3)))
		var variant_instances: Array = []
		for variant in range(variant_count):
			variant_instances.append([] as Array[Dictionary])
		for index in range(grass_instances.size()):
			(variant_instances[index % variant_count] as Array[Dictionary]).append(grass_instances[index])
		var range_end := float(grass_cfg.get("range", 72.0))
		var material := _fading_material(TextureLibrary.grass_material(), String(grass_cfg.get("texture", "grass_meadow")), range_end)
		var chunk_size := float(grass_cfg.get("chunk_size", 16.0))
		for variant in range(variant_count):
			var instances: Array[Dictionary] = variant_instances[variant]
			if instances.is_empty():
				continue
			var mesh := _clump_mesh(String(grass_cfg.get("texture", "grass_meadow")), variant, 3, 0.55, 0.52, 0.16)
			counts["chunks"] += WorldScatter.batch(parent, "Grass_%d" % variant, mesh, material,
				instances, chunk_size, {"visible_end": range_end, "cast_shadow": false})
		counts["grass"] = grass_instances.size()

	var flowers_cfg: Dictionary = style.ground_cover.get("flowers", {})
	var flower_instances := _collect(rng, flowers_cfg, center, ground, reserved)
	if not flower_instances.is_empty():
		var range_end := float(flowers_cfg.get("range", 60.0))
		var material := _fading_material(TextureLibrary.flower_material(), String(flowers_cfg.get("texture", "flowers")), range_end)
		var mesh := _clump_mesh(String(flowers_cfg.get("texture", "flowers")), 0, 3, 0.36, 0.4, 0.18)
		counts["chunks"] += WorldScatter.batch(parent, "Flowers", mesh, material,
			flower_instances, float(flowers_cfg.get("chunk_size", 16.0)),
			{"visible_end": range_end, "cast_shadow": false})
		counts["flowers"] = flower_instances.size()

	var fern_cfg: Dictionary = style.ground_cover.get("ferns", {})
	var fern_instances := _collect(rng, fern_cfg, center, ground, reserved)
	if not fern_instances.is_empty():
		var range_end := float(fern_cfg.get("range", 54.0))
		var material := _fading_material(TextureLibrary.fern_material(), String(fern_cfg.get("texture", "fern")), range_end)
		var mesh := _clump_mesh(String(fern_cfg.get("texture", "fern")), 1, 3, 0.95, 0.5, 0.85)
		counts["chunks"] += WorldScatter.batch(parent, "Ferns", mesh, material,
			fern_instances, float(fern_cfg.get("chunk_size", 16.0)),
			{"visible_end": range_end, "cast_shadow": false})
		counts["ferns"] = fern_instances.size()

	return counts


## Samples up to `count` accepted positions. Rejection: reserved areas, invalid
## ground, height range, slope above `max_slope`, and the near/far density curve.
static func _collect(rng: RandomNumberGenerator, cfg: Dictionary, center: Vector2,
		ground: Callable, reserved: Callable) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var target := int(cfg.get("count", 0))
	if target <= 0:
		return result
	var radius := maxf(1.0, float(cfg.get("radius", 110.0)))
	var tints: Array = cfg.get("tints", [])
	var shade_tint: Color = cfg.get("shade_tint", Color("6f8b4e"))
	var scale_range: Vector2 = cfg.get("scale", Vector2(0.8, 1.3))
	var falloff: Vector2 = cfg.get("density_falloff", Vector2(1.0, 0.55))
	var max_slope := float(cfg.get("max_slope", 30.0))
	var height_range: Vector2 = cfg.get("height_range", Vector2(-1000.0, 4000.0))
	var attempts := target * MAX_ATTEMPTS_PER_INSTANCE
	while result.size() < target and attempts > 0:
		attempts -= 1
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * radius
		var point := center + Vector2(cos(angle), sin(angle)) * distance
		var position: Vector3 = ground.call(point)
		if not position.is_finite():
			continue
		if position.y < height_range.x or position.y > height_range.y:
			continue
		if reserved.is_valid() and bool(reserved.call(point)):
			continue
		# Normalised radial distance: denser near the build centre, thinner out
		# at world edge. Scenes tune this with `density_falloff`.
		var radial := clampf(distance / radius, 0.0, 1.0)
		var density := lerpf(falloff.x, falloff.y, smoothstep(0.35, 1.0, radial))
		if rng.randf() > density:
			continue
		if _slope_degrees(ground, point) > max_slope:
			continue
		var tint := Color.WHITE
		if not tints.is_empty():
			tint = _colour(tints[rng.randi_range(0, tints.size() - 1)], Color.WHITE)
			tint = tint.lerp(shade_tint, rng.randf_range(0.0, 0.32))
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.1, 0.1))
		basis = basis * Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.1))
		var size := rng.randf_range(scale_range.x, scale_range.y)
		basis = basis * Basis.IDENTITY.scaled(Vector3(size, size * rng.randf_range(0.85, 1.2), size))
		result.append({
			"transform": Transform3D(basis, position),
			"color": tint,
		})
	return result


static func _slope_degrees(ground: Callable, point: Vector2) -> float:
	var east: Vector3 = ground.call(point + Vector2(SLOPE_SAMPLE, 0.0))
	var west: Vector3 = ground.call(point - Vector2(SLOPE_SAMPLE, 0.0))
	var south: Vector3 = ground.call(point + Vector2(0.0, SLOPE_SAMPLE))
	var north: Vector3 = ground.call(point - Vector2(0.0, SLOPE_SAMPLE))
	if not (east.is_finite() and west.is_finite() and south.is_finite() and north.is_finite()):
		return 90.0
	var run := SLOPE_SAMPLE * 2.0
	var gradient_x := (east.y - west.y) / run
	var gradient_z := (south.y - north.y) / run
	return rad_to_deg(atan(sqrt(gradient_x * gradient_x + gradient_z * gradient_z)))


## Three alpha cards fanned around Y. `tilt` leans the cards outward from the
## base; ferns use a large tilt to arch like a frond rosette.
static func _clump_mesh(texture_id: String, variant: int, card_count: int,
		width: float, height: float, tilt: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := TextureLibrary.cell_count(texture_id)
	for card_index in range(card_count):
		var angle := TAU * float(card_index) / float(card_count) + float(variant) * 0.35
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var right := Vector3(-outward.z, 0.0, outward.x)
		var up := (Vector3.UP * cos(tilt) + outward * sin(tilt)).normalized()
		var normal := right.cross(up).normalized()
		var cell := TextureLibrary.atlas_cell(texture_id, variant * card_count + card_index)
		_add_blade(st, right, up, normal, width, height, cell, rng_phase(card_index, variant))
	# SurfaceTool returns an ArrayMesh; no material is attached so callers can
	# share one override material across every variant and chunk.
	return st.commit()


## Adds one card with its base at the local origin and wind weight rising toward
## the tip (UV2.y), which keeps the base planted while the tip sways.
static func _add_blade(st: SurfaceTool, right: Vector3, up: Vector3, normal: Vector3,
		width: float, height: float, cell: Rect2, phase: float) -> void:
	var half := width * 0.5
	var p0 := -right * half
	var p1 := right * half
	var p2 := p1 + up * height
	var p3 := p0 + up * height
	var u0 := cell.position.x
	var u1 := cell.end.x
	var v0 := cell.position.y
	var v1 := cell.end.y
	var base_colour := Color(0.78, 0.78, 0.78, 1.0)
	var tip_colour := Color.WHITE
	# Two triangles, non-indexed. Culling is disabled by the grass shader.
	_blade_vertex(st, p0, normal, Vector2(u0, v1), Vector2(phase, 0.05), base_colour)
	_blade_vertex(st, p1, normal, Vector2(u1, v1), Vector2(phase, 0.05), base_colour)
	_blade_vertex(st, p2, normal, Vector2(u1, v0), Vector2(phase, 1.0), tip_colour)
	_blade_vertex(st, p0, normal, Vector2(u0, v1), Vector2(phase, 0.05), base_colour)
	_blade_vertex(st, p2, normal, Vector2(u1, v0), Vector2(phase, 1.0), tip_colour)
	_blade_vertex(st, p3, normal, Vector2(u0, v0), Vector2(phase, 1.0), tip_colour)


static func _blade_vertex(st: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2,
		wind_uv: Vector2, colour: Color) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.set_uv2(wind_uv)
	st.set_color(colour)
	st.add_vertex(point)


## Copies the cached material and points its distance fade at this config's
## visibility range so the shader fades out exactly where chunks cull.
static func _fading_material(base: ShaderMaterial, texture_id: String, range_end: float) -> ShaderMaterial:
	var material := base.duplicate() as ShaderMaterial
	material.set_shader_parameter("albedo_texture", TextureLibrary.texture(texture_id))
	material.set_shader_parameter("fade_start", maxf(1.0, range_end * 0.82))
	material.set_shader_parameter("fade_end", maxf(2.0, range_end))
	return material


static func rng_phase(card_index: int, variant: int) -> float:
	# Stable per-card phase; avoids needing an RNG so repeated builds match.
	var value := sin(float(card_index) * 12.9898 + float(variant) * 78.233) * 43758.5453
	return value - floor(value)


static func _colour(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return fallback
