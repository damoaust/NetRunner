class_name CP2020TurnManager
extends Node

signal turn_ended(is_netrunner_turn: bool)
signal ice_movement_stepped
signal actions_changed(remaining: int, max_actions: int)
signal movement_changed(remaining: int, max_movement: int)
signal initiative_rolled(netrunner_roll: int, system_roll: int, netrunner_first: bool, is_tie: bool)

# CP2020 action economy: a netrunner gets 1 program/Net action per turn
# (max_actions) PLUS up to 5 grid spaces of movement (max_movement). Movement
# is separate from the action budget — moving does NOT consume the action,
# and using a program does NOT consume movement. The turn ends when both
# budgets are exhausted OR the player explicitly ends the turn.
@export var max_actions: int = 1
@export var max_movement: int = 5

var is_netrunner_turn: bool = true
var actions_remaining: int = 1
var movement_remaining: int = 5
# True when this round's adversary phase is deferred to AFTER the netrunner's
# turn (the netrunner won or tied initiative, or round 1 where the runner acts
# first on entry). False when the system won initiative and the adversary
# phase already ran before the runner's turn.
var _post_round_adversary: bool = false


func start_netrunner_turn() -> void:
	is_netrunner_turn = true
	actions_remaining = max_actions
	movement_remaining = max_movement
	actions_changed.emit(actions_remaining, max_actions)
	movement_changed.emit(movement_remaining, max_movement)
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

func consume_movement() -> bool:
	if not is_netrunner_turn:
		return false
	if movement_remaining <= 0:
		return false
	movement_remaining -= 1
	movement_changed.emit(movement_remaining, max_movement)
	return true

func has_movement() -> bool:
	return is_netrunner_turn and movement_remaining > 0

# Run each adversary's take_turn once. Coroutine. Does NOT flip the turn flag
# or emit turn_ended — the caller (start_round / end_round) owns the round
# framing. Bails early if the tree detaches (e.g. the runner flatlined and the
# scene changed mid-phase).
func run_adversary_phase(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	for ice in ice_nodes:
		if not is_instance_valid(ice) or not ice.has_method("take_turn"):
			continue
		await ice.take_turn(target_pos, layout)
		if not is_inside_tree():
			return
		await get_tree().create_timer(0.3).timeout
		if not is_inside_tree():
			return
		ice_movement_stepped.emit()

# Begin a new round with a CP2020 initiative roll: runner 1D10 + REF + deck
# speed vs system 1D10 + System INT. If the SYSTEM wins, the adversary phase
# runs BEFORE the netrunner's turn (adversaries act first). If the RUNNER wins
# or TIES, the adversary phase is deferred to after the runner's turn — a tie
# is simultaneous (one phase, no bonus, no ordering). Fire-and-forget
# coroutine; callers do not await.
func start_round(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout, netrunner_int: int, system_int: int) -> void:
	var nr_roll := randi_range(1, 10) + netrunner_int
	var sys_roll := randi_range(1, 10) + system_int
	var is_tie := nr_roll == sys_roll
	var netrunner_first := nr_roll > sys_roll
	initiative_rolled.emit(nr_roll, sys_roll, netrunner_first, is_tie)
	if not is_tie and not netrunner_first:
		# System wins initiative — adversaries act before the runner this round.
		is_netrunner_turn = false
		await run_adversary_phase(ice_nodes, target_pos, layout)
		if not is_inside_tree():
			return
	else:
		# Runner wins or ties — adversary phase runs after the runner's turn.
		_post_round_adversary = true
	start_netrunner_turn()

# Resolve the end of the netrunner's turn: run the deferred adversary phase
# (if the runner won/tied initiative this round), then start the next round
# with a fresh initiative roll. Fire-and-forget coroutine; callers do not await.
func end_round(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout, netrunner_int: int, system_int: int) -> void:
	end_player_turn()
	if _post_round_adversary:
		_post_round_adversary = false
		await run_adversary_phase(ice_nodes, target_pos, layout)
		if not is_inside_tree():
			return
	start_round(ice_nodes, target_pos, layout, netrunner_int, system_int)
