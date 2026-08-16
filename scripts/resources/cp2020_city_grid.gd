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
const W: int = 1920
const H: int = 1080
const SCREEN_OFFSET: Vector2 = Vector2(20, 80)
const POPUP_THEME := preload("res://scripts/resources/cp2020_theme.gd")

# Cyberpunk/neon palette (matches the world map).
const COLOR_BG: Color = Color(0.02, 0.03, 0.06, 1.0)
const COLOR_GRID: Color = Color(0.0, 0.78, 0.92, 0.22)
const COLOR_GRID_BRIGHT: Color = Color(0.0, 0.9, 1.0, 0.55)
const COLOR_RUNNER: Color = Color(0.0, 1.0, 1.0, 1.0)
const COLOR_SCANLINE: Color = Color(0.0, 0.0, 0.0, 0.12)
const COLOR_TEXT_HEADER: Color = Color(0.85, 0.95, 1.0, 0.95)
const COLOR_TEXT_LABEL: Color = Color(0.7, 0.9, 1.0, 0.9)

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
@onready var clock_label: Label = get_node_or_null("HUDLayer/HUDOverlay/ClockLabel")
@onready var camera: Camera2D = get_node_or_null("RunnerCamera")

var _pulse_time: float = 0.0


func _ready() -> void:
	RunState.net_time_seconds = 0.0
	_build_grid()
	runner_pos = _resolve_entry()
	if turn_manager:
		turn_manager.start_netrunner_turn()
		if not turn_manager.actions_changed.is_connected(_on_actions_changed):
			turn_manager.actions_changed.connect(_on_actions_changed)
		if not turn_manager.action_consumed.is_connected(_on_action_consumed):
			turn_manager.action_consumed.connect(_on_action_consumed)
	_update_hud()
	_update_camera_limits()
	_center_camera_on_runner()
	queue_redraw()


# Webdings "C" glyph = tier-colored cityscape silhouette. The bundled
# webdings.ttf was regenerated with a Windows-platform (3,1) cmap (see
# tools/add_windows_cmap.py) so Godot/HarfBuzz can resolve U+0043.
const BUILDING_CHAR := "C"
const BUILDING_FONT_PATH := "res://data/webdings.ttf"

var _datafort_font: FontFile = null


func _create_datafort_font() -> FontFile:
	if _datafort_font != null:
		return _datafort_font
	var f := load(BUILDING_FONT_PATH) as FontFile
	if f == null:
		push_warning("CITY GRID: webdings.ttf missing — falling back to theme font for datafort glyph.")
		_datafort_font = _theme_font() as FontFile
	else:
		_datafort_font = f
	return _datafort_font


func _process(_delta: float) -> void:
	_pulse_time += _delta
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
	return Vector2i(int(grid_cols / 2.0), int(grid_rows / 2.0))


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
	# Keep the full grid (plus its margins) visible within the viewport.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = W
	camera.limit_bottom = H


func _center_camera_on_runner() -> void:
	if camera == null:
		return
	var center := SCREEN_OFFSET + Vector2(runner_pos.x * CELL + CELL / 2.0, runner_pos.y * CELL + CELL / 2.0)
	camera.position = center


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := _theme_font()
	var pulse := _pulse_value()

	_draw_background(pulse)
	_draw_scanlines()
	_draw_vignette()
	_draw_grid(pulse)
	_draw_dataforts(font, pulse)
	_draw_ldl_entry(font, pulse)
	_draw_runner(pulse)
	_draw_header(font, pulse)


func _pulse_value() -> float:
	return 0.5 + 0.5 * sin(_pulse_time * 3.0)


func _draw_background(_pulse: float) -> void:
	var canvas_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, canvas_size), COLOR_BG, true)


func _draw_scanlines() -> void:
	var canvas_size := get_viewport_rect().size
	var y: float = 0.0
	while y < canvas_size.y:
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), COLOR_SCANLINE, 1.0)
		y += 4.0


func _draw_vignette() -> void:
	var total_w := grid_cols * CELL
	var total_h := grid_rows * CELL
	var vignette := Color(0.0, 0.0, 0.0, 0.3)
	var ox := SCREEN_OFFSET.x
	var oy := SCREEN_OFFSET.y
	draw_rect(Rect2(ox, oy, total_w, 100), vignette, true)
	draw_rect(Rect2(ox, oy + total_h - 100, total_w, 100), vignette, true)
	draw_rect(Rect2(ox, oy, 100, total_h), vignette, true)
	draw_rect(Rect2(ox + total_w - 100, oy, 100, total_h), vignette, true)


func _draw_grid(pulse: float) -> void:
	var total_w := grid_cols * CELL
	var total_h := grid_rows * CELL
	var bright_alpha := COLOR_GRID_BRIGHT.a * (0.5 + 0.5 * pulse)
	var origin := SCREEN_OFFSET
	for x in range(grid_cols + 1):
		var line_color := COLOR_GRID
		if x % 5 == 0:
			line_color = Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bright_alpha)
		draw_line(origin + Vector2(x * CELL, 0), origin + Vector2(x * CELL, total_h), line_color, 1.0 if x % 5 != 0 else 1.5)
	for y in range(grid_rows + 1):
		var line_color := COLOR_GRID
		if y % 5 == 0:
			line_color = Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bright_alpha)
		draw_line(origin + Vector2(0, y * CELL), origin + Vector2(total_w, y * CELL), line_color, 1.0 if y % 5 != 0 else 1.5)
	_draw_tech_frame(origin, Vector2(total_w, total_h), COLOR_GRID_BRIGHT, 2.0)


func _draw_dataforts(label_font: Font, pulse: float) -> void:
	for df in dataforts:
		var tier: int = int(df.security_tier)
		var tier_color: Color = CP2020SecurityTier.COLORS.get(tier, Color(0.0, 1.0, 0.9, 1.0))
		var center := SCREEN_OFFSET + Vector2(df.pos.x * CELL + CELL / 2.0, df.pos.y * CELL + CELL / 2.0)

		# Neon glow.
		for i in range(3):
			var glow_radius := CELL * (0.55 + i * 0.18)
			var glow_alpha := (0.18 - i * 0.05) * (0.7 + 0.3 * pulse)
			draw_arc(center, glow_radius, 0, TAU, 32, Color(tier_color.r, tier_color.g, tier_color.b, glow_alpha), 3.0)

		# Corner brackets.
		_draw_corner_brackets(center, CELL * 0.55, tier_color, 2.0)

		# Cityscape glyph centered in the tile (tier-colored).
		var glyph_font := _create_datafort_font()
		var glyph_size := 30
		var glyph_dims := glyph_font.get_string_size(BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size)
		var glyph_pos := center - glyph_dims * 0.5 + Vector2(0, glyph_size * 0.35 + 10.0)
		draw_string(glyph_font, glyph_pos, BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size, tier_color)

		# Datafort label centered below the tile.
		var label_size := 11
		var label_dims := label_font.get_string_size(df.name, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
		var label_pos := SCREEN_OFFSET + Vector2(
			df.pos.x * CELL + (CELL - label_dims.x) * 0.5,
			df.pos.y * CELL + CELL + 12
		)
		draw_string(label_font, label_pos, df.name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, COLOR_TEXT_LABEL)


func _draw_ldl_entry(font: Font, pulse: float) -> void:
	if city_grid_layout == null:
		return
	var entry := city_grid_layout.ldl_entry
	var center := SCREEN_OFFSET + Vector2(entry.x * CELL + CELL / 2.0, entry.y * CELL + CELL / 2.0)
	var ring_alpha := 0.6 + 0.4 * pulse
	draw_arc(center, CELL * 0.42, _pulse_time * 2.0, _pulse_time * 2.0 + TAU * 0.85, 24, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, ring_alpha), 2.0)
	var label := "LDL"
	var label_size := 10
	var label_dims := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
	var label_pos := center - label_dims * 0.5 + Vector2(0, label_size * 0.35)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, 0.9))


func _draw_runner(pulse: float) -> void:
	var center := SCREEN_OFFSET + Vector2(runner_pos.x * CELL + CELL / 2.0, runner_pos.y * CELL + CELL / 2.0)
	# Rotating targeting ring.
	var ring_alpha := 0.6 + 0.4 * pulse
	draw_arc(center, CELL * 0.52, _pulse_time * 3.0, _pulse_time * 3.0 + TAU * 0.85, 32, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, ring_alpha), 2.0)
	# Neon glow.
	for i in range(3):
		var glow_radius := CELL * (0.35 + i * 0.12)
		var glow_alpha := (0.2 - i * 0.05) * (0.7 + 0.3 * pulse)
		draw_arc(center, glow_radius, 0, TAU, 32, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, glow_alpha), 2.5)
	# Diamond avatar.
	_draw_diamond(center, CELL * 0.28, COLOR_RUNNER, 2.0)
	# Inner core.
	draw_circle(center, CELL * 0.1, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, 0.8))


func _draw_header(font: Font, pulse: float) -> void:
	const LEGEND_ICON_SIZE := 12
	var title := "CITY GRID // %s" % city_name.to_upper()
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
	var grid_right := SCREEN_OFFSET.x + grid_cols * CELL + 8
	var legend_x := grid_right
	var legend_y := SCREEN_OFFSET.y + 4
	for i in range(CP2020SecurityTier.Tier.size()):
		var tier_color: Color = CP2020SecurityTier.COLORS[i]
		var short := String(CP2020SecurityTier.SHORT[i])
		var legend_font := _create_datafort_font()
		var icon_dims := legend_font.get_string_size(BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, LEGEND_ICON_SIZE)
		var icon_pos := Vector2(legend_x + (LEGEND_ICON_SIZE - icon_dims.x) * 0.5, legend_y + LEGEND_ICON_SIZE - 1)
		draw_string(legend_font, icon_pos, BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, LEGEND_ICON_SIZE, tier_color)
		draw_string(font, Vector2(legend_x + LEGEND_ICON_SIZE + 4, legend_y + 11), short, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85, 0.9))
		legend_y += 16


func _draw_corner_brackets(center: Vector2, half_size: float, color: Color, width: float) -> void:
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


func _draw_tech_frame(origin: Vector2, frame_size: Vector2, color: Color, width: float) -> void:
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


func _draw_diamond(center: Vector2, radius: float, color: Color, width: float) -> void:
	var top := center + Vector2(0, -radius)
	var right := center + Vector2(radius, 0)
	var bottom := center + Vector2(0, radius)
	var left := center + Vector2(-radius, 0)
	draw_line(top, right, color, width)
	draw_line(right, bottom, color, width)
	draw_line(bottom, left, color, width)
	draw_line(left, top, color, width)


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
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			# A dive changes the scene mid-input; stop touching the old node.
			if not is_instance_valid(self):
				return
			_update_hud()
			queue_redraw()
			_check_actions_exhausted()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var grid := _screen_to_grid(get_global_mouse_position())
		if grid == runner_pos:
			_open_return_popup()
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()


func _screen_to_grid(world_pos: Vector2) -> Vector2i:
	var x := int((world_pos.x - SCREEN_OFFSET.x) / CELL)
	var y := int((world_pos.y - SCREEN_OFFSET.y) / CELL)
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


func _on_action_consumed() -> void:
	RunState.net_time_seconds += CP2020TimeScale.CITY_GRID_SECONDS
	_update_clock_label()


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
	POPUP_THEME.apply_cyberpunk_theme(popup, 18)
	popup.add_item("Return to World Map", 998)
	popup.add_item("> Jack Out to Hub", 997)
	popup.add_item("Cancel", 999)
	popup.id_pressed.connect(_on_return_popup_id)
	var world_pos := SCREEN_OFFSET + Vector2(runner_pos.x * CELL + CELL, runner_pos.y * CELL)
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
	elif id == 997:
		_jack_out_to_hub()


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
	RunState.security_dispatch_turns = 0
	RunState.net_time_seconds = 0.0
	RunState.selected_city_grid_path = ""
	RunState.selected_security_tier = 0
	get_tree().change_scene_to_file("res://scenes/ui/cp2020_world_net_map.tscn")


func _jack_out_to_hub() -> void:
	# End the run and return to the Workbench to fence loot/files and gear up.
	print("CITY GRID: Jack Out to Hub. Run trace reset.")
	RunState.accumulated_trace = 0
	RunState.security_dispatch_turns = 0
	RunState.net_time_seconds = 0.0
	RunState.selected_subnet_path = ""
	RunState.selected_city_grid_path = ""
	RunState.selected_security_tier = 0
	get_tree().change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")


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
		if RunState.security_dispatch_turns > 0:
			trace_label.text += "  ⚠ RAID: %d turn(s)" % RunState.security_dispatch_turns
	if location_label:
		var df: Variant = _datafort_at(runner_pos)
		if df != null:
			location_label.text = "LOCATION: %s" % df.name.to_upper()
		else:
			location_label.text = "LOCATION: %s GRID" % city_name.to_upper()
	_update_clock_label()


func _update_clock_label() -> void:
	if clock_label:
		clock_label.text = "NET: %s" % CP2020TimeScale.format_clock(RunState.net_time_seconds)
