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
const CELL: int = 40

const OPEN_OCEAN_NAME: String = "OPEN OCEAN"

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
var runner_pos: Vector2i = Vector2i.ZERO
var interface_rank: int = 6

@onready var turn_manager: CP2020TurnManager = get_node_or_null("TurnManager")
@onready var actions_label: Label = get_node_or_null("HUDLayer/HUDOverlay/ActionsLabel")
@onready var credits_label: Label = get_node_or_null("HUDLayer/HUDOverlay/CreditsLabel")
@onready var location_label: Label = get_node_or_null("HUDLayer/HUDOverlay/LocationLabel")
@onready var trace_label: Label = get_node_or_null("HUDLayer/HUDOverlay/TraceLabel")
@onready var camera: Camera2D = get_node_or_null("RunnerCamera")

# Nearby hubs offered in the current jump/dive popup (survives the signal
# callback, mirroring the interaction_handler _current_programs pattern).
var _popup_nearby: Array = []


func _ready() -> void:
	_build_world()
	# Spawn runner on the layout's configured spawn hub (Night City fallback).
	var spawn_name: String = "Night City"
	if world_map_layout != null and world_map_layout.runner_spawn_hub != "":
		spawn_name = world_map_layout.runner_spawn_hub
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


# ---------------------------------------------------------------------------
# Camera follow
# ---------------------------------------------------------------------------

func _update_camera_limits() -> void:
	if camera == null:
		return
	# Clamp the camera so it never shows outside the world map rectangle.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = grid_cols * CELL
	camera.limit_bottom = grid_rows * CELL


func _center_camera_on_runner() -> void:
	if camera == null:
		return
	var center := Vector2(runner_pos.x * CELL + CELL / 2.0, runner_pos.y * CELL + CELL / 2.0)
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
				"ldl_cost": hub.ldl_cost,
				"security_code": hub.security_code,
				"trace_value": hub.trace_value,
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
	var ocean_color := Color(0.05, 0.12, 0.25, 1.0)
	var grid_color := Color(1, 1, 1, 0.08)
	var hub_color := Color(0.0, 1.0, 0.7, 0.9)
	var hub_outline := Color(0.0, 1.0, 0.9, 1.0)
	var runner_color := Color(0.2, 0.9, 1.0, 1.0)

	for x in range(grid_cols):
		for y in range(grid_rows):
			var cell := Vector2i(x, y)
			var rect := Rect2(x * CELL, y * CELL, CELL, CELL)
			# Colour by region (categorising only). Absence == open ocean.
			var region_index: int = tile_region.get(cell, -1)
			if region_index >= 0 and region_index < regions.size():
				draw_rect(rect, regions[region_index].color, true)
			else:
				draw_rect(rect, ocean_color, true)
			# Hub overlay outline.
			if hub_tiles.get(cell, false):
				draw_rect(rect, hub_color, false, 2.0)
			# Grid lines.
			draw_rect(rect, grid_color, false, 1.0)

	# Hub labels.
	for hub in city_hubs:
		var label_pos := Vector2(hub.pos.x * CELL + 4, hub.pos.y * CELL + CELL + 2)
		draw_string(_theme_font(), label_pos, hub.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hub_outline)

	# Runner avatar (cyan circle).
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
		# Right-click: if the clicked tile is the runner's tile and it's a hub, show popup.
		var grid := _screen_to_grid(get_global_mouse_position())
		if grid == runner_pos and _hub_at(grid) != null:
			_open_ldl_popup(grid)
			get_viewport().set_input_as_handled()


func _screen_to_grid(world_pos: Vector2) -> Vector2i:
	# Convert a world position (under the cursor) to a grid cell. The Node2D
	# sits at the origin with identity transform, so world == local here.
	var x := int(world_pos.x / CELL)
	var y := int(world_pos.y / CELL)
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

	# Build the nearby-hub jump list (Chebyshev <= 5, excluding self).
	_popup_nearby = _nearby_hubs(hub_pos)

	# Dive into the current hub's datafort. Trace is built by jumps, not by
	# diving, so the dive itself adds no trace.
	popup.add_item("DIVE into %s datafort" % hub.name, 0)
	popup.add_separator()
	for i in range(_popup_nearby.size()):
		var dest: Dictionary = _popup_nearby[i]
		popup.add_item("Hack LDL -> %s (Sec %d, +Trace %d)" % [dest.name, int(dest.security_code), int(dest.trace_value)], 100 + i)
		popup.add_item("Pay LDL -> %s (%d eb)" % [dest.name, int(dest.ldl_cost)], 200 + i)
	popup.add_separator()
	popup.add_item("Cancel", 999)

	popup.id_pressed.connect(_on_ldl_popup_id.bind(hub))
	# Position the popup near the hub in screen coordinates.
	var world_pos := Vector2(hub_pos.x * CELL + CELL, hub_pos.y * CELL)
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
		_dive_datafort(hub)
		return
	if id == 999:
		return  # Cancel
	if id >= 100 and id < 100 + _popup_nearby.size():
		_hack_jump(_popup_nearby[id - 100])
		return
	if id >= 200 and id < 200 + _popup_nearby.size():
		_pay_jump(_popup_nearby[id - 200])
		return


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


func _pay_for_ldl(hub: Dictionary) -> void:
	# Legacy single-hub pay entry — dives into the datafort (no trace added).
	var cost: int = int(hub.ldl_cost)
	if RunState.credits < cost:
		print("WORLD MAP: Insufficient credits (%d eb) for %s LDL (%d eb)." % [RunState.credits, hub.name, cost])
		_update_hud()
		return
	RunState.credits -= cost
	print("WORLD MAP: Paid %d eb for %s LDL. Credits remaining: %d" % [cost, hub.name, RunState.credits])
	_dive_datafort(hub)


func _hack_ldl(hub: Dictionary) -> void:
	# Legacy single-hub hack entry — dives into the datafort on success.
	var roll := randi_range(1, 10)
	print("WORLD MAP: Hack LDL vs %s — 1D10 %d vs Security Code %d." % [hub.name, roll, int(hub.security_code)])
	if roll >= int(hub.security_code):
		print("WORLD MAP: Hack succeeded — entering %s." % hub.name)
		_dive_datafort(hub)
		return
	print("WORLD MAP: Hack failed — caught scamming the LDL.")
	_caught_table(hub)


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


func _dive_datafort(hub: Dictionary) -> void:
	var subnet_path: String = hub.subnet_path
	# Trace is built by hub-to-hub LDL jumps; diving itself adds none.
	print("WORLD MAP: Diving into %s. Run trace difficulty: %d" % [hub.name, RunState.accumulated_trace])
	RunState.selected_subnet_path = subnet_path
	sub_net_selected.emit(subnet_path, hub.name)
	get_tree().change_scene_to_file("res://scenes/cp2020_gameplay.tscn")


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