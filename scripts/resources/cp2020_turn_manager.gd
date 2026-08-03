class_name CP2020TurnManager
extends Node

signal turn_ended(is_netrunner_turn: bool)
signal ice_movement_stepped
signal actions_changed(remaining: int, max_actions: int)
signal initiative_rolled(netrunner_roll: int, system_roll: int, netrunner_first: bool)

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

func _run_adversary_phase(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	for ice in ice_nodes:
		if not is_instance_valid(ice) or not ice.has_method("take_turn"):
			continue
		await ice.take_turn(target_pos, layout)
		# An adversary may have flatlined the netrunner, triggering a scene
		# change that detaches this node from the tree. Bail before touching
		# get_tree() to avoid a null reference.
		if not is_inside_tree():
			return
		await get_tree().create_timer(0.3).timeout
		if not is_inside_tree():
			return
		ice_movement_stepped.emit()

func execute_ice_turns(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout, netrunner_int: int = 0, system_int: int = 0) -> void:
	is_netrunner_turn = false
	end_player_turn()
	_run_adversary_phase(ice_nodes, target_pos, layout)
	if not is_inside_tree():
		return
	if system_int > 0:
		var nr_roll := randi_range(1, 10) + netrunner_int
		var sys_roll := randi_range(1, 10) + system_int
		var netrunner_first := nr_roll >= sys_roll
		initiative_rolled.emit(nr_roll, sys_roll, netrunner_first)
		if not netrunner_first:
			_run_adversary_phase(ice_nodes, target_pos, layout)
	start_netrunner_turn()
