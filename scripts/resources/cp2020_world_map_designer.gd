@tool
extends Control

# World map designer. Authors a serializable CP2020WorldMapLayout .tres that
# the runtime (cp_2020_world_net_map.gd) loads. Regions are categorising only
# (colour + HUD label); ocean is simply the absence of a region assignment and
# remains traversable.

const CELL: int = 40
const GRID_OFFSET_Y: int = 90

enum Tool { REGION, HUB, ERASER }

var current_tool: Tool = Tool.REGION
var active_region_index: int = 0
var selected_hub: CP2020WorldHub = null
var current_layout: CP2020WorldMapLayout = null

@onready var columns_spinbox: SpinBox = $TopPanel/SettingsRow/ColumnsSpinBox
@onready var rows_spinbox: SpinBox = $TopPanel/SettingsRow/RowsSpinBox
@onready var apply_size_button: Button = $TopPanel/SettingsRow/ApplySizeButton
@onready var region_option: OptionButton = $TopPanel/ToolRow/RegionOption
@onready var add_region_button: Button = $TopPanel/ToolRow/AddRegionButton
@onready var region_paint_button: Button = $TopPanel/ToolRow/RegionPaintButton
@onready var hub_button: Button = $TopPanel/ToolRow/HubButton
@onready var eraser_button: Button = $TopPanel/ToolRow/EraserButton
@onready var save_button: Button = $TopPanel/ToolRow/SaveButton
@onready var load_button: Button = $TopPanel/ToolRow/LoadButton

@onready var side_panel: VBoxContainer = $SidePanel
@onready var hub_name_edit: LineEdit = $SidePanel/HubNameEdit
@onready var subnet_path_edit: LineEdit = $SidePanel/SubnetPathEdit
@onready var browse_button: Button = $SidePanel/BrowseButton
@onready var ldl_cost_spinbox: SpinBox = $SidePanel/LdlCostSpinBox
@onready var security_code_spinbox: SpinBox = $SidePanel/SecurityCodeSpinBox
@onready var trace_value_spinbox: SpinBox = $SidePanel/TraceValueSpinBox
@onready var set_spawn_button: Button = $SidePanel/SetSpawnButton
@onready var delete_hub_button: Button = $SidePanel/DeleteHubButton

@onready var save_dialog: FileDialog = get_node_or_null("SaveDialog")
@onready var load_dialog: FileDialog = get_node_or_null("LoadDialog")
@onready var browse_dialog: FileDialog = get_node_or_null("BrowseDialog")


func _ready() -> void:
	if current_layout == null:
		current_layout = CP2020WorldMapLayout.new()
		current_layout.grid_cols = 32
		current_layout.grid_rows = 18
		_add_default_regions()
	_setup_file_dialogs_if_missing()
	_setup_signals()
	_refresh_region_option()
	_refresh_side_panel()
	queue_redraw()


func _add_default_regions() -> void:
	if current_layout.regions.size() > 0:
		return
	var defaults := [
		["NORTH AMERICA", Color(0.10, 0.30, 0.18, 1.0)],
		["SOUTH AMERICA", Color(0.10, 0.34, 0.26, 1.0)],
		["EUROPE", Color(0.14, 0.28, 0.30, 1.0)],
		["AFRICA", Color(0.32, 0.28, 0.12, 1.0)],
		["FAR EAST", Color(0.12, 0.30, 0.22, 1.0)],
		["OCEANIA", Color(0.12, 0.32, 0.30, 1.0)],
	]
	for entry in defaults:
		var region := CP2020WorldRegion.new()
		region.name = entry[0]
		region.color = entry[1]
		current_layout.regions.append(region)


func _setup_file_dialogs_if_missing() -> void:
	if not save_dialog:
		save_dialog = FileDialog.new()
		save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		save_dialog.access = FileDialog.ACCESS_RESOURCES
		save_dialog.add_filter("*.tres", "World Map Layout")
		add_child(save_dialog)
	if not load_dialog:
		load_dialog = FileDialog.new()
		load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		load_dialog.access = FileDialog.ACCESS_RESOURCES
		load_dialog.add_filter("*.tres", "World Map Layout")
		add_child(load_dialog)
	if not browse_dialog:
		browse_dialog = FileDialog.new()
		browse_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		browse_dialog.access = FileDialog.ACCESS_RESOURCES
		browse_dialog.add_filter("*.tres", "Subnet Resource")
		add_child(browse_dialog)


func _setup_signals() -> void:
	if apply_size_button and not apply_size_button.pressed.is_connected(_on_resize_pressed):
		apply_size_button.pressed.connect(_on_resize_pressed)
	if add_region_button and not add_region_button.pressed.is_connected(_on_add_region):
		add_region_button.pressed.connect(_on_add_region)
	if region_paint_button and not region_paint_button.pressed.is_connected(_on_tool_region):
		region_paint_button.pressed.connect(_on_tool_region)
	if hub_button and not hub_button.pressed.is_connected(_on_tool_hub):
		hub_button.pressed.connect(_on_tool_hub)
	if eraser_button and not eraser_button.pressed.is_connected(_on_tool_eraser):
		eraser_button.pressed.connect(_on_tool_eraser)
	if save_button and not save_button.pressed.is_connected(_on_save_pressed):
		save_button.pressed.connect(_on_save_pressed)
	if load_button and not load_button.pressed.is_connected(_on_load_pressed):
		load_button.pressed.connect(_on_load_pressed)
	if region_option and not region_option.item_selected.is_connected(_on_region_selected):
		region_option.item_selected.connect(_on_region_selected)
	if browse_button and not browse_button.pressed.is_connected(_on_browse_pressed):
		browse_button.pressed.connect(_on_browse_pressed)
	if hub_name_edit and not hub_name_edit.text_changed.is_connected(_on_hub_name_changed):
		hub_name_edit.text_changed.connect(_on_hub_name_changed)
	if subnet_path_edit and not subnet_path_edit.text_changed.is_connected(_on_subnet_path_changed):
		subnet_path_edit.text_changed.connect(_on_subnet_path_changed)
	if ldl_cost_spinbox and not ldl_cost_spinbox.value_changed.is_connected(_on_ldl_cost_changed):
		ldl_cost_spinbox.value_changed.connect(_on_ldl_cost_changed)
	if security_code_spinbox and not security_code_spinbox.value_changed.is_connected(_on_security_code_changed):
		security_code_spinbox.value_changed.connect(_on_security_code_changed)
	if trace_value_spinbox and not trace_value_spinbox.value_changed.is_connected(_on_trace_value_changed):
		trace_value_spinbox.value_changed.connect(_on_trace_value_changed)
	if set_spawn_button and not set_spawn_button.pressed.is_connected(_on_set_spawn):
		set_spawn_button.pressed.connect(_on_set_spawn)
	if delete_hub_button and not delete_hub_button.pressed.is_connected(_on_delete_hub):
		delete_hub_button.pressed.connect(_on_delete_hub)
	if save_dialog and not save_dialog.file_selected.is_connected(_on_file_saved):
		save_dialog.file_selected.connect(_on_file_saved)
	if load_dialog and not load_dialog.file_selected.is_connected(_on_file_loaded):
		load_dialog.file_selected.connect(_on_file_loaded)
	if browse_dialog and not browse_dialog.file_selected.is_connected(_on_browsed_file):
		browse_dialog.file_selected.connect(_on_browsed_file)


# ---------------------------------------------------------------------------
# Toolbar callbacks
# ---------------------------------------------------------------------------

func _on_resize_pressed() -> void:
	var new_cols := int(columns_spinbox.value) if columns_spinbox else current_layout.grid_cols
	var new_rows := int(rows_spinbox.value) if rows_spinbox else current_layout.grid_rows
	current_layout.grid_cols = new_cols
	current_layout.grid_rows = new_rows
	# Drop out-of-bounds region assignments and hubs.
	var keys_to_drop: Array = []
	for raw_key in current_layout.tile_region.keys():
		var coord := _parse_coord(raw_key)
		if coord.x >= new_cols or coord.y >= new_rows:
			keys_to_drop.append(raw_key)
	for k in keys_to_drop:
		current_layout.tile_region.erase(k)
	var hubs_to_drop: Array = []
	for hub in current_layout.hubs:
		if hub.pos.x >= new_cols or hub.pos.y >= new_rows:
			hubs_to_drop.append(hub)
	for h in hubs_to_drop:
		current_layout.hubs.erase(h)
	if selected_hub and hubs_to_drop.has(selected_hub):
		selected_hub = null
		_refresh_side_panel()
	queue_redraw()


func _on_add_region() -> void:
	var region := CP2020WorldRegion.new()
	region.name = "REGION %d" % (current_layout.regions.size() + 1)
	region.color = Color(randf(), randf(), randf(), 1.0)
	current_layout.regions.append(region)
	active_region_index = current_layout.regions.size() - 1
	_refresh_region_option()
	queue_redraw()


func _on_tool_region() -> void:
	current_tool = Tool.REGION


func _on_tool_hub() -> void:
	current_tool = Tool.HUB


func _on_tool_eraser() -> void:
	current_tool = Tool.ERASER


func _on_region_selected(index: int) -> void:
	active_region_index = index


func _on_save_pressed() -> void:
	if save_dialog:
		save_dialog.popup_centered(Vector2i(600, 400))


func _on_load_pressed() -> void:
	if load_dialog:
		load_dialog.popup_centered(Vector2i(600, 400))


func _on_browse_pressed() -> void:
	if browse_dialog:
		browse_dialog.popup_centered(Vector2i(600, 400))


func _on_file_saved(path: String) -> void:
	var err := ResourceSaver.save(current_layout, path)
	if err == OK:
		print("World map layout saved to: ", path)
	else:
		print("Error saving world map layout: ", err)


func _on_file_loaded(path: String) -> void:
	var loaded := ResourceLoader.load(path)
	if loaded is CP2020WorldMapLayout:
		current_layout = loaded
		selected_hub = null
		if columns_spinbox:
			columns_spinbox.value = current_layout.grid_cols
		if rows_spinbox:
			rows_spinbox.value = current_layout.grid_rows
		_refresh_region_option()
		_refresh_side_panel()
		queue_redraw()
		print("World map layout loaded from: ", path)
	else:
		print("Failed to load world map layout or invalid file type: ", path)


func _on_browsed_file(path: String) -> void:
	if selected_hub:
		selected_hub.subnet_path = path
		if subnet_path_edit:
			subnet_path_edit.text = path
		queue_redraw()


# ---------------------------------------------------------------------------
# Side-panel (hub editor) callbacks
# ---------------------------------------------------------------------------

func _on_hub_name_changed(new_text: String) -> void:
	if selected_hub:
		selected_hub.name = new_text
		queue_redraw()


func _on_subnet_path_changed(new_text: String) -> void:
	if selected_hub:
		selected_hub.subnet_path = new_text
		queue_redraw()


func _on_ldl_cost_changed(value: float) -> void:
	if selected_hub:
		selected_hub.ldl_cost = int(value)


func _on_security_code_changed(value: float) -> void:
	if selected_hub:
		selected_hub.security_code = int(value)


func _on_trace_value_changed(value: float) -> void:
	if selected_hub:
		selected_hub.trace_value = int(value)


func _on_set_spawn() -> void:
	if selected_hub:
		current_layout.runner_spawn_hub = selected_hub.name
		queue_redraw()


func _on_delete_hub() -> void:
	if selected_hub:
		current_layout.hubs.erase(selected_hub)
		selected_hub = null
		_refresh_side_panel()
		queue_redraw()


func _refresh_region_option() -> void:
	if not region_option:
		return
	region_option.clear()
	for region in current_layout.regions:
		region_option.add_item(region.name)
	region_option.select(active_region_index)


func _refresh_side_panel() -> void:
	if not side_panel:
		return
	side_panel.visible = selected_hub != null
	if selected_hub == null:
		return
	# Disconnect temporarily to avoid feedback loops while populating.
	if hub_name_edit and hub_name_edit.text_changed.is_connected(_on_hub_name_changed):
		hub_name_edit.text = selected_hub.name
	if subnet_path_edit and subnet_path_edit.text_changed.is_connected(_on_subnet_path_changed):
		subnet_path_edit.text = selected_hub.subnet_path
	if ldl_cost_spinbox and ldl_cost_spinbox.value_changed.is_connected(_on_ldl_cost_changed):
		ldl_cost_spinbox.value = selected_hub.ldl_cost
	if security_code_spinbox and security_code_spinbox.value_changed.is_connected(_on_security_code_changed):
		security_code_spinbox.value = selected_hub.security_code
	if trace_value_spinbox and trace_value_spinbox.value_changed.is_connected(_on_trace_value_changed):
		trace_value_spinbox.value = selected_hub.trace_value


# ---------------------------------------------------------------------------
# Canvas input / painting
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var grid := _screen_to_grid(event.position)
		if grid.x >= 0 and grid.x < current_layout.grid_cols and grid.y >= 0 and grid.y < current_layout.grid_rows:
			_apply_tool(grid)


func _apply_tool(coord: Vector2i) -> void:
	match current_tool:
		Tool.REGION:
			if active_region_index >= 0 and active_region_index < current_layout.regions.size():
				current_layout.tile_region[coord] = active_region_index
		Tool.HUB:
			var existing := current_layout.get_hub(coord)
			if existing:
				selected_hub = existing
			else:
				var hub := CP2020WorldHub.new()
				hub.name = "Hub %d" % (current_layout.hubs.size() + 1)
				hub.pos = coord
				current_layout.hubs.append(hub)
				selected_hub = hub
			_refresh_side_panel()
		Tool.ERASER:
			if current_layout.tile_region.has(coord):
				current_layout.tile_region.erase(coord)
			var hub := current_layout.get_hub(coord)
			if hub:
				current_layout.hubs.erase(hub)
				if selected_hub == hub:
					selected_hub = null
					_refresh_side_panel()
	queue_redraw()


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var x := int(screen_pos.x / CELL)
	var y := int((screen_pos.y - GRID_OFFSET_Y) / CELL)
	return Vector2i(clampi(x, 0, current_layout.grid_cols - 1), clampi(y, 0, current_layout.grid_rows - 1))


func _parse_coord(raw_key: Variant) -> Vector2i:
	if raw_key is Vector2i:
		return raw_key
	var parts := String(raw_key).split(",")
	return Vector2i(parts[0].to_int(), parts[1].to_int())


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if current_layout == null:
		return
	var total_w := current_layout.grid_cols * CELL
	var total_h := current_layout.grid_rows * CELL
	var ocean := Color(0.05, 0.12, 0.28, 1.0)
	var grid_line := Color(0.4, 0.4, 0.4, 1.0)

	# Ocean background.
	draw_rect(Rect2(0, GRID_OFFSET_Y, total_w, total_h), ocean, true)

	# Region tiles.
	for raw_key in current_layout.tile_region.keys():
		var coord := _parse_coord(raw_key)
		var idx := int(current_layout.tile_region[raw_key])
		if idx >= 0 and idx < current_layout.regions.size():
			var rect := Rect2(coord.x * CELL, GRID_OFFSET_Y + coord.y * CELL, CELL, CELL)
			draw_rect(rect, current_layout.regions[idx].color, true)

	# Grid lines.
	for x in range(current_layout.grid_cols + 1):
		draw_line(Vector2(x * CELL, GRID_OFFSET_Y), Vector2(x * CELL, GRID_OFFSET_Y + total_h), grid_line, 1.0)
	for y in range(current_layout.grid_rows + 1):
		draw_line(Vector2(0, GRID_OFFSET_Y + y * CELL), Vector2(total_w, GRID_OFFSET_Y + y * CELL), grid_line, 1.0)

	# Hubs.
	var font := _theme_font()
	for hub in current_layout.hubs:
		var rect := Rect2(hub.pos.x * CELL, GRID_OFFSET_Y + hub.pos.y * CELL, CELL, CELL)
		var outline := Color(0.0, 1.0, 0.9, 1.0)
		if hub == selected_hub:
			outline = Color(1.0, 1.0, 0.0, 1.0)
		draw_rect(rect, outline, false, 2.0)
		var label_pos := Vector2(hub.pos.x * CELL + 4, GRID_OFFSET_Y + hub.pos.y * CELL + CELL + 2)
		draw_string(font, label_pos, hub.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, outline)
		# Spawn hub marker.
		if hub.name == current_layout.runner_spawn_hub:
			var center := rect.get_center()
			draw_arc(center, CELL * 0.35, 0, TAU, 24, Color(0.2, 0.9, 1.0, 1.0), 2.0)


func _theme_font() -> Font:
	var label := Label.new()
	var f := label.get_theme_default_font()
	label.free()
	return f