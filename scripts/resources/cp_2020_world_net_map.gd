class_name CP2020WorldNetMap
extends Node2D

# Grid-based world map. Runner spawns on a city hub and moves tile-by-tile
# with a 5-action-per-turn limit (no ICE on the world map). Right-clicking the
# runner's tile when on a city hub offers Pay for LDL / Hack LDL to enter the
# datafort.
#
# Regions are purely for categorising (colour + HUD location label). The runner
# may traverse any in-bounds tile, including the blue open-ocean areas between
# landmasses. Hubs are an overlay on top of whichever region they sit in.

signal sub_net_selected(subnet_resource_path: String, target_city: String)

const DEFAULT_LAYOUT_PATH: String = "res://data/world_map_default.tres"
const FRAME_PATH: String = "res://data/world_map_frame.png"
const GRID_PATH: String = "res://data/world_map_grid.png"
const CELL: int = 40
const W: int = 1920
const H: int = 1080
const SCREEN_OFFSET: Vector2 = Vector2(20, 60)
const POPUP_THEME := preload("res://scripts/resources/cp2020_theme.gd")

const OPEN_OCEAN_NAME: String = "OPEN OCEAN"

# Cyberpunk/neon palette.
const COLOR_BG: Color = Color(0.02, 0.03, 0.06, 1.0)
const COLOR_GRID: Color = Color(0.0, 0.78, 0.92, 0.22)
const COLOR_GRID_BRIGHT: Color = Color(0.0, 0.9, 1.0, 0.55)
const COLOR_RUNNER: Color = Color(0.0, 1.0, 1.0, 1.0)
const COLOR_SCANLINE: Color = Color(0.0, 0.0, 0.0, 0.12)
const COLOR_HUB_GLOW: Color = Color(0.0, 1.0, 0.9, 0.35)
const COLOR_TEXT_HEADER: Color = Color(0.85, 0.95, 1.0, 0.95)
const COLOR_TEXT_LABEL: Color = Color(0.7, 0.9, 1.0, 0.9)

# Data source for the world map. Authored by the world map designer and saved
# as a .tres; the runtime loads it here. If unassigned, falls back to
# DEFAULT_LAYOUT_PATH.
@export var world_map_layout: CP2020WorldMapLayout

# Local caches built from world_map_layout in _build_world(). Kept as plain
# arrays/dicts so the draw/HUD/movement code stays unchanged.
var grid_cols: int = 32
var grid_rows: int = 18
var regions: Array = []              # [{name, color}]
var tile_region: Dictionary = {}     # Vector2i -> int region index
var hub_tiles: Dictionary = {}       # Vector2i -> true (overlay marker)
var city_hubs: Array = []            # {name, pos, subnet_path, ldl_cost, security_code, trace_value}
var backdrop_texture: Texture2D = null
var frame_texture: Texture2D = null
var grid_texture: Texture2D = null
var runner_pos: Vector2i = Vector2i.ZERO
var interface_rank: int = 6
var spawn_hub_name: String = ""

@onready var turn_manager: CP2020TurnManager = get_node_or_null("TurnManager")
@onready var actions_label: Label = get_node_or_null("HUDLayer/HUDOverlay/ActionsLabel")
@onready var credits_label: Label = get_node_or_null("HUDLayer/HUDOverlay/CreditsLabel")
@onready var location_label: Label = get_node_or_null("HUDLayer/HUDOverlay/LocationLabel")
@onready var trace_label: Label = get_node_or_null("HUDLayer/HUDOverlay/TraceLabel")
@onready var camera: Camera2D = get_node_or_null("RunnerCamera")

# Nearby hubs offered in the current jump/dive popup (survives the signal
# callback, mirroring the interaction_handler _current_programs pattern).
var _popup_nearby: Array = []

# Animation state for pulsing neon elements.
var _pulse_time: float = 0.0


func _ready() -> void:
	_build_world()
	# Spawn runner on the layout's configured spawn hub (Night City fallback).
	var spawn_name: String = "Night City"
	if world_map_layout != null and world_map_layout.runner_spawn_hub != "":
		spawn_name = world_map_layout.runner_spawn_hub
	spawn_hub_name = spawn_name
	runner_pos = _find_hub(spawn_name)
	interface_rank = _resolve_interface_rank()
	if turn_manager:
		turn_manager.start_netrunner_turn()
		if not turn_manager.actions_changed.is_connected(_on_actions_changed):
			turn_manager.actions_changed.connect(_on_actions_changed)
	_update_hud()
	_update_camera_limits()
	_center_camera_on_runner()
	queue_redraw()


func _process(_delta: float) -> void:
	_pulse_time += _delta
	queue_redraw()


# ---------------------------------------------------------------------------
# Camera follow
# ---------------------------------------------------------------------------

func _update_camera_limits() -> void:
	if camera == null:
		return
	# Clamp the camera so it can always show the full grid plus its margins.
	# The grid content occupies SCREEN_OFFSET.x .. right and SCREEN_OFFSET.y .. bottom.
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
# World building
# ---------------------------------------------------------------------------

func _build_world() -> void:
	tile_region.clear()
	hub_tiles.clear()
	regions.clear()
	city_hubs.clear()

	if world_map_layout == null:
		if ResourceLoader.exists(DEFAULT_LAYOUT_PATH):
			world_map_layout = ResourceLoader.load(DEFAULT_LAYOUT_PATH) as CP2020WorldMapLayout
	if world_map_layout == null:
		push_error("WORLD MAP: No world_map_layout assigned and default layout missing at %s" % DEFAULT_LAYOUT_PATH)
		return

	grid_cols = world_map_layout.grid_cols
	grid_rows = world_map_layout.grid_rows

	# Frame + grid layer (CRT-bezel with Pacifica content). Optional — falls
	# back to solid ocean if missing.
	if ResourceLoader.exists(FRAME_PATH):
		frame_texture = load(FRAME_PATH) as Texture2D
	if ResourceLoader.exists(GRID_PATH):
		grid_texture = load(GRID_PATH) as Texture2D

	# Regions (categorising only — colour + HUD label; never block movement).
	for region in world_map_layout.regions:
		if region is CP2020WorldRegion:
			regions.append({"name": region.name, "color": region.color})

	# Per-tile region assignment. Keys may be Vector2i or "x,y" strings.
	for raw_key in world_map_layout.tile_region.keys():
		var coord: Vector2i = _parse_coord(raw_key)
		tile_region[coord] = int(world_map_layout.tile_region[raw_key])

	# City hubs (overlay markers; their tile keeps its underlying region).
	for hub in world_map_layout.hubs:
		if hub is CP2020WorldHub:
			city_hubs.append({
				"name": hub.name,
				"pos": hub.pos,
				"subnet_path": hub.subnet_path,
				"city_grid_path": hub.city_grid_path,
				"ldl_cost": hub.ldl_cost,
				"security_code": hub.security_code,
				"trace_value": hub.trace_value,
				"security_tier": int(hub.security_tier),
			})
			hub_tiles[hub.pos] = true


func _parse_coord(raw_key: Variant) -> Vector2i:
	if raw_key is Vector2i:
		return raw_key
	var parts := String(raw_key).split(",")
	return Vector2i(parts[0].to_int(), parts[1].to_int())


func _find_hub(city_name: String) -> Vector2i:
	for hub in city_hubs:
		if hub.name == city_name:
			return hub.pos
	return Vector2i.ZERO


func _hub_at(pos: Vector2i) -> Variant:
	for hub in city_hubs:
		if hub.pos == pos:
			return hub
	return null


func _resolve_interface_rank() -> int:
	# Default to 6; pull from the loaded deck if available.
	var deck = RunState.selected_deck
	if deck != null and "interface_rank" in deck:
		return int(deck.interface_rank)
	return 6


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var font := _theme_font()
	var pulse := _pulse_value()

	_draw_background(pulse)
	_draw_scanlines()
	_draw_region_fills(pulse)
	_draw_grid(pulse)
	_draw_hubs(font, pulse)
	_draw_runner(pulse)
	_draw_header(font, pulse)


func _pulse_value() -> float:
	return 0.5 + 0.5 * sin(_pulse_time * 3.0)


func _draw_background(pulse: float) -> void:
	# Deep-space ocean fill.
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), COLOR_BG, true)

	# Subtle vignette: darkens edges so the neon grid pops.
	var vignette := Color(0.0, 0.0, 0.0, 0.35)
	var top := Rect2(0, 0, W, 120)
	var bottom := Rect2(0, H - 120, W, 120)
	var left := Rect2(0, 0, 120, H)
	var right := Rect2(W - 120, 0, 120, H)
	draw_rect(top, vignette, true)
	draw_rect(bottom, vignette, true)
	draw_rect(left, vignette, true)
	draw_rect(right, vignette, true)

	# Decorative horizon scan band behind the grid.
	var band_alpha := 0.04 + 0.03 * pulse
	draw_rect(Rect2(0, SCREEN_OFFSET.y - 4, W, 4), Color(COLOR_GRID.r, COLOR_GRID.g, COLOR_GRID.b, band_alpha), true)


func _draw_scanlines() -> void:
	# Classic CRT scanline overlay across the whole screen.
	var y: float = 0.0
	while y < H:
		draw_line(Vector2(0, y), Vector2(W, y), COLOR_SCANLINE, 1.0)
		y += 4.0


func _draw_grid(pulse: float) -> void:
	# Neon grid lines. Major divisions every 5 cells get a brighter pulse.
	var origin := SCREEN_OFFSET
	var grid_w := grid_cols * CELL
	var grid_h := grid_rows * CELL
	var bright_alpha := COLOR_GRID_BRIGHT.a * (0.5 + 0.5 * pulse)

	for x in range(grid_cols + 1):
		var line_color := COLOR_GRID
		if x % 5 == 0:
			line_color = Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bright_alpha)
		draw_line(origin + Vector2(x * CELL, 0), origin + Vector2(x * CELL, grid_h), line_color, 1.0 if x % 5 != 0 else 1.5)

	for y in range(grid_rows + 1):
		var line_color := COLOR_GRID
		if y % 5 == 0:
			line_color = Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, bright_alpha)
		draw_line(origin + Vector2(0, y * CELL), origin + Vector2(grid_w, y * CELL), line_color, 1.0 if y % 5 != 0 else 1.5)

	# Outer tech frame around the grid.
	_draw_tech_frame(origin, Vector2(grid_w, grid_h), COLOR_GRID_BRIGHT, 2.0)


func _draw_region_fills(pulse: float) -> void:
	# Dark neon region tiles with a soft inner glow.
	for raw_key in tile_region.keys():
		var coord: Vector2i = _parse_coord(raw_key)
		var idx: int = int(tile_region[raw_key])
		if idx < 0 or idx >= regions.size():
			continue
		var base: Color = regions[idx].color
		var rect := Rect2(SCREEN_OFFSET + Vector2(coord.x * CELL, coord.y * CELL), Vector2(CELL, CELL))
		# Darkened fill so the grid still reads through it.
		var fill := Color(base.r * 0.35, base.g * 0.35, base.b * 0.35, 0.55)
		draw_rect(rect, fill, true)
		# Subtle top edge highlight.
		var highlight := Color(base.r, base.g, base.b, 0.35 + 0.15 * pulse)
		draw_line(rect.position, rect.position + Vector2(CELL, 0), highlight, 1.5)


func _draw_hubs(font: Font, pulse: float) -> void:
	for hub in city_hubs:
		var center := SCREEN_OFFSET + Vector2(hub.pos.x * CELL + CELL / 2.0, hub.pos.y * CELL + CELL / 2.0)
		var tier: int = clampi(int(hub.get("security_tier", 0)), 0, CP2020SecurityTier.Tier.size() - 1)
		var tier_color: Color = CP2020SecurityTier.COLORS[tier]
		var glyph: String = CP2020SecurityTier.GLYPHS[tier]

		# Tier-colored neon glow behind the hub.
		for i in range(3):
			var glow_radius := CELL * (0.55 + i * 0.18)
			var glow_alpha := (0.18 - i * 0.05) * (0.7 + 0.3 * pulse)
			draw_arc(center, glow_radius, 0, TAU, 32, Color(tier_color.r, tier_color.g, tier_color.b, glow_alpha), 3.0)

		# Tech corner brackets.
		_draw_corner_brackets(center, CELL * 0.55, tier_color, 2.0)

		# Central tier glyph.
		var glyph_size := 16
		var glyph_dims := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size)
		var glyph_pos := center - glyph_dims * 0.5 + Vector2(0, glyph_size * 0.35)
		draw_string(font, glyph_pos, glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size, tier_color)

		# City label below the marker.
		var label_pos := SCREEN_OFFSET + Vector2(hub.pos.x * CELL + 4, hub.pos.y * CELL + CELL + 4)
		draw_string(font, label_pos, hub.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_LABEL)

		# Spawn hub: rotating cyan ring + LDL tag.
		if hub.name == spawn_hub_name:
			var ring_alpha := 0.6 + 0.4 * pulse
			draw_arc(center, CELL * 0.52, _pulse_time * 2.0, _pulse_time * 2.0 + TAU * 0.85, 32, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, ring_alpha), 2.5)
			draw_string(font, Vector2(center.x - 12, center.y + 26), "LDL", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, COLOR_RUNNER)


func _draw_runner(pulse: float) -> void:
	var center := SCREEN_OFFSET + Vector2(runner_pos.x * CELL + CELL / 2.0, runner_pos.y * CELL + CELL / 2.0)
	var size := CELL * 0.32 * (0.9 + 0.1 * pulse)

	# Outer rotating targeting ring.
	var ring_alpha := 0.5 + 0.3 * pulse
	draw_arc(center, CELL * 0.48, -_pulse_time * 3.0, -_pulse_time * 3.0 + TAU * 0.9, 32, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, ring_alpha), 2.0)

	# Neon glow.
	for i in range(3):
		var glow_size := size + i * 4.0
		var glow_alpha := 0.25 - i * 0.07
		_draw_diamond(center, glow_size, Color(COLOR_RUNNER.r, COLOR_RUNNER.g, COLOR_RUNNER.b, glow_alpha), true)

	# Solid diamond avatar.
	_draw_diamond(center, size, COLOR_RUNNER, true)
	_draw_diamond(center, size * 0.7, Color(0.0, 0.0, 0.0, 0.6), true)


func _draw_diamond(center: Vector2, size: float, color: Color, filled: bool) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(size, 0),
		center + Vector2(0, size),
		center + Vector2(-size, 0),
	])
	if filled:
		draw_polygon(points, PackedColorArray([color, color, color, color]))
	else:
		points.append(points[0])
		draw_polyline(points, color, 2.0)


func _draw_corner_brackets(center: Vector2, half_size: float, color: Color, width: float) -> void:
	var inset := half_size * 0.55
	var tl := center + Vector2(-half_size, -half_size)
	var top_r := center + Vector2(half_size, -half_size)
	var bl := center + Vector2(-half_size, half_size)
	var bottom_r := center + Vector2(half_size, half_size)
	# Top-left.
	draw_line(tl, tl + Vector2(inset, 0), color, width)
	draw_line(tl, tl + Vector2(0, inset), color, width)
	# Top-right.
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width)
	draw_line(top_r, top_r + Vector2(0, inset), color, width)
	# Bottom-left.
	draw_line(bl, bl + Vector2(inset, 0), color, width)
	draw_line(bl, bl + Vector2(0, -inset), color, width)
	# Bottom-right.
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width)


func _draw_tech_frame(origin: Vector2, size: Vector2, color: Color, width: float) -> void:
	var tl := origin
	var top_r := origin + Vector2(size.x, 0)
	var bl := origin + Vector2(0, size.y)
	var bottom_r := origin + size
	var inset := 18.0
	# Outer rectangle.
	draw_rect(Rect2(origin, size), color, false, width)
	# Corner accents.
	draw_line(tl, tl + Vector2(inset, 0), color, width + 1.0)
	draw_line(tl, tl + Vector2(0, inset), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(0, inset), color, width + 1.0)
	draw_line(bl, bl + Vector2(inset, 0), color, width + 1.0)
	draw_line(bl, bl + Vector2(0, -inset), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width + 1.0)


func _draw_header(font: Font, pulse: float) -> void:
	# Cyberpunk header bar with tech brackets, drawn below the HUD strip so
	# it never overlaps the Location/Actions/Credits/Trace labels.
	var header_y := 48.0
	var title := "WORLD NET MAP // PACIFIC RIM"
	draw_string(font, Vector2(18, header_y), "[", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, 0.7 + 0.3 * pulse))
	draw_string(font, Vector2(30, header_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT_HEADER)
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(34 + title_width, header_y), "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(COLOR_GRID_BRIGHT.r, COLOR_GRID_BRIGHT.g, COLOR_GRID_BRIGHT.b, 0.7 + 0.3 * pulse))

	# Thin underline with a travelling pulse.
	var line_y := header_y + 8
	var pulse_x := 30 + fmod(_pulse_time * 80.0, title_width + 20)
	draw_line(Vector2(18, line_y), Vector2(36 + title_width, line_y), COLOR_GRID_BRIGHT, 1.0)
	draw_circle(Vector2(30 + pulse_x, line_y), 3.0, COLOR_RUNNER)


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
		# Right-click on the runner's tile. On a hub, show the full LDL popup
		# (enter city grid, jump, jack out). Off-hub, show a minimal jack-out
		# popup so the runner can always exit to the Workbench.
		var grid := _screen_to_grid(get_global_mouse_position())
		if grid == runner_pos:
			if _hub_at(grid) != null:
				_open_ldl_popup(grid)
			else:
				_open_jackout_popup()
			get_viewport().set_input_as_handled()


func _screen_to_grid(world_pos: Vector2) -> Vector2i:
	# Convert a world position (under the cursor) to a grid cell. The map grid
	# is anchored at SCREEN_OFFSET, so subtract that before dividing by CELL.
	var local := world_pos - SCREEN_OFFSET
	var x := int(local.x / CELL)
	var y := int(local.y / CELL)
	return Vector2i(clampi(x, 0, grid_cols - 1), clampi(y, 0, grid_rows - 1))


func _try_move(target: Vector2i) -> bool:
	# Regions are categorising only — the runner may traverse any in-bounds
	# tile, including the blue open-ocean areas.
	if target.x < 0 or target.x >= grid_cols or target.y < 0 or target.y >= grid_rows:
		return false
	if turn_manager != null:
		if not turn_manager.has_actions():
			return false
		if not turn_manager.consume_action():
			return false
	runner_pos = target
	_center_camera_on_runner()
	return true


func _check_actions_exhausted() -> void:
	if turn_manager != null and not turn_manager.has_actions():
		# No ICE on the world map; just refresh the action pool.
		turn_manager.start_netrunner_turn()


func _on_actions_changed(remaining: int, max_actions: int) -> void:
	if actions_label:
		actions_label.text = "ACTIONS: %d/%d" % [remaining, max_actions]


# ---------------------------------------------------------------------------
# LDL entry popup
# ---------------------------------------------------------------------------

func _open_ldl_popup(hub_pos: Vector2i) -> void:
	var hub: Dictionary = _hub_at(hub_pos)
	if hub == null:
		return
	var popup := PopupMenu.new()
	# Parent to the HUD CanvasLayer so the popup stays in screen space (the
	# RunnerCamera scrolls anything under the Node2D root).
	var hud_layer := get_node_or_null("HUDLayer")
	if hud_layer != null:
		hud_layer.add_child(popup)
	else:
		add_child(popup)

	POPUP_THEME.apply_cyberpunk_theme(popup, 18)

	# Build the nearby-hub jump list (Chebyshev <= 5, excluding self).
	_popup_nearby = _nearby_hubs(hub_pos)

	# Enter the city's City Grid. Trace is built by inter-city jumps, not by
	# entering a city, so the enter itself adds no trace.
	popup.add_item("ENTER %s City Grid" % hub.name, 0)
	popup.add_separator()
	for i in range(_popup_nearby.size()):
		var dest: Dictionary = _popup_nearby[i]
		popup.add_item("Hack LDL -> %s (Sec %d, +Trace %d)" % [dest.name, int(dest.security_code), int(dest.trace_value)], 100 + i)
		popup.add_item("Pay LDL -> %s (%d eb)" % [dest.name, int(dest.ldl_cost)], 200 + i)
	popup.add_separator()
	popup.add_item("> Jack Out to Hub", 998)
	popup.add_item("Cancel", 999)

	popup.id_pressed.connect(_on_ldl_popup_id.bind(hub))
	# Position the popup near the hub in screen coordinates.
	var world_pos := SCREEN_OFFSET + Vector2(hub_pos.x * CELL + CELL, hub_pos.y * CELL)
	var screen_pos := _world_to_screen(world_pos) + Vector2(20, 20)
	popup.position = screen_pos
	popup.popup()
	popup.set_position(screen_pos)


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _nearby_hubs(pos: Vector2i) -> Array:
	var out: Array = []
	for hub in city_hubs:
		if hub.pos == pos:
			continue
		if _chebyshev(pos, hub.pos) <= 5:
			out.append(hub)
	return out


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	var vp_size := vp.get_visible_rect().size
	if camera == null:
		return world_pos
	var zoom := camera.zoom
	var screen_center := camera.get_screen_center_position()
	return (world_pos - screen_center) * zoom + vp_size * 0.5


func _on_ldl_popup_id(id: int, hub: Dictionary) -> void:
	if id == 0:
		_enter_city_grid(hub)
		return
	if id == 998:
		_jack_out_to_hub()
		return
	if id == 999:
		return  # Cancel
	if id >= 100 and id < 100 + _popup_nearby.size():
		_hack_jump(_popup_nearby[id - 100])
		return
	if id >= 200 and id < 200 + _popup_nearby.size():
		_pay_jump(_popup_nearby[id - 200])
		return


func _jack_out_to_hub() -> void:
	# End the run and return to the Workbench to fence loot/files and gear up.
	print("WORLD MAP: Jack Out to Hub. Run trace reset.")
	RunState.accumulated_trace = 0
	RunState.selected_subnet_path = ""
	RunState.selected_city_grid_path = ""
	RunState.selected_security_tier = 0
	get_tree().change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")


func _open_jackout_popup() -> void:
	# Minimal popup for jacking out when right-clicking off-hub.
	var popup := PopupMenu.new()
	var hud_layer := get_node_or_null("HUDLayer")
	if hud_layer != null:
		hud_layer.add_child(popup)
	else:
		add_child(popup)
	POPUP_THEME.apply_cyberpunk_theme(popup, 18)
	popup.add_item("> Jack Out to Hub", 998)
	popup.add_item("Cancel", 999)
	popup.id_pressed.connect(_on_jackout_popup_id)
	var world_pos := SCREEN_OFFSET + Vector2(runner_pos.x * CELL + CELL, runner_pos.y * CELL)
	var screen_pos := _world_to_screen(world_pos) + Vector2(20, 20)
	popup.position = screen_pos
	popup.popup()
	popup.set_position(screen_pos)


func _on_jackout_popup_id(id: int) -> void:
	if id == 998:
		_jack_out_to_hub()


func _hack_jump(dest: Dictionary) -> void:
	# Security Code rule: roll 1D10 >= destination security_code to scam the
	# LDL. Success builds trace and teleports; failure hits the caught table.
	var roll := randi_range(1, 10)
	print("WORLD MAP: Hack LDL -> %s — 1D10 %d vs Security Code %d." % [dest.name, roll, int(dest.security_code)])
	if roll >= int(dest.security_code):
		RunState.accumulated_trace += int(dest.trace_value)
		runner_pos = dest.pos
		_center_camera_on_runner()
		print("WORLD MAP: Jumped to %s. Run trace difficulty: %d" % [dest.name, RunState.accumulated_trace])
		_update_hud()
		queue_redraw()
		return
	print("WORLD MAP: Hack failed — caught scamming the LDL.")
	_caught_table(dest)


func _pay_jump(dest: Dictionary) -> void:
	var cost: int = int(dest.ldl_cost)
	if RunState.credits < cost:
		print("WORLD MAP: Insufficient credits (%d eb) for %s LDL (%d eb)." % [RunState.credits, dest.name, cost])
		_update_hud()
		return
	RunState.credits -= cost
	RunState.accumulated_trace += int(dest.trace_value)
	runner_pos = dest.pos
	_center_camera_on_runner()
	print("WORLD MAP: Paid %d eb, jumped to %s. Run trace difficulty: %d" % [cost, dest.name, RunState.accumulated_trace])
	_update_hud()
	queue_redraw()


func _caught_table(hub: Dictionary) -> void:
	# 1D6 immediate consequences for a failed LDL hack (no persistent state).
	var caught := randi_range(1, 6)
	print("WORLD MAP: NETWATCH roll 1D6 = %d" % caught)
	match caught:
		1, 2, 3, 4:
			var charge: int = int(hub.ldl_cost)
			RunState.credits = maxi(0, RunState.credits - charge)
			print("WORLD MAP: Cut off and charged for the call (-%d eb). Credits: %d" % [charge, RunState.credits])
		5:
			print("WORLD MAP: Cut off. NETWATCH has your access code — expect company in Realspace.")
		6:
			_handle_netcop_bust()
	_update_hud()


func _handle_netcop_bust() -> void:
	var bust := randi_range(1, 6)
	print("WORLD MAP: NetCops bust attempt — 1D6 = %d" % bust)
	match bust:
		1, 2:
			var fine := randi_range(1, 6) * 100
			RunState.credits = maxi(0, RunState.credits - fine)
			print("WORLD MAP: Fined %d eb. Credits: %d" % [fine, RunState.credits])
		3, 4, 5:
			var days := randi_range(1, 6) + 1
			print("WORLD MAP: You escape. NetCops patrol the area %d days hoping you show up." % days)
		6:
			print("WORLD MAP: You escape, but an All-Net Bulletin is issued. They are looking for you.")


func _enter_city_grid(hub: Dictionary) -> void:
	var grid_path: String = String(hub.get("city_grid_path", ""))
	if grid_path == "":
		print("WORLD MAP: %s has no City Grid assigned." % hub.name)
		_update_hud()
		return
	# Trace is built by inter-city LDL jumps; entering a city adds none.
	print("WORLD MAP: Entering %s City Grid. Run trace difficulty: %d" % [hub.name, RunState.accumulated_trace])
	RunState.selected_city_grid_path = grid_path
	get_tree().change_scene_to_file("res://scenes/ui/cp2020_city_grid.tscn")


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
		var hub: Variant = _hub_at(runner_pos)
		if hub != null:
			location_label.text = "LOCATION: %s" % hub.name.to_upper()
		else:
			var region_index: int = tile_region.get(runner_pos, -1)
			if region_index >= 0 and region_index < regions.size():
				location_label.text = "LOCATION: %s" % regions[region_index].name
			else:
				location_label.text = "LOCATION: %s" % OPEN_OCEAN_NAME
