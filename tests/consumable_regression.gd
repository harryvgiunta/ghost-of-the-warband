extends SceneTree
## Bandage and healing-potion channel, heal, hotkey and arena replication.

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("CONSUMABLE_FAIL  ",message)

func pause(seconds: float) -> void:
	await create_timer(seconds).timeout

func key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await pause(0.5)
	check(game.hud._bandage_button != null and game.hud._potion_button != null,"The frontier equipment menu exposes both consumables")
	game.health = 40.0
	game._unhandled_input(key_event(KEY_6))
	check(game.archer.phase == "BANDAGE" and game._consume_kind == "bandage","Hotkey 6 starts the bandage channel")
	check(game.archer._bandage_prop.visible,"The bandage roll is held during the channel")
	await pause(1.0)
	check(game.health == 40.0,"The bandage heals nothing before the three-second use completes")
	await pause(2.2)
	check(game.archer.phase == "READY" and game.archer._bandage_prop.visible == false,"The bandage use completes and hides the roll")
	await pause(3.2)
	check(absf(game.health - 75.0) < 1.0,"The bandage restores thirty-five health over three seconds")
	game.health = 30.0
	game.use_consumable("bandage")
	await pause(0.4)
	game.take_damage(5.0)
	check(game._consume_kind == "" and game.archer.phase == "READY","Damage cancels a bandage channel")
	check(game.health < 30.0,"The cancelling hit still damages the player")
	await pause(0.3)
	game.health = 40.0
	game.use_consumable("potion")
	check(game.archer.phase == "DRINK" and game.archer._potion_prop.visible,"The potion bottle appears during the half-second use")
	await pause(0.7)
	check(game.archer.phase == "READY" and absf(game.health - 90.0) < 1.0,"The potion restores fifty health after half a second")
	game.queue_free()
	await process_frame

	var socket := PacketPeerUDP.new()
	check(socket.bind(0) == OK,"Consumable fixture gets a free UDP port")
	var port := socket.get_local_port()
	socket.close()
	var arena = load("res://arena.tscn").instantiate()
	root.add_child(arena)
	arena.host_game(port,"Consumable Regression")
	await pause(0.3)
	for index in range(1,4):
		arena.actors[index].authoritative = false
		arena.actors[index].visible = false
	var actor = arena.actors[0]
	actor.health = 40.0
	arena.send_action("consume","bandage")
	await pause(0.2)
	check(actor.consume_kind == "bandage" and actor.rig.phase == "BANDAGE","The arena seat accepts a bandage use")
	check(is_equal_approx(actor.rig._player.get_animation("Bandage_Wrap").length,3.0),"The arena rig uses the authored bandage clip")
	actor.take_damage(5.0,-1)
	check(actor.consume_kind == "" and actor.rig.phase == "READY","Arena damage cancels the bandage channel")
	actor.health = 40.0
	await pause(0.3)
	arena.send_action("consume","bandage")
	await pause(3.4)
	check(actor.health > 40.0,"The hosted actor begins the bandage heal")
	await pause(3.1)
	check(actor.health >= 74.0,"The hosted actor completes the thirty-five point heal")
	actor.health = 40.0
	arena.send_action("consume","potion")
	await pause(0.7)
	check(is_equal_approx(actor.health,90.0),"The hosted actor's potion restores fifty health")
	arena.leave_game()
	await pause(0.2)
	arena.queue_free()
	await process_frame
	print("CONSUMABLE_REGRESSION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
