@tool
extends Control

# City Grid designer. Authors a serializable CP2020CityGridLayout .tres that
# the runtime (cp2020_city_grid.gd) loads. Tools: DATAFORT (place/select),
# LDL_ENTRY (set the runner arrival tile), ERASER (remove a datafort). The
# side panel edits the selected datafort's name, subnet path, security tier,
# LDL cost, security code and trace value.

const CELL: int = 40
const GRID_OFFSET_X: int = 20
const GRID_OFFSET_Y: int = 90
const W: int = 1280
const H: int = 720

enum Tool { DATAFORT, LDL_ENTRY, ERASER }

# Cyberpunk/neon palette (matches the world map designer).
const COLOR_BG: Color = Color(0.02, 0.03, 0.06, 1.0)
const COLOR_GRID: Color = Color(0.0, 0.78, 0.92, 0.22)
const COLOR_GRID_BRIGHT: Color = Color(0.0, 0.9, 1.0, 0.55)
const COLOR_RUNNER: Color = Color(0.0, 1.0, 1.0, 1.0)
const COLOR_SCANLINE: Color = Color(0.0, 0.0, 0.0, 0.12)
const COLOR_TEXT_LABEL: Color = Color(0.7, 0.9, 1.0, 0.9)
const COLOR_TEXT_HEADER: Color = Color(0.85, 0.95, 1.0, 0.95)
const COLOR_UI_BG: Color = Color(0.03, 0.05, 0.08, 0.92)
const COLOR_UI_BORDER: Color = Color(0.0, 0.85, 1.0, 0.85)
const COLOR_UI_TEXT: Color = Color(0.75, 0.95, 1.0, 1.0)
const COLOR_UI_HOVER: Color = Color(1.0, 1.0, 0.35, 1.0)

var current_tool: Tool = Tool.DATAFORT
var selected_datafort: CP2020CityGridDatafort = null
var current_layout: CP2020CityGridLayout = null
var _pulse_time: float = 0.0
var _datafort_font: Font = null

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
	_datafort_font = _create_datafort_font()
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
	_apply_cyberpunk_ui_theme()
	queue_redraw()


func _create_datafort_font() -> Font:
	# Try an emoji font first so the city marker can use the 🏢 office-building emoji.
	var emoji_paths := ["res://data/seguiemj.ttf", "C:/Windows/Fonts/seguiemj.ttf"]
	for ttf_path in emoji_paths:
		if FileAccess.file_exists(ttf_path):
			var ff := FontFile.new()
			var err := ff.load_dynamic_font(ttf_path)
			if err == OK:
				return ff
			push_warning("Failed to load emoji font from %s (error %d)" % [ttf_path, err])
	# Fallback to Webdings cityscape glyph.
	var webdings_paths := ["res://data/webdings.ttf", "C:/Windows/Fonts/webdings.ttf"]
	for ttf_path in webdings_paths:
		if FileAccess.file_exists(ttf_path):
			var ff := FontFile.new()
			var err := ff.load_dynamic_font(ttf_path)
			if err == OK:
				return ff
			push_warning("Failed to load Webdings from %s (error %d)" % [ttf_path, err])
	push_warning("No datafort marker font found; markers will not render correctly.")
	return null


func _process(_delta: float) -> void:
	_pulse_time += _delta
	queue_redraw()


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
	var x := int((screen_pos.x - GRID_OFFSET_X) / CELL)
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
	var font := _theme_font()
	var wfont := _datafort_font if _datafort_font != null else font
	var pulse := _pulse_value()

	_draw_designer_background(total_w, total_h)
	_draw_designer_scanlines()
	_draw_designer_grid(total_w, total_h, pulse)
	_draw_designer_ldl_entry(font, pulse)
	_draw_designer_dataforts(wfont, font, pulse)
	_draw_designer_header(font, wfont, pulse)


func _pulse_value() -> float:
	return 0.5 + 0.5 * sin(_pulse_time * 3.0)


func _draw_designer_background(total_w: int, total_h: int) -> void:
	var canvas_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, canvas_size), COLOR_BG, true)

	var vignette := Color(0.0, 0.0, 0.0, 0.3)
	draw_rect(Rect2(GRID_OFFSET_X, GRID_OFFSET_Y, total_w, 100), vignette, true)
	draw_rect(Rect2(GRID_OFFSET_X, GRID_OFFSET_Y + total_h - 100, total_w, 100), vignette, true)
	draw_rect(Rect2(GRID_OFFSET_X, GRID_OFFSET_Y, 100, total_h), vignette, true)
	draw_rect(Rect2(GRID_OFFSET_X + total_w - 100, GRID_OFFSET_Y, 100, total_h), vignette, true)


func _draw_designer_scanlines() -> void:
	var canvas_size := get_viewport_rect().size
	var y: float = 0.0
	while y < canvas_size.y:
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), COLOR_SCANLINE, 1.0)
		y += 4.0


func _draw_designer_grid(total_w: int, total_h: int, pulse: float) -> void:
	var bright_alpha := COLOR_GRID_BRIGHT.a * (0.5 + 0.5 * pulse)
	var origin := Vector2(GRID_OFFSET_X, GRID_OFFSET_Y)
	for x in range(current_layout.grid_cols + 1):
		var line_color := COLOR_GRID
		if x % 5 == 0:
			line_color = Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bright_alpha)
		draw_line(origin + Vector2(x * CELL, 0), origin + Vector2(x * CELL, total_h), line_color, 1.0 if x % 5 != 0 else 1.5)
	for y in range(current_layout.grid_rows + 1):
		var line_color := COLOR_GRID
		if y % 5 == 0:
			line_color = Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bright_alpha)
		draw_line(origin + Vector2(0, y * CELL), origin + Vector2(total_w, y * CELL), line_color, 1.0 if y % 5 != 0 else 1.5)
	_draw_designer_tech_frame(origin, Vector2(total_w, total_h), COLOR_GRID_BRIGHT, 2.0)


func _draw_designer_ldl_entry(font: Font, pulse: float) -> void:
	var entry := current_layout.ldl_entry
	var center := Vector2(GRID_OFFSET_X + entry.x * CELL + CELL / 2.0, GRID_OFFSET_Y + entry.y * CELL + CELL / 2.0)
	var ring_alpha := 0.6 + 0.4 * pulse
	draw_arc(center, CELL * 0.42, _pulse_time * 2.0, _pulse_time * 2.0 + TAU * 0.85, 24, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, ring_alpha), 2.0)
	var label := "LDL"
	var label_size := 10
	var label_dims := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
	var label_pos := center - label_dims * 0.5 + Vector2(0, label_size * 0.35)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, 0.9))


func _draw_designer_dataforts(wfont: Font, label_font: Font, pulse: float) -> void:
	const BUILDING_CHAR := "🏢"  # Office building emoji (U+1F3E2).
	const BUILDING_SIZE := 30
	for df in current_layout.dataforts:
		var tier: int = clampi(int(df.security_tier), 0, CP2020SecurityTier.Tier.size() - 1)
		var tier_color: Color = CP2020SecurityTier.COLORS[tier]
		var center := Vector2(GRID_OFFSET_X + df.pos.x * CELL + CELL / 2.0, GRID_OFFSET_Y + df.pos.y * CELL + CELL / 2.0)

		# Selection highlight overrides tier color.
		var df_color := tier_color
		if df == selected_datafort:
			df_color = Color(1.0, 1.0, 0.0, 1.0)

		# Neon glow.
		for i in range(3):
			var glow_radius := CELL * (0.55 + i * 0.18)
			var glow_alpha := (0.18 - i * 0.05) * (0.7 + 0.3 * pulse)
			draw_arc(center, glow_radius, 0, TAU, 32, Color(df_color.r, df_color.g, df_color.b, glow_alpha), 3.0)

		# Corner brackets.
		_draw_designer_corner_brackets(center, CELL * 0.55, df_color, 2.0)

		# Building emoji: larger, centered in the tile.
		var glyph_dims := wfont.get_string_size(BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, BUILDING_SIZE)
		var glyph_pos := center - glyph_dims * 0.5 + Vector2(0, 25)
		draw_string(wfont, glyph_pos, BUILDING_CHAR, HORIZONTAL_ALIGNMENT_LEFT, -1, BUILDING_SIZE, df_color)

		# Datafort label centered below the tile.
		var label_size := 11
		var label_dims := label_font.get_string_size(df.name, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
		var label_pos := Vector2(
			GRID_OFFSET_X + df.pos.x * CELL + (CELL - label_dims.x) * 0.5,
			GRID_OFFSET_Y + df.pos.y * CELL + CELL + 12
		)
		draw_string(label_font, label_pos, df.name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, COLOR_TEXT_LABEL)


func _draw_designer_header(font: Font, wfont: Font, pulse: float) -> void:
	const BUILDING_CHAR := "🏢"  # Office building emoji (U+1F3E2).
	const LEGEND_ICON_SIZE := 12
	var title := "CITY GRID DESIGNER // %s" % current_layout.city_name.to_upper()
	var header_y := 48.0
	var bracket_alpha := 0.7 + 0.3 * pulse
	draw_string(font, Vector2(18, header_y), "[", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bracket_alpha))
	draw_string(font, Vector2(30, header_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT_HEADER)
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(34 + title_width, header_y), "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bracket_alpha))
	var line_y := header_y + 8
	var pulse_x := 30 + fmod(_pulse_time * 80.0, title_width + 20)
	draw_line(Vector2(18, line_y), Vector2(36 + title_width, line_y), COLOR_GRID_BRIGHT, 1.0)
	draw_circle(Vector2(30 + pulse_x, line_y), 3.0, COLOR_RUNNER)

	# Tier legend (vertical, right of the grid, flush with the map edge).
	var grid_right := GRID_OFFSET_X + current_layout.grid_cols * CELL + 8
	var legend_x := grid_right
	var legend_y := GRID_OFFSET_Y + 4
	for i in range(CP2020SecurityTier.Tier.size()):
		var tier_color: Color = CP2020SecurityTier.COLORS[i]
		var short := String(CP2020SecurityTier.SHORT[i])
		var icon_pos := Vector2(legend_x, legend_y + 11)
		draw_string(wfont, icon_pos, BUILDING_CHAR, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_ICON_SIZE, tier_color)
		draw_string(font, Vector2(legend_x + LEGEND_ICON_SIZE + 4, legend_y + 11), short, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85, 0.9))
		legend_y += 16


func _draw_designer_corner_brackets(center: Vector2, half_size: float, color: Color, width: float) -> void:
	var inset := half_size * 0.55
	var tl := center + Vector2(-half_size, -half_size)
	var top_r := center + Vector2(half_size, -half_size)
	var bl := center + Vector2(-half_size, half_size)
	var bottom_r := center + Vector2(half_size, half_size)
	draw_line(tl, tl + Vector2(inset, 0), color, width)
	draw_line(tl, tl + Vector2(0, inset), color, width)
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width)
	draw_line(top_r, top_r + Vector2(0, inset), color, width)
	draw_line(bl, bl + Vector2(inset, 0), color, width)
	draw_line(bl, bl + Vector2(0, -inset), color, width)
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width)


func _draw_designer_tech_frame(origin: Vector2, frame_size: Vector2, color: Color, width: float) -> void:
	var tl := origin
	var top_r := origin + Vector2(frame_size.x, 0)
	var bl := origin + Vector2(0, frame_size.y)
	var bottom_r := origin + frame_size
	var inset := 18.0
	draw_rect(Rect2(origin, frame_size), color, false, width)
	draw_line(tl, tl + Vector2(inset, 0), color, width + 1.0)
	draw_line(tl, tl + Vector2(0, inset), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(0, inset), color, width + 1.0)
	draw_line(bl, bl + Vector2(inset, 0), color, width + 1.0)
	draw_line(bl, bl + Vector2(0, -inset), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width + 1.0)


func _theme_font() -> Font:
	var label := Label.new()
	var f := label.get_theme_default_font()
	label.free()
	return f
