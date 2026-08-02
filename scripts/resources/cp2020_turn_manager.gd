class_name CP2020TurnManager
extends Node

signal turn_ended(is_netrunner_turn: bool)
signal ice_movement_stepped

var is_netrunner_turn: bool = true

func start_netrunner_turn() -> void:
	is_netrunner_turn = true
	turn_ended.emit(is_netrunner_turn)

func end_player_turn() -> void:
	is_netrunner_turn = false
	turn_ended.emit(is_netrunner_turn)

func execute_ice_turns(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	is_netrunner_turn = false
	for ice in ice_nodes:
		if ice and ice.has_method("take_turn"):
			await ice.take_turn(target_pos, layout)
			await get_tree().create_timer(0.3).timeout
			ice_movement_stepped.emit()
	
	start_netrunner_turn()
