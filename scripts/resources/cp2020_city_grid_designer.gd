@tool
extends Control

# City Grid designer. Authors a serializable CP2020CityGridLayout .tres that
# the runtime (cp2020_city_grid.gd) loads. Tools: DATAFORT (place/select),
# LDL_ENTRY (set the runner arrival tile), ERASER (remove a datafort). The
# side panel edits the selected datafort's name, subnet path, security tier,
# LDL cost, security code and trace value. All grid rendering is delegated
# to the CP2020CityGridRenderer child node (GridRenderer) in the scene tree.

enum Tool { DATAFORT, LDL_ENTRY, ERASER }

# Grid geometry constants (mirror CP2020NeonGridRenderer.CELL and the
# designer renderer's GRID_OFFSET_X; duplicated locally so this designer
# script does not depend on the renderer's class-constant resolution).
const CELL: int = 40
const GRID_OFFSET_X: int = 20

# Cyberpunk/neon palette for the UI panels (grid palette lives on the renderer).
const COLOR_UI_BG: Color = Color(0.03, 0.05, 0.08, 0.92)
const COLOR_UI_BORDER: Color = Color(0.0, 0.85, 1.0, 0.85)
const COLOR_UI_TEXT: Color = Color(0.75, 0.95, 1.0, 1.0)
const COLOR_UI_HOVER: Color = Color(1.0, 1.0, 0.35, 1.0)

var current_tool: Tool = Tool.DATAFORT
var selected_datafort: CP2020CityGridDatafort = null
var current_layout: CP2020CityGridLayout = null

@onready var grid_renderer: CP2020CityGridRenderer = $GridRenderer

@onready var city_name_edit: LineEdit = get_node_or_null("TopPanel/SettingsRow/CityNameEdit")
@onready var columns_spinbox: SpinBox = $TopPanel/SettingsRow/ColumnsSpinBox
@onready var rows_spinbox: SpinBox = $TopPanel/SettingsRow/RowsSpinBox
@onready var apply_size_button: Button = $TopPanel/SettingsRow/ApplySizeButton
@onready var datafort_button: Button = $TopPanel/ToolRow/DatafortButton
@onready var ldl_entry_button: Button = $TopPanel/ToolRow/LdlEntryButton
@onready var eraser_button: Button = $TopPanel/ToolRow/EraserButton
@onready var top_panel: VBoxContainer = $TopPanel
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
	_setup_signals()
	_populate_tier_option()
	_refresh_side_panel()
	if city_name_edit and current_layout:
		city_name_edit.text = current_layout.city_name
	_apply_cyberpunk_ui_theme()
	_sync_renderer()


func _apply_cyberpunk_ui_theme() -> void:
	# Style every relevant Control under TopPanel and SidePanel.
	var controls: Array[Control] = []
	if top_panel:
		for child in top_panel.get_children():
			if child is Control:
				controls.append(child)
				for sub in child.get_children():
					if sub is Control:
						controls.append(sub)
	if side_panel:
		for child in side_panel.get_children():
			if child is Control:
				controls.append(child)

	for ctrl in controls:
		ctrl.add_theme_color_override("font_color", COLOR_UI_TEXT)
		ctrl.add_theme_constant_override("outline_size", 3)
		ctrl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		if ctrl is Button:
			ctrl.add_theme_color_override("font_color", COLOR_UI_TEXT)
			ctrl.add_theme_color_override("font_hover_color", COLOR_UI_HOVER)
			ctrl.add_theme_color_override("font_pressed_color", COLOR_UI_HOVER)
			ctrl.add_theme_color_override("font_focus_color", COLOR_UI_HOVER)
			ctrl.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4, 0.6))
			var btn_style := _make_panel_style(COLOR_UI_BG, COLOR_UI_BORDER)
			var btn_hover := _make_panel_style(Color(COLOR_UI_BG.r + 0.05, COLOR_UI_BG.g + 0.05, COLOR_UI_BG.b + 0.05, 0.95), COLOR_UI_HOVER)
			var btn_pressed := _make_panel_style(Color(COLOR_UI_BG.r * 0.8, COLOR_UI_BG.g * 0.8, COLOR_UI_BG.b * 0.8, 0.95), COLOR_UI_BORDER)
			ctrl.add_theme_stylebox_override("normal", btn_style)
			ctrl.add_theme_stylebox_override("hover", btn_hover)
			ctrl.add_theme_stylebox_override("pressed", btn_pressed)
			ctrl.add_theme_stylebox_override("focus", btn_hover)
			ctrl.add_theme_stylebox_override("disabled", btn_style)
		elif ctrl is LineEdit or ctrl is SpinBox:
			ctrl.add_theme_color_override("font_color", COLOR_UI_TEXT)
			ctrl.add_theme_color_override("font_placeholder_color", Color(0.5, 0.7, 0.75, 0.7))
			var edit_style := _make_panel_style(Color(0.02, 0.04, 0.06, 0.95), COLOR_UI_BORDER)
			ctrl.add_theme_stylebox_override("normal", edit_style)
			ctrl.add_theme_stylebox_override("focus", _make_panel_style(Color(0.02, 0.04, 0.06, 0.95), COLOR_UI_HOVER))
		elif ctrl is OptionButton:
			ctrl.add_theme_color_override("font_color", COLOR_UI_TEXT)
			ctrl.add_theme_color_override("font_hover_color", COLOR_UI_HOVER)
			var opt_style := _make_panel_style(Color(0.02, 0.04, 0.06, 0.95), COLOR_UI_BORDER)
			var opt_hover := _make_panel_style(Color(0.05, 0.08, 0.12, 0.95), COLOR_UI_HOVER)
			ctrl.add_theme_stylebox_override("normal", opt_style)
			ctrl.add_theme_stylebox_override("hover", opt_hover)
			ctrl.add_theme_stylebox_override("pressed", opt_hover)
			ctrl.add_theme_stylebox_override("focus", opt_hover)

	# Panel containers themselves get a dark glass background with a cyan border.
	if top_panel:
		top_panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_UI_BG, COLOR_UI_BORDER))
	if side_panel:
		side_panel.visible = selected_datafort != null
		side_panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_UI_BG, COLOR_UI_BORDER))


func _make_panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	return style


func _sync_renderer() -> void:
	if grid_renderer:
		# Derive the grid's vertical offset from the TopPanel's bottom edge so
		# it tracks the scene layout instead of a hardcoded magic number.
		if top_panel and top_panel.size.y > 0:
			grid_renderer.grid_offset_y = int(top_panel.position.y + top_panel.size.y) + 10
		grid_renderer.current_layout = current_layout
		grid_renderer.selected_datafort = selected_datafort
		grid_renderer.queue_redraw()


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
	_sync_renderer()


func _on_tool_datafort() -> void:
	current_tool = Tool.DATAFORT


func _on_tool_ldl_entry() -> void:
	current_tool = Tool.LDL_ENTRY


func _on_tool_eraser() -> void:
	current_tool = Tool.ERASER


func _on_city_name_changed(new_text: String) -> void:
	if current_layout:
		current_layout.city_name = new_text
		_sync_renderer()


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
		_sync_renderer()
		print("City grid layout loaded from: ", path)
	else:
		print("Failed to load city grid layout or invalid file type: ", path)


func _on_browsed_file(path: String) -> void:
	if selected_datafort:
		selected_datafort.subnet_path = path
		if subnet_path_edit:
			subnet_path_edit.text = path
		_sync_renderer()


# ---------------------------------------------------------------------------
# Side-panel (datafort editor) callbacks
# ---------------------------------------------------------------------------

func _on_df_name_changed(new_text: String) -> void:
	if selected_datafort:
		selected_datafort.name = new_text
		_sync_renderer()


func _on_subnet_path_changed(new_text: String) -> void:
	if selected_datafort:
		selected_datafort.subnet_path = new_text
		_sync_renderer()


func _on_security_tier_changed(index: int) -> void:
	if selected_datafort:
		selected_datafort.security_tier = int(index)
		_sync_renderer()


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
		_sync_renderer()


func _refresh_side_panel() -> void:
	if not side_panel:
		return
	side_panel.visible = selected_datafort != null
	if selected_datafort == null:
		return
	if df_name_edit:
		df_name_edit.set_block_signals(true)
		df_name_edit.text = selected_datafort.name
		df_name_edit.set_block_signals(false)
	if subnet_path_edit:
		subnet_path_edit.set_block_signals(true)
		subnet_path_edit.text = selected_datafort.subnet_path
		subnet_path_edit.set_block_signals(false)
	if security_tier_option:
		security_tier_option.set_block_signals(true)
		var tier := clampi(int(selected_datafort.security_tier), 0, CP2020SecurityTier.Tier.size() - 1)
		security_tier_option.select(tier)
		security_tier_option.set_block_signals(false)
	if ldl_cost_spinbox:
		ldl_cost_spinbox.set_block_signals(true)
		ldl_cost_spinbox.value = selected_datafort.ldl_cost
		ldl_cost_spinbox.set_block_signals(false)
	if security_code_spinbox:
		security_code_spinbox.set_block_signals(true)
		security_code_spinbox.value = selected_datafort.security_code
		security_code_spinbox.set_block_signals(false)
	if trace_value_spinbox:
		trace_value_spinbox.set_block_signals(true)
		trace_value_spinbox.value = selected_datafort.trace_value
		trace_value_spinbox.set_block_signals(false)


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
	_sync_renderer()


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var x := int((screen_pos.x - GRID_OFFSET_X) / CELL)
	var y := int((screen_pos.y - grid_offset_y_for_input()) / CELL)
	return Vector2i(clampi(x, 0, current_layout.grid_cols - 1), clampi(y, 0, current_layout.grid_rows - 1))


# Grid vertical offset used for mouse→grid conversion. Mirrors the renderer's
# scene-derived grid_offset_y so input stays aligned with the drawn grid.
func grid_offset_y_for_input() -> int:
	if grid_renderer:
		return grid_renderer.grid_offset_y
	return 90  # fallback before the designer pushes the scene-derived value
