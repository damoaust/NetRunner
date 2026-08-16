@tool
extends Control
class_name CP2020DatafortGridCanvas

## Grid canvas for the datafort designer. Handles procedural grid drawing,
## mouse interaction (paint / select / drag-to-move), and tile painting.
## Emits signals so the parent designer script can open/close side panels.
##
## This node is placed in the scene tree below the top toolbar; its own
## position replaces the old hardcoded 90px top-panel offset, so
## grid_offset_y is only ~16 (room for column tick labels above the grid).
## grid_offset_x is ~22 (room for row tick labels left of the grid).

@export var grid_rows: int = 15
@export var grid_columns: int = 15

var cell_size: int = 40
var grid_offset_y: int = 16
var grid_offset_x: int = 22

var current_layout: CP2020DatafortLayout
var selected_tile_type: CP2020DatafortLayout.TileType = CP2020DatafortLayout.TileType.CODE_GATE
# When true, clicking an existing tile selects it for editing (the designer
# root opens its side panel) instead of overwriting it with a fresh tile.
var select_mode: bool = false
# When true, painting an ENTRY tile marks it as an LDL link.
var ldl_link_mode: bool = false
# Coord of the tile currently selected in select mode (draw highlight).
var selected_coord: Vector2i = Vector2i(-1, -1)
# Drag-to-move state (Select mode only).
var dragging: bool = false
var drag_source_coord: Vector2i = Vector2i(-1, -1)
var drag_tile: CP2020TileData = null
var drag_ghost_pos: Vector2 = Vector2.ZERO
var drag_press_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD := 6.0

# Signals emitted so the parent designer can open/close side panels.
signal tile_selected(coord: Vector2i, tile: CP2020TileData)
signal tile_painted(coord: Vector2i, tile: CP2020TileData)
signal ldl_link_selected(coord: Vector2i)
signal ldl_link_painted(coord: Vector2i)
signal tile_moved(from: Vector2i, to: Vector2i, tile: CP2020TileData)


func _ready() -> void:
	if not current_layout:
		current_layout = CP2020DatafortLayout.new()
	fill_empty_tiles()
	queue_redraw()


func fill_empty_tiles() -> void:
	if not current_layout:
		return
	var f := current_layout.current_floor
	for x in range(grid_columns):
		for y in range(grid_rows):
			var coord = Vector2i(x, y)
			if current_layout.get_tile(coord, f) == null:
				var empty_tile = CP2020TileData.new()
				empty_tile.tile_type = CP2020DatafortLayout.TileType.EMPTY
				empty_tile.tile_name = "Empty Path"
				current_layout.set_tile(coord, empty_tile, f)


func _gui_input(event: InputEvent) -> void:
	# Drag ghost follows the cursor while a tile is picked up.
	if event is InputEventMouseMotion:
		if dragging:
			drag_ghost_pos = event.position
		# Redraw on every mouse motion so the floating coord tooltip
		# follows the cursor (cheap for a designer tool).
		queue_redraw()
		if dragging:
			return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var local_pos = event.position
	var adjusted_y = local_pos.y - grid_offset_y
	var grid_x = floori((local_pos.x - grid_offset_x) / cell_size)
	var grid_y = floori(adjusted_y / cell_size)
	var in_bounds = grid_x >= 0 and grid_x < grid_columns and grid_y >= 0 and grid_y < grid_rows
	var coord := Vector2i(grid_x, grid_y)
	var f := current_layout.current_floor if current_layout else 0
	if event.pressed:
		if not in_bounds:
			return
		# Select mode: pick up a non-empty tile to drag (editor opens on
		# release); clicking an empty cell clears the selection.
		if select_mode:
			var existing = current_layout.get_tile(coord, f) if current_layout else null
			if existing != null and existing.tile_type != CP2020DatafortLayout.TileType.EMPTY:
				dragging = true
				drag_source_coord = coord
				drag_tile = existing
				drag_ghost_pos = local_pos
				drag_press_pos = local_pos
			else:
				tile_selected.emit(coord, existing)
			queue_redraw()
			return
		# In LDL Link mode: clicking an existing LDL link selects it for
		# editing rather than overwriting it. Clicking anything else
		# paints a fresh LDL link and opens the editor on it.
		if ldl_link_mode:
			var existing = current_layout.get_tile(coord, f) if current_layout else null
			if existing and existing.tile_type == CP2020DatafortLayout.TileType.ENTRY and existing.is_ldl_link:
				ldl_link_selected.emit(coord)
			else:
				paint_tile(coord)
				ldl_link_painted.emit(coord)
			return
		paint_tile(coord)
		var painted = current_layout.get_tile(coord, f) if current_layout else null
		tile_painted.emit(coord, painted)
	else:
		# Release: finish a drag-to-move (Select mode only).
		if not dragging or drag_tile == null:
			return
		var source := drag_source_coord
		var tile := drag_tile
		# Reset drag state before dispatch so panels/redraw are clean.
		dragging = false
		drag_tile = null
		# Drag threshold: if the cursor barely moved (a jittery click rather
		# than a real drag), treat the release as a select-click on the source
		# tile regardless of which cell the cursor ended in.
		var travel: float = local_pos.distance_to(drag_press_pos)
		if travel < DRAG_THRESHOLD:
			tile_selected.emit(source, tile)
			queue_redraw()
			return
		# Out of bounds or same cell = cancel (treat as a select-click on source).
		if not in_bounds or coord == source:
			tile_selected.emit(source, tile)
			queue_redraw()
			return
		var target_tile = current_layout.get_tile(coord, f) if current_layout else null
		if target_tile != null and target_tile.tile_type != CP2020DatafortLayout.TileType.EMPTY:
			# Occupied: reject the drop, keep the tile at its source.
			print("Drag rejected — target %s is occupied." % coord)
			tile_selected.emit(source, tile)
			queue_redraw()
			return
		# Move the tile: erase source, place at target, fill source with a
		# fresh EMPTY so the grid stays a walkable floor.
		current_layout.erase_tile(source, f)
		current_layout.set_tile(coord, tile, f)
		var empty := CP2020TileData.new()
		empty.tile_type = CP2020DatafortLayout.TileType.EMPTY
		empty.tile_name = "Empty Path"
		current_layout.set_tile(source, empty, f)
		tile_moved.emit(source, coord, tile)
		queue_redraw()


func paint_tile(coord: Vector2i) -> void:
	var tile_data = CP2020TileData.new()
	tile_data.tile_type = selected_tile_type

	match selected_tile_type:
		CP2020DatafortLayout.TileType.CODE_GATE:
			tile_data.tile_name = "Code Gate"
			tile_data.strength_str = 4
		CP2020DatafortLayout.TileType.MEMORY_UNIT:
			tile_data.tile_name = "Memory Unit"
			tile_data.memory_units_mu = 2
		CP2020DatafortLayout.TileType.ENTRY:
			if ldl_link_mode:
				tile_data.tile_name = "LDL Link"
				tile_data.is_ldl_link = true
				tile_data.target_subnet_path = ""
				tile_data.target_entry_coord = Vector2i(-1, -1)
			else:
				tile_data.tile_name = "Netrunner Entry"
				tile_data.is_ldl_link = false
				tile_data.is_primary_entry = not _has_primary_entry()
		CP2020DatafortLayout.TileType.EMPTY:
			tile_data.tile_name = "Empty Path"
		CP2020DatafortLayout.TileType.CONTROL_NODE:
			tile_data.tile_name = "CPU"
			tile_data.cpu_int = 0
			tile_data.cpu_crashed_turns = 0
		CP2020DatafortLayout.TileType.BLACK_ICE:
			tile_data.tile_name = "Black ICE"
		CP2020DatafortLayout.TileType.NETWATCH:
			tile_data.tile_name = "NetWatch Agent"
			tile_data.npc_has_override = false
		CP2020DatafortLayout.TileType.NETRUNNER:
			tile_data.tile_name = "Netrunner"
			tile_data.npc_has_override = false

	current_layout.set_tile(coord, tile_data, current_layout.current_floor)
	queue_redraw()


func _has_primary_entry() -> bool:
	if not current_layout:
		return false
	var f := current_layout.current_floor
	for raw_key in current_layout.get_floor_tiles(f).keys():
		var other = current_layout.get_tile(_key_to_coord(raw_key), f)
		if other and other.tile_type == CP2020DatafortLayout.TileType.ENTRY and other.is_primary_entry:
			return true
	return false

# Convert a Dictionary key (Vector2i or "x,y" String) back to a Vector2i.
static func _key_to_coord(raw_key) -> Vector2i:
	if raw_key is String:
		var parts = raw_key.split(",")
		return Vector2i(parts[0].to_int(), parts[1].to_int())
	return raw_key


func _draw() -> void:
	var total_width = grid_columns * cell_size
	var total_height = grid_rows * cell_size

	draw_rect(Rect2(grid_offset_x, grid_offset_y, total_width, total_height), Color(0.1, 0.1, 0.1))

	for x in range(grid_columns + 1):
		draw_line(Vector2(grid_offset_x + x * cell_size, grid_offset_y), Vector2(grid_offset_x + x * cell_size, grid_offset_y + total_height), Color(0.4, 0.4, 0.4, 1.0))
	for y in range(grid_rows + 1):
		draw_line(Vector2(grid_offset_x, grid_offset_y + (y * cell_size)), Vector2(grid_offset_x + total_width, grid_offset_y + (y * cell_size)), Color(0.4, 0.4, 0.4, 1.0))

	if current_layout:
		var f := current_layout.current_floor
		for raw_key in current_layout.get_current_floor_tiles().keys():
			var coord: Vector2i
			if raw_key is String:
				var parts = raw_key.split(",")
				coord = Vector2i(parts[0].to_int(), parts[1].to_int())
			else:
				coord = raw_key

			var tile_data = current_layout.get_tile(coord, f)

			if tile_data:
				# Defensive: skip tiles stored outside the current grid bounds
				# (e.g. left over from a shrink or a hand-edited .tres) so they
				# never render beyond the drawn grid / coord markers.
				if coord.x < 0 or coord.x >= grid_columns or coord.y < 0 or coord.y >= grid_rows:
					continue
				var cell_rect = Rect2(grid_offset_x + coord.x * cell_size, grid_offset_y + (coord.y * cell_size), cell_size, cell_size)
				var inner_rect = Rect2(cell_rect.position + Vector2(4, 4), Vector2(cell_size - 8, cell_size - 8))

				draw_rect(cell_rect, Color(0.05, 0.05, 0.05))

				match tile_data.tile_type:
					CP2020DatafortLayout.TileType.DATAWALL:
						draw_rect(cell_rect, Color.BLACK)
						draw_rect(cell_rect, Color(0.3, 0.3, 0.3), false)

					CP2020DatafortLayout.TileType.ENTRY:
						var center = cell_rect.get_center()
						var has_up: bool = tile_data.can_go_up
						var has_down: bool = tile_data.can_go_down
						if tile_data.is_ldl_link:
							draw_rect(inner_rect, Color(0.05, 0.1, 0.25), true)
							draw_rect(inner_rect, Color.DEEP_SKY_BLUE, false, 2)
							draw_string(get_theme_default_font(), cell_rect.position + Vector2(12, 27), "L", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color.DEEP_SKY_BLUE)
						elif has_up and has_down:
							# Both: split teal (top) / purple (bottom) frame.
							var half := Rect2(cell_rect.position, Vector2(cell_rect.size.x, cell_rect.size.y * 0.5))
							var half2 := Rect2(cell_rect.position + Vector2(0, cell_rect.size.y * 0.5), Vector2(cell_rect.size.x, cell_rect.size.y * 0.5))
							draw_rect(inner_rect, Color(0.05, 0.12, 0.12), true)
							draw_rect(half, Color(0.0, 0.9, 0.9), false, 2)
							draw_rect(half2, Color(0.8, 0.4, 1.0), false, 2)
						elif has_up:
							draw_rect(inner_rect, Color(0.05, 0.12, 0.12), true)
							draw_rect(inner_rect, Color(0.0, 0.9, 0.9), false, 2)
						elif has_down:
							draw_rect(inner_rect, Color(0.06, 0.03, 0.12), true)
							draw_rect(inner_rect, Color(0.8, 0.4, 1.0), false, 2)
						else:
							draw_rect(inner_rect, Color(0.1, 0.2, 0.1), true)
							draw_rect(inner_rect, Color.WEB_GREEN, false)
							var points = PackedVector2Array([
								center + Vector2(0, -10),
								center + Vector2(-10, 8),
								center + Vector2(10, 8)
							])
							draw_polygon(points, PackedColorArray([Color.WEB_GREEN]))
						# Up/down glyphs in the top-left / bottom-left corners.
						var _ef := get_theme_default_font()
						if has_up:
							draw_string(_ef, cell_rect.position + Vector2(3, 11), "↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.0, 0.9, 0.9))
						if has_down:
							draw_string(_ef, cell_rect.position + Vector2(3, cell_rect.size.y - 3), "↓", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.4, 1.0))
						if tile_data.is_primary_entry:
							# Top-right corner so it doesn't clash with the glyphs.
							var mark := Rect2(cell_rect.position + Vector2(cell_rect.size.x - 12, 4), Vector2(8, 8))
							draw_rect(mark, Color.WHITE, true)
							draw_rect(mark, Color.BLACK, false, 1)

					CP2020DatafortLayout.TileType.CODE_GATE:
						draw_rect(inner_rect, Color(0.3, 0.15, 0), true)
						draw_rect(inner_rect, Color.DARK_ORANGE, false)
						draw_line(cell_rect.position + Vector2(0, cell_size / 2.0), cell_rect.position + Vector2(cell_size, cell_size / 2.0), Color.DARK_ORANGE, 2)

					CP2020DatafortLayout.TileType.MEMORY_UNIT:
						var chip_rect = Rect2(cell_rect.position + Vector2(8, 10), Vector2(24, 20))
						draw_rect(chip_rect, Color.DEEP_SKY_BLUE, false)
						draw_line(chip_rect.position + Vector2(-4, 4), chip_rect.position + Vector2(0, 4), Color.DEEP_SKY_BLUE, 2)
						draw_line(chip_rect.position + Vector2(-4, 12), chip_rect.position + Vector2(0, 12), Color.DEEP_SKY_BLUE, 2)
						draw_line(chip_rect.position + Vector2(24, 4), chip_rect.position + Vector2(28, 4), Color.DEEP_SKY_BLUE, 2)
						draw_line(chip_rect.position + Vector2(24, 12), chip_rect.position + Vector2(28, 12), Color.DEEP_SKY_BLUE, 2)

					CP2020DatafortLayout.TileType.CONTROL_NODE:
						draw_rect(inner_rect, Color.PURPLE, false)
						var center = cell_rect.get_center()
						var diamond = PackedVector2Array([
							center + Vector2(0, -10),
							center + Vector2(10, 0),
							center + Vector2(0, 10),
							center + Vector2(-10, 0)
						])
						draw_polygon(diamond, PackedColorArray([Color.PURPLE]))

					CP2020DatafortLayout.TileType.BLACK_ICE:
						var center = cell_rect.get_center()
						if tile_data.ice_program != null:
							var prog: NetProgram = tile_data.ice_program
							var sprite_tex: Texture2D = prog.get_sprite()
							if sprite_tex != null:
								# Sprite path: draw the program's sprite frame at the
								# tile center + sprite_offset, scaled to fill the tile
								# (× sprite_scale). Mirrors BlackICE.apply_visual_from_program.
								var frame_size: int = prog.sprite_frame_size
								if frame_size <= 0:
									frame_size = 128
								var atlas := AtlasTexture.new()
								atlas.atlas = sprite_tex
								atlas.region = Rect2(prog.sprite_frame * frame_size, 0, frame_size, frame_size)
								var scaled_size: float = cell_size * prog.sprite_scale
								var draw_pos: Vector2 = center + prog.sprite_offset - Vector2(scaled_size / 2.0, scaled_size / 2.0)
								draw_texture_rect(atlas, Rect2(draw_pos, Vector2(scaled_size, scaled_size)), false)
							else:
								# Glyph path: draw the program's glyph at the tile
								# center + glyph_offset, tinted with the program's color.
								# Mirrors BlackICE.apply_visual_from_program glyph logic.
								var vis: Dictionary = prog.get_visual()
								var gly: String = vis.get("glyph", "\u2620")
								var gly_col: Color = vis.get("color", Color.CRIMSON)
								var font_size: int = 30
								var font: Font = load("res://whitrabt.ttf") as Font
								if font == null:
									font = get_theme_default_font()
								var auto_offset: Vector2 = NetProgram.compute_glyph_centering(gly, font, font_size, cell_size)
								if auto_offset == Vector2.ZERO:
									var fb: Font = load("res://data/seguiemj.ttf") as Font
									if fb != null:
										var fb_offset: Vector2 = NetProgram.compute_glyph_centering(gly, fb, font_size, cell_size)
										if fb_offset != Vector2.ZERO:
											auto_offset = fb_offset
											font = fb
								if not prog.glyph_auto_center:
									auto_offset = Vector2.ZERO
								elif auto_offset == Vector2.ZERO:
									auto_offset = Vector2(-2, -4)
								var label_pos: Vector2 = cell_rect.position + auto_offset + prog.glyph_offset
								draw_string(font, label_pos, gly, HORIZONTAL_ALIGNMENT_CENTER, cell_size, font_size, gly_col)
						else:
							# No program assigned: draw the placeholder circle.
							draw_circle(center, 12, Color(0.3, 0, 0))
							draw_arc(center, 10, 0, TAU, 16, Color.CRIMSON, 2)
							draw_circle(center, 3, Color.CRIMSON)
					CP2020DatafortLayout.TileType.NETWATCH:
						var center_nw = cell_rect.get_center()
						draw_rect(inner_rect, Color(0.3, 0.05, 0.05), true)
						draw_rect(inner_rect, Color.CRIMSON, false)
						var s_left = center_nw + Vector2(-9, -10)
						var s_right = center_nw + Vector2(9, -10)
						var s_bottom = center_nw + Vector2(0, 11)
						var shield = PackedVector2Array([
							s_left,
							s_right,
							center_nw + Vector2(6, 2),
							s_bottom,
							center_nw + Vector2(-6, 2)
						])
						draw_polygon(shield, PackedColorArray([Color.CRIMSON]))
					CP2020DatafortLayout.TileType.NETRUNNER:
						var center_nr = cell_rect.get_center()
						draw_rect(inner_rect, Color(0.25, 0.2, 0.0), true)
						draw_rect(inner_rect, Color.GOLD, false)
						draw_circle(center_nr + Vector2(0, -7), 4, Color.GOLD)
						var body = PackedVector2Array([
							center_nr + Vector2(-7, 10),
							center_nr + Vector2(7, 10),
							center_nr + Vector2(4, -1),
							center_nr + Vector2(-4, -1)
						])
						draw_polygon(body, PackedColorArray([Color.GOLD]))

	# Highlight the selected tile (select mode).
	if select_mode and selected_coord != Vector2i(-1, -1) and not dragging:
		var sel_rect = Rect2(grid_offset_x + selected_coord.x * cell_size, grid_offset_y + (selected_coord.y * cell_size), cell_size, cell_size)
		draw_rect(sel_rect, Color(1.0, 0.85, 0.2), false, 2)
	# Drag-to-move: dim the source cell and draw a ghost under the cursor.
	if dragging and drag_tile != null:
		var src_rect = Rect2(grid_offset_x + drag_source_coord.x * cell_size, grid_offset_y + (drag_source_coord.y * cell_size), cell_size, cell_size)
		draw_rect(src_rect, Color(0.0, 0.0, 0.0, 0.55), true)
		var ghost_rect = Rect2(drag_ghost_pos.x - cell_size * 0.5, drag_ghost_pos.y - cell_size * 0.5, cell_size, cell_size)
		draw_rect(ghost_rect, Color(1.0, 0.85, 0.2, 0.35), true)
		draw_rect(ghost_rect, Color(1.0, 0.85, 0.2, 0.9), false, 2)
	_draw_coord_display()


func _draw_coord_display() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var tick_color := Color(0.7, 0.75, 0.8, 0.9)
	# Column (x) tick labels: centred above each column, in the strip just
	# above the grid (between the top panel and the first row).
	for x in range(grid_columns):
		var cx = grid_offset_x + x * cell_size + cell_size * 0.5
		draw_string(font, Vector2(cx - 5, grid_offset_y - 10), str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tick_color)
	# Row (y) tick labels: placed outside the grid, to the left of each row
	# (right-aligned in the strip left of the first column).
	for y in range(grid_rows):
		var ry = grid_offset_y + y * cell_size + cell_size * 0.5 + 4
		draw_string(font, Vector2(grid_offset_x - 18, ry), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tick_color)
	# Floating mouse tooltip: show the grid coord under the cursor.
	var mp := get_local_mouse_position()
	var ctrl_size := get_rect().size
	var mx = floori((mp.x - grid_offset_x) / cell_size)
	var my = floori((mp.y - grid_offset_y) / cell_size)
	if mx >= 0 and mx < grid_columns and my >= 0 and my < grid_rows:
		var tip := "(%d, %d)" % [mx, my]
		var tip_size := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var tip_pos := mp + Vector2(12, 12)
		# Clamp so the tooltip never clips off the control edge.
		if tip_pos.x + tip_size.x + 4 > ctrl_size.x:
			tip_pos.x = ctrl_size.x - tip_size.x - 4
		if tip_pos.y + tip_size.y + 4 > ctrl_size.y:
			tip_pos.y = ctrl_size.y - tip_size.y - 4
		if tip_pos.x < 2:
			tip_pos.x = 2
		if tip_pos.y < 2:
			tip_pos.y = 2
		draw_rect(Rect2(tip_pos - Vector2(2, 2), tip_size + Vector2(4, 4)), Color(0, 0, 0, 0.75), true)
		draw_string(font, tip_pos, tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 0.8))
