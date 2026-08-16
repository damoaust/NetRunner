class_name CP2020TurnManager
extends Node

signal turn_ended(is_netrunner_turn: bool)
signal ice_movement_stepped
signal actions_changed(remaining: int, max_actions: int)
signal movement_changed(remaining: int, max_movement: int)
signal initiative_rolled(netrunner_roll: int, system_roll: int, netrunner_first: bool, is_tie: bool)
# Emitted whenever an action is actually spent (program/Net action via
# consume_action(), or a completed movement action via _end_movement_action()).
# Scenes connect to this to advance RunState.net_time_seconds by their grid
# scale's per-action seconds. NOT emitted on failed/no-action-left calls.
signal action_consumed

# CP2020 unified action economy: the netrunner gets `max_actions` actions per
# turn (1 per CPU; mainframes raise this). Each action is EITHER a program/Net
# action OR movement of up to `max_movement` (5) grid spaces — NOT both.
# `movement_remaining` is the space budget for the CURRENT movement action; it
# resets to `max_movement` once that movement action is spent (all 5 spaces
# used, or the runner ends it early with Space). Using a program consumes an
# action and forfeits movement for that action. The turn ends when
# `actions_remaining` hits 0 (all actions spent) OR the player presses Space.
@export var max_actions: int = 1
@export var max_movement: int = 5

var is_netrunner_turn: bool = true
var actions_remaining: int = 1
var movement_remaining: int = 5
# True while the runner is mid-movement this action (moved ≥1 space, not yet
# exhausted or ended). A program cannot be fired while this is true — the
# runner must end the movement action (Space) first.
var _movement_action_active: bool = false
# Set by the game session when the cyberdeck is crashed: programs are
# unavailable, but movement is still allowed (CP2020 RAW — the runner can
# flee/jack out with a crashed deck). Reset to false at turn start.
var programs_blocked: bool = false
# True when this round's adversary phase is deferred to AFTER the netrunner's
# turn (the netrunner won or tied initiative, or round 1 where the runner acts
# first on entry). False when the system won initiative and the adversary
# phase already ran before the runner's turn.
var _post_round_adversary: bool = false


func start_netrunner_turn() -> void:
	is_netrunner_turn = true
	actions_remaining = max_actions
	movement_remaining = max_movement
	_movement_action_active = false
	programs_blocked = false
	actions_changed.emit(actions_remaining, max_actions)
	movement_changed.emit(movement_remaining, max_movement)
	turn_ended.emit(is_netrunner_turn)

func end_player_turn() -> void:
	is_netrunner_turn = false
	turn_ended.emit(is_netrunner_turn)

# Spend one action on a program/Net action. Forfeits any unused movement for
# this action (movement spaces don't carry over to a program action). Returns
# false if not the runner's turn or no actions remain.
func consume_action() -> bool:
	if not is_netrunner_turn:
		return false
	if actions_remaining <= 0:
		return false
	actions_remaining -= 1
	# A program action doesn't use movement; reset the space budget for the
	# next action (if any).
	movement_remaining = max_movement
	_movement_action_active = false
	actions_changed.emit(actions_remaining, max_actions)
	movement_changed.emit(movement_remaining, max_movement)
	action_consumed.emit()
	return true

func has_actions() -> bool:
	return is_netrunner_turn and actions_remaining > 0

# Whether the runner can fire a program right now: needs an action, programs
# not blocked (deck crash), and not mid-movement (must end the move first).
func can_use_programs() -> bool:
	return is_netrunner_turn and actions_remaining > 0 and not programs_blocked and not _movement_action_active

# Spend one movement space. Movement is a sub-activity of an action: the first
# step commits the current action to movement. When all `max_movement` spaces
# are used, the action is spent (actions_remaining decremented, movement
# resets for the next action). Returns false if not the runner's turn, no
# action to spend on movement, or no spaces left.
func consume_movement_step() -> bool:
	if not is_netrunner_turn:
		return false
	if actions_remaining <= 0:
		return false
	if movement_remaining <= 0:
		return false
	_movement_action_active = true
	movement_remaining -= 1
	movement_changed.emit(movement_remaining, max_movement)
	if movement_remaining <= 0:
		_end_movement_action()
	return true

func has_movement() -> bool:
	return is_netrunner_turn and actions_remaining > 0 and movement_remaining > 0

# End the in-progress movement action early (runner pressed Space after moving
# fewer than 5 spaces). Spends the action and resets the movement budget.
# Returns true if a movement action was active.
func end_movement_action() -> bool:
	if not _movement_action_active:
		return false
	_end_movement_action()
	return true

# Internal: finalize the current movement action — spend one action, reset the
# space budget, clear the mid-movement flag.
func _end_movement_action() -> void:
	_movement_action_active = false
	movement_remaining = max_movement
	actions_remaining -= 1
	actions_changed.emit(actions_remaining, max_actions)
	movement_changed.emit(movement_remaining, max_movement)
	action_consumed.emit()

# Count adversaries in `ice_nodes` that are still valid and can take a turn.
# Used to skip the adversary phase + initiative roll when there's no one left
# to act (auto round rollover).
func _count_valid_adversaries(ice_nodes: Array) -> int:
	var n := 0
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.has_method("take_turn"):
			n += 1
	return n

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
	# No enemies left to act → skip initiative + adversary phase, roll
	# straight back to the netrunner's turn.
	if _count_valid_adversaries(ice_nodes) == 0:
		start_netrunner_turn()
		return
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
# with a fresh initiative roll. If no enemies remain, both are skipped and the
# round rolls straight back to the netrunner. Fire-and-forget coroutine.
func end_round(ice_nodes: Array, target_pos: Vector2i, layout: CP2020DatafortLayout, netrunner_int: int, system_int: int) -> void:
	end_player_turn()
	if _post_round_adversary:
		_post_round_adversary = false
		# Enemies may have been killed during the runner's turn — only run the
		# deferred phase if some are still alive.
		if _count_valid_adversaries(ice_nodes) > 0:
			await run_adversary_phase(ice_nodes, target_pos, layout)
			if not is_inside_tree():
				return
	start_round(ice_nodes, target_pos, layout, netrunner_int, system_int)
