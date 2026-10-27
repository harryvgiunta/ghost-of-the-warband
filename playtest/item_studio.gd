extends Node3D
## Item screenshot studio: renders every catalog item as it appears in game and
## writes the icons the equipment menu shows in its slots.
##
##     godot --path . playtest/item_studio.tscn
##     godot --path . playtest/item_studio.tscn -- --probe
##
## Armour is framed on the body region it covers (gloves and boots bring both
## sides together in one picture); weapons are the held models, shot alone on a
## transparent background so the silhouette reads at slot size; jewellery is the
## worn piece on its own. Output: assets/ui/items/<item id>.png, RGBA 256 px.

const Archer = preload("res://scripts/archer.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const TrinketArt = preload("res://scripts/trinket_art.gd")
const ShieldScript = preload("res://scripts/shield.gd")
const StateScript = preload("res://scripts/player_state.gd")

const OUT_DIR := "res://assets/ui/items"
const ICON_SIZE := 256
const RENDER_SIZE := 512
const MARGIN := 1.10

## Armour icons are framed on the skeleton, not on a rest-pose mesh AABB, so the
## piece is shown on the posed body exactly as the paperdoll shows it.
const ARMOR_FRAME := {
	"head": {"bone":"Head", "offset":Vector3(0.0,0.06,0.0), "radius":0.27, "dir":Vector3(0.30,0.12,-1.0)},
	"chest": {"bone":"spine_03", "offset":Vector3(0.0,-0.16,0.0), "radius":0.38, "dir":Vector3(0.28,0.10,-1.0)},
	"hands": {"bones":["hand_l","hand_r"], "offset":Vector3(0.0,0.02,0.0), "radius":0.30, "dir":Vector3(0.22,0.06,-1.0)},
	"legs": {"bone":"pelvis", "offset":Vector3(0.0,-0.30,0.0), "radius":0.44, "dir":Vector3(0.25,0.08,-1.0)},
	"feet": {"bones":["foot_l","foot_r"], "offset":Vector3(0.0,0.02,0.0), "radius":0.27, "dir":Vector3(0.20,-0.04,-1.0)},
}

const PAIR_HALF := Vector2i(160,180)
const PAIR_GAP := 8

var _viewport: SubViewport
var _camera: Camera3D
var _rig
var _probe := false

func _ready() -> void:
	_probe = OS.get_cmdline_user_args().has("--probe")
	_build_stage()
	if _probe:
		await _render_probe()
	else:
		await _render_all()
	get_tree().quit()


func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE,RENDER_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.near = 0.02
	_camera.far = 40.0
	_viewport.add_child(_camera)
	_camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0,-32.0,0.0)
	key.light_energy = 1.9
	key.shadow_enabled = true
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0,138.0,0.0)
	fill.light_energy = 0.75
	fill.light_color = Color("a8c4c8")
	_viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-58.0,18.0,0.0)
	rim.light_energy = 0.55
	rim.light_color = Color("e9bf76")
	_viewport.add_child(rim)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0,0,0,0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6f8e93")
	env.ambient_light_energy = 1.45
	environment.environment = env
	_viewport.add_child(environment)
	_rig = Archer.new()
	_viewport.add_child(_rig)
	# The studio poses the rig once per item; nothing should advance the idle
	# clip between the loadout apply and the capture.
	_rig.set_physics_process(false)


func _render_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ids: Array = StateScript.ITEMS.keys()
	# `-- --only <item id>` re-shoots one icon without rewriting the other sixty.
	var args := OS.get_cmdline_user_args()
	var at_index := args.find("--only")
	if at_index >= 0 and at_index + 1 < args.size():
		var only := str(args[at_index + 1])
		if not StateScript.ITEMS.has(only):
			print("ITEM_ICON unknown item %s" % only)
			return
		await _render_item(only, "%s/%s.png" % [OUT_DIR, only])
		print("ITEM_ICON 1/1 %s" % only)
		return
	for index in ids.size():
		var item_id := str(ids[index])
		await _render_item(item_id,"%s/%s.png" % [OUT_DIR,item_id])
		print("ITEM_ICON %d/%d %s" % [index + 1,ids.size(),item_id])
	_write_manifest(ids)


func _render_item(item_id: String, output: String) -> void:
	var item: Dictionary = StateScript.ITEMS.get(item_id, {})
	if item.is_empty():
		return
	TrinketArt.clear(_rig.skeleton)
	_clear_display_art()
	_show_character()
	_viewport.size = Vector2i(RENDER_SIZE,RENDER_SIZE)
	var category := str(item.get("category",""))
	var slot := str(item.get("slot",""))
	if category == "armor" and slot in ["hands","feet"]:
		await _render_pair(item,slot,output)
		return
	if str(item.get("kind", "")) == "torch":
		_apply_torch(item_id)
		await _capture_alpha(Vector3(0.0, 0.0, 0.0), 0.42, Vector3(0.35, 0.18, -1.0), output)
		return
	match category:
		"armor":
			_apply_armor(item)
			var frame := _armor_frame(slot)
			await _capture_alpha(frame["center"],float(frame["radius"]),frame["dir"],output)
		"armor_bundle":
			_apply_armor_set(int(item.get("set",0)))
			await _capture_region({"center":Vector3(0.0,1.02,0.0), "radius":1.02,
				"dir":Vector3(0.22,0.08,-1.0)},output)
		"jewelry":
			_apply_jewelry(item_id,slot)
			var radius := 0.095 if slot == "neck" else 0.036
			await _capture_alpha(Vector3(0.0,0.0,0.0),radius,Vector3(0.45,0.30,-1.0),output)
		"shield":
			await _render_shield(item,output)
		_:
			_apply_weapon(item_id)
			var view := _weapon_view(item_id)
			await _capture_alpha(view["center"],float(view["radius"]),view["dir"],output,float(view.get("roll",0.0)))


func _write_manifest(ids: Array) -> void:
	var payload := {
		"source": "playtest/item_studio.gd",
		"size": ICON_SIZE,
		"items": ids,
	}
	var file := FileAccess.open("%s/items.json" % OUT_DIR,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload,"\t"))


func _apply_armor(item: Dictionary) -> void:
	var armor := _bare_armor()
	var slot := str(item.get("slot","head"))
	var set_index := int(item.get("set",0))
	armor[slot] = set_index
	_apply_pieces(armor)
	# An armour icon is the piece itself, not the ranger's whole body: hide the
	# base skin and every other set, then show only this slot's worn mesh.
	for node in _rig._model.find_children("*","MeshInstance3D",true,false):
		node.visible = false
	for node: Node3D in _rig._armor_meshes.get(slot,{}).get(set_index,[]):
		node.visible = true
	if _rig._quiver != null:
		_rig._quiver.visible = false


func _apply_armor_set(set_index: int) -> void:
	var armor := {}
	for slot in ArmorData.SLOTS:
		armor[slot] = set_index
	_apply_pieces(armor)


func _apply_pieces(pieces: Dictionary) -> void:
	TrinketArt.clear(_rig.skeleton)
	_rig.apply_loadout(StateScript.build_loadout("","",pieces))


func _apply_weapon(item_id: String) -> void:
	TrinketArt.clear(_rig.skeleton)
	var category := str(StateScript.ITEMS[item_id].get("category",""))
	var main := item_id
	var off := ""
	if category in ["shield","focus"]:
		main = "sword_short"
		off = item_id
	_rig.apply_loadout(StateScript.build_loadout(main,off,_bare_armor()))
	# Weapons and shields are shot alone, like item card art: the same held
	# model the ranger carries, without the body behind it.
	_hide_character()
	if category in ["shield","focus"]:
		# The off-hand shot keeps the shield or focus, not its supporting sword.
		for other: Node3D in [_rig.active_sword,_rig.active_dagger,_rig.active_staff,_rig.active_bow]:
			if other != null:
				other.visible = false


func _clear_display_art() -> void:
	for child in _rig.get_children():
		if str(child.name) == "ItemIconArt":
			_rig.remove_child(child)
			child.queue_free()


## A hand torch has no held model: its whole look is the brand and its flame, so
## the studio builds the same visual the world hangs off a hand.
func _apply_torch(_item_id: String) -> void:
	TrinketArt.clear(_rig.skeleton)
	_clear_display_art()
	_rig.apply_loadout(StateScript.build_loadout("", "", _bare_armor()))
	_hide_character()
	var art: Node3D = preload("res://scripts/warband/torch_light.gd").build_visual(907)
	art.name = "ItemIconArt"
	_rig.add_child(art)


func _apply_jewelry(item_id: String, slot: String) -> void:
	TrinketArt.clear(_rig.skeleton)
	_clear_display_art()
	_rig.apply_loadout(StateScript.build_loadout("","",_bare_armor()))
	_hide_character()
	var art: Node3D = TrinketArt.display(item_id,slot)
	if art == null:
		return
	art.name = "ItemIconArt"
	_rig.add_child(art)


func _show_character() -> void:
	_rig.visible = true
	for node in _rig._model.find_children("*","MeshInstance3D",true,false):
		node.visible = true
	if _rig._quiver != null:
		_rig._quiver.visible = true


func _hide_character() -> void:
	for node in _rig._model.find_children("*","MeshInstance3D",true,false):
		node.visible = false
	if _rig._quiver != null:
		_rig._quiver.visible = false


func _bare_armor() -> Dictionary:
	var armor := {}
	for slot in ArmorData.SLOTS:
		armor[slot] = ArmorData.NONE
	return armor


func _bone_origin(bone: String) -> Vector3:
	return _bone_transform(bone).origin


func _bone_transform(bone: String) -> Transform3D:
	var index := int(_rig.skeleton.find_bone(bone))
	if index < 0:
		return Transform3D.IDENTITY
	return _rig.skeleton.global_transform * _rig.skeleton.get_bone_global_pose(index)


func _armor_frame(slot: String) -> Dictionary:
	var spec: Dictionary = ARMOR_FRAME.get(slot, ARMOR_FRAME["chest"])
	var center := Vector3.ZERO
	if spec.has("bones"):
		var points: Array = spec["bones"]
		for bone: String in points:
			center += _bone_origin(bone)
		center /= float(points.size())
	else:
		center = _bone_origin(str(spec["bone"]))
	center += spec["offset"]
	return {"center":center, "radius":float(spec["radius"]), "dir":spec["dir"]}


## The held model's own world bounds, plus a camera direction that shows its
## broad side: a blade is viewed across its length, a shield across its face.
## The alpha pass then crops the render to these pixels.
func _weapon_view(item_id: String) -> Dictionary:
	var item: Dictionary = StateScript.ITEMS[item_id]
	var category := str(item.get("category",""))
	var kind := str(item.get("kind",""))
	var node: Node3D = _rig.active_sword
	match category:
		"bow":
			node = _rig.active_bow
		"staff":
			node = _rig.active_staff
		"focus":
			node = _rig.active_focus
		"1h","2h":
			node = _rig.active_dagger if kind == "dagger" else _rig.active_sword
	var bounds := _node_world_bounds(node)
	var center := bounds.get_center() if bounds.size.length_squared() > 0.000001 else \
		(node.global_position if node != null else Vector3(0.0,1.0,0.0))
	var radius := maxf(bounds.size.length() * 0.5,0.22)
	var direction := Vector3(0.26,0.10,-1.0)
	if node != null:
		if category in ["1h","2h","staff"]:
			var blade := -node.global_transform.basis.z
			blade.y = 0.0
			if blade.length_squared() > 0.0001:
				direction = blade.normalized().cross(Vector3.UP).normalized()
				direction.y = 0.12
				if direction.dot(Vector3(0.0,0.0,-1.0)) < 0.0:
					direction = -direction
					direction.y = 0.12
		elif category == "shield":
			# Carried on the left arm with the face turned outward; look at it
			# from outside the body so the front of the disc is the near face.
			direction = (center - Vector3(0.0,1.0,0.0)).normalized()
			direction.y += 0.08
	var roll := 38.0 if category in ["1h","2h","staff"] else 0.0
	return {"center":center, "radius":radius * 1.15, "dir":direction.normalized(), "roll":roll}


func _node_world_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var first := true
	if node == null:
		return bounds
	for child in _walk(node):
		if not child is MeshInstance3D or not child.is_visible_in_tree():
			continue
		var mesh := child as MeshInstance3D
		var box := mesh.get_aabb()
		for index in 8:
			var corner := box.position + Vector3(
				box.size.x if index & 1 else 0.0,
				box.size.y if index & 2 else 0.0,
				box.size.z if index & 4 else 0.0)
			var point := mesh.global_transform * corner
			if first:
				bounds = AABB(point,Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	return bounds


## A shield's face is its local -Z. The carried pose can lay it flat against
## the arm, so its card is a free-standing copy turned to the camera.
func _render_shield(item: Dictionary, output: String) -> void:
	_rig.visible = false
	var shield = ShieldScript.new()
	shield.variant = int(item.get("index",1))
	_viewport.add_child(shield)
	await _wait_frames(2)
	shield.sync_to_physics = false
	shield.set_active(true)
	shield.position = Vector3(0.0,1.0,0.0)
	shield.rotation = Vector3.ZERO
	await _wait_frames(2)
	await _capture_alpha(Vector3(0.0,1.0,0.0),0.72,Vector3(0.20,0.08,-1.0),output)
	shield.queue_free()
	_rig.visible = true


func _frame_region(spec: Dictionary) -> void:
	var center: Vector3 = spec["center"]
	var radius := float(spec["radius"])
	var dir: Vector3 = spec["dir"]
	var distance := radius / sin(deg_to_rad(_camera.fov * 0.5)) * MARGIN
	_camera.look_at_from_position(center + dir.normalized() * distance,center,Vector3.UP)
	var roll := float(spec.get("roll",0.0))
	if absf(roll) > 0.001:
		_camera.rotate_object_local(Vector3(0,0,1),deg_to_rad(roll))


func _wait_frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame


func _capture() -> Image:
	await _wait_frames(3)
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


## Region shots keep the composition (a helmet cut at the collar, a torso cut at
## the waist) and only lose their transparent border.
func _capture_region(spec: Dictionary, output: String) -> void:
	_frame_region(spec)
	var image := await _capture()
	image.resize(ICON_SIZE,ICON_SIZE,Image.INTERPOLATE_LANCZOS)
	image.save_png(output)


## Item shots are cropped to their own pixels. If the first framing clips the
## model, the camera backs off until the silhouette clears the border.
func _capture_alpha(center: Vector3, radius: float, direction: Vector3, output: String, roll := 0.0) -> void:
	var image: Image
	for attempt in 4:
		_frame_region({"center":center, "radius":radius, "dir":direction, "roll":roll})
		image = await _capture()
		var used := image.get_used_rect()
		if used.size.x > 2 and used.size.y > 2 \
				and used.position.x > 1 and used.position.y > 1 \
				and used.end.x < RENDER_SIZE - 1 and used.end.y < RENDER_SIZE - 1:
			break
		radius *= 1.35
	image = _crop_used(image)
	image.save_png(output)


func _crop_used(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return image
	var side := maxi(used.size.x,used.size.y)
	var pad := int(round(float(side) * 0.055)) + 6
	var left := clampi(used.position.x - pad,0,image.get_width() - 1)
	var top := clampi(used.position.y - pad,0,image.get_height() - 1)
	var right := clampi(used.end.x + pad,left + 2,image.get_width())
	var bottom := clampi(used.end.y + pad,top + 2,image.get_height())
	var crop := image.get_region(Rect2i(left,top,right - left,bottom - top))
	var square := maxi(crop.get_width(),crop.get_height())
	if crop.get_width() != square or crop.get_height() != square:
		var canvas := Image.create(square,square,false,Image.FORMAT_RGBA8)
		canvas.fill(Color(0,0,0,0))
		canvas.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),
			Vector2i((square - crop.get_width()) / 2,(square - crop.get_height()) / 2))
		crop = canvas
	crop.resize(ICON_SIZE,ICON_SIZE,Image.INTERPOLATE_LANCZOS)
	return crop


## Gloves and boots are one catalog item each, so their icon is the pair: two
## close-up shots of the worn piece, side by side.
func _render_pair(item: Dictionary, slot: String, output: String) -> void:
	_apply_armor(item)
	_viewport.size = PAIR_HALF
	var left_bone := "hand_l" if slot == "hands" else "foot_l"
	var right_bone := "hand_r" if slot == "hands" else "foot_r"
	var radius := 0.16 if slot == "hands" else 0.225
	var direction := Vector3(0.15,0.02,-1.0) if slot == "hands" else Vector3(0.60,0.10,-1.0)
	await _wait_frames(4)
	_frame_region({"center":_pair_center(left_bone,slot), "radius":radius, "dir":direction})
	var left_image: Image = await _capture()
	_frame_region({"center":_pair_center(right_bone,slot), "radius":radius, "dir":direction})
	var right_image: Image = await _capture()
	var canvas := Image.create(PAIR_HALF.x * 2 + PAIR_GAP,PAIR_HALF.y,false,Image.FORMAT_RGBA8)
	canvas.fill(Color(0,0,0,0))
	canvas.blit_rect(left_image,Rect2i(Vector2i.ZERO,PAIR_HALF),Vector2i.ZERO)
	canvas.blit_rect(right_image,Rect2i(Vector2i.ZERO,PAIR_HALF),Vector2i(PAIR_HALF.x + PAIR_GAP,0))
	canvas.save_png(output)
	_viewport.size = Vector2i(RENDER_SIZE,RENDER_SIZE)


func _pair_center(bone: String, slot: String) -> Vector3:
	var transform := _bone_transform(bone)
	if slot == "hands":
		return transform.origin + transform.basis.y.normalized() * 0.075
	return transform.origin + Vector3(0.0,-0.060,0.0) - transform.basis.z.normalized() * 0.02


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _render_probe() -> void:
	var probes := {
		"armor_plate_chest":"res://playtest/_probe_armor.png",
		"armor_makeshift_hands":"res://playtest/_probe_hands.png",
		"armor_plate_feet":"res://playtest/_probe_feet.png",
		"sword_arming":"res://playtest/_probe_sword.png",
		"bow_long":"res://playtest/_probe_bow.png",
		"shield_kite":"res://playtest/_probe_shield.png",
		"focus_tome":"res://playtest/_probe_focus.png",
		"staff_fire":"res://playtest/_probe_staff.png",
		"ring_blood":"res://playtest/_probe_ring.png",
		"neck_shield":"res://playtest/_probe_neck.png",
		"armor_plate":"res://playtest/_probe_bundle.png",
	}
	for item_id: String in probes:
		await _render_item(item_id,str(probes[item_id]))
		print("ITEM_STUDIO_PROBE ",item_id)
