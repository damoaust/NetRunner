@tool
extends Control

@export var map_name: String = "New Datafort"
@export var grid_rows: int = 15
@export var grid_columns: int = 15

var cell_size: int = 40
var grid_offset_y: int = 90 

var current_layout: CP2020DatafortLayout
var selected_tile_type: CP2020DatafortLayout.TileType = CP2020DatafortLayout.TileType.CODE_GATE

@onready var dynamic_button_row: HBoxContainer = $TopPanel/DynamicButtonRow
@onready var columns_spinbox: SpinBox = $TopPanel/SettingsRow/ColumnsSpinBox
@onready var rows_spinbox: SpinBox = $TopPanel/SettingsRow/RowsSpinBox
@onready var apply_size_button: Button = $TopPanel/SettingsRow/Button

@onready var save_dialog: FileDialog = get_node_or_null("SaveDialog")
@onready var load_dialog: FileDialog = get_node_or_null("LoadDialog")

func _ready() -> void:
	setup_new_map()
	setup_file_dialogs_if_missing()
	setup_toolbar_signals()
	setup_toolbar_buttons()
	queue_redraw()

func setup_new_map() -> void:
	if not current_layout:
		current_layout = CP2020DatafortLayout.new()
	current_layout.fort_name = map_name
	current_layout.rows = grid_rows
	current_layout.columns = grid_columns
	
	if columns_spinbox:
		columns_spinbox.value = grid_columns
	if rows_spinbox:
		rows_spinbox.value = grid_rows
		
	fill_empty_tiles()

func fill_empty_tiles() -> void:
	if not current_layout:
		return
		
	for x in range(grid_columns):
		for y in range(grid_rows):
			var coord = Vector2i(x, y)
			if not current_layout.grid_tiles.has(coord):
				var empty_tile = CP2020TileData.new()
				empty_tile.tile_type = CP2020DatafortLayout.TileType.EMPTY
				empty_tile.tile_name = "Empty Path"
				current_layout.grid_tiles[coord] = empty_tile

func setup_file_dialogs_if_missing() -> void:
	if not save_dialog:
		save_dialog = FileDialog.new()
		save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		save_dialog.access = FileDialog.ACCESS_RESOURCES
		save_dialog.add_filter("*.tres", "CP2020 Datafort Resource")
		add_child(save_dialog)
		
	if not load_dialog:
		load_dialog = FileDialog.new()
		load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		load_dialog.access = FileDialog.ACCESS_RESOURCES
		load_dialog.add_filter("*.tres", "CP2020 Datafort Resource")
		add_child(load_dialog)

func setup_toolbar_signals() -> void:
	if apply_size_button and not apply_size_button.pressed.is_connected(_on_resize_pressed):
		apply_size_button.pressed.connect(_on_resize_pressed)
		
	if save_dialog and not save_dialog.file_selected.is_connected(_on_file_saved):
		save_dialog.file_selected.connect(_on_file_saved)
		
	if load_dialog and not load_dialog.file_selected.is_connected(_on_file_loaded):
		load_dialog.file_selected.connect(_on_file_loaded)

# Add an LDL tool button inside setup_toolbar_buttons()
func setup_toolbar_buttons() -> void:
	if not dynamic_button_row:
		return
		
	for child in dynamic_button_row.get_children():
		child.queue_free()
		
	add_tool_button("Entry", CP2020DatafortLayout.TileType.ENTRY)
	add_tool_button("Datawall", CP2020DatafortLayout.TileType.DATAWALL)
	add_tool_button("Code Gate", CP2020DatafortLayout.TileType.CODE_GATE)
	add_tool_button("Memory Unit", CP2020DatafortLayout.TileType.MEMORY_UNIT)
	add_tool_button("Control Node", CP2020DatafortLayout.TileType.CONTROL_NODE)
	add_tool_button("Black ICE", CP2020DatafortLayout.TileType.BLACK_ICE)
	add_tool_button("LDL Link", CP2020DatafortLayout.TileType.ENTRY) # Can map to entry/custom or flag as LDL
	add_tool_button("Eraser", CP2020DatafortLayout.TileType.EMPTY)
	
	var sep = VSeparator.new()
	dynamic_button_row.add_child(sep)
	
	var save_btn = Button.new()
	save_btn.text = "Save Map"
	save_btn.pressed.connect(_on_save_pressed)
	dynamic_button_row.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "Load Map"
	load_btn.pressed.connect(_on_load_pressed)
	dynamic_button_row.add_child(load_btn)
	
func add_tool_button(label_text: String, tile_type: CP2020DatafortLayout.TileType) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.pressed.connect(func(): 
		selected_tile_type = tile_type
		print("Selected Tool: ", label_text)
	)
	dynamic_button_row.add_child(btn)

func _on_resize_pressed() -> void:
	if not current_layout:
		return
		
	var new_cols = int(columns_spinbox.value) if columns_spinbox else grid_columns
	var new_rows = int(rows_spinbox.value) if rows_spinbox else grid_rows
	
	grid_columns = new_cols
	grid_rows = new_rows
	current_layout.columns = new_cols
	current_layout.rows = new_rows
	
	var keys_to_delete: Array = []
	for raw_key in current_layout.grid_tiles.keys():
		# Safely parse the key whether it's a String or Vector2i
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
			
		if coord.x >= new_cols or coord.y >= new_rows:
			keys_to_delete.append(raw_key)
			
	for raw_key in keys_to_delete:
		current_layout.grid_tiles.erase(raw_key)
		print("Deleted out-of-bounds tile at: ", raw_key)
		
	fill_empty_tiles()
	print("Map resized to %d x %d" % [new_cols, new_rows])
	queue_redraw()

func _on_save_pressed() -> void:
	if save_dialog:
		save_dialog.popup_centered(Vector2i(600, 400))

func _on_load_pressed() -> void:
	if load_dialog:
		load_dialog.popup_centered(Vector2i(600, 400))

func _on_file_saved(path: String) -> void:
	if current_layout:
		var err = ResourceSaver.save(current_layout, path)
		if err == OK:
			print("Datafort layout successfully saved to: ", path)
		else:
			print("Error saving datafort layout: ", err)

func _on_file_loaded(path: String) -> void:
	var loaded_resource = ResourceLoader.load(path)
	if loaded_resource is CP2020DatafortLayout:
		current_layout = loaded_resource
		grid_columns = current_layout.columns
		grid_rows = current_layout.rows
		map_name = current_layout.fort_name
		
		if columns_spinbox:
			columns_spinbox.value = grid_columns
		if rows_spinbox:
			rows_spinbox.value = grid_rows
			
		fill_empty_tiles()
		queue_redraw()
		print("Datafort layout successfully loaded from: ", path)
	else:
		print("Failed to load layout or invalid file type.")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = event.position
			var adjusted_y = local_pos.y - grid_offset_y 
			
			var grid_x = int(local_pos.x / cell_size)
			var grid_y = int(adjusted_y / cell_size)
			
			if grid_x >= 0 and grid_x < grid_columns and grid_y >= 0 and grid_y < grid_rows:
				paint_tile(Vector2i(grid_x, grid_y))

# Update paint_tile to flag LDL options if needed
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
			tile_data.tile_name = "Netrunner Entry / LDL Node"
			tile_data.is_ldl_link = true # Flag as LDL routing line connection point
			tile_data.target_subnet_path = "res://scenes/forts/fort2.tres" # Default target subnet path example
			tile_data.target_entry_coord = Vector2i(0, 0)
		CP2020DatafortLayout.TileType.EMPTY:
			tile_data.tile_name = "Empty Path"
			
	current_layout.grid_tiles[coord] = tile_data
	queue_redraw()
	

func _draw() -> void:
	var total_width = grid_columns * cell_size
	var total_height = grid_rows * cell_size
	
	draw_rect(Rect2(0, grid_offset_y, total_width, total_height), Color(0.1, 0.1, 0.1))
	
	for x in range(grid_columns + 1):
		draw_line(Vector2(x * cell_size, grid_offset_y), Vector2(x * cell_size, grid_offset_y + total_height), Color(0.4, 0.4, 0.4, 1.0))
	for y in range(grid_rows + 1):
		draw_line(Vector2(0, grid_offset_y + (y * cell_size)), Vector2(total_width, grid_offset_y + (y * cell_size)), Color(0.4, 0.4, 0.4, 1.0))
		
	if current_layout:
		for raw_key in current_layout.grid_tiles.keys():
			# 1. Convert the string key from the resource file back into a Vector2i
			var coord: Vector2i
			if raw_key is String:
				var parts = raw_key.split(",")
				coord = Vector2i(parts[0].to_int(), parts[1].to_int())
			else:
				coord = raw_key
				
			# 2. Safe fallback: Check if get_tile exists; otherwise read the dictionary directly
			var tile_data = null
			if current_layout.has_method("get_tile"):
				tile_data = current_layout.get_tile(coord)
			else:
				tile_data = current_layout.grid_tiles.get(raw_key)
			
			if tile_data:
				# 3. Safe to calculate using coord.x and coord.y now!
				var cell_rect = Rect2(coord.x * cell_size, grid_offset_y + (coord.y * cell_size), cell_size, cell_size)
				var inner_rect = Rect2(cell_rect.position + Vector2(4, 4), Vector2(cell_size - 8, cell_size - 8))
				
				# Empty tiles will just draw this background color and then break, which is perfect for the editor
				draw_rect(cell_rect, Color(0.05, 0.05, 0.05))
				
				match tile_data.tile_type:
					CP2020DatafortLayout.TileType.DATAWALL:
						draw_rect(cell_rect, Color.BLACK)
						draw_rect(cell_rect, Color(0.3, 0.3, 0.3), false)
						
					CP2020DatafortLayout.TileType.ENTRY:
						draw_rect(inner_rect, Color(0.1, 0.2, 0.1), true)
						draw_rect(inner_rect, Color.WEB_GREEN, false)
						var center = cell_rect.get_center()
						var points = PackedVector2Array([
							center + Vector2(0, -10),
							center + Vector2(-10, 8),
							center + Vector2(10, 8)
						])
						draw_polygon(points, PackedColorArray([Color.WEB_GREEN]))
						
					CP2020DatafortLayout.TileType.CODE_GATE:
						draw_rect(inner_rect, Color(0.3, 0.15, 0), true)
						draw_rect(inner_rect, Color.DARK_ORANGE, false)
						draw_line(cell_rect.position + Vector2(0, cell_size/2), cell_rect.position + Vector2(cell_size, cell_size/2), Color.DARK_ORANGE, 2)
						
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
						draw_circle(center, 12, Color(0.3, 0, 0))
						draw_arc(center, 10, 0, TAU, 16, Color.CRIMSON, 2)
						draw_circle(center, 3, Color.CRIMSON)
