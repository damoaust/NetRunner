@tool
extends Control

# City Grid designer. Authors a serializable CP2020CityGridLayout .tres that
# the runtime (cp2020_city_grid.gd) loads. Tools: DATAFORT (place/select),
# LDL_ENTRY (set the runner arrival tile), ERASER (remove a datafort). The
# side panel edits the selected datafort's name, subnet path, security tier,
# LDL cost, security code and trace value.

const CELL: int = 40
const GRID_OFFSET_Y: int = 90

enum Tool { DATAFORT, LDL_ENTRY, ERASER }

var current_tool: Tool = Tool.DATAFORT
var selected_datafort: CP2020CityGridDatafort = null
var current_layout: CP2020CityGridLayout = null

@onready var city_name_edit: LineEdit = get_node_or_null("TopPanel/SettingsRow/CityNameEdit")
@onready var columns_spinbox: SpinBox = $TopPanel/SettingsRow/ColumnsSpinBox
@onready var rows_spinbox: SpinBox = $TopPanel/SettingsRow/RowsSpinBox
@onready var apply_size_button: Button = $TopPanel/SettingsRow/ApplySizeButton
@onready var datafort_button: Button = $TopPanel/ToolRow/DatafortButton
@onready var ldl_entry_button: Button = $TopPanel/ToolRow/LdlEntryButton
@onready var eraser_button: Button = $TopPanel/ToolRow/EraserButton
@onready var save_button: Button = $TopPanel/ToolRow/SaveButton
@onready var load_button: Button = $TopPanel/ToolRow/LoadButton

@onready var side_panel: VBoxContainer = $SidePanel
@onready var df_name_edit: LineEdit = $SidePanel/DatafortNameEdit
@onready var subnet_path_edit: LineEdit = $SidePanel/SubnetPathEdit
@onready var browse_button: Button = $SidePanel/BrowseButton
@onready var security_tier_option: OptionButton = $SidePanel/SecurityTierOption
@onready var ldl_cost_spinbox: SpinBox = $SidePanel/LdlCostSpinBox
@onready var security_code_spinbox: SpinBox = $SidePanel/SecurityCodeSpinBox
@onready var trace_value_spinbox: SpinBox = $SidePanel/TraceValueSpinBox
@onready var delete_datafort_button: Button = $SidePanel/DeleteDatafortButton

@onready var save_dialog: FileDialog = get_node_or_null("SaveDialog")
@onready var load_dialog: FileDialog = get_node_or_null("LoadDialog")
@onready var browse_dialog: FileDialog = get_node_or_null("BrowseDialog")


func _ready() -> void:
	if current_layout == null:
		current_layout = CP2020CityGridLayout.new()
		current_layout.grid_cols = 20
		current_layout.grid_rows = 12
	_setup_file_dialogs_if_missing()
	_setup_signals()
	_populate_tier_option()
	_refresh_side_panel()
	if city_name_edit and current_layout:
		city_name_edit.text = current_layout.city_name
	queue_redraw()


func _setup_file_dialogs_if_missing() -> void:
	if not save_dialog:
		save_dialog = FileDialog.new()
		save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		save_dialog.access = FileDialog.ACCESS_RESOURCES
		save_dialog.add_filter("*.tres", "City Grid Layout")
		add_child(save_dialog)
	if not load_dialog:
		load_dialog = FileDialog.new()
		load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		load_dialog.access = FileDialog.ACCESS_RESOURCES
		load_dialog.add_filter("*.tres", "City Grid Layout")
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
	if datafort_button and not datafort_button.pressed.is_connected(_on_tool_datafort):
		datafort_button.pressed.connect(_on_tool_datafort)
	if ldl_entry_button and not ldl_entry_button.pressed.is_connected(_on_tool_ldl_entry):
		ldl_entry_button.pressed.connect(_on_tool_ldl_entry)
	if eraser_button and not eraser_button.pressed.is_connected(_on_tool_eraser):
		eraser_button.pressed.connect(_on_tool_eraser)
	if save_button and not save_button.pressed.is_connected(_on_save_pressed):
		save_button.pressed.connect(_on_save_pressed)
	if load_button and not load_button.pressed.is_connected(_on_load_pressed):
		load_button.pressed.connect(_on_load_pressed)
	if city_name_edit and not city_name_edit.text_changed.is_connected(_on_city_name_changed):
		city_name_edit.text_changed.connect(_on_city_name_changed)
	if browse_button and not browse_button.pressed.is_connected(_on_browse_pressed):
		browse_button.pressed.connect(_on_browse_pressed)
	if df_name_edit and not df_name_edit.text_changed.is_connected(_on_df_name_changed):
		df_name_edit.text_changed.connect(_on_df_name_changed)
	if subnet_path_edit and not subnet_path_edit.text_changed.is_connected(_on_subnet_path_changed):
		subnet_path_edit.text_changed.connect(_on_subnet_path_changed)
	if security_tier_option and not security_tier_option.item_selected.is_connected(_on_security_tier_changed):
		security_tier_option.item_selected.connect(_on_security_tier_changed)
	if ldl_cost_spinbox and not ldl_cost_spinbox.value_changed.is_connected(_on_ldl_cost_changed):
		ldl_cost_spinbox.value_changed.connect(_on_ldl_cost_changed)
	if security_code_spinbox and not security_code_spinbox.value_changed.is_connected(_on_security_code_changed):
		security_code_spinbox.value_changed.connect(_on_security_code_changed)
	if trace_value_spinbox and not trace_value_spinbox.value_changed.is_connected(_on_trace_value_changed):
		trace_value_spinbox.value_changed.connect(_on_trace_value_changed)
	if delete_datafort_button and not delete_datafort_button.pressed.is_connected(_on_delete_datafort):
		delete_datafort_button.pressed.connect(_on_delete_datafort)
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
	# Drop out-of-bounds dataforts.
	var to_drop: Array = []
	for df in current_layout.dataforts:
		if df.pos.x >= new_cols or df.pos.y >= new_rows:
			to_drop.append(df)
	for d in to_drop:
		current_layout.dataforts.erase(d)
	if selected_datafort and to_drop.has(selected_datafort):
		selected_datafort = null
		_refresh_side_panel()
	# Clamp LDL entry.
	current_layout.ldl_entry = Vector2i(clampi(current_layout.ldl_entry.x, 0, new_cols - 1), clampi(current_layout.ldl_entry.y, 0, new_rows - 1))
	queue_redraw()


func _on_tool_datafort() -> void:
	current_tool = Tool.DATAFORT


func _on_tool_ldl_entry() -> void:
	current_tool = Tool.LDL_ENTRY


func _on_tool_eraser() -> void:
	current_tool = Tool.ERASER


func _on_city_name_changed(new_text: String) -> void:
	if current_layout:
		current_layout.city_name = new_text
		queue_redraw()


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
		print("City grid layout saved to: ", path)
	else:
		print("Error saving city grid layout: ", err)


func _on_file_loaded(path: String) -> void:
	var loaded := ResourceLoader.load(path)
	if loaded is CP2020CityGridLayout:
		current_layout = loaded
		selected_datafort = null
		if city_name_edit:
			city_name_edit.text = current_layout.city_name
		if columns_spinbox:
			columns_spinbox.value = current_layout.grid_cols
		if rows_spinbox:
			rows_spinbox.value = current_layout.grid_rows
		_refresh_side_panel()
		queue_redraw()
		print("City grid layout loaded from: ", path)
	else:
		print("Failed to load city grid layout or invalid file type: ", path)


func _on_browsed_file(path: String) -> void:
	if selected_datafort:
		selected_datafort.subnet_path = path
		if subnet_path_edit:
			subnet_path_edit.text = path
		queue_redraw()


# ---------------------------------------------------------------------------
# Side-panel (datafort editor) callbacks
# ---------------------------------------------------------------------------

func _on_df_name_changed(new_text: String) -> void:
	if selected_datafort:
		selected_datafort.name = new_text
		queue_redraw()


func _on_subnet_path_changed(new_text: String) -> void:
	if selected_datafort:
		selected_datafort.subnet_path = new_text
		queue_redraw()


func _on_security_tier_changed(index: int) -> void:
	if selected_datafort:
		selected_datafort.security_tier = int(index)
		queue_redraw()


func _on_ldl_cost_changed(value: float) -> void:
	if selected_datafort:
		selected_datafort.ldl_cost = int(value)


func _on_security_code_changed(value: float) -> void:
	if selected_datafort:
		selected_datafort.security_code = int(value)


func _on_trace_value_changed(value: float) -> void:
	if selected_datafort:
		selected_datafort.trace_value = int(value)


func _populate_tier_option() -> void:
	if not security_tier_option:
		return
	security_tier_option.clear()
	for i in range(CP2020SecurityTier.Tier.size()):
		security_tier_option.add_item(String(CP2020SecurityTier.LABELS[i]), i)


func _on_delete_datafort() -> void:
	if selected_datafort:
		current_layout.dataforts.erase(selected_datafort)
		selected_datafort = null
		_refresh_side_panel()
		queue_redraw()


func _refresh_side_panel() -> void:
	if not side_panel:
		return
	side_panel.visible = selected_datafort != null
	if selected_datafort == null:
		return
	if df_name_edit and df_name_edit.text_changed.is_connected(_on_df_name_changed):
		df_name_edit.text = selected_datafort.name
	if subnet_path_edit and subnet_path_edit.text_changed.is_connected(_on_subnet_path_changed):
		subnet_path_edit.text = selected_datafort.subnet_path
	if security_tier_option and security_tier_option.item_selected.is_connected(_on_security_tier_changed):
		var tier := clampi(int(selected_datafort.security_tier), 0, CP2020SecurityTier.Tier.size() - 1)
		security_tier_option.select(tier)
	if ldl_cost_spinbox and ldl_cost_spinbox.value_changed.is_connected(_on_ldl_cost_changed):
		ldl_cost_spinbox.value = selected_datafort.ldl_cost
	if security_code_spinbox and security_code_spinbox.value_changed.is_connected(_on_security_code_changed):
		security_code_spinbox.value = selected_datafort.security_code
	if trace_value_spinbox and trace_value_spinbox.value_changed.is_connected(_on_trace_value_changed):
		trace_value_spinbox.value = selected_datafort.trace_value


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
		Tool.DATAFORT:
			var existing: CP2020CityGridDatafort = current_layout.get_datafort(coord)
			if existing:
				selected_datafort = existing
			else:
				var df := CP2020CityGridDatafort.new()
				df.name = "Datafort %d" % (current_layout.dataforts.size() + 1)
				df.pos = coord
				current_layout.dataforts.append(df)
				selected_datafort = df
			_refresh_side_panel()
		Tool.LDL_ENTRY:
			current_layout.ldl_entry = coord
		Tool.ERASER:
			var df: CP2020CityGridDatafort = current_layout.get_datafort(coord)
			if df:
				current_layout.dataforts.erase(df)
				if selected_datafort == df:
					selected_datafort = null
					_refresh_side_panel()
	queue_redraw()


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var x := int(screen_pos.x / CELL)
	var y := int((screen_pos.y - GRID_OFFSET_Y) / CELL)
	return Vector2i(clampi(x, 0, current_layout.grid_cols - 1), clampi(y, 0, current_layout.grid_rows - 1))


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if current_layout == null:
		return
	var total_w := current_layout.grid_cols * CELL
	var total_h := current_layout.grid_rows * CELL
	var bg := Color(0.04, 0.08, 0.16, 1.0)
	var grid_line := Color(0.4, 0.4, 0.4, 1.0)

	draw_rect(Rect2(0, GRID_OFFSET_Y, total_w, total_h), bg, true)

	# Grid lines.
	for x in range(current_layout.grid_cols + 1):
		draw_line(Vector2(x * CELL, GRID_OFFSET_Y), Vector2(x * CELL, GRID_OFFSET_Y + total_h), grid_line, 1.0)
	for y in range(current_layout.grid_rows + 1):
		draw_line(Vector2(0, GRID_OFFSET_Y + y * CELL), Vector2(total_w, GRID_OFFSET_Y + y * CELL), grid_line, 1.0)

	var font := _theme_font()

	# LDL entry marker.
	var entry := current_layout.ldl_entry
	var ecenter := Vector2(entry.x * CELL + CELL / 2.0, GRID_OFFSET_Y + entry.y * CELL + CELL / 2.0)
	draw_arc(ecenter, CELL * 0.42, 0, TAU, 24, Color(0.2, 0.9, 1.0, 1.0), 2.0)
	draw_string(font, Vector2(ecenter.x - 10, ecenter.y + 4), "LDL", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.2, 0.9, 1.0, 1.0))

	# Datafort chips.
	for df in current_layout.dataforts:
		var tier: int = int(df.security_tier)
		var tier_color: Color = CP2020SecurityTier.COLORS.get(tier, Color(0.0, 1.0, 0.9, 1.0))
		var outline := tier_color
		if df == selected_datafort:
			outline = Color(1.0, 1.0, 0.0, 1.0)
		var rect := Rect2(df.pos.x * CELL, GRID_OFFSET_Y + df.pos.y * CELL, CELL, CELL)
		draw_rect(rect, Color(tier_color.r, tier_color.g, tier_color.b, 0.35), true)
		draw_rect(rect, outline, false, 2.0)
		var glyph := String(CP2020SecurityTier.GLYPHS.get(tier, "?"))
		draw_string(font, Vector2(df.pos.x * CELL + 12, GRID_OFFSET_Y + df.pos.y * CELL + 26), glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, outline)
		var label_pos := Vector2(df.pos.x * CELL + 4, GRID_OFFSET_Y + df.pos.y * CELL + CELL + 2)
		draw_string(font, label_pos, df.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, outline)


func _theme_font() -> Font:
	var label := Label.new()
	var f := label.get_theme_default_font()
	label.free()
	return f