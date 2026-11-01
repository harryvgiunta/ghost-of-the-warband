extends "res://tests/cage_escape_regression.gd"
## Throwaway control: the cage regression with the squad's map taken away before
## the latches, so the walk-out check runs against straight-line steering.


func check_latches() -> void:
	game.squad.nav = null
	await super.check_latches()
