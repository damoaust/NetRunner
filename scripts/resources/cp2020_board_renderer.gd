class_name CP2020BoardRenderer
extends Node2D

@export var cell_size: int = 40
@export var grid_offset_y: int = 90

# Reference to the current layout being displayed
var current_layout: CP2020DatafortLayout

# Watchdog beacon positions deployed by the netrunner. Set by the game
# session; the renderer draws a pulsing amber "W" glyph at each beacon.
var watchdog_beacons: Array[Vector2i] = []

# Rezzed attack-program nodes deployed by the netrunner. Set by the game
# session; the renderer draws a cyan "◆" glyph at each node's position. Only
# nodes on the current floor are drawn (floor-gated like ICE).
var rezzed_program_nodes: Array = []

# Cached default theme font for runtime text overlays (e.g. worm integrity).
var _default_font: Font = null

# Floor-change flash: alpha decays from 1.0 to 0 over ~1.5s. Driven by
# _process; the centered "Floor N — Name" text is drawn over the board
# while alpha > 0. A persistent HUD label is always drawn in the header.
var _floor_flash_alpha: float = 0.0

func _get_default_font() -> Font:
	if _default_font == null:
		var label := Label.new()
		_default_font = label.get_theme_default_font()
		label.free()
	return _default_font

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
	var font := _get_default_font()
	var f := current_layout.current_floor
	var count := current_layout.get_floor_count()
	var fname: String = ""
	if f >= 0 and f < current_layout.floors.size():
		fname = current_layout.floors[f].floor_name
	if fname == "":
		fname = "Floor %d" % f
	# Persistent label, top-left of the header strip (above the grid).
	var hud_text := "Floor %d/%d — %s" % [f + 1, count, fname]
	draw_string(font, Vector2(8, 18), hud_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.85, 1.0, 1.0))
	# Centered flash overlay (fades after a floor switch).
	if _floor_flash_alpha > 0.0:
		var flash_text := "▼ %s ▲" % fname
		var total_width := current_layout.columns * cell_size
		var center_x := total_width * 0.5
		var flash_y := grid_offset_y + (current_layout.rows * cell_size) * 0.5
		var col := Color(1.0, 1.0, 1.0, _floor_flash_alpha)
		# Shadow for legibility against any tile underneath.
		draw_string(font, Vector2(center_x - 80, flash_y), flash_text, HORIZONTAL_ALIGNMENT_CENTER, 160, 28, Color(0, 0, 0, _floor_flash_alpha * 0.8))
		draw_string(font, Vector2(center_x - 80, flash_y), flash_text, HORIZONTAL_ALIGNMENT_CENTER, 160, 28, col)

# Trigger a centered floor-change flash. Called by the game session after
# _set_current_floor + redraw. The flash decays in _process.
func flash_floor_label() -> void:
	_floor_flash_alpha = 1.0
	queue_redraw()

func _process(_delta: float) -> void:
	if _floor_flash_alpha > 0.0:
		_floor_flash_alpha = max(0.0, _floor_flash_alpha - _delta * 0.7)
		queue_redraw()

func draw_grid(canvas: CanvasItem, layout: CP2020DatafortLayout) -> void:
	# Render only the current floor's tiles. Empty current floor -> blank board.
	if not layout or layout.get_current_floor_tiles().is_empty():
		return

	var total_width = layout.columns * cell_size
	var total_height = layout.rows * cell_size

	# STATE 3 (UNEXPLORED): Paint whole board black
	canvas.draw_rect(Rect2(0, grid_offset_y, total_width, total_height), Color.BLACK)

	for raw_key in layout.get_current_floor_tiles().keys():
		# 1. Safely convert the string key from the .tres file back into a Vector2i
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
			
		# 2. Safely get the tile using our helper function (current floor)
		var tile_data = layout.get_tile(coord, layout.current_floor)
		
		if not tile_data or not tile_data.is_explored:
			continue # Leave it total black

		# 3. Now coord.x and coord.y will work perfectly!
		var cell_rect = Rect2(coord.x * cell_size, grid_offset_y + (coord.y * cell_size), cell_size, cell_size)

		if tile_data.is_visible:
			# STATE 1 (VISIBLE): Brighter floor
			canvas.draw_rect(cell_rect, Color(0.08, 0.08, 0.08), true)
			_draw_tile_graphics(canvas, tile_data, cell_rect, true)
			canvas.draw_rect(cell_rect, Color(0.3, 0.4, 0.5, 0.8), false, 1.0)
		else:
			# STATE 2 (EXPLORED / FOG OF WAR): Darker floor
			canvas.draw_rect(cell_rect, Color(0.04, 0.04, 0.05, 1.0), true)
			_draw_tile_graphics(canvas, tile_data, cell_rect, false)
			canvas.draw_rect(cell_rect, Color(0.15, 0.15, 0.2, 0.6), false, 1.0)

	# Watchdog beacon overlay: draw a pulsing amber "W" glyph at each
	# beacon position deployed by the netrunner. Drawn after all tiles so
	# the beacon is visible on top of any tile graphics.
	for beacon in watchdog_beacons:
		var beacon_rect = Rect2(beacon.x * cell_size, grid_offset_y + (beacon.y * cell_size), cell_size, cell_size)
		var center = beacon_rect.get_center()
		var beacon_color = Color(0.9, 0.6, 0.1, 1.0)
		var pulse_radius: float = 8.0 + sin(Time.get_ticks_msec() * 0.005) * 2.0
		canvas.draw_circle(center, pulse_radius, Color(0.7, 0.4, 0.05, 0.35))
		var s: float = 7.0
		canvas.draw_line(center + Vector2(-s, -s), center + Vector2(0, s), beacon_color, 2.0)
		canvas.draw_line(center + Vector2(0, s), center + Vector2(s, -s), beacon_color, 2.0)
		canvas.draw_line(center + Vector2(s, -s), center + Vector2(s * 2.0, s), beacon_color, 2.0)

	# Rezzed attack-program overlay: draw a pulsing cyan diamond "◆" glyph at
	# each rezzed node's position. Only nodes on the current floor are drawn
	# (floor-gated like ICE). Drawn after tiles + beacons so it sits on top.
	for rez in rezzed_program_nodes:
		if not is_instance_valid(rez):
			continue
		if rez.home_floor != current_layout.current_floor:
			continue
		var rez_rect = Rect2(rez.current_position.x * cell_size, grid_offset_y + (rez.current_position.y * cell_size), cell_size, cell_size)
		var rcenter = rez_rect.get_center()
		var rez_color = Color(0.2, 0.9, 1.0, 1.0)
		var rpulse: float = 9.0 + sin(Time.get_ticks_msec() * 0.006) * 2.0
		canvas.draw_circle(rcenter, rpulse, Color(0.1, 0.6, 0.8, 0.3))
		# Diamond outline.
		var ds: float = 8.0
		var d := PackedVector2Array([
			rcenter + Vector2(0, -ds),
			rcenter + Vector2(ds, 0),
			rcenter + Vector2(0, ds),
			rcenter + Vector2(-ds, 0),
		])
		canvas.draw_polyline(d, rez_color, 2.0, true)
		# Label the program's initial so the player can tell rezzed programs apart.
		var prog_name: String = rez.program.program_name if rez.program else "?"
		var initial := prog_name.substr(0, 1)
		var font := _get_default_font()
		canvas.draw_string(font, rcenter + Vector2(-4, 4), initial, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, rez_color)

func _draw_tile_graphics(canvas: CanvasItem, tile_data: CP2020TileData, cell_rect: Rect2, is_visible: bool) -> void:
	var alpha_mult: float = 1.0 if is_visible else 0.3

	match tile_data.tile_type:
		
		CP2020DatafortLayout.TileType.EMPTY:
			# Draw a subtle inner dot in the center of empty tiles to mark them as walkable paths
			var center = cell_rect.get_center()
			var dot_color = Color(0.3, 0.4, 0.5, 0.4 * alpha_mult)
			canvas.draw_circle(center, 2.0, dot_color)

		CP2020DatafortLayout.TileType.ENTRY:
			canvas.draw_rect(cell_rect, Color(0.0, 0.4, 0.8, 0.3 * alpha_mult), true)
			# Vertical-travel frame: up=teal, down=purple, both=split. An LDL
			# link keeps the cyan frame. This is the primary at-a-glance
			# indicator that a tile allows up/down movement (see
			# docs/multi-floor-travel-plan.md §3).
			var has_up := tile_data.can_go_up
			var has_down := tile_data.can_go_down
			if has_up and has_down:
				var half := Rect2(cell_rect.position, Vector2(cell_rect.size.x, cell_rect.size.y * 0.5))
				canvas.draw_rect(half, Color(0.0, 0.8, 0.8, 1.0 * alpha_mult), false, 2.0)
				var half2 := Rect2(cell_rect.position + Vector2(0, cell_rect.size.y * 0.5), Vector2(cell_rect.size.x, cell_rect.size.y * 0.5))
				canvas.draw_rect(half2, Color(0.6, 0.2, 0.8, 1.0 * alpha_mult), false, 2.0)
			elif has_up:
				canvas.draw_rect(cell_rect, Color(0.0, 0.8, 0.8, 1.0 * alpha_mult), false, 2.0)
			elif has_down:
				canvas.draw_rect(cell_rect, Color(0.6, 0.2, 0.8, 1.0 * alpha_mult), false, 2.0)
			else:
				canvas.draw_rect(cell_rect, Color(Color.CYAN, 1.0 * alpha_mult), false, 2.0)
			# Compact corner glyphs: "↑" top-left, "↓" bottom-left (8px). Kept
			# to the corners so the tile doesn't clutter when both are set.
			if has_up or has_down:
				var font := _get_default_font()
				var glyph_size := 8
				var up_color := Color(0.0, 0.9, 0.9, 1.0 * alpha_mult)
				var down_color := Color(0.8, 0.4, 1.0, 1.0 * alpha_mult)
				if has_up:
					canvas.draw_string(font, cell_rect.position + Vector2(2, glyph_size + 1), "↑", HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, up_color)
				if has_down:
					canvas.draw_string(font, cell_rect.position + Vector2(2, cell_rect.size.y - 1), "↓", HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, down_color)
			# Primary-entry marker: a small white inset square marks this
			# ENTRY as the map's designated arrival point (initial dive +
			# inbound LDL fallback). Only one ENTRY per map should carry this.
			if tile_data.is_primary_entry:
				var mark := Rect2(cell_rect.position + Vector2(cell_rect.size.x - 12, 4), Vector2(8, 8))
				canvas.draw_rect(mark, Color(1.0, 1.0, 1.0, 1.0 * alpha_mult), true)

		CP2020DatafortLayout.TileType.DATAWALL:
			canvas.draw_rect(cell_rect, Color(0.8, 0.1, 0.1, 0.6 * alpha_mult), true)
			canvas.draw_rect(cell_rect, Color(Color.RED, 1.0 * alpha_mult), false, 2.0)

		CP2020DatafortLayout.TileType.CODE_GATE:
			var base_color = Color.GREEN if tile_data.is_unlocked else Color.ORANGE
			canvas.draw_rect(cell_rect, Color(base_color, 0.3 * alpha_mult), true)
			canvas.draw_rect(cell_rect, Color(base_color, 1.0 * alpha_mult), false, 2.0)
			
			var mid_y = cell_rect.position.y + (cell_rect.size.y / 2.0)
			canvas.draw_line(
				Vector2(cell_rect.position.x, mid_y), 
				Vector2(cell_rect.end.x, mid_y), 
				Color(base_color, 1.0 * alpha_mult), 
				2.0
			)

		CP2020DatafortLayout.TileType.MEMORY_UNIT:
			canvas.draw_rect(cell_rect, Color(0.0, 0.4, 0.7, 0.25 * alpha_mult), true)
			canvas.draw_rect(cell_rect, Color(Color.DEEP_SKY_BLUE, 0.8 * alpha_mult), false, 2.0)
			
			var chip_rect = Rect2(cell_rect.position + Vector2(8, 10), Vector2(24, 20))
			canvas.draw_rect(chip_rect, Color(0.0, 0.3, 0.6, 0.4 * alpha_mult), true)
			canvas.draw_rect(chip_rect, Color(Color.DEEP_SKY_BLUE, 1.0 * alpha_mult), false, 2.0)
			
			# IC pin details
			var pin_color = Color(Color.DEEP_SKY_BLUE, 1.0 * alpha_mult)
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
				canvas.draw_circle(dot_pos, 3.0, Color(0.2, 0.9, 0.3, 0.9 * alpha_mult))

		CP2020DatafortLayout.TileType.CONTROL_NODE:
			# A datafort CPU. Crashed CPUs (Krash) render dimmed red with an "X"
			# so the player can see which CPUs are down; active CPUs keep the
			# normal purple diamond.
			var crashed: bool = tile_data.cpu_crashed_turns > 0
			if crashed:
				canvas.draw_rect(cell_rect, Color(0.3, 0.05, 0.05, 0.5 * alpha_mult), true)
				canvas.draw_rect(cell_rect, Color(Color.RED, 1.0 * alpha_mult), false, 2.0)
				var center = cell_rect.get_center()
				canvas.draw_line(center + Vector2(-9, -9), center + Vector2(9, 9), Color(Color.RED, 1.0 * alpha_mult), 2.5)
				canvas.draw_line(center + Vector2(9, -9), center + Vector2(-9, 9), Color(Color.RED, 1.0 * alpha_mult), 2.5)
			else:
				canvas.draw_rect(cell_rect, Color(0.5, 0.0, 0.5, 0.25 * alpha_mult), true)
				canvas.draw_rect(cell_rect, Color(Color.PURPLE, 0.8 * alpha_mult), false, 2.0)
				var inner_rect = Rect2(cell_rect.position + Vector2(4, 4), Vector2(cell_rect.size.x - 8, cell_rect.size.y - 8))
				canvas.draw_rect(inner_rect, Color(Color.PURPLE, 0.6 * alpha_mult), false, 1.5)
				var center = cell_rect.get_center()
				var diamond = PackedVector2Array([
					center + Vector2(0, -10),
					center + Vector2(10, 0),
					center + Vector2(0, 10),
					center + Vector2(-10, 0)
				])
				canvas.draw_polygon(diamond, PackedColorArray([Color(0.6, 0.2, 0.8, 0.7 * alpha_mult)]))

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
		var worm_color = Color(0.7, 0.3, 0.9, 1.0 * alpha_mult)
		var max_int: int = tile_data.worm_max_integrity if tile_data.worm_max_integrity > 0 else 1
		var integrity_ratio: float = float(tile_data.worm_integrity) / float(max_int)
		if integrity_ratio < 1.0:
			# Blend purple → orange as integrity drops.
			worm_color = Color(0.9, 0.5, 0.2, 1.0 * alpha_mult).lerp(Color(0.7, 0.3, 0.9, 1.0 * alpha_mult), integrity_ratio)
		if integrity_ratio <= 0.34:
			worm_color = Color(0.9, 0.2, 0.2, 1.0 * alpha_mult)
		# Pulsing background circle to draw attention.
		var pulse_radius: float = 8.0 + sin(Time.get_ticks_msec() * 0.005) * 2.0
		canvas.draw_circle(center, pulse_radius, Color(0.5, 0.2, 0.7, 0.35 * alpha_mult))
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
