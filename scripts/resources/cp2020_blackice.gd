class_name BlackIce
extends Node2D

signal message_logged(msg: String)
signal moved_to(new_pos: Vector2i)
signal attacked_netrunner(strength: int)
# Emitted by anti-program (DEREZ_ICE) ICE when it has line of sight to a
# Emitted by anti-program (DEREZ_ICE) ICE when it has line of sight to a
# rezzed attack program on the grid. Carries the attacker's STR (for the
# opposed roll) and the grid coord of the rezzed program being attacked.
# The game session resolves an opposed roll (Killer STR + 1D10 vs rezzed
# program integrity + 1D10); only the Killer can deal damage on a win —
# rezzed programs are passive defenders during the adversary phase.
signal attacked_program(attacker_str: int, tile_coord: Vector2i)
signal alarm_triggered
signal destroyed
# Emitted when a dormant ICE's opposed roll pierces the netrunner's active
# Invisibility cloak. The game session clears the cloak globally (on all
# adversaries) so subsequent detections proceed normally.
signal cloak_pierced

enum State { IDLE, PURSUE }

# The assigned program that defines this ICE's behavior (effect_type, strength,
# damage_dice, program_name come from here — BlackICE has no program-specific
# logic of its own; it delegates to program.take_ice_turn). Always set by
# CP2020GameSession.spawn_black_ice (either the assigned .tres duplicate, or a
# NetProgram built from the tier template). Set BEFORE initialize().
var program: NetProgram = null

# ICE structural integrity. Set from `program.strength` at spawn time (1:1),
# so a stronger program is also tougher to DEREZ. initialize() copies this
# into current_integrity. No longer @export-authored per tile.
@export var max_integrity: int = 4

# Program sight radius (separate from the runner's sight_range so future
# modifiers can affect one side without the other). Defaults to 20, matching
# the runner's fog-of-war vision. Used to gate take_turn on line of sight.
@export var sight_range: int = 20

var current_position: Vector2i = Vector2i.ZERO
var current_state: State = State.IDLE
# Floor this ICE was spawned on. Adversaries stay on their floor — they do
# not follow the runner up/down. The game session gates take_turn by
# `home_floor == layout.current_floor`. See docs/multi-floor-travel-plan.md §2b.
var home_floor: int = 0
var astar_grid: AStarGrid2D
var current_integrity: int = 4
var _activated: bool = false
# Tracks the previous turn's LoS state so transition (seen<->lost) messages
# log only on the change, not every turn.
var _had_los: bool = false
# The netrunner's active Invisibility cloak, or null. Set by the game session
# on every ice_nodes entry when the runner raises the cloak, and cleared (on
# all entries) when a seeker pierces it. While set, a dormant ICE (not yet
# _activated) that gains LoS must win an opposed roll (1D10+cloak.strength vs
# 1D10+this.program.strength) to detect the runner; on a hold the ICE stays
# dormant this turn (re-tests next LoS turn), on a pierce the ICE activates and
# the cloak is broken globally. Already-active ICE ignore the cloak.
var cloak_program: NetProgram = null

# Reference to the game session's rezzed_program_nodes array, set at spawn
# time. GDScript Arrays are reference types, so additions/removals during
# gameplay are visible to all ICE without re-pushing. Used by anti-program
# (DEREZ_ICE) ICE to scan for rezzed attack programs within LoS.
var rezzed_programs: Array = []

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
	# DEREZ_ICE (Killer) is a stationary anti-program sentry that scans for
	# Worms in LoS — it does not care about the netrunner, so skip the runner
	# LoS check, _had_los tracking, and Invisibility cloak gate entirely.
	# program.take_ice_turn branches to _take_killer_turn for DEREZ_ICE.
	if program and program.effect_type == NetProgram.EffectType.DEREZ_ICE:
		program.take_ice_turn(self, target_pos, layout)
		return
	# LoS gating is shared infrastructure for ALL ICE (including Watchdog):
	# a program can only act when it has line of sight within sight_range,
	# blocked by Datawalls / locked Code Gates. The program-specific
	# behavior (hunt, alarm, etc.) is delegated to program.take_ice_turn.
	var los := layout.line_of_sight(current_position, target_pos, sight_range, home_floor)
	if not los:
		if _had_los:
			emit_log("%s loses sight of the netrunner — holding position." % program.program_name)
		_had_los = false
		return
	if not _had_los and _activated:
		emit_log("%s reacquires the netrunner!" % program.program_name)
	_had_los = true
	# Invisibility cloak gate: a dormant ICE (not yet _activated) that just
	# gained LoS must beat the cloak in an opposed roll to detect the runner.
	# Already-active ICE (already hunting) bypass the cloak — Invisibility only
	# prevents initial notice, not ongoing attacks. Hold -> stay dormant this
	# turn (re-roll next LoS turn); pierce -> activate normally and break the
	# cloak globally (emit cloak_pierced so the session clears it on all foes).
	if cloak_program != null and not _activated:
		var hider_roll := randi_range(1, 10) + cloak_program.strength
		var seeker_roll := randi_range(1, 10) + program.strength
		emit_log("Invisibility check: you %d (1D10+%d) vs %s %d (1D10+%d)." % [hider_roll, cloak_program.strength, program.program_name, seeker_roll, program.strength])
		if seeker_roll <= hider_roll:
			emit_log("Invisibility holds — %s registers you as static and ignores you." % program.program_name)
			# Did not acquire the runner this turn: keep _had_los false so the
			# lose/reacquire transition messages stay consistent next turn.
			_had_los = false
			return
		emit_log("Invisibility pierced by %s! Cloak burned out." % program.program_name)
		cloak_program = null
		cloak_pierced.emit()
		# Fall through: this ICE now activates normally.
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

func emit_attack_program(atk_str: int, coord: Vector2i) -> void:
	attacked_program.emit(atk_str, coord)

func emit_alarm() -> void:
	alarm_triggered.emit()

func emit_log(msg: String) -> void:
	message_logged.emit(msg)

# Apply this ICE's on-map visual identity from its assigned program: sets the
# skull label text + tints its LabelSettings font_color. The LabelSettings is
# duplicated per instance so the shared scene sub-resource is never mutated.
# The label position is auto-centred using the glyph's TextServer bitmap metrics
# (so different Unicode glyphs sit centred without manual tuning); the
# per-program `glyph_offset` stacks on top for stubborn edge cases. No-op if
# the label or program is missing. Call after initialize().
func apply_visual_from_program() -> void:
	if skull_label == null or program == null:
		return
	var vis: Dictionary = program.get_visual()
	var glyph: String = vis.get("glyph", "☠")
	skull_label.text = glyph
	var col: Color = vis.get("color", Color.RED)
	if skull_label.label_settings:
		skull_label.label_settings = skull_label.label_settings.duplicate()
		skull_label.label_settings.font_color = col
	else:
		skull_label.add_theme_color_override("font_color", col)
	# Auto-centre the glyph via its TextServer bitmap metrics. Falls back to the
	# node's manual label_visual_offset when metrics are unavailable.
	# NB: the scene LabelSettings sets font_size (30) but no font, so the Font
	# reference falls back to the theme default font while the SIZE must still
	# come from label_settings — measuring at the default size (~16) while the
	# Label renders at 30 produces a centring offset for the wrong glyph size.
	var font: Font = null
	var font_size: int = 0
	if skull_label.label_settings:
		font = skull_label.label_settings.font
		font_size = int(skull_label.label_settings.font_size)
	if font == null:
		font = skull_label.get_theme_default_font()
	if font_size <= 0:
		font_size = int(skull_label.get_theme_default_font_size())
	# Resolve which font has the glyph. The theme font (whitrabt) lacks many
	# Unicode symbols, so fall back to seguiemj.ttf (Segoe UI Emoji) for both
	# metrics and rendering when the glyph isn't found.
	var auto_offset: Vector2 = NetProgram.compute_glyph_centering(glyph, font, font_size, cell_size)
	if auto_offset == Vector2.ZERO:
		var fallback_font: Font = load("res://data/seguiemj.ttf") as Font
		if fallback_font != null:
			var fb_offset: Vector2 = NetProgram.compute_glyph_centering(glyph, fallback_font, font_size, cell_size)
			if fb_offset != Vector2.ZERO:
				auto_offset = fb_offset
				if skull_label.label_settings:
					skull_label.label_settings.font = fallback_font
				else:
					skull_label.add_theme_font_override("font", fallback_font)
	# When auto-center is disabled the designer positions the glyph entirely via
	# glyph_offset in the Inspector; auto_offset is discarded.
	if not program.glyph_auto_center:
		auto_offset = Vector2.ZERO
	elif auto_offset == Vector2.ZERO:
		auto_offset = label_visual_offset
	skull_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + auto_offset + program.glyph_offset

# Line-of-sight from this ICE's position to `target_pos` within sight_range.
func has_los_to(target_pos: Vector2i, layout: CP2020DatafortLayout) -> bool:
	return layout.line_of_sight(current_position, target_pos, sight_range, home_floor)

# Rebuild the astar solid region from Datawalls and locked Code Gates. Called
# by the program's behavior each turn before pathing.
func refresh_pathfinding(layout: CP2020DatafortLayout) -> void:
	astar_grid.fill_solid_region(astar_grid.region, false)

	for raw_key in layout.get_floor_tiles(home_floor).keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
		var tile = layout.get_tile(coord, home_floor)
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

func update_visibility(_is_explored: bool, p_visible: bool) -> void:
	if not skull_label:
		return
	skull_label.visible = p_visible

func take_damage(amount: int) -> bool:
	current_integrity -= amount
	message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [program.program_name, amount, max(0, current_integrity), max_integrity])
	if current_integrity <= 0:
		message_logged.emit("%s DEREZED! ICE destroyed." % program.program_name)
		destroyed.emit()
		queue_free()
		return true
	return false
