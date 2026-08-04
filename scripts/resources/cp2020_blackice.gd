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

# The assigned program that defines this ICE's behavior (effect_type, strength,
# damage_dice, program_name come from here — BlackICE has no program-specific
# logic of its own; it delegates to program.take_ice_turn). Always set by
# CP2020GameSession.spawn_black_ice (either the assigned .tres duplicate, or a
# NetProgram built from the tier template). Set BEFORE initialize().
var program: NetProgram = null

@export var max_ap: int = 3
@export var max_integrity: int = 4
# Tracing-type ICE: on activation it must trace the netrunner's signal before it
# can hunt. Rolls 1D10 + strength vs RunState.accumulated_trace once per run.
@export var traces: bool = false

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
	# LoS gating is shared infrastructure for ALL ICE (including Watchdog):
	# a program can only act when it has line of sight within sight_range,
	# blocked by Datawalls / locked Code Gates. The program-specific
	# behavior (hunt, alarm, etc.) is delegated to program.take_ice_turn.
	var los := layout.line_of_sight(current_position, target_pos, sight_range)
	if not los:
		if _had_los:
			emit_log("%s loses sight of the netrunner — holding position." % program.program_name)
		_had_los = false
		return
	if not _had_los and _activated:
		emit_log("%s reacquires the netrunner!" % program.program_name)
	_had_los = true
	program.take_ice_turn(self, target_pos, layout)

# Next grid step toward `target_pos` via the astar grid, or `current_position`
# if already adjacent/at target. Convenience for subclasses doing manual
# pathing; the default take_ice_turn reads astar_grid directly.
func next_step_to(target_pos: Vector2i) -> Vector2i:
	var path = astar_grid.get_id_path(current_position, target_pos)
	return path[1] if path.size() > 1 else current_position

# Animates a single step to `coord`. The caller MUST set `current_position`
# to `coord` before calling — this only updates the visual, awaits the step
# timer, and emits moved_to. Resources can't await get_tree(), so the await
# lives here on the Node2D.
func move_to_step(coord: Vector2i) -> void:
	update_visual_position()
	await get_tree().create_timer(0.3).timeout
	moved_to.emit(current_position)

# Emit hooks so NetProgram behavior can fire ICE signals without reaching
# into the Node's signal list directly.
func emit_attack_netrunner(dmg: int) -> void:
	attacked_netrunner.emit(dmg)

func emit_attack_program(dmg: int) -> void:
	attacked_program.emit(dmg)

func emit_alarm() -> void:
	alarm_triggered.emit()

func emit_log(msg: String) -> void:
	message_logged.emit(msg)

# Line-of-sight from this ICE's position to `target_pos` within sight_range.
func has_los_to(target_pos: Vector2i, layout: CP2020DatafortLayout) -> bool:
	return layout.line_of_sight(current_position, target_pos, sight_range)

# Rebuild the astar solid region from Datawalls and locked Code Gates. Called
# by the program's behavior each turn before pathing.
func refresh_pathfinding(layout: CP2020DatafortLayout) -> void:
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
		message_logged.emit("ALARM: %s woken and hunting!" % program.program_name)

func update_visibility(is_explored: bool, is_visible: bool) -> void:
	if not skull_label:
		return
	skull_label.visible = is_visible

func take_damage(amount: int) -> bool:
	current_integrity -= amount
	message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [program.program_name, amount, max(0, current_integrity), max_integrity])
	if current_integrity <= 0:
		message_logged.emit("%s DEREZED! ICE destroyed." % program.program_name)
		destroyed.emit()
		queue_free()
		return true
	return false
