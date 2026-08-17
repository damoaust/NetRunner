class_name BlackIce
extends GridEntityBase

signal message_logged(msg: String)
signal attacked_netrunner(strength: int)
# Emitted by anti-program (DEREZ_ICE) ICE when it has line of sight to a
# rezzed attack program on the grid. Carries the attacker's STR (for the
# opposed roll) and the grid coord of the rezzed program being attacked.
# The game session resolves an opposed roll (Killer STR + 1D10 vs rezzed
# program integrity + 1D10); only the Killer can deal damage on a win —
# rezzed programs are passive defenders during the adversary phase.
signal attacked_program(attacker_str: int, tile_coord: Vector2i)
signal alarm_triggered
# Emitted by a tracing DETECTION ICE (Watchdog) when its trace check
# (1D10 + program.strength >= RunState.accumulated_trace) succeeds on first
# LoS detection. Carries the tracing program so the game session can log /
# resolve the trace. The game session starts the meatspace security-dispatch
# countdown on this signal.
signal trace_succeeded(program: NetProgram)
signal destroyed
# Emitted when a dormant ICE's opposed roll pierces the netrunner's active
# Invisibility cloak. The game session clears the cloak globally (on all
# adversaries) so subsequent detections proceed normally.
signal cloak_pierced

enum State { IDLE, PURSUE }

# ICE structural integrity. Set from `program.strength` at spawn time (1:1),
# so a stronger program is also tougher to DEREZ. initialize() copies this
# into current_integrity. No longer @export-authored per tile.
@export var max_integrity: int = 4

# Program sight radius (separate from the runner's sight_range so future
# modifiers can affect one side without the other). Defaults to 20, matching
# the runner's fog-of-war vision. Used to gate take_turn on line of sight.
@export var sight_range: int = 20

var current_state: State = State.IDLE
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

@onready var skull_label = $SkullLabel
@onready var sprite = $Sprite2D
# True when apply_visual_from_program chose the sprite path (program has a
# sprite_texture). update_visibility uses this to toggle the correct node.
var _use_sprite: bool = false

func _ready() -> void:
	# Point the shared base-class glyph label at this ICE's SkullLabel node so
	# the inherited glyph visual code targets it uniformly.
	glyph_label = skull_label

func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	super.initialize(start_pos, layout_size)
	current_integrity = max_integrity

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
		var result := CP2020Dice.roll_opposed(program.strength, cloak_program.strength)
		emit_log("Invisibility check: you %d (1D10+%d) vs %s %d (1D10+%d)." % [result.def_roll, cloak_program.strength, program.program_name, result.atk_roll, program.strength])
		if not result.attacker_wins:
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
func move_to_step(_coord: Vector2i) -> void:
	# The caller MUST set `current_position` to `coord` before calling — the
	# guarded helper updates the visual, awaits the step timer, and emits
	# moved_to. Guarding get_tree() avoids a crash if the ICE was freed
	# (e.g. derezzed during its movement loop). Awaited so the caller's
	# `await move_to_step(...)` pauses for the full step animation.
	await _guarded_step_timer(0.3)

# Emit hooks so NetProgram behavior can fire ICE signals without reaching
# into the Node's signal list directly.
func emit_attack_netrunner(dmg: int) -> void:
	attacked_netrunner.emit(dmg)

func emit_attack_program(atk_str: int, coord: Vector2i) -> void:
	attacked_program.emit(atk_str, coord)

func emit_alarm() -> void:
	alarm_triggered.emit()

# Emit hook for the trace-success signal (Watchdog tracing programs). Mirrors
# emit_alarm so NetProgram behavior can fire it without reaching into the
# Node's signal list directly.
func emit_trace_succeeded(prog: NetProgram) -> void:
	trace_succeeded.emit(prog)

func emit_log(msg: String) -> void:
	message_logged.emit(msg)

# Apply this ICE's on-map visual identity from its assigned program.
func apply_visual_from_program(p_program: NetProgram, p_glyph: String, p_color: Color) -> void:
	if p_program == null:
		return
		
	var sprite_tex: Texture2D = p_program.get_sprite()
	if sprite_tex != null and sprite:
		_use_sprite = true
		var frame_size: int = p_program.sprite_frame_size
		if frame_size <= 0:
			frame_size = 128
		var atlas := AtlasTexture.new()
		atlas.atlas = sprite_tex
		atlas.region = Rect2(p_program.sprite_frame * frame_size, 0, frame_size, frame_size)
		sprite.texture = atlas
		sprite.scale = Vector2(cell_size / float(frame_size), cell_size / float(frame_size)) * p_program.sprite_scale
		# sprite_offset is in screen pixels (same as glyph_offset), applied on
		# top of the Sprite2D's automatic tile-centring (centered=true at 0,0).
		sprite.position = p_program.sprite_offset
		sprite.visible = true
		if glyph_label:
			glyph_label.visible = false
		return
		
	# Glyph fallback path for ICE without a sprite.
	_use_sprite = false
	if sprite:
		sprite.visible = false
		
	# Pass the program and the hardcoded ICE fallback values to the parent
	super.apply_visual_from_program(p_program, p_glyph, p_color)

# Line-of-sight from this ICE's position to `target_pos` within sight_range.
func has_los_to(target_pos: Vector2i, layout: CP2020DatafortLayout) -> bool:
	return layout.line_of_sight(current_position, target_pos, sight_range, home_floor)

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
	if _use_sprite:
		if sprite:
			sprite.visible = p_visible
		if glyph_label:
			glyph_label.visible = false
	else:
		if glyph_label:
			glyph_label.visible = p_visible
		if sprite:
			sprite.visible = false

func take_damage(amount: int) -> bool:
	current_integrity -= amount
	message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [program.program_name, amount, max(0, current_integrity), max_integrity])
	if current_integrity <= 0:
		message_logged.emit("%s DEREZED! ICE destroyed." % program.program_name)
		destroyed.emit()
		queue_free()
		return true
	return false
