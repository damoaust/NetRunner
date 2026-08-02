class_name CP2020WorldNetMap
extends Node2D

# Grid-based world map. Runner spawns on a city hub and moves tile-by-tile
# with a 5-action-per-turn limit (no ICE on the world map). Right-clicking the
# runner's tile when on a city hub offers Pay for LDL / Hack LDL to enter the
# datafort.

signal sub_net_selected(subnet_resource_path: String, target_city: String)

const GRID_COLS: int = 32
const GRID_ROWS: int = 18
const CELL: int = 40

const OCEAN: int = 0
const LAND: int = 1
const HUB: int = 2

var world_tiles: Dictionary = {}  # Vector2i -> int region type
var city_hubs: Array = []           # {name, pos, subnet_path, ldl_cost, ldl_strength}
var runner_pos: Vector2i = Vector2i.ZERO
var interface_rank: int = 6

@onready var turn_manager: CP2020TurnManager = get_node_or_null("TurnManager")
@onready var actions_label: Label = get_node_or_null("HUDOverlay/ActionsLabel")
@onready var credits_label: Label = get_node_or_null("HUDOverlay/CreditsLabel")
@onready var location_label: Label = get_node_or_null("HUDOverlay/LocationLabel")


func _ready() -> void:
	_build_world()
	# Spawn runner on the Night City hub.
	runner_pos = _find_hub("Night City")
	interface_rank = _resolve_interface_rank()
	if turn_manager:
		turn_manager.start_netrunner_turn()
		if not turn_manager.actions_changed.is_connected(_on_actions_changed):
			turn_manager.actions_changed.connect(_on_actions_changed)
	_update_hud()
	queue_redraw()


# ---------------------------------------------------------------------------
# World building
# ---------------------------------------------------------------------------

func _build_world() -> void:
	world_tiles.clear()
	# Default everything to ocean.
	for x in range(GRID_COLS):
		for y in range(GRID_ROWS):
			world_tiles[Vector2i(x, y)] = OCEAN

	# Rough continental landmasses shaded onto the grid.
	_fill_rect(0, 8, 6, 11, LAND)    # Night City region (west coast)
	_fill_rect(0, 11, 4, 14, LAND)
	_fill_rect(10, 3, 18, 9, LAND)   # Europe / London region
	_fill_rect(20, 4, 22, 8, LAND)
	_fill_rect(24, 6, 31, 12, LAND)  # Tokyo / Far East region
	_fill_rect(26, 4, 30, 6, LAND)
	# A few ocean gaps stay open between landmasses.

	# City hubs.
	city_hubs = [
		{
			"name": "Night City",
			"pos": Vector2i(3, 10),
			"subnet_path": "res://scenes/forts/night_city_subnet.tres",
			"ldl_cost": 50,
			"ldl_strength": 4,
		},
		{
			"name": "London",
			"pos": Vector2i(14, 6),
			"subnet_path": "res://scenes/forts/london_subnet.tres",
			"ldl_cost": 80,
			"ldl_strength": 6,
		},
		{
			"name": "Tokyo",
			"pos": Vector2i(28, 9),
			"subnet_path": "res://scenes/forts/tokyo_subnet.tres",
			"ldl_cost": 100,
			"ldl_strength": 8,
		},
	]
	for hub in city_hubs:
		world_tiles[hub.pos] = HUB


func _fill_rect(x0: int, y0: int, x1: int, y1: int, region: int) -> void:
	for x in range(maxi(0, x0), mini(GRID_COLS, x1 + 1)):
		for y in range(maxi(0, y0), mini(GRID_ROWS, y1 + 1)):
			world_tiles[Vector2i(x, y)] = region


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
	var land_color := Color(0.10, 0.30, 0.18, 1.0)
	var grid_color := Color(1, 1, 1, 0.08)
	var hub_color := Color(0.0, 1.0, 0.7, 0.9)
	var hub_outline := Color(0.0, 1.0, 0.9, 1.0)
	var runner_color := Color(0.2, 0.9, 1.0, 1.0)

	for x in range(GRID_COLS):
		for y in range(GRID_ROWS):
			var cell := Vector2i(x, y)
			var rect := Rect2(x * CELL, y * CELL, CELL, CELL)
			match world_tiles.get(cell, OCEAN):
				OCEAN:
					draw_rect(rect, ocean_color, true)
				LAND:
					draw_rect(rect, land_color, true)
				HUB:
					draw_rect(rect, land_color, true)
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
		var grid := _screen_to_grid(event.position)
		if grid == runner_pos and _hub_at(grid) != null:
			_open_ldl_popup(grid)
			get_viewport().set_input_as_handled()


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	# Node2D origin is the viewport top-left; no camera transform on this scene.
	var x := int(screen_pos.x / CELL)
	var y := int(screen_pos.y / CELL)
	return Vector2i(clampi(x, 0, GRID_COLS - 1), clampi(y, 0, GRID_ROWS - 1))


func _try_move(target: Vector2i) -> bool:
	if target.x < 0 or target.x >= GRID_COLS or target.y < 0 or target.y >= GRID_ROWS:
		return false
	var region: int = world_tiles.get(target, OCEAN)
	if region == OCEAN:
		return false  # Can't walk on water.
	if turn_manager != null:
		if not turn_manager.has_actions():
			return false
		if not turn_manager.consume_action():
			return false
	runner_pos = target
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
	add_child(popup)
	popup.id_pressed.connect(_on_ldl_popup_id.bind(hub))
	popup.add_item("Pay for LDL (%d eb)" % hub.ldl_cost, 0)
	popup.add_item("Hack LDL (vs STR %d)" % hub.ldl_strength, 1)
	popup.add_separator()
	popup.add_item("Cancel", 2)
	# Position the popup near the runner tile.
	var screen_pos := Vector2(hub_pos.x * CELL + CELL, hub_pos.y * CELL)
	popup.position = screen_pos + Vector2(20, 20)
	popup.popup()
	popup.set_position(screen_pos + Vector2(20, 20))


func _on_ldl_popup_id(id: int, hub: Dictionary) -> void:
	match id:
		0:
			_pay_for_ldl(hub)
		1:
			_hack_ldl(hub)
		2:
			pass  # Cancel


func _pay_for_ldl(hub: Dictionary) -> void:
	var cost: int = int(hub.ldl_cost)
	if RunState.credits < cost:
		print("WORLD MAP: Insufficient credits (%d eb) for %s LDL (%d eb)." % [RunState.credits, hub.name, cost])
		_update_hud()
		return
	RunState.credits -= cost
	print("WORLD MAP: Paid %d eb for %s LDL. Credits remaining: %d" % [cost, hub.name, RunState.credits])
	_enter_datafort(hub)


func _hack_ldl(hub: Dictionary) -> void:
	var runner_roll := randi_range(1, 10) + interface_rank
	var ice_roll := randi_range(1, 10) + int(hub.ldl_strength)
	print("WORLD MAP: Hack LDL vs %s — runner %d (1d10+%d) vs ICE %d (1d10+%d)." % [hub.name, runner_roll, interface_rank, ice_roll, hub.ldl_strength])
	if runner_roll >= ice_roll:
		print("WORLD MAP: Hack succeeded — entering %s." % hub.name)
		_enter_datafort(hub)
	else:
		var damage := randi_range(1, 6)
		print("WORLD MAP: Hack failed — taking %d damage." % damage)
		# World map has no flatline risk; just log it. The datafort session
		# will apply deck health separately.
		_update_hud()


func _enter_datafort(hub: Dictionary) -> void:
	var subnet_path: String = hub.subnet_path
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
	if location_label:
		var hub: Variant = _hub_at(runner_pos)
		if hub != null:
			location_label.text = "LOCATION: %s" % hub.name.to_upper()
		elif world_tiles.get(runner_pos, OCEAN) == LAND:
			location_label.text = "LOCATION: WILDLANDS"
		else:
			location_label.text = "LOCATION: OCEAN (adrift)"