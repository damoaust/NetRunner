class_name CP2020BoardRenderer
extends Node2D

@export var cell_size: int = 40
@export var grid_offset_y: int = 90

# --- Themeable colors (inspector-editable; defaults reproduce the original
# hardcoded palette). Colours used with the fog alpha multiplier store their
# base alpha here; _a() scales it by alpha_mult at draw time. ---

@export_group("Grid")
@export var color_grid_bg: Color = Color(0.02, 0.03, 0.06, 1.0)
@export var color_grid_line: Color = Color(0.0, 0.78, 0.92, 0.22)
@export var color_grid_line_bright: Color = Color(0.0, 0.9, 1.0, 0.55)
@export var color_unexplored_fill: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var color_fog_overlay: Color = Color(0.01, 0.02, 0.04, 0.88)
@export var color_visible_overlay: Color = Color(0.04, 0.08, 0.12, 0.35)
@export var color_empty_dot: Color = Color(0.0, 0.78, 0.92, 0.35)

@export_group("Grid Effects")
@export var color_scanline: Color = Color(0.0, 0.0, 0.0, 0.12)
@export var color_vignette: Color = Color(0.0, 0.0, 0.0, 0.3)
@export var color_tech_frame: Color = Color(0.0, 0.9, 1.0, 0.55)

@export_group("Entry")
@export var color_entry_fill: Color = Color(0.0, 0.4, 0.8, 0.3)
@export var color_entry_frame: Color = Color(0.0, 1.0, 1.0, 1.0)
@export var color_entry_up: Color = Color(0.0, 0.8, 0.8, 1.0)
@export var color_entry_down: Color = Color(0.6, 0.2, 0.8, 1.0)
@export var color_entry_up_glyph: Color = Color(0.0, 0.9, 0.9, 1.0)
@export var color_entry_down_glyph: Color = Color(0.8, 0.4, 1.0, 1.0)
@export var color_primary_entry_mark: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Datawall")
@export var color_wall_fill: Color = Color(0.8, 0.1, 0.1, 0.6)
@export var color_wall_border: Color = Color(1.0, 0.0, 0.0, 1.0)

@export_group("Code Gate")
@export var color_gate_unlocked: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var color_gate_locked: Color = Color(1.0, 0.5, 0.0, 1.0)

@export_group("Memory Unit")
@export var color_mu_fill: Color = Color(0.0, 0.4, 0.7, 0.25)
@export var color_mu_border: Color = Color(0.0, 0.75, 1.0, 0.8)
@export var color_mu_chip_fill: Color = Color(0.0, 0.3, 0.6, 0.4)
@export var color_mu_chip_border: Color = Color(0.0, 0.75, 1.0, 1.0)
@export var color_mu_copied_dot: Color = Color(0.2, 0.9, 0.3, 0.9)

@export_group("Control Node")
@export var color_cpu_fill: Color = Color(0.5, 0.0, 0.5, 0.25)
@export var color_cpu_border: Color = Color(0.5, 0.0, 0.5, 0.8)
@export var color_cpu_inner: Color = Color(0.5, 0.0, 0.5, 0.6)
@export var color_cpu_diamond: Color = Color(0.6, 0.2, 0.8, 0.7)
@export var color_cpu_crashed_fill: Color = Color(0.3, 0.05, 0.05, 0.5)
@export var color_cpu_crashed_border: Color = Color(1.0, 0.0, 0.0, 1.0)

@export_group("Watchdog")
@export var color_beacon: Color = Color(0.9, 0.6, 0.1, 1.0)
@export var color_beacon_halo: Color = Color(0.7, 0.4, 0.05, 0.35)

@export_group("Rezzed")
@export var color_rez_default: Color = Color(0.2, 0.9, 1.0, 1.0)

@export_group("Worm")
@export var color_worm_full: Color = Color(0.7, 0.3, 0.9, 1.0)
@export var color_worm_damaged: Color = Color(0.9, 0.5, 0.2, 1.0)
@export var color_worm_critical: Color = Color(0.9, 0.2, 0.2, 1.0)
@export var color_worm_halo: Color = Color(0.5, 0.2, 0.7, 0.35)

@export_group("Floor HUD")
@export var color_flash: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Hover Highlight")
@export var color_hover_outline: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var hover_outline_width: float = 2.0
@export var hover_edge_threshold: float = 0.15

# Reference to the current layout being displayed
var current_layout: CP2020DatafortLayout

# Watchdog beacon positions deployed by the netrunner. Set by the game
# session; the renderer draws a pulsing amber "W" glyph at each beacon.
var watchdog_beacons: Array[Vector2i] = []

# Rezzed attack-program nodes deployed by the netrunner. Set by the game
# session; the renderer draws a cyan "◆" glyph at each node's position. Only
# nodes on the current floor are drawn (floor-gated like ICE).
var rezzed_program_nodes: Array = []

# --- Hover highlight ---
# The grid coord currently under the mouse, and whether it is interactable
# (offers a right-click context menu). Set by the game session from its
# _input handler; the _HoverHighlight child draws a shader outline over the
# tile when hover_interactable is true.
var hovered_coord: Vector2i = Vector2i(-1, -1)
var hover_interactable: bool = false
var _hover_highlight: _HoverHighlight = null

# Cached default theme font for runtime text overlays (e.g. worm integrity).
var _default_font: Font = null

# Floor-change flash: alpha decays from 1.0 to 0 over ~1.5s. Driven by
# _process; the centered "Floor N — Name" text is drawn over the board
# while alpha > 0. A persistent HUD label is always drawn in the header.
var _floor_flash_alpha: float = 0.0
var _pulse_time: float = 0.0

func _get_default_font() -> Font:
	if _default_font == null:
		var label := Label.new()
		_default_font = label.get_theme_default_font()
		label.free()
	return _default_font

# Scale a colour's alpha by the fog multiplier (explored-not-visible tiles).
func _a(c: Color, alpha_mult: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha_mult)

func _draw() -> void:
	if current_layout:
		draw_grid(self, current_layout)
	_draw_floor_hud()

# Persistent HUD floor label (top header area) + centered floor-change flash.
# The HUD label always shows the current floor so the player knows which
# level they are on. The flash fades out shortly after a floor switch.
func _draw_floor_hud() -> void:
	if current_layout == null:
		return
	# The persistent floor label now lives in the scene tree as a themed
	# Label (FloorHudLabel, updated by the game session). Only the
	# transient centered flash is drawn here.
	if _floor_flash_alpha > 0.0:
		var font := _get_default_font()
		var f := current_layout.current_floor
		var fname: String = ""
		if f >= 0 and f < current_layout.floors.size():
			fname = current_layout.floors[f].floor_name
		if fname == "":
			fname = "Floor %d" % f
		var flash_text := "▼ %s ▲" % fname
		var total_width := current_layout.columns * cell_size
		var center_x := total_width * 0.5
		var flash_y := grid_offset_y + (current_layout.rows * cell_size) * 0.5
		var col := Color(color_flash.r, color_flash.g, color_flash.b, color_flash.a * _floor_flash_alpha)
		# Shadow for legibility against any tile underneath.
		draw_string(font, Vector2(center_x - 80, flash_y), flash_text, HORIZONTAL_ALIGNMENT_CENTER, 160, 28, Color(0, 0, 0, _floor_flash_alpha * 0.8))
		draw_string(font, Vector2(center_x - 80, flash_y), flash_text, HORIZONTAL_ALIGNMENT_CENTER, 160, 28, col)

# Trigger a centered floor-change flash. Called by the game session after
# _set_current_floor + redraw. The flash decays in _process.
func flash_floor_label() -> void:
	_floor_flash_alpha = 1.0
	queue_redraw()

func _ready() -> void:
	# BackBufferCopy ensures screen_texture in the outline shader samples the
	# current frame's rendered output (the board content drawn by _draw()).
	# COPY_MODE_VIEWPORT copies the full screen — simplest and avoids camera-
	# transform coordinate issues. Placed as the first child so it runs after
	# the parent's _draw() but before the HoverHighlight child.
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)

	# HoverHighlight is a child Node2D that draws after the BackBufferCopy,
	# so the shader's screen_texture contains the fully-rendered board.
	_hover_highlight = _HoverHighlight.new()
	_hover_highlight.cell_size = cell_size
	_hover_highlight.grid_offset_y = grid_offset_y
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = preload("res://scripts/ui/outline_screen.gdshader")
	shader_mat.set_shader_parameter("outline_color", color_hover_outline)
	shader_mat.set_shader_parameter("outline_width", hover_outline_width)
	shader_mat.set_shader_parameter("edge_threshold", hover_edge_threshold)
	_hover_highlight.material = shader_mat
	add_child(_hover_highlight)

func _process(delta: float) -> void:
	# Sync hover highlight properties each frame (cheap; handles export
	# changes in the inspector at runtime too).
	if _hover_highlight:
		_hover_highlight.hovered_coord = hovered_coord
		_hover_highlight.hover_interactable = hover_interactable
	_pulse_time += delta
	if _floor_flash_alpha > 0.0:
		_floor_flash_alpha = max(0.0, _floor_flash_alpha - delta * 0.7)
	queue_redraw()

func _pulse_value() -> float:
	return 0.5 + 0.5 * sin(_pulse_time * 3.0)

func _draw_neon_grid_lines(total_w: float, total_h: float) -> void:
	var pulse := _pulse_value()
	var bright_alpha := color_grid_line_bright.a * (0.5 + 0.5 * pulse)
	var oy := float(grid_offset_y)
	for x in range(current_layout.columns + 1):
		var px := float(x * cell_size)
		if x % 5 == 0:
			draw_line(Vector2(px, oy), Vector2(px, oy + total_h),
				Color(color_grid_line_bright.r, color_grid_line_bright.g, color_grid_line_bright.b, bright_alpha), 1.5)
		else:
			draw_line(Vector2(px, oy), Vector2(px, oy + total_h), color_grid_line, 1.0)
	for y in range(current_layout.rows + 1):
		var py := oy + float(y * cell_size)
		if y % 5 == 0:
			draw_line(Vector2(0, py), Vector2(total_w, py),
				Color(color_grid_line_bright.r, color_grid_line_bright.g, color_grid_line_bright.b, bright_alpha), 1.5)
		else:
			draw_line(Vector2(0, py), Vector2(total_w, py), color_grid_line, 1.0)

func _draw_scanlines(total_w: float, total_h: float) -> void:
	var oy := float(grid_offset_y)
	var y: float = oy
	while y < oy + total_h:
		draw_line(Vector2(0, y), Vector2(total_w, y), color_scanline, 1.0)
		y += 4.0

func _draw_vignette(total_w: float, total_h: float) -> void:
	var oy := float(grid_offset_y)
	var margin := 100.0
	draw_rect(Rect2(0, oy, total_w, margin), color_vignette, true)
	draw_rect(Rect2(0, oy + total_h - margin, total_w, margin), color_vignette, true)
	draw_rect(Rect2(0, oy, margin, total_h), color_vignette, true)
	draw_rect(Rect2(total_w - margin, oy, margin, total_h), color_vignette, true)

func _draw_tech_frame(total_w: float, total_h: float) -> void:
	var oy := float(grid_offset_y)
	var origin := Vector2(0, oy)
	var frame_size := Vector2(total_w, total_h)
	var tl := origin
	var top_r := origin + Vector2(frame_size.x, 0)
	var bl := origin + Vector2(0, frame_size.y)
	var bottom_r := origin + frame_size
	var inset := 18.0
	var w := 2.0
	draw_rect(Rect2(origin, frame_size), color_tech_frame, false, w)
	draw_line(tl, tl + Vector2(inset, 0), color_tech_frame, w + 1.0)
	draw_line(tl, tl + Vector2(0, inset), color_tech_frame, w + 1.0)
	draw_line(top_r, top_r + Vector2(-inset, 0), color_tech_frame, w + 1.0)
	draw_line(top_r, top_r + Vector2(0, inset), color_tech_frame, w + 1.0)
	draw_line(bl, bl + Vector2(inset, 0), color_tech_frame, w + 1.0)
	draw_line(bl, bl + Vector2(0, -inset), color_tech_frame, w + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color_tech_frame, w + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color_tech_frame, w + 1.0)

func draw_grid(canvas: CanvasItem, layout: CP2020DatafortLayout) -> void:
	# Render only the current floor's tiles. Empty current floor -> blank board.
	if not layout or layout.get_current_floor_tiles().is_empty():
		return

	var total_width: float = float(layout.columns * cell_size)
	var total_height: float = float(layout.rows * cell_size)

	# 1. Base background (dark navy) across the grid area.
	canvas.draw_rect(Rect2(0, grid_offset_y, total_width, total_height), color_grid_bg)

	# 2. Neon grid lines across the full grid (dim + bright every 5th, pulsing).
	_draw_neon_grid_lines(total_width, total_height)

	# 3+4. Fog-state overlays + tile graphics per cell.
	# Iterate every cell so unexplored/no-tile areas are painted as black void.
	var oy: float = float(grid_offset_y)
	for x in range(layout.columns):
		for y in range(layout.rows):
			var coord := Vector2i(x, y)
			var tile_data := layout.get_tile(coord, layout.current_floor)
			var cell_rect := Rect2(float(x * cell_size), oy + float(y * cell_size), float(cell_size), float(cell_size))

			if tile_data == null or not tile_data.is_explored:
				# UNEXPLORED: opaque black void — hide grid lines.
				canvas.draw_rect(cell_rect, color_unexplored_fill, true)
				continue

			if tile_data.is_visible:
				# VISIBLE: subtle floor tint — grid lines clearly visible.
				canvas.draw_rect(cell_rect, color_visible_overlay, true)
				_draw_tile_graphics(canvas, tile_data, cell_rect, true)
			else:
				# EXPLORED (FOG): semi-transparent dark overlay — dim grid lines.
				canvas.draw_rect(cell_rect, color_fog_overlay, true)
				_draw_tile_graphics(canvas, tile_data, cell_rect, false)

	# 5. Scanlines across the grid area.
	_draw_scanlines(total_width, total_height)

	# 6. Vignette around the grid edges.
	_draw_vignette(total_width, total_height)

	# 7. Tech frame (corner brackets + border) around the grid.
	_draw_tech_frame(total_width, total_height)

	# 8. Watchdog beacon overlay — pulsing amber "W" glyph at each beacon.
	for beacon in watchdog_beacons:
		var beacon_rect = Rect2(beacon.x * cell_size, grid_offset_y + (beacon.y * cell_size), cell_size, cell_size)
		var center = beacon_rect.get_center()
		var beacon_color = color_beacon
		var pulse_radius: float = 8.0 + sin(Time.get_ticks_msec() * 0.005) * 2.0
		canvas.draw_circle(center, pulse_radius, color_beacon_halo)
		var s: float = 7.0
		canvas.draw_line(center + Vector2(-s, -s), center + Vector2(0, s), beacon_color, 2.0)
		canvas.draw_line(center + Vector2(0, s), center + Vector2(s, -s), beacon_color, 2.0)
		canvas.draw_line(center + Vector2(s, -s), center + Vector2(s * 2.0, s), beacon_color, 2.0)

	# 9. Rezzed attack-program overlay — pulsing diamond + tinted halo.
	for rez in rezzed_program_nodes:
		if not is_instance_valid(rez):
			continue
		if rez.home_floor != current_layout.current_floor:
			continue
		var rez_rect = Rect2(rez.current_position.x * cell_size, grid_offset_y + (rez.current_position.y * cell_size), cell_size, cell_size)
		var rcenter = rez_rect.get_center()
		var vis: Dictionary = rez.program.get_visual() if rez.program else {}
		var rez_color: Color = vis.get("color", color_rez_default)
		var rpulse: float = 9.0 + sin(Time.get_ticks_msec() * 0.006) * 2.0
		canvas.draw_circle(rcenter, rpulse, Color(rez_color.r, rez_color.g, rez_color.b, 0.3))
		var ds: float = 8.0
		var d := PackedVector2Array([
			rcenter + Vector2(0, -ds),
			rcenter + Vector2(ds, 0),
			rcenter + Vector2(0, ds),
			rcenter + Vector2(-ds, 0),
		])
		canvas.draw_polyline(d, rez_color, 2.0, true)

func _draw_tile_graphics(canvas: CanvasItem, tile_data: CP2020TileData, cell_rect: Rect2, is_visible: bool) -> void:
	var alpha_mult: float = 1.0 if is_visible else 0.3

	match tile_data.tile_type:
		
		CP2020DatafortLayout.TileType.EMPTY:
			# Draw a subtle inner dot in the center of empty tiles to mark them as walkable paths
			var center = cell_rect.get_center()
			canvas.draw_circle(center, 2.0, _a(color_empty_dot, alpha_mult))

		CP2020DatafortLayout.TileType.ENTRY:
			canvas.draw_rect(cell_rect, _a(color_entry_fill, alpha_mult), true)
			# Vertical-travel frame: up=teal, down=purple, both=split. An LDL
			# link keeps the cyan frame. This is the primary at-a-glance
			# indicator that a tile allows up/down movement (see
			# docs/multi-floor-travel-plan.md §3).
			var has_up := tile_data.can_go_up
			var has_down := tile_data.can_go_down
			if has_up and has_down:
				var half := Rect2(cell_rect.position, Vector2(cell_rect.size.x, cell_rect.size.y * 0.5))
				canvas.draw_rect(half, _a(color_entry_up, alpha_mult), false, 2.0)
				var half2 := Rect2(cell_rect.position + Vector2(0, cell_rect.size.y * 0.5), Vector2(cell_rect.size.x, cell_rect.size.y * 0.5))
				canvas.draw_rect(half2, _a(color_entry_down, alpha_mult), false, 2.0)
			elif has_up:
				canvas.draw_rect(cell_rect, _a(color_entry_up, alpha_mult), false, 2.0)
			elif has_down:
				canvas.draw_rect(cell_rect, _a(color_entry_down, alpha_mult), false, 2.0)
			else:
				canvas.draw_rect(cell_rect, _a(color_entry_frame, alpha_mult), false, 2.0)
			# Compact corner glyphs: "↑" top-left, "↓" bottom-left (8px). Kept
			# to the corners so the tile doesn't clutter when both are set.
			if has_up or has_down:
				var font := _get_default_font()
				var glyph_size := 8
				if has_up:
					canvas.draw_string(font, cell_rect.position + Vector2(2, glyph_size + 1), "↑", HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, _a(color_entry_up_glyph, alpha_mult))
				if has_down:
					canvas.draw_string(font, cell_rect.position + Vector2(2, cell_rect.size.y - 1), "↓", HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, _a(color_entry_down_glyph, alpha_mult))
			# Primary-entry marker: a small white inset square marks this
			# ENTRY as the map's designated arrival point (initial dive +
			# inbound LDL fallback). Only one ENTRY per map should carry this.
			if tile_data.is_primary_entry:
				var mark := Rect2(cell_rect.position + Vector2(cell_rect.size.x - 12, 4), Vector2(8, 8))
				canvas.draw_rect(mark, _a(color_primary_entry_mark, alpha_mult), true)

		CP2020DatafortLayout.TileType.DATAWALL:
			canvas.draw_rect(cell_rect, _a(color_wall_fill, alpha_mult), true)
			canvas.draw_rect(cell_rect, _a(color_wall_border, alpha_mult), false, 2.0)

		CP2020DatafortLayout.TileType.CODE_GATE:
			var base_color = color_gate_unlocked if tile_data.is_unlocked else color_gate_locked
			canvas.draw_rect(cell_rect, _a(base_color, alpha_mult * 0.3), true)
			canvas.draw_rect(cell_rect, _a(base_color, alpha_mult), false, 2.0)
			
			var mid_y = cell_rect.position.y + (cell_rect.size.y / 2.0)
			canvas.draw_line(
				Vector2(cell_rect.position.x, mid_y), 
				Vector2(cell_rect.end.x, mid_y), 
				_a(base_color, alpha_mult), 
				2.0
			)

		CP2020DatafortLayout.TileType.MEMORY_UNIT:
			canvas.draw_rect(cell_rect, _a(color_mu_fill, alpha_mult), true)
			canvas.draw_rect(cell_rect, _a(color_mu_border, alpha_mult), false, 2.0)
			
			var chip_rect = Rect2(cell_rect.position + Vector2(8, 10), Vector2(24, 20))
			canvas.draw_rect(chip_rect, _a(color_mu_chip_fill, alpha_mult), true)
			canvas.draw_rect(chip_rect, _a(color_mu_chip_border, alpha_mult), false, 2.0)
			
			# IC pin details
			var pin_color = _a(color_mu_chip_border, alpha_mult)
			canvas.draw_line(chip_rect.position + Vector2(-4, 4), chip_rect.position + Vector2(0, 4), pin_color, 2.0)
			canvas.draw_line(chip_rect.position + Vector2(-4, 12), chip_rect.position + Vector2(0, 12), pin_color, 2.0)
			canvas.draw_line(chip_rect.position + Vector2(24, 4), chip_rect.position + Vector2(28, 4), pin_color, 2.0)
			canvas.draw_line(chip_rect.position + Vector2(24, 12), chip_rect.position + Vector2(28, 12), pin_color, 2.0)

			# "Data copied" indicator: when every authored file on this memory
			# unit has been copied this dive, draw a small green filled dot at the
			# chip's bottom-right corner so the player can see it's harvested.
			# Empty (no-file) tiles are not marked copied — only fully drained ones.
			var all_copied: bool = tile_data.files.size() > 0 and tile_data.copied_file_paths.size() >= tile_data.files.size()
			if all_copied:
				var dot_pos = chip_rect.position + chip_rect.size - Vector2(4, 4)
				canvas.draw_circle(dot_pos, 3.0, _a(color_mu_copied_dot, alpha_mult))

		CP2020DatafortLayout.TileType.CONTROL_NODE:
			# A datafort CPU. Crashed CPUs (Krash) render dimmed red with an "X"
			# so the player can see which CPUs are down; active CPUs keep the
			# normal purple diamond.
			var crashed: bool = tile_data.cpu_crashed_turns > 0
			if crashed:
				canvas.draw_rect(cell_rect, _a(color_cpu_crashed_fill, alpha_mult), true)
				canvas.draw_rect(cell_rect, _a(color_cpu_crashed_border, alpha_mult), false, 2.0)
				var center = cell_rect.get_center()
				canvas.draw_line(center + Vector2(-9, -9), center + Vector2(9, 9), _a(color_cpu_crashed_border, alpha_mult), 2.5)
				canvas.draw_line(center + Vector2(9, -9), center + Vector2(-9, 9), _a(color_cpu_crashed_border, alpha_mult), 2.5)
			else:
				canvas.draw_rect(cell_rect, _a(color_cpu_fill, alpha_mult), true)
				canvas.draw_rect(cell_rect, _a(color_cpu_border, alpha_mult), false, 2.0)
				var inner_rect = Rect2(cell_rect.position + Vector2(4, 4), Vector2(cell_rect.size.x - 8, cell_rect.size.y - 8))
				canvas.draw_rect(inner_rect, _a(color_cpu_inner, alpha_mult), false, 1.5)
				var center = cell_rect.get_center()
				var diamond = PackedVector2Array([
					center + Vector2(0, -10),
					center + Vector2(10, 0),
					center + Vector2(0, 10),
					center + Vector2(-10, 0)
				])
				canvas.draw_polygon(diamond, PackedColorArray([_a(color_cpu_diamond, alpha_mult)]))

	# NETWATCH / NETRUNNER tiles have no board renderer case — like
	# BLACK_ICE, they are spawn markers only. The spawned NPC nodes
	# (cp2020_npc_netrunner.tscn) render their own glyphs at runtime.
	# Tile glyphs for these types are drawn exclusively in the designer.

	# Worm-in-progress overlay: when a Worm program is working on a DATAWALL
	# or locked CODE_GATE (worm_turns_remaining > 0), draw a small purple "W"
	# glyph in the tile center so the player can see the worm at work. When
	# the Worm has taken damage from a Killer (DEREZ_ICE), shift the color
	# toward yellow/orange and draw a "cur/max" integrity readout below the W.
	if tile_data.worm_turns_remaining > 0:
		var center = cell_rect.get_center()
		# Color shifts from purple (full) → orange (damaged) → red (near 0).
		var max_int: int = tile_data.worm_max_integrity if tile_data.worm_max_integrity > 0 else 1
		var integrity_ratio: float = float(tile_data.worm_integrity) / float(max_int)
		var worm_color: Color = _a(color_worm_full, alpha_mult)
		if integrity_ratio < 1.0:
			# Blend purple → orange as integrity drops.
			worm_color = _a(color_worm_damaged, alpha_mult).lerp(_a(color_worm_full, alpha_mult), integrity_ratio)
		if integrity_ratio <= 0.34:
			worm_color = _a(color_worm_critical, alpha_mult)
		# Pulsing background circle to draw attention.
		var pulse_radius: float = 8.0 + sin(Time.get_ticks_msec() * 0.005) * 2.0
		canvas.draw_circle(center, pulse_radius, _a(color_worm_halo, alpha_mult))
		# "W" glyph drawn as three diagonal strokes.
		var s: float = 7.0
		canvas.draw_line(center + Vector2(-s, -s), center + Vector2(0, s), worm_color, 2.0)
		canvas.draw_line(center + Vector2(0, s), center + Vector2(s, -s), worm_color, 2.0)
		canvas.draw_line(center + Vector2(s, -s), center + Vector2(s * 2.0, s), worm_color, 2.0)
		# Integrity readout (only when the Worm has been damaged).
		if tile_data.worm_max_integrity > 0 and tile_data.worm_integrity < tile_data.worm_max_integrity:
			var txt := "%d/%d" % [tile_data.worm_integrity, tile_data.worm_max_integrity]
			var font := _get_default_font()
			canvas.draw_string(font, center + Vector2(-10, s + 12.0), txt, HORIZONTAL_ALIGNMENT_CENTER, 20, 8, worm_color)


# ─── Hover highlight child node ───
# Draws a filled rect over the hovered tile when hover_interactable is true.
# The node's ShaderMaterial (set by the parent board renderer) uses the
# screen-texture outline shader, which samples the back buffer to detect
# luminance edges within the tile and renders a white outline around entity
# glyphs and tile visuals. The rect is inset by 2px to avoid sampling
# neighbouring tiles / bright grid lines at the tile boundary.
class _HoverHighlight extends Node2D:
	var hovered_coord: Vector2i = Vector2i(-1, -1)
	var hover_interactable: bool = false
	var cell_size: int = 40
	var grid_offset_y: int = 90
	const _inset: int = 2

	func _draw() -> void:
		if not hover_interactable or hovered_coord.x < 0:
			return
		var rect := Rect2(
			float(hovered_coord.x * cell_size + _inset),
			float(grid_offset_y + hovered_coord.y * cell_size + _inset),
			float(cell_size - _inset * 2),
			float(cell_size - _inset * 2)
		)
		# The fill color is overridden by the shader; we just need the rect
		# to be drawn so the shader runs on its pixels.
		draw_rect(rect, Color(1, 1, 1, 1))

	func _process(_delta: float) -> void:
		# Redraw every frame so the shader re-evaluates as the board pulse
		# shifts tile colours and as the mouse moves to a new tile.
		queue_redraw()
