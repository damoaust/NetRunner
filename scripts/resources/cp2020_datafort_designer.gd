@tool
extends Control

@export var map_name: String = "New Datafort"
@export var grid_rows: int = 15
@export var grid_columns: int = 15

var current_layout: CP2020DatafortLayout

# --- Grid canvas (child node that handles drawing + input) ---
@onready var grid_canvas: CP2020DatafortGridCanvas = $GridCanvas

# --- Toolbar (scene-tree nodes) ---
@onready var dynamic_button_row: HBoxContainer = $TopPanel/DynamicButtonRow
@onready var columns_spinbox: SpinBox = $TopPanel/SettingsRow/ColumnsSpinBox
@onready var rows_spinbox: SpinBox = $TopPanel/SettingsRow/RowsSpinBox
@onready var apply_size_button: Button = $TopPanel/SettingsRow/ApplyButton

# --- File dialogs (scene-tree nodes) ---
@onready var save_dialog: FileDialog = $SaveDialog
@onready var load_dialog: FileDialog = $LoadDialog
@onready var ldl_browse_dialog: FileDialog = $LdlBrowseDialog
@onready var ice_program_dialog: FileDialog = $IceProgramDialog
@onready var loot_add_dialog: FileDialog = $LootAddDialog
@onready var programs_add_dialog: FileDialog = $ProgramsAddDialog

# --- LDL link editor panel ---
@onready var ldl_panel: PanelContainer = $LDLLinkPanel
@onready var ldl_target_edit: LineEdit = $LDLLinkPanel/VBox/TargetEdit
@onready var ldl_x_spinbox: SpinBox = $LDLLinkPanel/VBox/XSpinBox
@onready var ldl_y_spinbox: SpinBox = $LDLLinkPanel/VBox/YSpinBox
@onready var ldl_primary_check: CheckBox = $LDLLinkPanel/VBox/PrimaryCheck
var selected_ldl_coord: Vector2i = Vector2i(-1, -1)

# --- Entry editor panel ---
@onready var entry_panel: PanelContainer = $EntryEditorPanel
@onready var entry_coord_label: Label = $EntryEditorPanel/VBox/CoordLabel
@onready var entry_primary_check: CheckBox = $EntryEditorPanel/VBox/PrimaryCheck
var selected_entry_coord: Vector2i = Vector2i(-1, -1)
# Shared coord for the "Primary entry" checkbox in either the LDL or Entry
# panel. Set by _open_ldl_editor / _open_entry_editor; read by
# _on_primary_entry_toggled to know which tile's flag is being toggled.
var selected_primary_coord: Vector2i = Vector2i(-1, -1)

# --- ICE editor panel ---
@onready var ice_panel: PanelContainer = $IceEditorPanel
@onready var ice_program_label: Label = $IceEditorPanel/VBox/ProgramLabel
var selected_ice_coord: Vector2i = Vector2i(-1, -1)

# --- NPC editor panel ---
@onready var npc_panel: PanelContainer = $NpcEditorPanel
@onready var npc_name_edit: LineEdit = $NpcEditorPanel/VBox/NameEdit
@onready var npc_str_spinbox: SpinBox = $NpcEditorPanel/VBox/StrSpinBox
@onready var npc_ap_spinbox: SpinBox = $NpcEditorPanel/VBox/ApSpinBox
@onready var npc_int_spinbox: SpinBox = $NpcEditorPanel/VBox/IntSpinBox
@onready var npc_health_spinbox: SpinBox = $NpcEditorPanel/VBox/HealthSpinBox
@onready var npc_mu_spinbox: SpinBox = $NpcEditorPanel/VBox/MuSpinBox
@onready var npc_deck_edit: LineEdit = $NpcEditorPanel/VBox/DeckEdit
@onready var npc_disposition_option: OptionButton = $NpcEditorPanel/VBox/DispositionOption
var selected_npc_coord: Vector2i = Vector2i(-1, -1)

# --- CPU editor panel ---
@onready var cpu_panel: PanelContainer = $CpuEditorPanel
var selected_cpu_coord: Vector2i = Vector2i(-1, -1)

# --- Loot editor panel ---
@onready var loot_panel: PanelContainer = $LootEditorPanel
@onready var loot_cpu_info_label: Label = $LootEditorPanel/VBox/CpuInfoLabel
@onready var loot_credits_spinbox: SpinBox = $LootEditorPanel/VBox/CreditsSpinBox
@onready var loot_programs_list: ItemList = $LootEditorPanel/VBox/ProgramsList
var selected_loot_coord: Vector2i = Vector2i(-1, -1)

# --- Files editor panel ---
@onready var files_panel: PanelContainer = $FilesEditorPanel
@onready var files_list: ItemList = $FilesEditorPanel/VBox/FilesList
@onready var file_name_edit: LineEdit = $FilesEditorPanel/VBox/NameEdit
@onready var file_desc_edit: TextEdit = $FilesEditorPanel/VBox/DescEdit
@onready var file_value_spinbox: SpinBox = $FilesEditorPanel/VBox/ValueSpinBox
@onready var file_mu_spinbox: SpinBox = $FilesEditorPanel/VBox/MuSpinBox
var selected_files_coord: Vector2i = Vector2i(-1, -1)

# --- Layout-level resident programs editor ---
@onready var programs_panel: PanelContainer = $ProgramsEditorPanel
@onready var programs_list: ItemList = $ProgramsEditorPanel/VBox/ProgramsList
@onready var programs_mu_label: Label = $ProgramsEditorPanel/VBox/MuLabel
@onready var programs_toggle_button: Button = $ProgramsToggleButton


func _ready() -> void:
	setup_new_map()
	_connect_toolbar_signals()
	_connect_panel_signals()
	_connect_grid_signals()
	grid_canvas.queue_redraw()


func setup_new_map() -> void:
	if not current_layout:
		current_layout = CP2020DatafortLayout.new()
	current_layout.fort_name = map_name
	current_layout.rows = grid_rows
	current_layout.columns = grid_columns
	grid_canvas.grid_rows = grid_rows
	grid_canvas.grid_columns = grid_columns
	grid_canvas.current_layout = current_layout
	grid_canvas.fill_empty_tiles()
	if columns_spinbox:
		columns_spinbox.value = grid_columns
	if rows_spinbox:
		rows_spinbox.value = grid_rows


func _connect_toolbar_signals() -> void:
	if apply_size_button and not apply_size_button.pressed.is_connected(_on_resize_pressed):
		apply_size_button.pressed.connect(_on_resize_pressed)
	if save_dialog and not save_dialog.file_selected.is_connected(_on_file_saved):
		save_dialog.file_selected.connect(_on_file_saved)
	if load_dialog and not load_dialog.file_selected.is_connected(_on_file_loaded):
		load_dialog.file_selected.connect(_on_file_loaded)

	# Tool buttons — set grid canvas state + hide all panels.
	if dynamic_button_row:
		var select_btn = dynamic_button_row.get_node_or_null("SelectButton")
		if select_btn and not select_btn.pressed.is_connected(_on_select_tool):
			select_btn.pressed.connect(_on_select_tool)
		var entry_btn = dynamic_button_row.get_node_or_null("EntryButton")
		if entry_btn and not entry_btn.pressed.is_connected(_on_entry_tool):
			entry_btn.pressed.connect(_on_entry_tool)
		var datawall_btn = dynamic_button_row.get_node_or_null("DatawallButton")
		if datawall_btn and not datawall_btn.pressed.is_connected(_on_datawall_tool):
			datawall_btn.pressed.connect(_on_datawall_tool)
		var codegate_btn = dynamic_button_row.get_node_or_null("CodeGateButton")
		if codegate_btn and not codegate_btn.pressed.is_connected(_on_codegate_tool):
			codegate_btn.pressed.connect(_on_codegate_tool)
		var memunit_btn = dynamic_button_row.get_node_or_null("MemoryUnitButton")
		if memunit_btn and not memunit_btn.pressed.is_connected(_on_memoryunit_tool):
			memunit_btn.pressed.connect(_on_memoryunit_tool)
		var ctrlnode_btn = dynamic_button_row.get_node_or_null("ControlNodeButton")
		if ctrlnode_btn and not ctrlnode_btn.pressed.is_connected(_on_controlnode_tool):
			ctrlnode_btn.pressed.connect(_on_controlnode_tool)
		var blackice_btn = dynamic_button_row.get_node_or_null("BlackIceButton")
		if blackice_btn and not blackice_btn.pressed.is_connected(_on_blackice_tool):
			blackice_btn.pressed.connect(_on_blackice_tool)
		var netwatch_btn = dynamic_button_row.get_node_or_null("NetWatchButton")
		if netwatch_btn and not netwatch_btn.pressed.is_connected(_on_netwatch_tool):
			netwatch_btn.pressed.connect(_on_netwatch_tool)
		var netrunner_btn = dynamic_button_row.get_node_or_null("NetrunnerButton")
		if netrunner_btn and not netrunner_btn.pressed.is_connected(_on_netrunner_tool):
			netrunner_btn.pressed.connect(_on_netrunner_tool)
		var ldl_btn = dynamic_button_row.get_node_or_null("LdlLinkButton")
		if ldl_btn and not ldl_btn.pressed.is_connected(_on_ldl_link_tool):
			ldl_btn.pressed.connect(_on_ldl_link_tool)
		var eraser_btn = dynamic_button_row.get_node_or_null("EraserButton")
		if eraser_btn and not eraser_btn.pressed.is_connected(_on_eraser_tool):
			eraser_btn.pressed.connect(_on_eraser_tool)
		var save_btn = dynamic_button_row.get_node_or_null("SaveButton")
		if save_btn and not save_btn.pressed.is_connected(_on_save_pressed):
			save_btn.pressed.connect(_on_save_pressed)
		var load_btn = dynamic_button_row.get_node_or_null("LoadButton")
		if load_btn and not load_btn.pressed.is_connected(_on_load_pressed):
			load_btn.pressed.connect(_on_load_pressed)

	if programs_toggle_button and not programs_toggle_button.pressed.is_connected(_toggle_programs_panel):
		programs_toggle_button.pressed.connect(_toggle_programs_panel)


func _connect_panel_signals() -> void:
	# LDL panel
	if ldl_target_edit and not ldl_target_edit.text_changed.is_connected(_on_ldl_target_changed):
		ldl_target_edit.text_changed.connect(_on_ldl_target_changed)
	if ldl_x_spinbox and not ldl_x_spinbox.value_changed.is_connected(_on_ldl_coord_changed):
		ldl_x_spinbox.value_changed.connect(_on_ldl_coord_changed)
	if ldl_y_spinbox and not ldl_y_spinbox.value_changed.is_connected(_on_ldl_coord_changed):
		ldl_y_spinbox.value_changed.connect(_on_ldl_coord_changed)
	var ldl_browse_btn = ldl_panel.get_node_or_null("VBox/BrowseButton")
	if ldl_browse_btn and not ldl_browse_btn.pressed.is_connected(_on_ldl_browse):
		ldl_browse_btn.pressed.connect(_on_ldl_browse)
	var ldl_clear_btn = ldl_panel.get_node_or_null("VBox/ClearButton")
	if ldl_clear_btn and not ldl_clear_btn.pressed.is_connected(_clear_ldl_target):
		ldl_clear_btn.pressed.connect(_clear_ldl_target)
	if ldl_primary_check and not ldl_primary_check.toggled.is_connected(_on_primary_entry_toggled):
		ldl_primary_check.toggled.connect(_on_primary_entry_toggled)
	if ldl_browse_dialog and not ldl_browse_dialog.file_selected.is_connected(_on_ldl_target_selected):
		ldl_browse_dialog.file_selected.connect(_on_ldl_target_selected)

	# Entry panel
	if entry_primary_check and not entry_primary_check.toggled.is_connected(_on_primary_entry_toggled):
		entry_primary_check.toggled.connect(_on_primary_entry_toggled)

	# ICE panel
	var ice_browse_btn = ice_panel.get_node_or_null("VBox/BrowseButton")
	if ice_browse_btn and not ice_browse_btn.pressed.is_connected(_open_ice_program_dialog):
		ice_browse_btn.pressed.connect(_open_ice_program_dialog)
	var ice_clear_btn = ice_panel.get_node_or_null("VBox/ClearButton")
	if ice_clear_btn and not ice_clear_btn.pressed.is_connected(_clear_ice_program):
		ice_clear_btn.pressed.connect(_clear_ice_program)
	if ice_program_dialog and not ice_program_dialog.file_selected.is_connected(_on_ice_program_picked):
		ice_program_dialog.file_selected.connect(_on_ice_program_picked)

	# NPC panel
	if npc_name_edit and not npc_name_edit.text_changed.is_connected(_on_npc_field_changed):
		npc_name_edit.text_changed.connect(_on_npc_field_changed)
	if npc_str_spinbox and not npc_str_spinbox.value_changed.is_connected(_on_npc_field_changed):
		npc_str_spinbox.value_changed.connect(_on_npc_field_changed)
	if npc_ap_spinbox and not npc_ap_spinbox.value_changed.is_connected(_on_npc_field_changed):
		npc_ap_spinbox.value_changed.connect(_on_npc_field_changed)
	if npc_int_spinbox and not npc_int_spinbox.value_changed.is_connected(_on_npc_field_changed):
		npc_int_spinbox.value_changed.connect(_on_npc_field_changed)
	if npc_health_spinbox and not npc_health_spinbox.value_changed.is_connected(_on_npc_field_changed):
		npc_health_spinbox.value_changed.connect(_on_npc_field_changed)
	if npc_mu_spinbox and not npc_mu_spinbox.value_changed.is_connected(_on_npc_field_changed):
		npc_mu_spinbox.value_changed.connect(_on_npc_field_changed)
	if npc_deck_edit and not npc_deck_edit.text_changed.is_connected(_on_npc_field_changed):
		npc_deck_edit.text_changed.connect(_on_npc_field_changed)
	if npc_disposition_option and not npc_disposition_option.item_selected.is_connected(_on_npc_field_changed):
		npc_disposition_option.item_selected.connect(_on_npc_field_changed)
	if npc_disposition_option and npc_disposition_option.item_count == 0:
		npc_disposition_option.add_item("Hostile", 0)
		npc_disposition_option.add_item("Neutral", 1)
	var npc_clear_btn = npc_panel.get_node_or_null("VBox/ClearButton")
	if npc_clear_btn and not npc_clear_btn.pressed.is_connected(_clear_npc_override):
		npc_clear_btn.pressed.connect(_clear_npc_override)

	# Loot panel
	if loot_credits_spinbox and not loot_credits_spinbox.value_changed.is_connected(_on_loot_credits_changed):
		loot_credits_spinbox.value_changed.connect(_on_loot_credits_changed)
	var loot_add_btn = loot_panel.get_node_or_null("VBox/AddButton")
	if loot_add_btn and not loot_add_btn.pressed.is_connected(_open_loot_add_dialog):
		loot_add_btn.pressed.connect(_open_loot_add_dialog)
	var loot_remove_btn = loot_panel.get_node_or_null("VBox/RemoveButton")
	if loot_remove_btn and not loot_remove_btn.pressed.is_connected(_remove_selected_loot_program):
		loot_remove_btn.pressed.connect(_remove_selected_loot_program)
	var loot_clear_btn = loot_panel.get_node_or_null("VBox/ClearButton")
	if loot_clear_btn and not loot_clear_btn.pressed.is_connected(_clear_loot_list):
		loot_clear_btn.pressed.connect(_clear_loot_list)
	if loot_add_dialog and not loot_add_dialog.file_selected.is_connected(_on_loot_program_added):
		loot_add_dialog.file_selected.connect(_on_loot_program_added)

	# Files panel
	var files_add_btn = files_panel.get_node_or_null("VBox/AddButton")
	if files_add_btn and not files_add_btn.pressed.is_connected(_add_file):
		files_add_btn.pressed.connect(_add_file)
	var files_update_btn = files_panel.get_node_or_null("VBox/UpdateButton")
	if files_update_btn and not files_update_btn.pressed.is_connected(_update_selected_file):
		files_update_btn.pressed.connect(_update_selected_file)
	var files_remove_btn = files_panel.get_node_or_null("VBox/RemoveButton")
	if files_remove_btn and not files_remove_btn.pressed.is_connected(_remove_selected_file):
		files_remove_btn.pressed.connect(_remove_selected_file)
	var files_clear_btn = files_panel.get_node_or_null("VBox/ClearButton")
	if files_clear_btn and not files_clear_btn.pressed.is_connected(_clear_files):
		files_clear_btn.pressed.connect(_clear_files)

	# Programs panel
	var prog_add_btn = programs_panel.get_node_or_null("VBox/AddButton")
	if prog_add_btn and not prog_add_btn.pressed.is_connected(_open_programs_add_dialog):
		prog_add_btn.pressed.connect(_open_programs_add_dialog)
	var prog_remove_btn = programs_panel.get_node_or_null("VBox/RemoveButton")
	if prog_remove_btn and not prog_remove_btn.pressed.is_connected(_remove_selected_program):
		prog_remove_btn.pressed.connect(_remove_selected_program)
	if programs_add_dialog and not programs_add_dialog.file_selected.is_connected(_on_program_added):
		programs_add_dialog.file_selected.connect(_on_program_added)


func _connect_grid_signals() -> void:
	if grid_canvas:
		if not grid_canvas.tile_selected.is_connected(_on_grid_tile_selected):
			grid_canvas.tile_selected.connect(_on_grid_tile_selected)
		if not grid_canvas.tile_painted.is_connected(_on_grid_tile_painted):
			grid_canvas.tile_painted.connect(_on_grid_tile_painted)
		if not grid_canvas.ldl_link_selected.is_connected(_on_grid_ldl_link_selected):
			grid_canvas.ldl_link_selected.connect(_on_grid_ldl_link_selected)
		if not grid_canvas.ldl_link_painted.is_connected(_on_grid_ldl_link_painted):
			grid_canvas.ldl_link_painted.connect(_on_grid_ldl_link_painted)
		if not grid_canvas.tile_moved.is_connected(_on_grid_tile_moved):
			grid_canvas.tile_moved.connect(_on_grid_tile_moved)


# ---------------------------------------------------------------------------
# Toolbar button handlers — set grid canvas state + hide all panels.
# ---------------------------------------------------------------------------

func _hide_all_panels() -> void:
	_hide_ldl_panel()
	_hide_entry_panel()
	_hide_ice_panel()
	_hide_npc_panel()
	_hide_cpu_panel()
	_hide_loot_panel()
	_hide_files_panel()

func _on_select_tool() -> void:
	grid_canvas.select_mode = true
	grid_canvas.ldl_link_mode = false
	grid_canvas.selected_coord = Vector2i(-1, -1)
	grid_canvas.dragging = false
	grid_canvas.drag_tile = null
	_hide_all_panels()
	grid_canvas.queue_redraw()
	print("Selected Tool: Select (click a tile to edit it)")

func _on_entry_tool() -> void:
	grid_canvas.selected_tile_type = CP2020DatafortLayout.TileType.ENTRY
	grid_canvas.select_mode = false
	grid_canvas.ldl_link_mode = false
	grid_canvas.selected_coord = Vector2i(-1, -1)
	grid_canvas.dragging = false
	grid_canvas.drag_tile = null
	_hide_all_panels()
	grid_canvas.queue_redraw()
	print("Selected Tool: Entry (plain datafort entrance)")

func _on_datawall_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.DATAWALL, "Datawall")

func _on_codegate_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.CODE_GATE, "Code Gate")

func _on_memoryunit_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.MEMORY_UNIT, "Memory Unit")

func _on_controlnode_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.CONTROL_NODE, "Control Node")

func _on_blackice_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.BLACK_ICE, "Black ICE")

func _on_netwatch_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.NETWATCH, "NetWatch")

func _on_netrunner_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.NETRUNNER, "Netrunner")

func _on_eraser_tool() -> void:
	_set_paint_tool(CP2020DatafortLayout.TileType.EMPTY, "Eraser")

func _set_paint_tool(tile_type: CP2020DatafortLayout.TileType, label: String) -> void:
	grid_canvas.selected_tile_type = tile_type
	grid_canvas.select_mode = false
	grid_canvas.ldl_link_mode = false
	grid_canvas.selected_coord = Vector2i(-1, -1)
	grid_canvas.dragging = false
	grid_canvas.drag_tile = null
	_hide_all_panels()
	grid_canvas.queue_redraw()
	print("Selected Tool: ", label)

func _on_ldl_link_tool() -> void:
	grid_canvas.selected_tile_type = CP2020DatafortLayout.TileType.ENTRY
	grid_canvas.select_mode = false
	grid_canvas.ldl_link_mode = true
	grid_canvas.selected_coord = Vector2i(-1, -1)
	grid_canvas.dragging = false
	grid_canvas.drag_tile = null
	_hide_all_panels()
	grid_canvas.queue_redraw()
	print("Selected Tool: LDL Link (paint/select an LDL link, then edit it in the side panel)")


# ---------------------------------------------------------------------------
# Grid canvas signal handlers — dispatch to the right side panel.
# ---------------------------------------------------------------------------

func _on_grid_tile_selected(coord: Vector2i, tile: CP2020TileData) -> void:
	grid_canvas.selected_coord = coord
	_open_editor_for_tile(coord, tile)

func _on_grid_tile_painted(coord: Vector2i, tile: CP2020TileData) -> void:
	_hide_ldl_panel()
	if tile and tile.tile_type == CP2020DatafortLayout.TileType.BLACK_ICE:
		_open_ice_editor(coord)
	elif tile and (tile.tile_type == CP2020DatafortLayout.TileType.NETWATCH or tile.tile_type == CP2020DatafortLayout.TileType.NETRUNNER):
		_open_npc_editor(coord)
	elif tile and tile.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE:
		_hide_cpu_panel()
		_hide_files_panel()
		_open_loot_editor(coord)
	elif tile and tile.tile_type == CP2020DatafortLayout.TileType.MEMORY_UNIT:
		_hide_loot_panel()
		_open_files_editor(coord)
	else:
		_hide_ice_panel()
		_hide_npc_panel()
		_hide_cpu_panel()
		_hide_loot_panel()
		_hide_files_panel()

func _on_grid_ldl_link_selected(coord: Vector2i) -> void:
	_hide_entry_panel()
	_open_ldl_editor(coord)

func _on_grid_ldl_link_painted(coord: Vector2i) -> void:
	_open_ldl_editor(coord)

func _on_grid_tile_moved(_from: Vector2i, to: Vector2i, tile: CP2020TileData) -> void:
	grid_canvas.selected_coord = to
	_open_editor_for_tile(to, tile)


# ---------------------------------------------------------------------------
# Resize / save / load
# ---------------------------------------------------------------------------

func _on_resize_pressed() -> void:
	if not current_layout:
		return
	grid_rows = int(rows_spinbox.value)
	grid_columns = int(columns_spinbox.value)
	current_layout.rows = grid_rows
	current_layout.columns = grid_columns
	grid_canvas.grid_rows = grid_rows
	grid_canvas.grid_columns = grid_columns
	grid_canvas.fill_empty_tiles()
	grid_canvas.queue_redraw()

func _on_save_pressed() -> void:
	if save_dialog:
		save_dialog.popup_centered(Vector2i(800, 600))

func _on_load_pressed() -> void:
	if load_dialog:
		load_dialog.popup_centered(Vector2i(800, 600))

func _on_file_saved(path: String) -> void:
	if not current_layout:
		return
	ResourceSaver.save(current_layout, path)
	print("Map saved to: ", path)

func _on_file_loaded(path: String) -> void:
	var loaded = ResourceLoader.load(path)
	if loaded is CP2020DatafortLayout:
		current_layout = loaded
		grid_rows = current_layout.rows
		grid_columns = current_layout.columns
		grid_canvas.current_layout = current_layout
		grid_canvas.grid_rows = grid_rows
		grid_canvas.grid_columns = grid_columns
		grid_canvas.fill_empty_tiles()
		grid_canvas.queue_redraw()
		print("Map loaded from: ", path)
	else:
		print("Failed to load layout from: ", path)


# ---------------------------------------------------------------------------
# Tile selection → side panel dispatch
# ---------------------------------------------------------------------------

func _open_editor_for_tile(coord: Vector2i, tile: CP2020TileData) -> void:
	grid_canvas.selected_coord = coord
	if tile == null or tile.tile_type == CP2020DatafortLayout.TileType.EMPTY:
		_hide_all_panels()
	elif tile.tile_type == CP2020DatafortLayout.TileType.ENTRY and tile.is_ldl_link:
		_hide_entry_panel()
		_open_ldl_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.ENTRY:
		_hide_ldl_panel()
		_open_entry_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.BLACK_ICE:
		_hide_ldl_panel()
		_hide_entry_panel()
		_open_ice_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.NETWATCH or tile.tile_type == CP2020DatafortLayout.TileType.NETRUNNER:
		_hide_ldl_panel()
		_hide_entry_panel()
		_open_npc_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE:
		_hide_ldl_panel()
		_hide_entry_panel()
		_hide_cpu_panel()
		_hide_files_panel()
		_open_loot_editor(coord)
	elif tile.tile_type == CP2020DatafortLayout.TileType.MEMORY_UNIT:
		_hide_ldl_panel()
		_hide_entry_panel()
		_hide_loot_panel()
		_open_files_editor(coord)
	else:
		_hide_all_panels()


# ---------------------------------------------------------------------------
# LDL link editor
# ---------------------------------------------------------------------------

func _open_ldl_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.ENTRY:
		return
	selected_ldl_coord = coord
	ldl_target_edit.set_block_signals(true)
	ldl_target_edit.text = tile.target_subnet_path
	ldl_target_edit.set_block_signals(false)
	ldl_x_spinbox.set_block_signals(true)
	ldl_x_spinbox.value = tile.target_entry_coord.x
	ldl_x_spinbox.set_block_signals(false)
	ldl_y_spinbox.set_block_signals(true)
	ldl_y_spinbox.value = tile.target_entry_coord.y
	ldl_y_spinbox.set_block_signals(false)
	ldl_primary_check.set_block_signals(true)
	ldl_primary_check.set_pressed_no_signal(tile.is_primary_entry)
	ldl_primary_check.set_block_signals(false)
	selected_primary_coord = coord
	ldl_panel.visible = true

func _hide_ldl_panel() -> void:
	if ldl_panel:
		ldl_panel.visible = false
	selected_ldl_coord = Vector2i(-1, -1)

func _write_ldl_field() -> void:
	if not current_layout or selected_ldl_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_ldl_coord)
	if tile == null:
		return
	tile.target_subnet_path = ldl_target_edit.text.strip_edges()
	tile.target_entry_coord = Vector2i(int(ldl_x_spinbox.value), int(ldl_y_spinbox.value))
	grid_canvas.queue_redraw()

func _on_ldl_target_changed(_new_text: String) -> void:
	_write_ldl_field()

func _on_ldl_coord_changed(_value: float) -> void:
	_write_ldl_field()

func _on_ldl_browse() -> void:
	if ldl_browse_dialog:
		ldl_browse_dialog.popup_centered(Vector2i(600, 400))

func _on_ldl_target_selected(path: String) -> void:
	ldl_target_edit.text = path
	_write_ldl_field()

func _clear_ldl_target() -> void:
	if not current_layout or selected_ldl_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_ldl_coord)
	if tile == null:
		return
	tile.target_subnet_path = ""
	tile.target_entry_coord = Vector2i(-1, -1)
	ldl_target_edit.text = ""
	ldl_x_spinbox.value = -1
	ldl_y_spinbox.value = -1
	grid_canvas.queue_redraw()


# ---------------------------------------------------------------------------
# Entry editor
# ---------------------------------------------------------------------------

func _open_entry_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.ENTRY:
		return
	selected_entry_coord = coord
	if entry_coord_label:
		entry_coord_label.text = "Tile: (%d, %d)" % [coord.x, coord.y]
	if entry_primary_check:
		entry_primary_check.set_block_signals(true)
		entry_primary_check.set_pressed_no_signal(tile.is_primary_entry)
		entry_primary_check.set_block_signals(false)
	selected_primary_coord = coord
	entry_panel.visible = true

func _hide_entry_panel() -> void:
	if entry_panel:
		entry_panel.visible = false
	selected_entry_coord = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Primary entry toggle (shared by LDL + Entry panels)
# ---------------------------------------------------------------------------

func _on_primary_entry_toggled(button_pressed: bool) -> void:
	if not current_layout or selected_primary_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_primary_coord)
	if tile == null:
		return
	if button_pressed:
		for raw_key in current_layout.grid_tiles.keys():
			if raw_key == selected_primary_coord:
				continue
			var other = current_layout.grid_tiles[raw_key] as CP2020TileData
			if other and other.tile_type == CP2020DatafortLayout.TileType.ENTRY and other.is_primary_entry:
				other.is_primary_entry = false
		tile.is_primary_entry = true
	else:
		tile.is_primary_entry = false
	grid_canvas.queue_redraw()


# ---------------------------------------------------------------------------
# ICE editor
# ---------------------------------------------------------------------------

func _open_ice_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.BLACK_ICE:
		return
	selected_ice_coord = coord
	_refresh_ice_program_label(tile)
	ice_panel.visible = true

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
		grid_canvas.queue_redraw()

func _clear_ice_program() -> void:
	if not current_layout or selected_ice_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_ice_coord)
	if tile == null:
		return
	tile.ice_program = null
	_refresh_ice_program_label(tile)
	grid_canvas.queue_redraw()

func _hide_ice_panel() -> void:
	if ice_panel:
		ice_panel.visible = false
	selected_ice_coord = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# NPC editor
# ---------------------------------------------------------------------------

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
	npc_panel.visible = true

func _hide_npc_panel() -> void:
	if npc_panel:
		npc_panel.visible = false
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
	grid_canvas.queue_redraw()

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
# CPU editor
# ---------------------------------------------------------------------------

func _open_cpu_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.CONTROL_NODE:
		return
	selected_cpu_coord = coord
	cpu_panel.visible = true

func _hide_cpu_panel() -> void:
	if cpu_panel:
		cpu_panel.visible = false
	selected_cpu_coord = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Loot editor
# ---------------------------------------------------------------------------

func _open_loot_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null:
		return
	if tile.tile_type != CP2020DatafortLayout.TileType.CONTROL_NODE:
		return
	selected_loot_coord = coord
	_hide_files_panel()
	loot_cpu_info_label.visible = true
	loot_credits_spinbox.set_block_signals(true)
	loot_credits_spinbox.value = tile.loot_credits
	loot_credits_spinbox.set_block_signals(false)
	_refresh_loot_programs_list()
	loot_panel.visible = true

func _hide_loot_panel() -> void:
	if loot_panel:
		loot_panel.visible = false
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
	grid_canvas.queue_redraw()

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
			grid_canvas.queue_redraw()
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
	grid_canvas.queue_redraw()

func _clear_loot_list() -> void:
	if not current_layout or selected_loot_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_loot_coord)
	if tile == null:
		return
	tile.loot_programs.clear()
	_refresh_loot_programs_list()
	grid_canvas.queue_redraw()


# ---------------------------------------------------------------------------
# Files editor
# ---------------------------------------------------------------------------

func _open_files_editor(coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(coord)
	if tile == null or tile.tile_type != CP2020DatafortLayout.TileType.MEMORY_UNIT:
		return
	_hide_loot_panel()
	_hide_cpu_panel()
	selected_files_coord = coord
	_refresh_files_list()
	files_panel.visible = true

func _hide_files_panel() -> void:
	if files_panel:
		files_panel.visible = false
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
	grid_canvas.queue_redraw()

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
	grid_canvas.queue_redraw()

func _remove_selected_file() -> void:
	if not current_layout or not files_list or selected_files_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_files_coord)
	if tile == null:
		return
	var idxs: PackedInt32Array = files_list.get_selected_items()
	if idxs.is_empty():
		return
	idxs.reverse()
	for i: int in idxs:
		if i >= 0 and i < tile.files.size():
			tile.files.remove_at(i)
	_refresh_files_list()
	grid_canvas.queue_redraw()

func _clear_files() -> void:
	if not current_layout or selected_files_coord == Vector2i(-1, -1):
		return
	var tile = current_layout.get_tile(selected_files_coord)
	if tile == null:
		return
	tile.files.clear()
	_refresh_files_list()
	grid_canvas.queue_redraw()


# ---------------------------------------------------------------------------
# Layout-level resident programs editor
# ---------------------------------------------------------------------------

func _toggle_programs_panel() -> void:
	if programs_panel:
		programs_panel.visible = not programs_panel.visible
		if programs_panel.visible:
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
			grid_canvas.queue_redraw()

func _remove_selected_program() -> void:
	if not current_layout or not programs_list:
		return
	var idxs = programs_list.get_selected_items()
	if idxs.is_empty():
		return
	idxs.reverse()
	for i in idxs:
		if i >= 0 and i < current_layout.resident_programs.size():
			current_layout.resident_programs.remove_at(i)
	_refresh_programs_list()
	grid_canvas.queue_redraw()