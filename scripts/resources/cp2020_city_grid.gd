class_name CP2020CityGrid
extends Node2D

# City Grid — the middle layer of the 3-level map model
# (World Map -> City Grid -> Datafort). Loaded from a CP2020CityGridLayout
# resource (RunState.selected_city_grid_path). The runner arrives on the
# grid's `ldl_entry` tile and moves 5 tiles/turn. Stepping onto a datafort
# icon auto-dives into its subnet (no Hack/Pay LDL — that is a world-map-only
# mechanic). Right-click the runner's tile to Return to the World Map.
# Tier-coded datafort icons reuse CP2020SecurityTier consts.

const CELL: int = 40

@export var city_grid_layout: CP2020CityGridLayout

var grid_cols: int = 20
var grid_rows: int = 12
var dataforts: Array = []          # [{name,pos,subnet_path,security_tier,ldl_cost,security_code,trace_value}]
var datafort_tiles: Dictionary = {} # Vector2i -> true
var runner_pos: Vector2i = Vector2i.ZERO
var city_name: String = "City Grid"

@onready var turn_manager: CP2020TurnManager = get_node_or_null("TurnManager")
@onready var actions_label: Label = get_node_or_null("HUDLayer/HUDOverlay/ActionsLabel")
@onready var credits_label: Label = get_node_or_null("HUDLayer/HUDOverlay/CreditsLabel")
@onready var location_label: Label = get_node_or_null("HUDLayer/HUDOverlay/LocationLabel")
@onready var trace_label: Label = get_node_or_null("HUDLayer/HUDOverlay/TraceLabel")
@onready var camera: Camera2D = get_node_or_null("RunnerCamera")


func _ready() -> void:
	_build_grid()
	runner_pos = _resolve_entry()
	if turn_manager:
		turn_manager.start_netrunner_turn()
		if not turn_manager.actions_changed.is_connected(_on_actions_changed):
			turn_manager.actions_changed.connect(_on_actions_changed)
	_update_hud()
	_update_camera_limits()
	_center_camera_on_runner()
	queue_redraw()


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_grid() -> void:
	dataforts.clear()
	datafort_tiles.clear()
	if city_grid_layout == null:
		var path := RunState.selected_city_grid_path
		if path != "" and ResourceLoader.exists(path):
			city_grid_layout = ResourceLoader.load(path) as CP2020CityGridLayout
	if city_grid_layout == null:
		push_error("CITY GRID: No layout assigned and RunState.selected_city_grid_path is empty.")
		return
	grid_cols = city_grid_layout.grid_cols
	grid_rows = city_grid_layout.grid_rows
	city_name = city_grid_layout.city_name
	for df in city_grid_layout.dataforts:
		if df is CP2020CityGridDatafort:
			dataforts.append({
				"name": df.name,
				"pos": df.pos,
				"subnet_path": df.subnet_path,
				"security_tier": int(df.security_tier),
				"ldl_cost": int(df.ldl_cost),
				"security_code": int(df.security_code),
				"trace_value": int(df.trace_value),
			})
			datafort_tiles[df.pos] = true


func _resolve_entry() -> Vector2i:
	if city_grid_layout != null:
		return city_grid_layout.ldl_entry
	return Vector2i(grid_cols / 2, grid_rows / 2)


func _datafort_at(pos: Vector2i) -> Variant:
	for df in dataforts:
		if df.pos == pos:
			return df
	return null


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _update_camera_limits() -> void:
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = grid_cols * CELL
	camera.limit_bottom = grid_rows * CELL


func _center_camera_on_runner() -> void:
	if camera == null:
		return
	camera.position = Vector2(runner_pos.x * CELL + CELL / 2.0, runner_pos.y * CELL + CELL / 2.0)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var bg := Color(0.04, 0.08, 0.16, 1.0)
	var grid_color := Color(1, 1, 1, 0.08)
	var runner_color := Color(0.2, 0.9, 1.0, 1.0)
	var font := _theme_font()

	# CITY GRID title.
	draw_string(font, Vector2(8, 18), "CITY GRID — %s" % city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.9, 1.0, 0.9))

	# Tier legend (top-right).
	var legend_x := grid_cols * CELL - 8
	var legend_y := 14
	for i in range(CP2020SecurityTier.Tier.size()):
		var tier_color: Color = CP2020SecurityTier.COLORS[i]
		var short := String(CP2020SecurityTier.SHORT[i])
		var tw := font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		legend_x -= tw + 18
		draw_rect(Rect2(legend_x, legend_y, 12, 12), tier_color, true)
		draw_string(font, Vector2(legend_x + 16, legend_y + 11), short, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85, 0.9))

	# Grid tiles.
	for x in range(grid_cols):
		for y in range(grid_rows):
			var rect := Rect2(x * CELL, y * CELL, CELL, CELL)
			draw_rect(rect, bg, true)
			draw_rect(rect, grid_color, false, 1.0)

	# LDL entry marker.
	if city_grid_layout != null:
		var entry := city_grid_layout.ldl_entry
		var ecenter := Vector2(entry.x * CELL + CELL / 2.0, entry.y * CELL + CELL / 2.0)
		draw_arc(ecenter, CELL * 0.42, 0, TAU, 24, Color(0.2, 0.9, 1.0, 1.0), 2.0)
		draw_string(font, Vector2(ecenter.x - 10, ecenter.y + 4), "LDL", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.2, 0.9, 1.0, 1.0))

	# Datafort chips.
	for df in dataforts:
		var tier: int = int(df.security_tier)
		var tier_color: Color = CP2020SecurityTier.COLORS.get(tier, Color(0.0, 1.0, 0.9, 1.0))
		var rect := Rect2(df.pos.x * CELL, df.pos.y * CELL, CELL, CELL)
		draw_rect(rect, Color(tier_color.r, tier_color.g, tier_color.b, 0.45), true)
		draw_rect(rect, tier_color, false, 2.0)
		var glyph := String(CP2020SecurityTier.GLYPHS.get(tier, "?"))
		draw_string(font, Vector2(df.pos.x * CELL + 12, df.pos.y * CELL + 26), glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, tier_color)
		draw_string(font, Vector2(df.pos.x * CELL + 4, df.pos.y * CELL + CELL + 2), df.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tier_color)

	# Runner avatar.
	var center := Vector2(runner_pos.x * CELL + CELL / 2.0, runner_pos.y * CELL + CELL / 2.0)
	draw_arc(center, CELL * 0.35, 0, TAU, 24, runner_color, 2.0)
	draw_circle(center, CELL * 0.18, runner_color)


func _theme_font() -> Font:
	var label := Label.new()
	var f := label.get_theme_default_font()
	label.free()
	return f


# ---------------------------------------------------------------------------
# Input / movement
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var moved := false
		match event.keycode:
			KEY_W, KEY_UP:
				moved = _try_move(runner_pos + Vector2i(0, -1))
			KEY_S, KEY_DOWN:
				moved = _try_move(runner_pos + Vector2i(0, 1))
			KEY_A, KEY_LEFT:
				moved = _try_move(runner_pos + Vector2i(-1, 0))
			KEY_D, KEY_RIGHT:
				moved = _try_move(runner_pos + Vector2i(1, 0))
		if moved:
			get_viewport().set_input_as_handled()
			_update_hud()
			queue_redraw()
			_check_actions_exhausted()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var grid := _screen_to_grid(get_global_mouse_position())
		if grid == runner_pos:
			_open_return_popup()
			get_viewport().set_input_as_handled()


func _screen_to_grid(world_pos: Vector2) -> Vector2i:
	var x := int(world_pos.x / CELL)
	var y := int(world_pos.y / CELL)
	return Vector2i(clampi(x, 0, grid_cols - 1), clampi(y, 0, grid_rows - 1))


func _try_move(target: Vector2i) -> bool:
	if target.x < 0 or target.x >= grid_cols or target.y < 0 or target.y >= grid_rows:
		return false
	if turn_manager != null:
		if not turn_manager.has_actions():
			return false
		if not turn_manager.consume_action():
			return false
	runner_pos = target
	_center_camera_on_runner()
	# Stepping onto a datafort icon auto-dives into its subnet.
	var df: Variant = _datafort_at(target)
	if df != null:
		_dive_datafort(df)
	return true


func _check_actions_exhausted() -> void:
	if turn_manager != null and not turn_manager.has_actions():
		turn_manager.start_netrunner_turn()


func _on_actions_changed(remaining: int, max_actions: int) -> void:
	if actions_label:
		actions_label.text = "ACTIONS: %d/%d" % [remaining, max_actions]


# ---------------------------------------------------------------------------
# Right-click popup (Return to World Map only)
# ---------------------------------------------------------------------------

func _open_return_popup() -> void:
	var popup := PopupMenu.new()
	var hud_layer := get_node_or_null("HUDLayer")
	if hud_layer != null:
		hud_layer.add_child(popup)
	else:
		add_child(popup)
	popup.add_item("Return to World Map", 998)
	popup.add_item("Cancel", 999)
	popup.id_pressed.connect(_on_return_popup_id)
	var world_pos := Vector2(runner_pos.x * CELL + CELL, runner_pos.y * CELL)
	var screen_pos := _world_to_screen(world_pos) + Vector2(20, 20)
	popup.position = screen_pos
	popup.popup()
	popup.set_position(screen_pos)


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	var vp_size := vp.get_visible_rect().size
	if camera == null:
		return world_pos
	var zoom := camera.zoom
	var screen_center := camera.get_screen_center_position()
	return (world_pos - screen_center) * zoom + vp_size * 0.5


func _on_return_popup_id(id: int) -> void:
	if id == 998:
		_return_to_world_map()


func _dive_datafort(df: Variant) -> void:
	var subnet_path: String = df.subnet_path
	print("CITY GRID: Diving into %s [%s]. Run trace difficulty: %d" % [df.name, CP2020SecurityTier.SHORT.get(int(df.security_tier), "?"), RunState.accumulated_trace])
	RunState.selected_subnet_path = subnet_path
	RunState.selected_security_tier = int(df.security_tier)
	# Keep selected_city_grid_path so the datafort can return here.
	get_tree().change_scene_to_file("res://scenes/cp2020_gameplay.tscn")


func _return_to_world_map() -> void:
	# Leaving the city grid entirely aborts the run.
	print("CITY GRID: Returning to World Map. Run trace reset.")
	RunState.accumulated_trace = 0
	RunState.selected_city_grid_path = ""
	RunState.selected_security_tier = 0
	get_tree().change_scene_to_file("res://scenes/ui/cp2020_world_net_map.tscn")


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _update_hud() -> void:
	if actions_label and turn_manager:
		actions_label.text = "ACTIONS: %d/%d" % [turn_manager.actions_remaining, turn_manager.max_actions]
	if credits_label:
		credits_label.text = "CREDITS: %d eb" % RunState.credits
	if trace_label:
		trace_label.text = "TRACE: %d" % RunState.accumulated_trace
	if location_label:
		var df: Variant = _datafort_at(runner_pos)
		if df != null:
			location_label.text = "LOCATION: %s" % df.name.to_upper()
		else:
			location_label.text = "LOCATION: %s GRID" % city_name.to_upper()