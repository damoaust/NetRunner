class_name GridEntityBase
extends Node2D

# Shared base for on-grid entity nodes (BlackICE / RezzedProgram / NPC
# netrunners). Centralises the duplicated pixel<->grid math, AStarGrid2D
# construction + obstacle marking, the program-driven glyph visual applier,
# and a guarded step-timer (so a freed entity mid-movement doesn't crash on
# `await get_tree()`). Entity-specific logic (AI, combat, signals beyond
# moved_to) lives in the subclasses.

signal moved_to(new_pos: Vector2i)

# Preloaded once — replaces the per-call load("res://data/seguiemj.ttf") that
# every glyph applier used to issue on the fallback path.
const FALLBACK_FONT := preload("res://data/seguiemj.ttf")

@export var cell_size: int = 40
@export var grid_offset_y: int = 90
@export var label_visual_offset: Vector2 = Vector2(-2, -4)

var current_position: Vector2i = Vector2i.ZERO
# Floor this entity was spawned on. Adversaries stay on their floor — they do
# not follow the runner up/down. Set by the game session (before or after
# initialize, depending on the entity) and read at runtime by pathfinding / LoS.
var home_floor: int = 0
var astar_grid: AStarGrid2D
# Visual source program (BlackICE / RezzedProgram). NPCs leave this null and
# style their glyph from faction instead.
var program: NetProgram = null
# The Label node used for the glyph fallback visual. Subclasses assign their
# scene label (SkullLabel / GlyphLabel) here in _ready() so the shared visual
# code can target it uniformly.
var glyph_label: Label = null
# When true, the 2D glyph/sprite visual is hidden because a 3D proxy renders
# the entity in the board_3d layer instead. Set by the game session when the
# 3D board is active.
var visual_3d_mode: bool = false


func set_visual_3d_mode(active: bool) -> void:
	visual_3d_mode = active
	# Hide the 2D glyph immediately when 3D mode is on so a freshly-spawned
	# entity (e.g. a rezzed program created mid-game, after the load-time fog
	# pass) doesn't show its 2D glyph for a frame until the next
	# update_visibility call. Restoring visibility on deactivate is left to
	# the next update_visibility (fog) pass — 3D mode is set once at load and
	# rarely toggled off mid-run.
	if active and glyph_label:
		glyph_label.visible = false


# Common setup shared by every entity's initialize(): records the start
# position, sizes/aligns the glyph label to its tile, snaps the visual to the
# start cell, builds a fresh AStarGrid2D sized to the layout, and emits the
# initial moved_to. Subclasses call this via super.initialize() then apply
# their own integrity/health/glyph-style. Does NOT touch home_floor (the
# session sets that separately, sometimes after initialize).
func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	current_position = start_pos
	_setup_label()
	update_visual_position()
	_build_astar_grid(layout_size)
	moved_to.emit(current_position)


# Build a fresh AStarGrid2D sized to `layout_size` with the shared config
# (unit cell, no diagonals). Frees any prior grid first.
func _build_astar_grid(layout_size: Vector2i) -> void:
	if astar_grid:
		astar_grid.free()
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, layout_size.x, layout_size.y)
	astar_grid.cell_size = Vector2(1, 1)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()


# Size/align the glyph label to fill its tile. No-op if the label is missing.
func _setup_label() -> void:
	if glyph_label == null:
		return
	glyph_label.size = Vector2(cell_size, cell_size)
	glyph_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + label_visual_offset
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func update_visual_position() -> void:
	var center_x = (current_position.x * cell_size) + (cell_size / 2.0)
	var center_y = grid_offset_y + (current_position.y * cell_size) + (cell_size / 2.0)
	position = Vector2(center_x, center_y)


# Rebuild the astar solid region from Datawalls and locked Code Gates on this
# entity's home floor. Called by each entity before pathing each turn.
func refresh_pathfinding(layout: CP2020DatafortLayout) -> void:
	astar_grid.fill_solid_region(astar_grid.region, false)

	for raw_key in layout.get_floor_tiles(home_floor).keys():
		var coord := CP2020DatafortLayout.parse_coord(raw_key)
		var tile = layout.get_tile(coord, home_floor)
		if tile:
			if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL or (tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked):
				astar_grid.set_point_solid(coord, true)


# Apply this entity's on-map visual identity from its assigned program: sets
# the glyph label text + tints its LabelSettings font_color. The LabelSettings
# is duplicated per instance so the shared scene sub-resource is never mutated.
# The label position is auto-centred using the glyph's TextServer bitmap metrics
# (so different Unicode glyphs sit centred without manual tuning); the
# per-program `glyph_offset` stacks on top for stubborn edge cases. No-op if
# the label or program is missing. `fallback_glyph` / `fallback_color` are used
# when the program has no visual override (per effect-type defaults come from
# program.get_visual()). Call after initialize().
func apply_visual_from_program(p_program: NetProgram, fallback_glyph: String, fallback_color: Color) -> void:
	if glyph_label == null or p_program == null:
		return
	var vis: Dictionary = p_program.get_visual()
	var glyph: String = vis.get("glyph", fallback_glyph)
	glyph_label.text = glyph
	var col: Color = vis.get("color", fallback_color)
	if glyph_label.label_settings:
		glyph_label.label_settings = glyph_label.label_settings.duplicate()
		glyph_label.label_settings.font_color = col
	else:
		glyph_label.add_theme_color_override("font_color", col)
	# Auto-centre the glyph via its TextServer bitmap metrics. Falls back to the
	# node's manual label_visual_offset when metrics are unavailable.
	# NB: the scene LabelSettings sets font_size but no font, so the Font
	# reference falls back to the theme default font while the SIZE must still
	# come from label_settings — measuring at the default size while the Label
	# renders at the LabelSettings size produces a centring offset for the
	# wrong glyph size.
	var font: Font = null
	var font_size: int = 0
	if glyph_label.label_settings:
		font = glyph_label.label_settings.font
		font_size = int(glyph_label.label_settings.font_size)
	if font == null:
		font = glyph_label.get_theme_default_font()
	if font_size <= 0:
		font_size = int(glyph_label.get_theme_default_font_size())
	# Resolve which font has the glyph. The theme font (whitrabt) lacks many
	# Unicode symbols, so fall back to seguiemj.ttf (Segoe UI Emoji) for both
	# metrics and rendering when the glyph isn't found.
	var auto_offset: Vector2 = NetProgram.compute_glyph_centering(glyph, font, font_size, cell_size)
	if auto_offset == Vector2.ZERO:
		var fallback_font: Font = FALLBACK_FONT
		if fallback_font != null:
			var fb_offset: Vector2 = NetProgram.compute_glyph_centering(glyph, fallback_font, font_size, cell_size)
			if fb_offset != Vector2.ZERO:
				auto_offset = fb_offset
				if glyph_label.label_settings:
					glyph_label.label_settings.font = fallback_font
				else:
					glyph_label.add_theme_font_override("font", fallback_font)
	# When auto-center is disabled the designer positions the glyph entirely via
	# glyph_offset in the Inspector; auto_offset is discarded.
	if not p_program.glyph_auto_center:
		auto_offset = Vector2.ZERO
	elif auto_offset == Vector2.ZERO:
		auto_offset = label_visual_offset
	glyph_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + auto_offset + p_program.glyph_offset


# Guarded step timer: update the visual, await a SceneTree timer, then emit
# moved_to. If the tree is gone mid-turn (entity freed/removed during its
# movement loop), bail by emitting moved_to immediately instead of crashing on
# `await get_tree().create_timer()`. The caller MUST set `current_position`
# to the destination before calling — this only updates the visual, awaits,
# and emits. Fixes the unguarded await crash in NPC movement + RezzedProgram.
func _guarded_step_timer(seconds: float) -> void:
	update_visual_position()
	var tree: SceneTree = get_tree()
	if tree == null:
		moved_to.emit(current_position)
		return
	await tree.create_timer(seconds).timeout
	moved_to.emit(current_position)