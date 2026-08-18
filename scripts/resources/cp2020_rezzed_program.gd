class_name RezzedProgram
extends GridEntityBase

# A runner-owned attack program rezzed onto the net as an active, visible
# node. Modeled on BlackIce but friendly: it auto-follows the runner each
# turn (trailing to an adjacent tile) and can be commanded to attack a target
# (Black ICE / NPC / CPU). The runner rezzes it (1 action) and later commands
# it to attack (1 action). It can be de-rezzed at any time (free).
#
# The node owns a duplicate of the installed program (so mutating it never
# touches the cached .tres); `source_program` references the original installed
# copy for de-rez bookkeeping (one rezzed node per installed copy).
#
# Integrity (HP) is derived 1:1 from program.strength, matching BlackIce. In
# Phase 1 enemy anti-program ICE does not target rezzed programs, but the
# fields exist for a later phase.

signal message_logged(msg: String)
signal destroyed

# Reference to the original installed program copy — used by the game session
# to track which installed copies are currently rezzed (one node per copy).
var source_program: NetProgram = null

@export var max_integrity: int = 4
var current_integrity: int = 4

func _ready() -> void:
	glyph_label = $GlyphLabel

func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	super.initialize(start_pos, layout_size)
	current_integrity = max_integrity

# Animates a single step to `coord`. The caller MUST set `current_position`
# to `coord` before calling — this only updates the visual, awaits the step
# timer, and emits moved_to. Resources can't await get_tree(), so the await
# lives here on the Node2D.
func move_to_step(_coord: Vector2i) -> void:
	# The caller MUST set `current_position` to `coord` before calling. The
	# guarded helper updates the visual, awaits the step timer, and emits
	# moved_to, bailing cleanly if the node was freed mid-turn. Awaited so
	# the caller's `await move_to_step(...)` pauses for the full animation.
	await _guarded_step_timer(0.3)

func emit_log(msg: String) -> void:
	message_logged.emit(msg)



# Apply this node's on-map visual identity from its assigned program. Delegates
# to the shared glyph applier in GridEntityBase using the rezzed-program glyph
# fallback. Call after initialize().
func apply_visual_from_program(p_program: NetProgram = null, p_glyph: String = "◆", p_color: Color = Color.CYAN) -> void:
	# If called with no arguments, fall back to the node's internal 'program' property
	var target_program: NetProgram = p_program
	if target_program == null:
		target_program = self.program
		
	# Pass the target program and the hardcoded friendly ICE fallback values to the parent
	super.apply_visual_from_program(target_program, p_glyph, p_color)

func update_visibility(_is_explored: bool, p_visible: bool) -> void:
	if not glyph_label:
		return
	glyph_label.visible = p_visible and not visual_3d_mode

func take_damage(amount: int) -> bool:
	current_integrity -= amount
	message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [program.program_name, amount, max(0, current_integrity), max_integrity])
	if current_integrity <= 0:
		message_logged.emit("%s DEREZZED! Program destroyed." % program.program_name)
		destroyed.emit()
		queue_free()
		return true
	return false
