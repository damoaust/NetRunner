class_name CP2020BoardRenderer
extends Node2D

@export var cell_size: int = 40
@export var grid_offset_y: int = 90

# Reference to the current layout being displayed
var current_layout: CP2020DatafortLayout

func _draw() -> void:
	if current_layout:
		draw_grid(self, current_layout)

func draw_grid(canvas: CanvasItem, layout: CP2020DatafortLayout) -> void:
	if not layout or not layout.grid_tiles:
		return

	var total_width = layout.columns * cell_size
	var total_height = layout.rows * cell_size

	# STATE 3 (UNEXPLORED): Paint whole board black
	canvas.draw_rect(Rect2(0, grid_offset_y, total_width, total_height), Color.BLACK)

	for raw_key in layout.grid_tiles.keys():
		# 1. Safely convert the string key from the .tres file back into a Vector2i
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
			
		# 2. Safely get the tile using our helper function
		var tile_data = layout.get_tile(coord)
		
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
			canvas.draw_rect(cell_rect, Color(Color.CYAN, 1.0 * alpha_mult), false, 2.0)

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

		CP2020DatafortLayout.TileType.CONTROL_NODE:
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

		CP2020DatafortLayout.TileType.NETWATCH:
			# NetWatch spawn marker: red shield/badge glyph on a dark red floor.
			canvas.draw_rect(cell_rect, Color(0.5, 0.05, 0.05, 0.3 * alpha_mult), true)
			canvas.draw_rect(cell_rect, Color(Color.RED, 0.9 * alpha_mult), false, 2.0)
			var nw_center = cell_rect.get_center()
			# Shield outline
			var shield = PackedVector2Array([
				nw_center + Vector2(-8, -9),
				nw_center + Vector2(8, -9),
				nw_center + Vector2(8, 2),
				nw_center + Vector2(0, 10),
				nw_center + Vector2(-8, 2)
			])
			canvas.draw_polygon(shield, PackedColorArray([Color(0.8, 0.1, 0.1, 0.55 * alpha_mult)]))
			# Badge crossbar
			canvas.draw_line(
				nw_center + Vector2(-5, -2),
				nw_center + Vector2(5, -2),
				Color(Color.WHITE, 0.9 * alpha_mult), 2.0)

		CP2020DatafortLayout.TileType.NETRUNNER:
			# Random netrunner spawn marker: yellow person glyph on a dark floor.
			canvas.draw_rect(cell_rect, Color(0.4, 0.35, 0.05, 0.3 * alpha_mult), true)
			canvas.draw_rect(cell_rect, Color(Color.YELLOW, 0.9 * alpha_mult), false, 2.0)
			var nr_center = cell_rect.get_center()
			# Head
			canvas.draw_circle(nr_center + Vector2(0, -5), 3.0, Color(0.9, 0.8, 0.1, 0.8 * alpha_mult))
			# Body
			var body = PackedVector2Array([
				nr_center + Vector2(-5, 3),
				nr_center + Vector2(5, 3),
				nr_center + Vector2(4, 10),
				nr_center + Vector2(-4, 10)
			])
			canvas.draw_polygon(body, PackedColorArray([Color(0.9, 0.8, 0.1, 0.7 * alpha_mult)]))
