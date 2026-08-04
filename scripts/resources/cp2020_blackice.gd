class_name BlackIce
extends Node2D

signal message_logged(msg: String)
signal moved_to(new_pos: Vector2i)
signal attacked_netrunner(strength: int)
# Emitted by anti-program (DEREZ_ICE) ICE when it reaches the netrunner. The
# runner handles it by damaging an installed program (STR = max integrity).
signal attacked_program(strength: int)
signal alarm_triggered
signal destroyed

enum State { IDLE, PURSUE }

@export var program_name: String = "Hellhound"
@export var max_ap: int = 3
@export var strength: int = 4
@export var max_integrity: int = 4
# Tracing-type ICE: on activation it must trace the netrunner's signal before it
# can hunt. Rolls 1D10 + strength vs RunState.accumulated_trace once per run.
@export var traces: bool = false

# The ICE's attack behavior, sourced from an assigned NetProgram .tres
# (effect_type) in the datafort designer. DAMAGE_RUNNER (anti-personnel) hits
# the netrunner's health; DEREZ_ICE (anti-program) targets an installed
# program instead. Defaults to DAMAGE_RUNNER for backward compatibility with
# existing scalar-only ICE tiles.
@export var effect_type: int = NetProgram.EffectType.DAMAGE_RUNNER

# Per-hit damage dice, sourced from an assigned NetProgram .tres with
# `damage_dice > 0`. 0 = emit flat `strength` as damage (existing behaviour);
# >0 = roll 1D{damage_dice} per attack hit instead (e.g. Sword rolls 1D6).
# Set by CP2020GameSession.spawn_black_ice from the assigned program.
@export var damage_dice: int = 0

# Program sight radius (separate from the runner's sight_range so future
# modifiers can affect one side without the other). Defaults to 20, matching
# the runner's fog-of-war vision. Used to gate take_turn on line of sight.
@export var sight_range: int = 20

var current_position: Vector2i = Vector2i.ZERO
var current_state: State = State.IDLE
var astar_grid: AStarGrid2D
var current_integrity: int = 4
var _activated: bool = false
# Tracks the previous turn's LoS state so transition (seen<->lost) messages
# log only on the change, not every turn.
var _had_los: bool = false

@export var cell_size: int = 40
@export var grid_offset_y: int = 90
@export var label_visual_offset: Vector2 = Vector2(-2, -4)

@onready var skull_label = $SkullLabel

func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	current_position = start_pos
	current_integrity = max_integrity
	
	if skull_label:
		skull_label.size = Vector2(cell_size, cell_size)
		skull_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + label_visual_offset
		skull_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skull_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	update_visual_position()
	
	if astar_grid:
		astar_grid.free()
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, layout_size.x, layout_size.y)
	astar_grid.cell_size = Vector2(1, 1)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()
	
	moved_to.emit(current_position)

func update_visual_position() -> void:
	var center_x = (current_position.x * cell_size) + (cell_size / 2.0)
	var center_y = grid_offset_y + (current_position.y * cell_size) + (cell_size / 2.0)
	position = Vector2(center_x, center_y)

func take_turn(target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	# Sight gating: a program can only act against the netrunner when it has
	# line of sight to them, within `sight_range` spaces and blocked by
	# Datawalls/locked Code Gates. Without LoS the ICE goes dormant (holds
	# position, no activation/pursue this turn). The one-time `traces` check
	# therefore fires the first turn the ICE gains LoS.
	var los := layout.line_of_sight(current_position, target_pos, sight_range)
	if not los:
		if _had_los:
			message_logged.emit("%s loses sight of the netrunner — holding position." % program_name)
		_had_los = false
		return
	if not _had_los and _activated:
		message_logged.emit("%s reacquires the netrunner!" % program_name)
	_had_los = true

	var was_activated := _activated
	if not _activated:
		_activated = true
		if traces:
			# Tracing programs must beat the run's accumulated trace difficulty
			# to locate the netrunner's signal before they can hunt.
			var trace_roll := randi_range(1, 10) + strength
			if trace_roll < RunState.accumulated_trace:
				message_logged.emit("%s failed to trace your signal (1D10+STR %d vs trace %d) — idle." % [program_name, trace_roll, RunState.accumulated_trace])
				return
			message_logged.emit("%s traced your signal (1D10+STR %d vs trace %d)." % [program_name, trace_roll, RunState.accumulated_trace])

	# DETECTION ICE (Watchdog): on first activation, trip the alarm and
	# stay stationary. It never pursues or attacks — its job is to alert
	# other ICE, not fight.
	if effect_type == NetProgram.EffectType.DETECTION:
		if not was_activated:
			message_logged.emit("ALARM: %s detects intruder! Sounding alarm!" % program_name)
			alarm_triggered.emit()
		return

	if current_state == State.IDLE:
		current_state = State.PURSUE
		message_logged.emit("WARNING: %s activated and is hunting!" % program_name)
		
	if current_state != State.PURSUE:
		return
		
	_update_obstacles(layout)
	
	var ap_remaining = max_ap
	while ap_remaining > 0:
		var path = astar_grid.get_id_path(current_position, target_pos)
		
		if path.size() > 1: 
			var next_step = path[1]
			
			if next_step == target_pos:
				var dmg := _roll_damage()
				match effect_type:
					NetProgram.EffectType.DEREZ_ICE:
						message_logged.emit("CRITICAL: %s executes DEREZ_ICE attack for %d damage!" % [program_name, dmg])
						attacked_program.emit(dmg)
					_:
						message_logged.emit("CRITICAL: %s attacks Netrunner for %d damage!" % [program_name, dmg])
						attacked_netrunner.emit(dmg)
				break
				
			current_position = next_step
			ap_remaining -= 1
			update_visual_position()
			
			await get_tree().create_timer(0.3).timeout
			moved_to.emit(current_position)
		else:
			break

# Returns the damage dealt per attack hit. When `damage_dice > 0` rolls
# 1D{damage_dice} (per the assigned program's profile, e.g. Sword's 1D6);
# otherwise uses flat `strength` (existing behaviour for all legacy programs
# and scalar/tier-template ICE without an assigned program).
func _roll_damage() -> int:
	return strength if damage_dice <= 0 else randi_range(1, damage_dice)

func _update_obstacles(layout: CP2020DatafortLayout) -> void:
	astar_grid.fill_solid_region(astar_grid.region, false)

	for raw_key in layout.grid_tiles.keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
		var tile = layout.get_tile(coord)
		if tile:
			if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL or (tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked):
				astar_grid.set_point_solid(coord, true)

# Called by the game session when a Watchdog trips the alarm. Wakes this
# dormant ICE and sets it to PURSUE, even if it hasn't seen the netrunner
# yet. Used to activate all attack ICE in the datafort at once.
func activate_alarm() -> void:
	if not _activated:
		_activated = true
	if current_state == State.IDLE:
		current_state = State.PURSUE
		message_logged.emit("ALARM: %s woken and hunting!" % program_name)

func update_visibility(is_explored: bool, is_visible: bool) -> void:
	if not skull_label:
		return
	skull_label.visible = is_visible

func take_damage(amount: int) -> bool:
	current_integrity -= amount
	message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [program_name, amount, max(0, current_integrity), max_integrity])
	if current_integrity <= 0:
		message_logged.emit("%s DEREZED! ICE destroyed." % program_name)
		destroyed.emit()
		queue_free()
		return true
	return false
