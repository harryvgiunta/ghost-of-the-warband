extends SceneTree
## Throwaway: what a node costs the main loop on this machine.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 0
	var empty := await _measure("empty tree", 0)
	var small := await _measure("29k nodes", 29000)
	var big := await _measure("29k nodes + 900 meshes", 29000, 900)
	print("RESULT empty=%.4f ms  nodes29k=%.4f ms  with_meshes=%.4f ms" % [empty, small, big])
	quit()


func _measure(label: String, nodes: int, meshes: int = 0) -> float:
	var holder := Node3D.new()
	root.add_child(holder)
	var made := 0
	while made < nodes:
		var node := Node3D.new()
		holder.add_child(node)
		made += 1
	for index in meshes:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		holder.add_child(mesh)
	for index in 30:
		await process_frame
	var started := Time.get_ticks_usec()
	for index in 300:
		await process_frame
	var spent := float(Time.get_ticks_usec() - started) / 300000.0
	holder.queue_free()
	await process_frame
	print("  %-22s %d nodes %d meshes -> %.4f ms/frame" % [label, nodes, meshes, spent])
	return spent
