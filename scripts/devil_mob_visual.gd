extends Node3D

## Presentation-only controller for the imported devil mobs.
##
## Gameplay owns root motion, damage and death. This node samples the authored
## GLB clips, maps the six gameplay states onto idle/walk/run/attack/hit/death,
## and adjusts the physics-clock attack playback so the authored impact frame
## always coincides with the gameplay strike.

const SCENES := {
	"hell_goat": "res://assets/characters/devils/ironwood_hell_goat.glb",
	"succubus": "res://assets/characters/devils/ironwood_succubus.glb",
	"spawn": "res://assets/characters/devils/ironwood_spawn.glb",
	"beast": "res://assets/characters/devils/ironwood_beast.glb",
	"gargoyle": "res://assets/characters/devils/ironwood_gargoyle.glb",
}

## Clip inventory, measured playback speeds and head-zone extents.
## These mirror the adjacent GLB metadata; tests/devil_mobs_regression.gd
## compares them against the imported assets.
const DATA := {
	"hell_goat": {
		"idle": "HellGoat_Idle_Loop", "walk": "HellGoat_Walk_Loop",
		"run": "HellGoat_Run_Loop", "attack": "HellGoat_Attack",
		"hit": "HellGoat_Hit", "death": "HellGoat_Death",
		"walk_speed": 1.50, "run_speed": 4.00, "run_threshold": 2.15,
		"impact": 0.62, "duration": 1.45,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.20, "head_half": 0.15, "organic": true, "hover": 0.0,
	},
	"succubus": {
		"idle": "Succubus_Idle_Loop", "walk": "Succubus_Walk_Loop",
		"run": "Succubus_Run_Loop", "attack": "Succubus_Attack",
		"hit": "Succubus_Hit", "death": "Succubus_Death",
		"walk_speed": 1.40, "run_speed": 4.20, "run_threshold": 2.00,
		"impact": 0.58, "duration": 1.35,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.135, "head_half": 0.095, "organic": true, "hover": 0.0,
	},
	"spawn": {
		"idle": "Spawn_Idle_Loop", "walk": "Spawn_Walk_Loop",
		"run": "Spawn_Run_Loop", "attack": "Spawn_Attack",
		"hit": "Spawn_Hit", "death": "Spawn_Death",
		"walk_speed": 1.30, "run_speed": 4.60, "run_threshold": 1.95,
		"impact": 0.48, "duration": 1.10,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.165, "head_half": 0.13, "organic": true, "hover": 0.0,
	},
	"beast": {
		"idle": "Beast_Idle_Loop", "walk": "Beast_Walk_Loop",
		"run": "Beast_Run_Loop", "attack": "Beast_Attack",
		"hit": "Beast_Hit", "death": "Beast_Death",
		"walk_speed": 1.40, "run_speed": 3.80, "run_threshold": 2.40,
		"impact": 0.82, "duration": 1.60,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.38, "head_half": 0.20, "organic": true, "hover": 0.0,
	},
	"gargoyle": {
		"idle": "Gargoyle_Idle_Loop", "walk": "Gargoyle_Walk_Loop",
		"run": "Gargoyle_Run_Loop", "attack": "Gargoyle_Attack",
		"hit": "Gargoyle_Hit", "death": "Gargoyle_Death",
		"walk_speed": 1.00, "run_speed": 2.80, "run_threshold": 1.80,
		"impact": 0.95, "duration": 1.80,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.30, "head_half": 0.20, "organic": false, "hover": 0.0,
	},
}

const MOVE_THRESHOLD := 0.22

var mob_id := "hell_goat"
var profile: Dictionary = {}

var _data: Dictionary
var _instance: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone := -1
var _clip := ""
var _speed := 0.0
var _grounded := true
var _attack_playing := false
var _combat_state := ""
var _combat_time := 0.0
var _last_state := ""
var _hit_playing := false
var _hit_time := 0.0
var _hit_duration := 0.5
var _dead := false
var _death_time := 0.0
var _death_held := false
var _hover_time := 0.0


func _ready() -> void:
	if not SCENES.has(mob_id):
		push_error("Unknown devil mob: " + mob_id)
		return
	_data = DATA[mob_id]
	var packed: PackedScene = load(SCENES[mob_id])
	if packed == null:
		push_error("Missing devil scene: " + SCENES[mob_id])
		return
	_instance = packed.instantiate()
	add_child(_instance)
	_player = _instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = _instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null or _skeleton == null:
		push_error("Devil visual is missing its AnimationPlayer or Skeleton3D: " + mob_id)
		return
	_head_bone = _skeleton.find_bone("head")
	for key in ["idle", "walk", "run", "attack", "hit", "death"]:
		if not _player.has_animation(str(_data[key])):
			push_error("Devil visual is missing clip %s for %s" % [_data[key], mob_id])
			return
	for key in ["idle", "walk", "run"]:
		_player.get_animation(str(_data[key])).loop_mode = Animation.LOOP_LINEAR
	for key in ["attack", "hit", "death"]:
		_player.get_animation(str(_data[key])).loop_mode = Animation.LOOP_NONE
	_hit_duration = _player.get_animation(str(_data["hit"])).length
	_clip = str(_data["idle"])
	_player.play(_clip, 0.0)
	_player.speed_scale = 1.0
	_tune_materials()


func _tune_materials() -> void:
	if _instance == null:
		return
	for mesh_instance in _instance.find_children("*", "MeshInstance3D", true, false):
		var node := mesh_instance as MeshInstance3D
		for surface in node.mesh.get_surface_count():
			var material := node.get_active_material(surface)
			if material is StandardMaterial3D:
				var tuned := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				tuned.emission_energy_multiplier = 1.35
				tuned.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				var mat_name := tuned.resource_name.to_lower()
				var fleshy := mat_name.contains("skin") or mat_name.contains("membrane") \
						or mat_name.contains("fur") or mat_name.contains("flesh")
				if bool(_data.get("organic", false)) and fleshy \
						and RenderingServer.get_current_rendering_method() == "forward_plus":
					tuned.subsurf_scatter_enabled = true
					tuned.subsurf_scatter_strength = 0.06
				node.set_surface_override_material(surface, tuned)


func set_motion(velocity: Vector3, grounded: bool) -> void:
	_speed = Vector2(velocity.x, velocity.z).length()
	_grounded = grounded


func set_combat(state: String, time: float) -> void:
	if _player == null:
		return
	var previous := _last_state
	_last_state = state
	_combat_state = state
	_combat_time = time
	if _dead:
		return
	if state == "DEAD":
		die()
		return
	if state == "STAGGER":
		if previous != "STAGGER":
			_attack_playing = false
			_hit_playing = true
			_hit_time = 0.0
			_clip = str(_data["hit"])
			_player.speed_scale = 1.0
			_player.play(_clip, 0.06)
		return
	if state in ["WINDUP", "STRIKE", "RECOVER"]:
		if _hit_playing:
			_hit_playing = false
		if not _attack_playing:
			_attack_playing = true
			_clip = str(_data["attack"])
			_player.speed_scale = 1.0
			_player.play(_clip, 0.05)
		return
	if _attack_playing:
		_attack_playing = false
	_select_locomotion()


func die() -> void:
	if _dead or _player == null:
		return
	_dead = true
	_attack_playing = false
	_hit_playing = false
	_death_time = 0.0
	_death_held = false
	_clip = str(_data["death"])
	_player.speed_scale = 1.0
	_player.play(_clip, 0.06)


func head_hitbox_center() -> Vector3:
	if _skeleton == null or _head_bone < 0:
		return global_position + Vector3(0.0, 1.0, 0.0)
	var pose := _skeleton.get_bone_global_pose(_head_bone)
	var offset: Vector3 = _data.get("head_offset", Vector3.ZERO)
	return _skeleton.global_transform * (pose.origin + pose.basis * offset)


func head_hit_profile() -> Vector2:
	return Vector2(float(_data.get("head_radius", 0.25)), float(_data.get("head_half", 0.12)))


func get_clip_name() -> String:
	return _clip


func is_dead() -> bool:
	return _dead


func _process(delta: float) -> void:
	if _player == null:
		return
	_hover_time += delta
	if _instance != null:
		var hover := float(_data.get("hover", 0.0))
		if hover > 0.0:
			var target_height := 0.0 if _dead else hover + sin(_hover_time * 2.2) * 0.025
			_instance.position.y = lerpf(_instance.position.y, target_height,
				minf(1.0, delta * 8.0))
	if _dead:
		_advance_death(delta)
		return
	if _attack_playing:
		_seek_attack()
		return
	if _hit_playing:
		_hit_time += delta
		if _hit_time >= _hit_duration:
			_hit_playing = false
			_select_locomotion()
		return
	_select_locomotion()


func _seek_attack() -> void:
	if profile.is_empty():
		return
	var impact := float(_data.get("impact", 0.6))
	var total := float(_data.get("duration", 1.4))
	var windup := maxf(0.05, float(profile.get("windup", 0.45)))
	var strike := maxf(0.05, float(profile.get("strike", 0.18)))
	var recover := maxf(0.05, float(profile.get("recover", 0.55)))
	var post_impact := maxf(0.05, total - impact)
	var t := impact
	if _combat_state == "WINDUP":
		t = impact * clampf(_combat_time / windup, 0.0, 1.0)
	elif _combat_state == "STRIKE":
		t = impact + clampf(_combat_time / strike, 0.0, 1.0) * 0.10
	elif _combat_state == "RECOVER":
		t = impact + 0.10 + clampf(_combat_time / recover, 0.0, 1.0) * maxf(0.05, post_impact - 0.10)
	_player.seek(clampf(t, 0.0, total), true)


func _select_locomotion() -> void:
	var target := str(_data["idle"])
	var scale := 1.0
	if _speed > MOVE_THRESHOLD:
		var threshold := float(_data.get("run_threshold", 2.0))
		if _speed >= threshold:
			target = str(_data["run"])
			scale = clampf(_speed / maxf(0.1, float(_data["run_speed"])), 0.55, 1.9)
		else:
			target = str(_data["walk"])
			scale = clampf(_speed / maxf(0.1, float(_data["walk_speed"])), 0.55, 1.9)
	if _clip != target:
		_clip = target
		_player.play(target, 0.18)
	_player.speed_scale = scale


func _advance_death(delta: float) -> void:
	if _death_held:
		return
	_death_time += delta
	var duration := _player.get_animation(str(_data["death"])).length
	if _death_time >= duration:
		_death_held = true
		_player.seek(duration, true)
		_player.pause()
