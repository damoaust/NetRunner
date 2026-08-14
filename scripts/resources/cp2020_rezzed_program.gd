class_name RezzedProgram
extends Node2D

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
signal moved_to(new_pos: Vector2i)
signal destroyed

# The program this node represents (a duplicate of the installed copy).
var program: NetProgram = null
# Reference to the original installed program copy — used by the game session
# to track which installed copies are currently rezzed (one node per copy).
var source_program: NetProgram = null

@export var max_integrity: int = 4
var current_integrity: int = 4

var current_position: Vector2i = Vector2i.ZERO
# Floor the program was rezzed on. Stays on its floor (like ICE) — does not
# follow the runner up/down. Only programs with home_floor == current_floor
# follow or render.
var home_floor: int = 0
var astar_grid: AStarGrid2D

@export var cell_size: int = 40
@export var grid_offset_y: int = 90
@export var label_visual_offset: Vector2 = Vector2(-2, -4)

@onready var glyph_label = $GlyphLabel

func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	current_position = start_pos
	current_integrity = max_integrity

	if glyph_label:
		glyph_label.size = Vector2(cell_size, cell_size)
		glyph_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + label_visual_offset
		glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

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

# Animates a single step to `coord`. The caller MUST set `current_position`
# to `coord` before calling — this only updates the visual, awaits the step
# timer, and emits moved_to. Resources can't await get_tree(), so the await
# lives here on the Node2D.
func move_to_step(coord: Vector2i) -> void:
	update_visual_position()
	await get_tree().create_timer(0.3).timeout
	moved_to.emit(current_position)

func emit_log(msg: String) -> void:
	message_logged.emit(msg)

# Apply this node's on-map visual identity from its assigned program: sets the
# glyph label text + tints its LabelSettings font_color. The LabelSettings is
# duplicated per instance so the shared scene sub-resource is never mutated.
# The label position is auto-centred using the glyph's TextServer bitmap metrics
# (so different Unicode glyphs sit centred without manual tuning); the
# per-program `glyph_offset` stacks on top for stubborn edge cases. No-op if
# the label or program is missing. Call after initialize().
func apply_visual_from_program() -> void:
	if glyph_label == null or program == null:
		return
	var vis: Dictionary = program.get_visual()
	var glyph: String = vis.get("glyph", "◆")
	glyph_label.text = glyph
	var col: Color = vis.get("color", Color.CYAN)
	if glyph_label.label_settings:
		glyph_label.label_settings = glyph_label.label_settings.duplicate()
		glyph_label.label_settings.font_color = col
	else:
		glyph_label.add_theme_color_override("font_color", col)
	# Auto-centre the glyph via its TextServer bitmap metrics. Falls back to the
	# node's manual label_visual_offset when metrics are unavailable.
	var font: Font = null
	var font_size: int = 0
	if glyph_label.label_settings and glyph_label.label_settings.font:
		font = glyph_label.label_settings.font
		font_size = int(glyph_label.label_settings.font_size)
	else:
		font = glyph_label.get_theme_default_font()
		font_size = int(glyph_label.get_theme_default_font_size())
	var auto_offset: Vector2 = NetProgram.compute_glyph_centering(glyph, font, font_size, cell_size)
	if auto_offset == Vector2.ZERO:
		auto_offset = label_visual_offset
	glyph_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + auto_offset + program.glyph_offset

# Rebuild the astar solid region from Datawalls and locked Code Gates. Called
# by the game session before the auto-follow path each turn.
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

func update_visibility(is_explored: bool, is_visible: bool) -> void:
	if not glyph_label:
		return
	glyph_label.visible = is_visible

func take_damage(amount: int) -> bool:
	current_integrity -= amount
	message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [program.program_name, amount, max(0, current_integrity), max_integrity])
	if current_integrity <= 0:
		message_logged.emit("%s DEREZZED! Program destroyed." % program.program_name)
		destroyed.emit()
		queue_free()
		return true
	return false