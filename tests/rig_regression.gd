extends SceneTree

const Geo = preload("res://scripts/geo.gd")
const Archer = preload("res://scripts/archer.gd")
const Bow = preload("res://scripts/bow.gd")
var failures := 0
var checks := 0
var emitted := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func check_limbs(rig: Node3D, label: String) -> void:
	var joints: Dictionary = rig.get_joint_positions()
	for side in ["left", "right"]:
		var suffix := "l" if side == "left" else "r"
		for segment in [["shoulder","elbow","lowerarm"],["elbow","wrist","hand"],["hip","knee","calf"],["knee","ankle","foot"]]:
			var bone: int = rig.skeleton.find_bone(segment[2]+"_"+suffix)
			var rest_length: float = rig.skeleton.get_bone_rest(bone).origin.length()
			check(absf(joints[side+"_"+segment[0]].distance_to(joints[side+"_"+segment[1]])-rest_length)<0.001, label+" retains the imported anatomical segment length")

func advance_to(rig: Node3D, desired_phase: String) -> void:
	for step in 240:
		if rig.phase == desired_phase:
			return
		rig.advance_animation(1.0 / 60.0)
	check(false, "Animation must reach " + desired_phase)

func check_bows(holder: Node3D) -> void:
	for kind in 3:
		var bow := Bow.new()
		bow.bow_kind = kind
		bow.bow_length = Archer.BOW_DATA[kind].length
		holder.add_child(bow)
		var cord_length: float = bow._strings[0].basis.y.length()
		var wood_lengths: Array[float] = []
		for piece in bow._limbs:
			wood_lengths.append(piece.basis.y.length())
		for draw in [0.2, 0.65, 1.0]:
			bow.set_draw(draw)
			for cord in bow._strings:
				check(absf(cord.basis.y.length() - cord_length) < 0.0001, "Drawing must not stretch the bowstring")
			for index in bow._limbs.size():
				check(absf(bow._limbs[index].basis.y.length() - wood_lengths[index]) < 0.0001, "Bending must not stretch wood segments")
		bow.free()

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	check_bows(holder)
	var a := Vector3(0.1, 1.2, -0.6)
	var b := Vector3(0.0, 1.5, -0.42)
	var beam := Geo.beam(holder, a, b, 0.02, Geo.material(Color.WHITE))
	check((beam.transform * Vector3(0, -0.5, 0)).is_equal_approx(a), "Diagonal beam must retain its first endpoint")
	check((beam.transform * Vector3(0, 0.5, 0)).is_equal_approx(b), "Diagonal beam must retain its second endpoint")
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	rig.arrow_released.connect(func(_origin, _direction, _speed, _charge): emitted += 1)
	rig.aim_at(Vector3(0, 1.7, -30))
	check_limbs(rig, "carry")
	rig.set_locomotion(Vector3(0, 0, -5.0), true)
	for step in 12:
		rig.advance_animation(0.05)
		check_limbs(rig, "walking")
	rig.set_locomotion(Vector3.ZERO, true)
	rig.begin_draw()
	for step in 30:
		rig.advance_animation(1.0 / 60.0)
		check_limbs(rig, "raising")
	var progress := rig.draw_amount
	rig.set_bow(2)
	rig.set_armor(2)
	check(is_equal_approx(rig.draw_amount, progress) and rig.phase == "DRAWING", "Mid-draw swap preserves tension and state")
	advance_to(rig, "HOLDING")
	var joints := rig.get_joint_positions()
	var arrow_direction := rig.active_bow.get_arrow_direction()
	check(absf(rig.get_stance_forward().dot(arrow_direction)) < 0.25, "Torso must stand side-on, not square to the target")
	var foot_span: Vector3 = joints.left_foot - joints.right_foot
	check(foot_span.length() > 0.32 and foot_span.length() < 0.60, "Feet must form a stable human-width stance")
	check(absf(foot_span.normalized().dot(arrow_direction)) > 0.85, "Feet must align with the side-on stance")
	check(rig.string_hand.global_position.distance_to(joints.anchor) < 0.005, "Full draw must anchor at the jaw")
	check((joints.right_elbow - joints.right_wrist).dot(arrow_direction) < -0.10, "Draw elbow must sit behind the wrist")
	check(absf(joints.right_elbow.y - joints.right_wrist.y) < 0.22, "Draw elbow must remain near arrow height, not above the skull")
	var upper_direction: Vector3 = (joints.left_elbow - joints.left_shoulder).normalized()
	var lower_direction: Vector3 = (joints.left_wrist - joints.left_elbow).normalized()
	check(upper_direction.dot(lower_direction) > 0.90, "Bow arm must be nearly extended with a soft elbow")
	check_limbs(rig, "full draw")
	rig.set_bow(0)
	check(rig.phase == "HOLDING" and is_equal_approx(rig.draw_amount, 1.0), "Full-draw bow swap preserves hold")
	check(rig.bow_hand.global_position.distance_to(rig.active_bow.get_grip_position()) < 0.0001, "Bow stays in the real grip")
	check(rig.string_hand.global_position.distance_to(rig.active_bow.get_nock_position()) < 0.0001, "Fingers remain on the loaded string")
	var before_hand := rig.string_hand.global_position
	var before_bow := rig.bow_hand.global_position
	rig.release_string()
	rig.release_string()
	check(emitted == 1, "Repeated release emits exactly one projectile")
	advance_to(rig, "RECOVER")
	check((rig.string_hand.global_position - before_hand).dot(arrow_direction) < -0.09, "Release hand follows BACKWARD, never with the snapping string")
	check(rig.bow_hand.global_position.distance_to(before_bow) < 0.015, "Bow arm remains extended through follow-through")
	check(rig.string_hand.global_position.distance_to(rig.active_bow.get_nock_position()) > 0.50, "Released hand separates from the returning string")
	check_limbs(rig, "follow-through")
	advance_to(rig, "READY")
	rig.begin_draw()
	rig.advance_animation(0.5)
	rig.cancel_draw()
	rig.release_string()
	check(emitted == 1 and rig.phase == "READY", "Canceled draw never fires")
	# Uneven ground must alter the planted soles, not stretch either leg.
	rig.set_ground_sampler(func(point: Vector3) -> float: return point.x * 0.16 + point.z * 0.10)
	rig.begin_draw()
	advance_to(rig, "HOLDING")
	joints = rig.get_joint_positions()
	for side in ["left", "right"]:
		var foot: Vector3 = joints[side + "_foot"]
		check(absf(foot.y - (foot.x * 0.16 + foot.z * 0.10)) < 0.015, "Planted sole follows actual slope")
	check_limbs(rig, "slope")
	holder.queue_free()
	await process_frame
	print("RIG_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
