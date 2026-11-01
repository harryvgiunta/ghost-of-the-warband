extends "res://tests/escape_run_regression.gd"
## Throwaway: the trail regression with the escort's own state dumped while it
## follows, to see why allies stay in the camp.


func check_follow() -> void:
	var soul = game.controller.active_body(1)
	var squad = game.squad
	print("PROBE trail size=%d base=%d" % [squad._trail.size(), squad._trail_base])
	var line := ""
	for index in mini(squad._trail.size(), 14):
		var at: Vector3 = squad._trail[index]
		line += " %d:(%.1f,%.1f,%.1f)" % [index + squad._trail_base, at.x, at.y, at.z]
	print("PROBE first crumbs" + line)
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0
	for beat in 8:
		await create_timer(1.0).timeout
		for merc_id in game.squad_ids:
			if int(merc_id) == game.controller.merc_for_peer(1):
				continue
			var ally = game.controller.body_of(int(merc_id))
			var track: Dictionary = squad._track.get(int(merc_id), {})
			var number := int(track.get("crumb", -1))
			var index: int = number - squad._trail_base
			var target := Vector3.ZERO
			if index >= 0 and index < squad._trail.size():
				target = squad._trail[index]
			var here: Vector3 = ally.global_position
			var route: PackedVector3Array = track.get("route", PackedVector3Array())
			print("PROBE t%d m%d at (%.1f,%.1f,%.1f) crumb=%d target=(%.1f,%.1f,%.1f) d=%.2f route=%d at=%d mapped=%s clear=%s r=%.2f s=%.2f move=%s eng=%s" % [
				beat, int(merc_id), here.x, here.y, here.z, number, target.x, target.y, target.z,
				here.distance_to(target), route.size(), int(track.get("route_at", 0)),
				str(squad._mapped(here, target)),
				str(squad.nav.clear_line(here, target)) if squad._mapped(here, target) else "-",
				float(track.get("retreat", 0.0)), float(track.get("side", 0.0)),
				str(ally.move_direction), str(track.get("engaged", false))])
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	quit(0)
