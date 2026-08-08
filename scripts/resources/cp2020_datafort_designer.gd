@tool
extends Control

@export var map_name: String = "New Datafort"
@export var grid_rows: int = 15
@export var grid_columns: int = 15

var cell_size: int = 40
var grid_offset_y: int = 90 

var current_layout: CP2020DatafortLayout
var selected_tile_type: CP2020DatafortLayout.TileType = CP2020DatafortLayout.TileType.CODE_GATE
# When true, clicking an existing tile selects it for editing (opens its side
# panel on the live tile) instead of overwriting it with a fresh tile.
var select_mode: bool = false
# Coord of the tile currently selected in select mode (for the draw highlight).
var selected_coord: Vector2i = Vector2i(-1, -1)
# Drag-to-move state (Select mode only). On left-press over a non-empty tile
# the tile is picked up; dragging shows a ghost under the cursor; releasing
# over an empty cell moves the tile there (preserving its configured fields).
var dragging: bool = false
var drag_source_coord: Vector2i = Vector2i(-1, -1)
var drag_tile: CP2020TileData = null
var drag_ghost_pos: Vector2 = Vector2.ZERO
# Pixel position where the drag was initiated. Used by the release handler to
# distinguish a real drag from a jittery click: if the cursor travelled less
# than DRAG_THRESHOLD pixels we treat the release as a select-click on the
# source tile instead of a move (avoids accidental 1-cell moves when a click
# near a cell edge drifts across the boundary during press→release).
var drag_press_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD := 6.0
# When true, painting an ENTRY tile marks it as an LDL link (a tile the
# runner can travel through to reach another datafort / the world map).
var ldl_link_mode: bool = false
# Tile currently being edited in the LDL link side panel.
var selected_ldl_coord: Vector2i = Vector2i(-1, -1)

@onready var dynamic_button_row: HBoxContainer = $TopPanel/DynamicButtonRow
@onready var columns_spinbox: SpinBox = $TopPanel/SettingsRow/ColumnsSpinBox
@onready var rows_spinbox: SpinBox = $TopPanel/SettingsRow/RowsSpinBox
@onready var apply_size_button: Button = $TopPanel/SettingsRow/Button

@onready var save_dialog: FileDialog = get_node_or_null("SaveDialog")
@onready var load_dialog: FileDialog = get_node_or_null("LoadDialog")

# LDL link editor panel (built in code so the scene file stays simple).
var ldl_panel: VBoxContainer
var ldl_panel_bg: PanelContainer
var ldl_target_edit: LineEdit
var ldl_x_spinbox: SpinBox
var ldl_y_spinbox: SpinBox
var ldl_browse_dialog: FileDialog

# ICE editor panel (built in code; shown when a BLACK_ICE tile is selected).
var ice_panel: VBoxContainer
var ice_panel_bg: PanelContainer
var ice_program_label: Label
var ice_program_dialog: FileDialog
var selected_ice_coord: Vector2i = Vector2i(-1, -1)

# NPC editor panel (built in code; shown when a NETWATCH/NETRUNNER tile is selected).
var npc_panel: VBoxContainer
var npc_panel_bg: PanelContainer
var npc_name_edit: LineEdit
var npc_str_spinbox: SpinBox
var npc_ap_spinbox: SpinBox
var npc_int_spinbox: SpinBox
var npc_health_spinbox: SpinBox
var npc_mu_spinbox: SpinBox
var npc_deck_edit: LineEdit
var npc_disposition_option: OptionButton
var selected_npc_coord: Vector2i = Vector2i(-1, -1)

# CPU editor panel (built in code; shown when a CONTROL_NODE tile is selected).
var cpu_panel: VBoxContainer
var cpu_panel_bg: PanelContainer
var selected_cpu_coord: Vector2i = Vector2i(-1, -1)

# Loot editor panel (built in code; shown when a CONTROL_NODE tile is
# selected). Lets designers author the programs/credits a runner gets when
# looting a CPU. MEMORY_UNIT tiles use the Files Editor instead. Mirrors the
# ICE/NPC override panel pattern.
var loot_panel: VBoxContainer
var loot_panel_bg: PanelContainer
var loot_credits_spinbox: SpinBox
var loot_programs_list: ItemList
var loot_add_dialog: FileDialog
var loot_cpu_info_label: Label
var selected_loot_coord: Vector2i = Vector2i(-1, -1)

# Files editor panel (built in code; shown when a MEMORY_UNIT tile is
# selected). Files are discrete data files a netrunner copies to deck memory
# (consuming MU) and fences at the hub for their credit value. Replaces the
# loot editor for MEMORY_UNIT tiles; CONTROL_NODE still uses the loot editor.
var files_panel: VBoxContainer
var files_panel_bg: PanelContainer
var files_list: ItemList
var file_name_edit: LineEdit
var file_desc_edit: TextEdit
var file_value_spinbox: SpinBox
var file_mu_spinbox: SpinBox
var selected_files_coord: Vector2i = Vector2i(-1, -1)

# Layout-level resident programs editor (programs the datafort's CPUs run).
var programs_panel: VBoxContainer
var programs_panel_bg: PanelContainer
var programs_list: ItemList
var programs_add_dialog: FileDialog
var programs_mu_label: Label

func _ready() -> void:
	setup_new_map()
	setup_file_dialogs_if_missing()
	setup_toolbar_signals()
	setup_toolbar_buttons()
	build_ldl_panel()
	build_ice_panel()
	build_npc_panel()
	build_cpu_panel()
	build_loot_panel()
	build_files_panel()
	build_programs_panel()
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
			# Use get_tile so both key forms (Vector2i and "x,y" string) are
			# checked. Without this, the fill would add an EMPTY Vector2i tile on
			# top of hand-authored string-key tiles, and get_tile() (which checks
			# Vector2i first) would return the EMPTY, hiding the authored content.
			if current_layout.get_tile(coord) == null:
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
		
	add_select_tool_button("Select")
	add_entry_tool_button("Entry")
	add_tool_button("Datawall", CP2020DatafortLayout.TileType.DATAWALL)
	add_tool_button("Code Gate", CP2020DatafortLayout.TileType.CODE_GATE)
	add_tool_button("Memory Unit", CP2020DatafortLayout.TileType.MEMORY_UNIT)
	add_tool_button("Control Node", CP2020DatafortLayout.TileType.CONTROL_NODE)
	add_tool_button("Black ICE", CP2020DatafortLayout.TileType.BLACK_ICE)
	add_tool_button("NetWatch", CP2020DatafortLayout.TileType.NETWATCH)
	add_tool_button("Netrunner", CP2020DatafortLayout.TileType.NETRUNNER)
	add_ldl_tool_button("LDL Link")
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
	
func add_select_tool_button(label_text: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.pressed.connect(func():
		select_mode = true
		ldl_link_mode = false
		selected_coord = Vector2i(-1, -1)
		dragging = false
		drag_tile = null
		_hide_ldl_panel()
		_hide_ice_panel()
		_hide_npc_panel()
		_hide_loot_panel()
		_hide_files_panel()
		queue_redraw()
		print("Selected Tool: ", label_text, " (click a tile to edit it)")
	)
	dynamic_button_row.add_child(btn)

func add_tool_button(label_text: String, tile_type: CP2020DatafortLayout.TileType) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.pressed.connect(func():
		selected_tile_type = tile_type
		select_mode = false
		ldl_link_mode = false
		selected_coord = Vector2i(-1, -1)
		dragging = false
		drag_tile = null
		_hide_ldl_panel()
		_hide_ice_panel()
		_hide_npc_panel()
		_hide_loot_panel()
		_hide_files_panel()
		queue_redraw()
		print("Selected Tool: ", label_text)
	)
	dynamic_button_row.add_child(btn)

func add_entry_tool_button(label_text: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.pressed.connect(func():
		selected_tile_type = CP2020DatafortLayout.TileType.ENTRY
		select_mode = false
		ldl_link_mode = false
		selected_coord = Vector2i(-1, -1)
		dragging = false
		drag_tile = null
		_hide_ldl_panel()
		_hide_ice_panel()
		_hide_npc_panel()
		_hide_loot_panel()
		_hide_files_panel()
		queue_redraw()
		print("Selected Tool: ", label_text, " (plain datafort entrance)")
	)
	dynamic_button_row.add_child(btn)

func add_ldl_tool_button(label_text: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.pressed.connect(func():
		selected_tile_type = CP2020DatafortLayout.TileType.ENTRY
		select_mode = false
		ldl_link_mode = true
		selected_coord = Vector2i(-1, -1)
		dragging = false
		drag_tile = null
		_hide_ice_panel()
		_hide_npc_panel()
		_hide_loot_panel()
		_hide_files_panel()
		queue_redraw()
		print("Selected Tool: ", label_text, " (paint/select an LDL link, then edit it in the side panel)")
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

# Open the appropriate side panel for an existing tile at coord (select mode
# + drag-drop share this). Hides every panel for tiles with no editor.
func _open_editor_for_tile(coord: Vector2i, tile: CP2020TileData) -> void:
	selected_coord = coord
	if tile == null or tile.tile_type == CP2020DatafortLayout.TileType.EMPTY:
		_hide_ldl_panel()
		_hide_ice_panel()
		_hide_npc_panel()
		_hide_cpu_panel()
		_hide_loot_panel()
		_hide_files_panel()
	elif tile.tile_type == CP2020DatafortLayout.TileType.ENTRY and tile.is_ldl_link:
		_open_ldl_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.BLACK_ICE:
		_hide_ldl_panel()
		_open_ice_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.NETWATCH or tile.tile_type == CP2020DatafortLayout.TileType.NETRUNNER:
		_hide_ldl_panel()
		_open_npc_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE:
		_hide_ldl_panel()
		_hide_cpu_panel()
		_hide_files_panel()
		_open_loot_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.MEMORY_UNIT:
		_hide_ldl_panel()
		_hide_loot_panel()
		_open_files_editor(coord)
	else:
		_hide_ldl_panel()
		_hide_ice_panel()
		_hide_npc_panel()
		_hide_cpu_panel()
		_hide_loot_panel()
		_hide_files_panel()

func _gui_input(event: InputEvent) -> void:
	# Drag ghost follows the cursor while a tile is picked up.
	if event is InputEventMouseMotion and dragging:
		drag_ghost_pos = event.position
		queue_redraw()
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var local_pos = event.position
	var adjusted_y = local_pos.y - grid_offset_y
	# Use floori (floor-toward-negative-infinity) instead of int() (which
	# truncates toward zero): a release above the grid (adjusted_y < 0) must
	# map to a negative row so it's correctly treated as out-of-bounds, not
	# silently dropped onto row 0.
	var grid_x = floori(local_pos.x / cell_size)
	var grid_y = floori(adjusted_y / cell_size)
	var in_bounds = grid_x >= 0 and grid_x < grid_columns and grid_y >= 0 and grid_y < grid_rows
	var coord := Vector2i(grid_x, grid_y)
	if event.pressed:
		if not in_bounds:
			return
		# Select mode: pick up a non-empty tile to drag (editor opens on
		# release); clicking an empty cell clears the selection.
		if select_mode:
			var existing = current_layout.get_tile(coord) if current_layout else null
			if existing != null and existing.tile_type != CP2020DatafortLayout.TileType.EMPTY:
				dragging = true
				drag_source_coord = coord
				drag_tile = existing
				drag_ghost_pos = local_pos
				drag_press_pos = local_pos
			else:
				_open_editor_for_tile(coord, existing)
			queue_redraw()
			return
		# In LDL Link mode: clicking an existing LDL link selects it for
		# editing rather than overwriting it. Clicking anything else
		# paints a fresh LDL link and opens the editor on it.
		if ldl_link_mode:
			var existing = current_layout.get_tile(coord) if current_layout else null
			if existing and existing.tile_type == CP2020DatafortLayout.TileType.ENTRY and existing.is_ldl_link:
				_open_ldl_editor(coord)
			else:
				paint_tile(coord)
				_open_ldl_editor(coord)
			return
		paint_tile(coord)
		_hide_ldl_panel()
		var painted = current_layout.get_tile(coord) if current_layout else null
		if painted and painted.tile_type == CP2020DatafortLayout.TileType.BLACK_ICE:
			_open_ice_editor(coord)
		elif painted and (painted.tile_type == CP2020DatafortLayout.TileType.NETWATCH or painted.tile_type == CP2020DatafortLayout.TileType.NETRUNNER):
			_open_npc_editor(coord)
		elif painted and painted.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE:
			_hide_cpu_panel()
			_hide_files_panel()
			_open_loot_editor(coord)
		elif painted and painted.tile_type == CP2020DatafortLayout.TileType.MEMORY_UNIT:
			_hide_loot_panel()
			_open_files_editor(coord)
		else:
			_hide_ice_panel()
			_hide_npc_panel()
			_hide_cpu_panel()
			_hide_loot_panel()
			_hide_files_panel()
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
		# tile regardless of which cell the cursor ended in. This prevents an
		# accidental 1-cell move when a click near a cell edge drifts across
		# the boundary during press→release.
		var travel: float = local_pos.distance_to(drag_press_pos)
		if travel < DRAG_THRESHOLD:
			_open_editor_for_tile(source, tile)
			queue_redraw()
			return
		# Out of bounds or same cell = cancel (treat as a select-click on source).
		if not in_bounds or coord == source:
			_open_editor_for_tile(source, tile)
			queue_redraw()
			return
		var target_tile = current_layout.get_tile(coord) if current_layout else null
		if target_tile != null and target_tile.tile_type != CP2020DatafortLayout.TileType.EMPTY:
			# Occupied: reject the drop, keep the tile at its source.
			print("Drag rejected — target %s is occupied." % coord)
			_open_editor_for_tile(source, tile)
			queue_redraw()
			return
		# Move the tile: erase source, place at target, fill source with a
		# fresh EMPTY so the grid stays a walkable floor.
		current_layout.erase_tile(source)
		current_layout.set_tile(coord, tile)
		var empty := CP2020TileData.new()
		empty.tile_type = CP2020DatafortLayout.TileType.EMPTY
		empty.tile_name = "Empty Path"
		current_layout.set_tile(source, empty)
		_open_editor_for_tile(coord, tile)
		queue_redraw()

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
			if ldl_link_mode:
				# An LDL link is an ENTRY tile the runner can travel through to
				# reach another datafort (or return to the world map). The
				# target is configured afterwards via the LDL side panel.
				tile_data.tile_name = "LDL Link"
				tile_data.is_ldl_link = true
				tile_data.target_subnet_path = ""
				tile_data.target_entry_coord = Vector2i(-1, -1)
			else:
				# A plain Entry is this datafort's arrival point when diving
				# in from the world map (no outbound LDL link).
				tile_data.tile_name = "Netrunner Entry"
				tile_data.is_ldl_link = false
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
			
	current_layout.set_tile(coord, tile_data)
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
						if tile_data.is_ldl_link:
							# LDL links get a distinct blue frame + "L" glyph so the
							# designer can tell them apart from plain netrunner entries.
							draw_rect(inner_rect, Color(0.05, 0.1, 0.25), true)
							draw_rect(inner_rect, Color.DEEP_SKY_BLUE, false, 2)
							draw_string(get_theme_default_font(), cell_rect.position + Vector2(12, 27), "L", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color.DEEP_SKY_BLUE)
						else:
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
					CP2020DatafortLayout.TileType.NETWATCH:
						# NetWatch: red shield/badge glyph.
						var center_nw = cell_rect.get_center()
						draw_rect(inner_rect, Color(0.3, 0.05, 0.05), true)
						draw_rect(inner_rect, Color.CRIMSON, false)
						# Shield shape.
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
						# Netrunner: yellow person glyph.
						var center_nr = cell_rect.get_center()
						draw_rect(inner_rect, Color(0.25, 0.2, 0.0), true)
						draw_rect(inner_rect, Color.GOLD, false)
						# Head.
						draw_circle(center_nr + Vector2(0, -7), 4, Color.GOLD)
						# Body.
						var body = PackedVector2Array([
							center_nr + Vector2(-7, 10),
							center_nr + Vector2(7, 10),
							center_nr + Vector2(4, -1),
							center_nr + Vector2(-4, -1)
						])
						draw_polygon(body, PackedColorArray([Color.GOLD]))

	# Highlight the selected tile (select mode) so the designer can see which
	# tile the open side panel is editing.
	if select_mode and selected_coord != Vector2i(-1, -1) and not dragging:
		var sel_rect = Rect2(selected_coord.x * cell_size, grid_offset_y + (selected_coord.y * cell_size), cell_size, cell_size)
		draw_rect(sel_rect, Color(1.0, 0.85, 0.2), false, 2)
	# Drag-to-move: dim the source cell and draw a ghost under the cursor.
	if dragging and drag_tile != null:
		var src_rect = Rect2(drag_source_coord.x * cell_size, grid_offset_y + (drag_source_coord.y * cell_size), cell_size, cell_size)
		draw_rect(src_rect, Color(0.0, 0.0, 0.0, 0.55), true)
		var ghost_rect = Rect2(drag_ghost_pos.x - cell_size * 0.5, drag_ghost_pos.y - cell_size * 0.5, cell_size, cell_size)
		draw_rect(ghost_rect, Color(1.0, 0.85, 0.2, 0.35), true)
		draw_rect(ghost_rect, Color(1.0, 0.85, 0.2, 0.9), false, 2)

# ---------------------------------------------------------------------------
# LDL link editor side panel
# ---------------------------------------------------------------------------

func build_ldl_panel() -> void:
	# Panel container gives the editor a readable background over the grid.
	var panel_bg = PanelContainer.new()
	panel_bg.name = "LDLLinkPanel"
	panel_bg.anchor_left = 1.0
	panel_bg.anchor_right = 1.0
	panel_bg.anchor_top = 0.0
	panel_bg.anchor_bottom = 1.0
	panel_bg.offset_left = -300
	panel_bg.offset_right = -10
	panel_bg.offset_top = 90
	panel_bg.offset_bottom = -10
	panel_bg.visible = false
	add_child(panel_bg)
	ldl_panel_bg = panel_bg

	ldl_panel = VBoxContainer.new()
	ldl_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ldl_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_bg.add_child(ldl_panel)

	var title = Label.new()
	title.text = "LDL Link Editor"
	ldl_panel.add_child(title)

	var target_lbl = Label.new()
	target_lbl.text = "Target subnet (.tres):"
	ldl_panel.add_child(target_lbl)

	var target_row = HBoxContainer.new()
	ldl_target_edit = LineEdit.new()
	ldl_target_edit.placeholder_text = "res://scenes/forts/..."
	ldl_target_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ldl_target_edit.text_changed.connect(_on_ldl_target_changed)
	target_row.add_child(ldl_target_edit)
	var browse_btn = Button.new()
	browse_btn.text = "..."
	browse_btn.pressed.connect(_on_ldl_browse)
	target_row.add_child(browse_btn)
	ldl_panel.add_child(target_row)

	var coord_lbl = Label.new()
	coord_lbl.text = "Target entry coord (X, Y):"
	ldl_panel.add_child(coord_lbl)

	var coord_row = HBoxContainer.new()
	ldl_x_spinbox = SpinBox.new()
	ldl_x_spinbox.min_value = -1
	ldl_x_spinbox.max_value = 999
	ldl_x_spinbox.value_changed.connect(_on_ldl_coord_changed)
	coord_row.add_child(ldl_x_spinbox)
	ldl_y_spinbox = SpinBox.new()
	ldl_y_spinbox.min_value = -1
	ldl_y_spinbox.max_value = 999
	ldl_y_spinbox.value_changed.connect(_on_ldl_coord_changed)
	coord_row.add_child(ldl_y_spinbox)
	ldl_panel.add_child(coord_row)

	var clear_btn = Button.new()
	clear_btn.text = "Clear target (world-map return only)"
	clear_btn.pressed.connect(_clear_ldl_target)
	ldl_panel.add_child(clear_btn)

	var hint = Label.new()
	hint.text = "Empty target = 'Return to City Grid' only.\nSet a .tres to also offer 'Travel to <datafort>'."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ldl_panel.add_child(hint)

	# Browse dialog scoped to the forts folder.
	ldl_browse_dialog = FileDialog.new()
	ldl_browse_dialog.name = "LDLBrowseDialog"
	ldl_browse_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	ldl_browse_dialog.access = FileDialog.ACCESS_RESOURCES
	ldl_browse_dialog.current_dir = "res://scenes/forts"
	ldl_browse_dialog.filters = PackedStringArray(["*.tres ; Godot Resource"])
	ldl_browse_dialog.file_selected.connect(_on_ldl_target_selected)
	add_child(ldl_browse_dialog)


func _open_ldl_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.ENTRY or not tile.is_ldl_link:
		print("No LDL link at ", coord, " to edit.")
		return
	selected_ldl_coord = coord
	# Populate fields without retriggering the write-back handlers.
	ldl_target_edit.set_block_signals(true)
	ldl_x_spinbox.set_block_signals(true)
	ldl_y_spinbox.set_block_signals(true)
	ldl_target_edit.text = tile.target_subnet_path
	ldl_x_spinbox.value = tile.target_entry_coord.x
	ldl_y_spinbox.value = tile.target_entry_coord.y
	ldl_target_edit.set_block_signals(false)
	ldl_x_spinbox.set_block_signals(false)
	ldl_y_spinbox.set_block_signals(false)
	ldl_panel_bg.visible = true
	print("Editing LDL link at ", coord)


func _hide_ldl_panel() -> void:
	if ldl_panel_bg:
		ldl_panel_bg.visible = false
	selected_ldl_coord = Vector2i(-1, -1)


func _write_ldl_field() -> void:
	if not current_layout or selected_ldl_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_ldl_coord)
	if tile == null:
		return
	tile.target_subnet_path = ldl_target_edit.text.strip_edges()
	tile.target_entry_coord = Vector2i(int(ldl_x_spinbox.value), int(ldl_y_spinbox.value))
	queue_redraw()


func _on_ldl_target_changed(_new_text: String) -> void:
	_write_ldl_field()


func _on_ldl_coord_changed(_value: float) -> void:
	_write_ldl_field()


func _on_ldl_browse() -> void:
	ldl_browse_dialog.popup_centered(Vector2i(600, 400))


func _on_ldl_target_selected(path: String) -> void:
	ldl_target_edit.text = path
	_write_ldl_field()


func _clear_ldl_target() -> void:
	ldl_target_edit.text = ""
	ldl_x_spinbox.value = -1
	ldl_y_spinbox.value = -1
	_write_ldl_field()


# ---------------------------------------------------------------------------
# ICE editor side panel (BLACK_ICE tiles)
# ---------------------------------------------------------------------------

func build_ice_panel() -> void:
	var panel_bg = PanelContainer.new()
	panel_bg.name = "IceEditorPanel"
	panel_bg.anchor_left = 1.0
	panel_bg.anchor_right = 1.0
	panel_bg.anchor_top = 0.0
	panel_bg.anchor_bottom = 1.0
	panel_bg.offset_left = -300
	panel_bg.offset_right = -10
	panel_bg.offset_top = 90
	panel_bg.offset_bottom = -10
	panel_bg.visible = false
	add_child(panel_bg)
	ice_panel_bg = panel_bg

	ice_panel = VBoxContainer.new()
	ice_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ice_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_bg.add_child(ice_panel)

	var title = Label.new()
	title.text = "ICE Editor"
	ice_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Assign a program .tres (REQUIRED). Every BLACK_ICE tile must have an assigned program — tiles without one are skipped at spawn. The program supplies the ICE's name / strength / effect_type / damage; integrity is derived from the program's strength; movement is STR-based."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ice_panel.add_child(hint)

	# Assigned program .tres picker. The program fully defines the ICE's
	# name / strength / effect_type / damage (driving in-game behavior);
	# integrity is derived 1:1 from the program's strength.
	var prog_lbl = Label.new()
	prog_lbl.text = "Program .tres (required):"
	ice_panel.add_child(prog_lbl)
	ice_program_label = Label.new()
	ice_program_label.text = "(none)"
	ice_program_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ice_panel.add_child(ice_program_label)
	var prog_browse_btn = Button.new()
	prog_browse_btn.text = "Assign program .tres..."
	prog_browse_btn.pressed.connect(_open_ice_program_dialog)
	ice_panel.add_child(prog_browse_btn)
	var prog_clear_btn = Button.new()
	prog_clear_btn.text = "Clear assigned program"
	prog_clear_btn.pressed.connect(_clear_ice_program)
	ice_panel.add_child(prog_clear_btn)

	ice_program_dialog = FileDialog.new()
	ice_program_dialog.access = FileDialog.ACCESS_RESOURCES
	ice_program_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	ice_program_dialog.filters = PackedStringArray(["*.tres ; Program resource"])
	ice_program_dialog.file_selected.connect(_on_ice_program_picked)
	add_child(ice_program_dialog)


func _open_ice_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.BLACK_ICE:
		return
	selected_ice_coord = coord
	_refresh_ice_program_label(tile)
	ice_panel_bg.visible = true


func _refresh_ice_program_label(tile: CP2020TileData) -> void:
	if tile.ice_program != null:
		var prog: NetProgram = tile.ice_program
		var label := "%s (STR %d, %s" % [prog.program_name, prog.strength, _ice_effect_label(prog.effect_type)]
		if prog.damage_dice > 0:
			var dice_str = "%dD%d" % [prog.damage_dice_count, prog.damage_dice] if prog.damage_dice_count > 1 else "1D%d" % prog.damage_dice
			label += ", %s dmg" % dice_str
		label += ")"
		ice_program_label.text = label
	else:
		ice_program_label.text = "(NONE — WARNING: no program assigned! This ICE will be skipped at spawn.)"


func _ice_effect_label(effect_type: int) -> String:
	match effect_type:
		NetProgram.EffectType.DAMAGE_RUNNER:
			return "DAMAGE_RUNNER (anti-personnel)"
		NetProgram.EffectType.DEREZ_ICE:
			return "DEREZ_ICE (anti-program)"
		_:
			return "Effect %d" % effect_type


func _open_ice_program_dialog() -> void:
	if ice_program_dialog:
		ice_program_dialog.popup_centered(Vector2i(600, 400))


func _on_ice_program_picked(path: String) -> void:
	if not current_layout or selected_ice_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_ice_coord)
	if tile == null:
		return
	var prog = ResourceLoader.load(path)
	if prog is NetProgram:
		tile.ice_program = prog
		_refresh_ice_program_label(tile)
		queue_redraw()


func _clear_ice_program() -> void:
	if not current_layout or selected_ice_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_ice_coord)
	if tile == null:
		return
	tile.ice_program = null
	_refresh_ice_program_label(tile)
	queue_redraw()


func _hide_ice_panel() -> void:
	if ice_panel_bg:
		ice_panel_bg.visible = false
	selected_ice_coord = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# NPC editor side panel (NETWATCH / NETRUNNER tiles)
# ---------------------------------------------------------------------------

func build_npc_panel() -> void:
	var panel_bg = PanelContainer.new()
	panel_bg.name = "NpcEditorPanel"
	panel_bg.anchor_left = 1.0
	panel_bg.anchor_right = 1.0
	panel_bg.anchor_top = 0.0
	panel_bg.anchor_bottom = 1.0
	panel_bg.offset_left = -300
	panel_bg.offset_right = -10
	panel_bg.offset_top = 90
	panel_bg.offset_bottom = -10
	panel_bg.visible = false
	add_child(panel_bg)
	npc_panel_bg = panel_bg

	npc_panel = VBoxContainer.new()
	npc_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_bg.add_child(npc_panel)

	var title = Label.new()
	title.text = "NPC Editor"
	npc_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Leave fields at 0/empty to use the hub security-tier template. Set any field to override the template for this tile."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_panel.add_child(hint)

	var name_lbl = Label.new()
	name_lbl.text = "Name:"
	npc_panel.add_child(name_lbl)
	npc_name_edit = LineEdit.new()
	npc_name_edit.placeholder_text = "e.g. NetWatch Officer (blank = template)"
	npc_name_edit.text_changed.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_name_edit)

	var str_lbl = Label.new()
	str_lbl.text = "Strength:"
	npc_panel.add_child(str_lbl)
	npc_str_spinbox = SpinBox.new()
	npc_str_spinbox.min_value = 0
	npc_str_spinbox.max_value = 20
	npc_str_spinbox.value_changed.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_str_spinbox)

	var ap_lbl = Label.new()
	ap_lbl.text = "Max AP:"
	npc_panel.add_child(ap_lbl)
	npc_ap_spinbox = SpinBox.new()
	npc_ap_spinbox.min_value = 0
	npc_ap_spinbox.max_value = 20
	npc_ap_spinbox.value_changed.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_ap_spinbox)

	var int_lbl = Label.new()
	int_lbl.text = "Max integrity:"
	npc_panel.add_child(int_lbl)
	npc_int_spinbox = SpinBox.new()
	npc_int_spinbox.min_value = 0
	npc_int_spinbox.max_value = 20
	npc_int_spinbox.value_changed.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_int_spinbox)

	var hp_lbl = Label.new()
	hp_lbl.text = "Max health:"
	npc_panel.add_child(hp_lbl)
	npc_health_spinbox = SpinBox.new()
	npc_health_spinbox.min_value = 0
	npc_health_spinbox.max_value = 40
	npc_health_spinbox.value_changed.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_health_spinbox)

	var mu_lbl = Label.new()
	mu_lbl.text = "Max MU:"
	npc_panel.add_child(mu_lbl)
	npc_mu_spinbox = SpinBox.new()
	npc_mu_spinbox.min_value = 0
	npc_mu_spinbox.max_value = 40
	npc_mu_spinbox.value_changed.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_mu_spinbox)

	var deck_lbl = Label.new()
	deck_lbl.text = "Cyberdeck name:"
	npc_panel.add_child(deck_lbl)
	npc_deck_edit = LineEdit.new()
	npc_deck_edit.placeholder_text = "e.g. Cyberdyne (blank = template)"
	npc_deck_edit.text_changed.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_deck_edit)

	var disp_lbl = Label.new()
	disp_lbl.text = "Disposition:"
	npc_panel.add_child(disp_lbl)
	npc_disposition_option = OptionButton.new()
	npc_disposition_option.add_item("Hostile", 0)
	npc_disposition_option.add_item("Neutral", 1)
	npc_disposition_option.item_selected.connect(_on_npc_field_changed)
	npc_panel.add_child(npc_disposition_option)

	var clear_btn = Button.new()
	clear_btn.text = "Reset to template (clear override)"
	clear_btn.pressed.connect(_clear_npc_override)
	npc_panel.add_child(clear_btn)


func _open_npc_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or (tile.tile_type != CP2020DatafortLayout.TileType.NETWATCH and tile.tile_type != CP2020DatafortLayout.TileType.NETRUNNER):
		return
	selected_npc_coord = coord
	npc_name_edit.set_block_signals(true)
	npc_str_spinbox.set_block_signals(true)
	npc_ap_spinbox.set_block_signals(true)
	npc_int_spinbox.set_block_signals(true)
	npc_health_spinbox.set_block_signals(true)
	npc_mu_spinbox.set_block_signals(true)
	npc_deck_edit.set_block_signals(true)
	npc_disposition_option.set_block_signals(true)
	npc_name_edit.text = tile.npc_name
	npc_str_spinbox.value = tile.npc_strength
	npc_ap_spinbox.value = tile.npc_max_ap
	npc_int_spinbox.value = tile.npc_max_integrity
	npc_health_spinbox.value = tile.npc_max_health
	npc_mu_spinbox.value = tile.npc_max_mu
	npc_deck_edit.text = tile.npc_deck_name
	npc_disposition_option.select(0 if tile.npc_disposition <= 0 else 1)
	npc_name_edit.set_block_signals(false)
	npc_str_spinbox.set_block_signals(false)
	npc_ap_spinbox.set_block_signals(false)
	npc_int_spinbox.set_block_signals(false)
	npc_health_spinbox.set_block_signals(false)
	npc_mu_spinbox.set_block_signals(false)
	npc_deck_edit.set_block_signals(false)
	npc_disposition_option.set_block_signals(false)
	npc_panel_bg.visible = true


func _hide_npc_panel() -> void:
	if npc_panel_bg:
		npc_panel_bg.visible = false
	selected_npc_coord = Vector2i(-1, -1)


func _write_npc_field() -> void:
	if not current_layout or selected_npc_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_npc_coord)
	if tile == null:
		return
	tile.npc_name = npc_name_edit.text.strip_edges()
	tile.npc_strength = int(npc_str_spinbox.value)
	tile.npc_max_ap = int(npc_ap_spinbox.value)
	tile.npc_max_integrity = int(npc_int_spinbox.value)
	tile.npc_max_health = int(npc_health_spinbox.value)
	tile.npc_max_mu = int(npc_mu_spinbox.value)
	tile.npc_deck_name = npc_deck_edit.text.strip_edges()
	tile.npc_disposition = npc_disposition_option.selected
	tile.npc_has_override = tile.npc_name != "" or tile.npc_strength > 0 or tile.npc_max_ap > 0 or tile.npc_max_integrity > 0 or tile.npc_max_health > 0 or tile.npc_max_mu > 0 or tile.npc_deck_name != ""
	queue_redraw()


func _on_npc_field_changed(_value: Variant = null) -> void:
	_write_npc_field()


func _clear_npc_override() -> void:
	npc_name_edit.text = ""
	npc_str_spinbox.value = 0
	npc_ap_spinbox.value = 0
	npc_int_spinbox.value = 0
	npc_health_spinbox.value = 0
	npc_mu_spinbox.value = 0
	npc_deck_edit.text = ""
	npc_disposition_option.select(0)
	_write_npc_field()


# ---------------------------------------------------------------------------
# CPU editor side panel (CONTROL_NODE tiles)
# ---------------------------------------------------------------------------

func build_cpu_panel() -> void:
	var panel_bg = PanelContainer.new()
	panel_bg.name = "CpuEditorPanel"
	panel_bg.anchor_left = 1.0
	panel_bg.anchor_right = 1.0
	panel_bg.anchor_top = 0.0
	panel_bg.anchor_bottom = 1.0
	panel_bg.offset_left = -300
	panel_bg.offset_right = -10
	panel_bg.offset_top = 90
	panel_bg.offset_bottom = -10
	panel_bg.visible = false
	add_child(panel_bg)
	cpu_panel_bg = panel_bg

	cpu_panel = VBoxContainer.new()
	cpu_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpu_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_bg.add_child(cpu_panel)

	var title = Label.new()
	title.text = "CPU Editor"
	cpu_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Per CP2020 PnP rules, each CPU contributes a flat 3 INT, 1 action/turn, and 10 MU of storage capacity. A Krash anti-system program crashes a CPU for 1D6+1 turns."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cpu_panel.add_child(hint)

	var stats = Label.new()
	stats.text = "Stats per CPU: INT 3 | Actions 1 | MU 10"
	cpu_panel.add_child(stats)


func _open_cpu_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.CONTROL_NODE:
		return
	selected_cpu_coord = coord
	cpu_panel_bg.visible = true


func _hide_cpu_panel() -> void:
	if cpu_panel_bg:
		cpu_panel_bg.visible = false
	selected_cpu_coord = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Loot editor side panel (CONTROL_NODE tiles)
# ---------------------------------------------------------------------------

func build_loot_panel() -> void:
	var panel_bg = PanelContainer.new()
	panel_bg.name = "LootEditorPanel"
	panel_bg.anchor_left = 1.0
	panel_bg.anchor_right = 1.0
	panel_bg.anchor_top = 0.0
	panel_bg.anchor_bottom = 1.0
	panel_bg.offset_left = -300
	panel_bg.offset_right = -10
	panel_bg.offset_top = 90
	panel_bg.offset_bottom = -10
	panel_bg.visible = false
	add_child(panel_bg)
	loot_panel_bg = panel_bg

	loot_panel = VBoxContainer.new()
	loot_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_bg.add_child(loot_panel)

	var title = Label.new()
	title.text = "Loot Editor"
	loot_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Programs and credits a netrunner receives when looting this tile. Loot is granted once per run (the is_looted flag is reset on load)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loot_panel.add_child(hint)

	# CPU info label — only visible when the selected tile is a CONTROL_NODE,
	# so the designer still sees the fixed CPU stats when the loot panel
	# replaces the standalone CPU editor for that tile type.
	loot_cpu_info_label = Label.new()
	loot_cpu_info_label.text = "CPU stats: INT 3 | Actions 1 | MU 10\nEach CPU contributes a flat 3 INT, 1 action/turn, 10 MU storage."
	loot_cpu_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loot_cpu_info_label.visible = false
	loot_panel.add_child(loot_cpu_info_label)

	var credits_lbl = Label.new()
	credits_lbl.text = "Loot credits:"
	loot_panel.add_child(credits_lbl)
	loot_credits_spinbox = SpinBox.new()
	loot_credits_spinbox.min_value = 0
	loot_credits_spinbox.max_value = 100000
	loot_credits_spinbox.suffix = " eb"
	loot_credits_spinbox.value_changed.connect(_on_loot_credits_changed)
	loot_panel.add_child(loot_credits_spinbox)

	var prog_lbl = Label.new()
	prog_lbl.text = "Loot programs:"
	loot_panel.add_child(prog_lbl)

	loot_programs_list = ItemList.new()
	loot_programs_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loot_programs_list.custom_minimum_size = Vector2(0, 120)
	loot_panel.add_child(loot_programs_list)

	var add_btn = Button.new()
	add_btn.text = "Add program (.tres)..."
	add_btn.pressed.connect(_open_loot_add_dialog)
	loot_panel.add_child(add_btn)

	var remove_btn = Button.new()
	remove_btn.text = "Remove selected"
	remove_btn.pressed.connect(_remove_selected_loot_program)
	loot_panel.add_child(remove_btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear loot list"
	clear_btn.pressed.connect(_clear_loot_list)
	loot_panel.add_child(clear_btn)

	# Dedicated file dialog for picking loot program .tres files. Kept separate
	# from the layout-level programs_add_dialog so the two editors don't fight
	# over a shared dialog state.
	loot_add_dialog = FileDialog.new()
	loot_add_dialog.name = "LootAddDialog"
	loot_add_dialog.access = FileDialog.ACCESS_RESOURCES
	loot_add_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	loot_add_dialog.filters = PackedStringArray(["*.tres ; Program resource"])
	loot_add_dialog.file_selected.connect(_on_loot_program_added)
	add_child(loot_add_dialog)


func _open_loot_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null:
		return
	if tile.tile_type != CP2020DatafortLayout.TileType.CONTROL_NODE:
		return
	selected_loot_coord = coord
	# Only one side panel shows at a time.
	_hide_files_panel()
	loot_cpu_info_label.visible = true
	loot_credits_spinbox.set_block_signals(true)
	loot_credits_spinbox.value = tile.loot_credits
	loot_credits_spinbox.set_block_signals(false)
	_refresh_loot_programs_list()
	loot_panel_bg.visible = true


func _hide_loot_panel() -> void:
	if loot_panel_bg:
		loot_panel_bg.visible = false
	selected_loot_coord = Vector2i(-1, -1)


func _on_loot_credits_changed(_value: float) -> void:
	_write_loot_credits()


func _write_loot_credits() -> void:
	if not current_layout or selected_loot_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_loot_coord)
	if tile == null:
		return
	tile.loot_credits = int(loot_credits_spinbox.value)
	queue_redraw()


func _refresh_loot_programs_list() -> void:
	if not loot_programs_list or not current_layout or selected_loot_coord == Vector2i(-1, -1):
		return
	loot_programs_list.clear()
	var tile = current_layout.get_tile(selected_loot_coord)
	if tile == null:
		return
	for p in tile.loot_programs:
		if p is NetProgram:
			loot_programs_list.add_item("%s (STR %d, %d MU)" % [p.program_name, p.strength, p.memory_cost])
		else:
			loot_programs_list.add_item("(invalid program)")


func _open_loot_add_dialog() -> void:
	if loot_add_dialog:
		loot_add_dialog.popup_centered(Vector2i(600, 400))


func _on_loot_program_added(path: String) -> void:
	if not current_layout or selected_loot_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_loot_coord)
	if tile == null:
		return
	if ResourceLoader.exists(path):
		var prog = ResourceLoader.load(path) as NetProgram
		if prog:
			tile.loot_programs.append(prog)
			_refresh_loot_programs_list()
			queue_redraw()
		else:
			print("Selected file is not a NetProgram resource: ", path)


func _remove_selected_loot_program() -> void:
	if not current_layout or not loot_programs_list or selected_loot_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_loot_coord)
	if tile == null:
		return
	var idxs = loot_programs_list.get_selected_items()
	if idxs.is_empty():
		return
	idxs.reverse()
	for i in idxs:
		if i >= 0 and i < tile.loot_programs.size():
			tile.loot_programs.remove_at(i)
	_refresh_loot_programs_list()
	queue_redraw()


func _clear_loot_list() -> void:
	if not current_layout or selected_loot_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_loot_coord)
	if tile == null:
		return
	tile.loot_programs.clear()
	_refresh_loot_programs_list()
	queue_redraw()


# ---------------------------------------------------------------------------
# Files editor side panel (MEMORY_UNIT tiles)
# ---------------------------------------------------------------------------

func build_files_panel() -> void:
	var panel_bg = PanelContainer.new()
	panel_bg.name = "FilesEditorPanel"
	panel_bg.anchor_left = 1.0
	panel_bg.anchor_right = 1.0
	panel_bg.anchor_top = 0.0
	panel_bg.anchor_bottom = 1.0
	panel_bg.offset_left = -300
	panel_bg.offset_right = -10
	panel_bg.offset_top = 90
	panel_bg.offset_bottom = -10
	panel_bg.visible = false
	add_child(panel_bg)
	files_panel_bg = panel_bg

	files_panel = VBoxContainer.new()
	files_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_bg.add_child(files_panel)

	var title = Label.new()
	title.text = "Files Editor"
	files_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Files are discrete data files a netrunner copies to deck memory (consuming MU alongside programs) during a dive, then fences at the hub for their credit value (eb). The credit value is hidden from the player in the datafort menu and only revealed at the hub shop."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	files_panel.add_child(hint)

	var name_lbl = Label.new()
	name_lbl.text = "File name:"
	files_panel.add_child(name_lbl)
	file_name_edit = LineEdit.new()
	file_name_edit.placeholder_text = "e.g. Corporate Payroll Logs"
	files_panel.add_child(file_name_edit)

	var desc_lbl = Label.new()
	desc_lbl.text = "Description:"
	files_panel.add_child(desc_lbl)
	file_desc_edit = TextEdit.new()
	file_desc_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_desc_edit.custom_minimum_size = Vector2(0, 60)
	file_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	files_panel.add_child(file_desc_edit)

	var value_lbl = Label.new()
	value_lbl.text = "Credit value (fence price):"
	files_panel.add_child(value_lbl)
	file_value_spinbox = SpinBox.new()
	file_value_spinbox.min_value = 0
	file_value_spinbox.max_value = 100000
	file_value_spinbox.suffix = " eb"
	files_panel.add_child(file_value_spinbox)

	var mu_lbl = Label.new()
	mu_lbl.text = "MU size:"
	files_panel.add_child(mu_lbl)
	file_mu_spinbox = SpinBox.new()
	file_mu_spinbox.min_value = 1
	file_mu_spinbox.max_value = 100
	file_mu_spinbox.suffix = " MU"
	file_mu_spinbox.value = 1
	files_panel.add_child(file_mu_spinbox)

	files_list = ItemList.new()
	files_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	files_list.custom_minimum_size = Vector2(0, 120)
	files_panel.add_child(files_list)

	var add_btn = Button.new()
	add_btn.text = "Add file"
	add_btn.pressed.connect(_add_file)
	files_panel.add_child(add_btn)

	var update_btn = Button.new()
	update_btn.text = "Update selected"
	update_btn.pressed.connect(_update_selected_file)
	files_panel.add_child(update_btn)

	var remove_btn = Button.new()
	remove_btn.text = "Remove selected"
	remove_btn.pressed.connect(_remove_selected_file)
	files_panel.add_child(remove_btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear files"
	clear_btn.pressed.connect(_clear_files)
	files_panel.add_child(clear_btn)


func _open_files_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.MEMORY_UNIT:
		return
	# Only one side panel shows at a time.
	_hide_loot_panel()
	_hide_cpu_panel()
	selected_files_coord = coord
	_refresh_files_list()
	files_panel_bg.visible = true


func _hide_files_panel() -> void:
	if files_panel_bg:
		files_panel_bg.visible = false
	selected_files_coord = Vector2i(-1, -1)


func _refresh_files_list() -> void:
	if not files_list or not current_layout or selected_files_coord == Vector2i(-1, -1):
		return
	files_list.clear()
	var tile = current_layout.get_tile(selected_files_coord)
	if tile == null:
		return
	var i := 0
	for f in tile.files:
		if f is NetFile:
			files_list.add_item("%s — %d eb, %d MU" % [f.file_name, f.credit_value, f.mu_size])
		else:
			files_list.add_item("(invalid file)")
		files_list.set_item_metadata(i, i)
		i += 1


func _read_file_fields_from_inputs() -> NetFile:
	# Helper used by add/update so both buttons read the same input fields.
	var f := NetFile.new()
	f.file_name = file_name_edit.text.strip_edges()
	if f.file_name == "":
		f.file_name = "Untitled File"
	f.description = file_desc_edit.text
	f.credit_value = int(file_value_spinbox.value)
	f.mu_size = int(file_mu_spinbox.value)
	return f


func _add_file() -> void:
	if not current_layout or selected_files_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_files_coord)
	if tile == null:
		return
	var f := _read_file_fields_from_inputs()
	tile.files.append(f)
	_refresh_files_list()
	queue_redraw()


func _update_selected_file() -> void:
	if not current_layout or not files_list or selected_files_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_files_coord)
	if tile == null:
		return
	var idxs: PackedInt32Array = files_list.get_selected_items()
	if idxs.is_empty():
		return
	var i: int = idxs[0]
	if i < 0 or i >= tile.files.size():
		return
	var existing = tile.files[i] as NetFile
	if existing == null:
		return
	existing.file_name = file_name_edit.text.strip_edges()
	if existing.file_name == "":
		existing.file_name = "Untitled File"
	existing.description = file_desc_edit.text
	existing.credit_value = int(file_value_spinbox.value)
	existing.mu_size = int(file_mu_spinbox.value)
	_refresh_files_list()
	queue_redraw()


func _remove_selected_file() -> void:
	if not current_layout or not files_list or selected_files_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_files_coord)
	if tile == null:
		return
	var idxs: PackedInt32Array = files_list.get_selected_items()
	if idxs.is_empty():
		return
	# Remove highest index first to keep indices valid.
	idxs.reverse()
	for i: int in idxs:
		if i >= 0 and i < tile.files.size():
			tile.files.remove_at(i)
	_refresh_files_list()
	queue_redraw()


func _clear_files() -> void:
	if not current_layout or selected_files_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_files_coord)
	if tile == null:
		return
	tile.files.clear()
	_refresh_files_list()
	queue_redraw()


# ---------------------------------------------------------------------------
# Layout-level resident programs editor (programs the datafort CPUs run)
# ---------------------------------------------------------------------------

func build_programs_panel() -> void:
	var panel_bg = PanelContainer.new()
	panel_bg.name = "ProgramsEditorPanel"
	panel_bg.anchor_left = 1.0
	panel_bg.anchor_right = 1.0
	panel_bg.anchor_top = 1.0
	panel_bg.anchor_bottom = 1.0
	panel_bg.offset_left = -300
	panel_bg.offset_right = -10
	panel_bg.offset_top = -260
	panel_bg.offset_bottom = -10
	panel_bg.visible = false
	add_child(panel_bg)
	programs_panel_bg = panel_bg

	programs_panel = VBoxContainer.new()
	programs_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	programs_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_bg.add_child(programs_panel)

	var title = Label.new()
	title.text = "Datafort Resident Programs"
	programs_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Programs the datafort's CPUs run against intruding netrunners each turn. Add anti-personnel programs for the CPU adversary to attack the runner."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	programs_panel.add_child(hint)

	programs_list = ItemList.new()
	programs_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	programs_list.custom_minimum_size = Vector2(0, 120)
	programs_panel.add_child(programs_list)

	programs_mu_label = Label.new()
	programs_mu_label.text = "MU: 0/0"
	programs_panel.add_child(programs_mu_label)

	var add_btn = Button.new()
	add_btn.text = "Add program (.tres)..."
	add_btn.pressed.connect(_open_programs_add_dialog)
	programs_panel.add_child(add_btn)

	var remove_btn = Button.new()
	remove_btn.text = "Remove selected"
	remove_btn.pressed.connect(_remove_selected_program)
	programs_panel.add_child(remove_btn)

	var toggle_btn = Button.new()
	toggle_btn.text = "Show / Hide programs editor"
	toggle_btn.pressed.connect(_toggle_programs_panel)
	# Anchor a small toggle button to the bottom-right so the editor is on demand.
	toggle_btn.anchor_left = 1.0
	toggle_btn.anchor_right = 1.0
	toggle_btn.anchor_top = 1.0
	toggle_btn.anchor_bottom = 1.0
	toggle_btn.offset_left = -200
	toggle_btn.offset_right = -10
	toggle_btn.offset_top = -32
	toggle_btn.offset_bottom = -10
	add_child(toggle_btn)

	# File dialog for picking program .tres files.
	programs_add_dialog = FileDialog.new()
	programs_add_dialog.access = FileDialog.ACCESS_RESOURCES
	programs_add_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	programs_add_dialog.filters = PackedStringArray(["*.tres ; Program resource"])
	programs_add_dialog.file_selected.connect(_on_program_added)
	add_child(programs_add_dialog)


func _toggle_programs_panel() -> void:
	if programs_panel_bg:
		programs_panel_bg.visible = not programs_panel_bg.visible
		if programs_panel_bg.visible:
			_refresh_programs_list()


func _refresh_programs_list() -> void:
	if not programs_list or not current_layout:
		return
	programs_list.clear()
	var used := 0
	for p in current_layout.resident_programs:
		if p is NetProgram:
			programs_list.add_item("%s (STR %d, %d MU)" % [p.program_name, p.strength, p.memory_cost])
			used += p.memory_cost
	var cpu_count := _count_cpus()
	var total_mu := cpu_count * 10
	programs_mu_label.text = "MU: %d/%d" % [used, total_mu]
	if used > total_mu:
		programs_mu_label.text += " (OVERFLOW!)"
		programs_mu_label.add_theme_color_override("font_color", Color.RED)
	else:
		programs_mu_label.add_theme_color_override("font_color", Color.WHITE)


func _count_cpus() -> int:
	if not current_layout:
		return 0
	var count := 0
	for raw_key in current_layout.grid_tiles.keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
		var tile = current_layout.get_tile(coord)
		if tile and tile.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE:
			count += 1
	return count


func _open_programs_add_dialog() -> void:
	if programs_add_dialog:
		programs_add_dialog.popup_centered(Vector2i(600, 400))


func _on_program_added(path: String) -> void:
	if not current_layout:
		return
	if ResourceLoader.exists(path):
		var prog = ResourceLoader.load(path) as NetProgram
		if prog:
			var cpu_count := _count_cpus()
			var total_mu := cpu_count * 10
			var used_mu := 0
			for p in current_layout.resident_programs:
				if p is NetProgram:
					used_mu += p.memory_cost
			if used_mu + prog.memory_cost > total_mu:
				programs_mu_label.text = "MU FULL: %d/%d — cannot add %s (%d MU)" % [used_mu, total_mu, prog.program_name, prog.memory_cost]
				programs_mu_label.add_theme_color_override("font_color", Color.RED)
				return
			current_layout.resident_programs.append(prog)
			_refresh_programs_list()
			queue_redraw()


func _remove_selected_program() -> void:
	if not current_layout or not programs_list:
		return
	var idxs = programs_list.get_selected_items()
	if idxs.is_empty():
		return
	# Remove highest index first to keep indices valid.
	idxs.reverse()
	for i in idxs:
		if i >= 0 and i < current_layout.resident_programs.size():
			current_layout.resident_programs.remove_at(i)
	_refresh_programs_list()
	queue_redraw()
