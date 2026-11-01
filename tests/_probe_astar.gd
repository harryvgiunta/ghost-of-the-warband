extends SceneTree


func _initialize() -> void:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, 10, 10)
	grid.cell_size = Vector2(0.5, 0.5)
	grid.offset = Vector2(-2.25, -2.25)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for x in range(2, 8):
		grid.set_point_solid(Vector2i(x, 5))
	var path: Array[Vector2i] = grid.get_id_path(Vector2i(4, 2), Vector2i(4, 8))
	print("PROBE path=", path)
	print("PROBE points=", grid.get_point_path(Vector2i(4, 2), Vector2i(4, 8)))
	print("PROBE solid_end_partial=", grid.get_id_path(Vector2i(4, 2), Vector2i(4, 5), true))
	print("PROBE solid_end_strict=", grid.get_id_path(Vector2i(4, 2), Vector2i(4, 5), false))
	print("PROBE solid_start=", grid.get_id_path(Vector2i(4, 5), Vector2i(4, 8), false))
	print("PROBE engine=", Engine.get_version_info().string,
		" physics=", ProjectSettings.get_setting("physics/3d/physics_engine"))
	quit(0)
