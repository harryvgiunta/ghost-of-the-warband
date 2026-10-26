class_name BushKit
extends RefCounted
## Woodland undergrowth. A bush is a fistful of leaf cards around a low centre -
## no trunk, no rig, no collision - so it batches through `WorldScatter` with the
## tree foliage and costs one draw call per atlas and chunk.
##
## Card geometry, UV2 wind channels and vertex-colour tinting come straight from
## `TreeKit`, so bushes light and sway exactly like the crowns above them.

const TreeKit = preload("res://scripts/world/tree_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")


## Three silhouettes for one foliage atlas: a low carpet, a scrubby mound and a
## thin elder. Returns `[{mesh, height, radius}]`, deterministic from `seed`.
static func build_variants(leaves_id: String, seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cells := TextureLibrary.cell_count(leaves_id)
	var variants: Array[Dictionary] = []
	for shape in range(3):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cards := 32 + shape * 8
		var height := 0.52 + float(shape) * 0.26
		var radius := 0.36 + float(shape) * 0.18
		for i in range(cards):
			var normal := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.25, 1.0),
				rng.randf_range(-1.0, 1.0)).normalized()
			var right := normal.cross(Vector3.UP)
			if right.length_squared() < 1.0e-6:
				right = Vector3.RIGHT
			right = right.normalized()
			var up := right.cross(normal).normalized()
			# roll the card about its own normal so no two cards line up
			var turn := rng.randf_range(0.0, TAU)
			var card_right := right * cos(turn) + up * sin(turn)
			var card_up := -right * sin(turn) + up * cos(turn)
			var at := Vector3(rng.randf_range(-radius, radius),
				rng.randf_range(0.10, height), rng.randf_range(-radius, radius))
			var half := rng.randf_range(0.15, 0.29)
			var cell := TextureLibrary.atlas_cell(leaves_id, rng.randi_range(0, cells - 1))
			var tint := Color(rng.randf_range(0.80, 1.0), rng.randf_range(0.82, 1.0),
				rng.randf_range(0.78, 1.0), 1.0)
			TreeKit._add_card(st, at, card_right, card_up, half, half, cell, tint,
				tint * Color(0.84, 0.86, 0.84, 1.0),
				Vector2(rng.randf(), rng.randf_range(0.0, 0.35)))
		variants.append({"mesh": st.commit(), "height": height + 0.25, "radius": radius})
	return variants
