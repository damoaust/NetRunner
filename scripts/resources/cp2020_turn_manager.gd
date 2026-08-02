class_name CP2020TurnManager
extends Node

signal turn_ended(is_netrunner_turn: bool)
signal ice_movement_stepped
signal actions_changed(remaining: int, max_actions: int)

@export var max_actions: int = 5

var is_netrunner_turn: bool = true
var actions_remaining: int = 5


func start_netrunner_turn() -> void:
	is_netrunner_turn = true
	actions_remaining = max_actions
	actions_changed.emit(actions_remaining, max_actions)
	turn_ended.emit(is_netrunner_turn)

func end_player_turn() -> void:
	is_netrunner_turn = false
	turn_ended.emit(is_netrunner_turn)

func consume_action() -> bool:
	if not is_netrunner_turn:
		return false
	if actions_remaining <= 0:
		return false
	actions_remaining -= 1
	actions_changed.emit(actions_remaining, max_actions)
	return true

func has_actions() -> bool:
	return is_netrunner_turn and actions_remaining > 0

func execute_ice_turns(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	is_netrunner_turn = false
	end_player_turn()
	for ice in ice_nodes:
		if ice and ice.has_method("take_turn"):
			await ice.take_turn(target_pos, layout)
			await get_tree().create_timer(0.3).timeout
			ice_movement_stepped.emit()

	start_netrunner_turn()
