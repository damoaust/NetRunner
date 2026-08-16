class_name CP2020WorldNetMap
extends Node2D

# Grid-based world map. Runner spawns on a city hub and moves tile-by-tile
# with a 5-action-per-turn limit (no ICE on the world map). A persistent LDL
# command panel (right side of the HUD) lists all hackable LDLs (any range —
# the runner, plus ENTER City Grid (when on a hub) and Jack Out. Hacking an
# LDL is a raw 1D10 roll vs the LDL's Security Level (CP2020 RAW: no STAT +
# Skill added); a failure just drops the line (no trace, no auto-NetWatch).
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

# Terminal log line colours (cyberpunk feed prefixes).
const COLOR_LOG_SYS: Color = Color(0.0, 0.9, 1.0, 1.0)    # cyan — system/info
const COLOR_LOG_OK: Color = Color(0.2, 1.0, 0.5, 1.0)     # green — success
const COLOR_LOG_WARN: Color = Color(1.0, 0.75, 0.2, 1.0)  # amber — warning
const COLOR_LOG_FAIL: Color = Color(1.0, 0.3, 0.3, 1.0)   # red — failure

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
@onready var clock_label: Label = get_node_or_null("HUDLayer/HUDOverlay/ClockLabel")
@onready var camera: Camera2D = get_node_or_null("RunnerCamera")
# Terminal log feed (scene-tree node under HUDOverlay). Append colour-coded
# bbcode lines via _log_terminal(); auto-scrolls via scroll_following.
@onready var terminal_log: RichTextLabel = get_node_or_null("HUDLayer/HUDOverlay/TerminalPanel/TerminalMargin/TerminalVBox/TerminalLog")
@onready var _ldl_list: ItemList = get_node_or_null("HUDLayer/HUDOverlay/LDLPanel/LDLMargin/LDLVBox/LDLList")
@onready var _ldl_enter_button: Button = get_node_or_null("HUDLayer/HUDOverlay/LDLPanel/LDLMargin/LDLVBox/LDLEnterButton")

# LDL command panel (scene-tree nodes under HUDLayer/HUDOverlay/LDLPanel).
# Replaces the old right-click popup. The list section rebuilds on every
# _update_hud() so it stays in sync with the runner's position.
# Cached nearby-hub dictionaries + the bound dest for each list button, so
# the button signal callbacks can resolve which hub was clicked.
var _ldl_panel_hubs: Array = []

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
		if not turn_manager.action_consumed.is_connected(_on_action_consumed):
			turn_manager.action_consumed.connect(_on_action_consumed)
	_init_ldl_panel()
	_log_terminal("NET MAP ONLINE // jackpoint: %s" % spawn_hub_name, COLOR_LOG_SYS)
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
		return int(deck.effective_interface_rank())
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
	# Log arrival when stepping onto a city hub (movement signal without
	# spamming every ocean tile).
	var hub: Variant = _hub_at(target)
	if hub != null:
		_log_terminal("ARRIVED @ %s" % String(hub.name), COLOR_LOG_SYS)
	return true


func _check_actions_exhausted() -> void:
	if turn_manager != null and not turn_manager.has_actions():
		# No ICE on the world map; just refresh the action pool.
		turn_manager.start_netrunner_turn()


func _on_actions_changed(remaining: int, max_actions: int) -> void:
	if actions_label:
		actions_label.text = "ACTIONS: %d/%d" % [remaining, max_actions]


func _on_action_consumed() -> void:
	RunState.net_time_seconds += CP2020TimeScale.WORLD_MAP_SECONDS
	_update_clock_label()


# ---------------------------------------------------------------------------
# Terminal log feed
# ---------------------------------------------------------------------------

# Append a colour-coded line to the on-screen terminal log. No-op if the
# scene node is missing. Lines are prefixed with a `> ` prompt and capped at
# ~200 entries so the feed stays bounded over a long session.
func _log_terminal(msg: String, color: Color = COLOR_LOG_SYS) -> void:
	if terminal_log == null:
		return
	var hex: String = "#%02x%02x%02x" % [int(round(color.r * 255.0)), int(round(color.g * 255.0)), int(round(color.b * 255.0))]
	terminal_log.text += "[color=%s]> %s[/color]\n" % [hex, msg]
	# Trim oldest lines once over the cap (drop everything up to the Nth line).
	const MAX_LINES: int = 200
	var lines: PackedStringArray = terminal_log.text.split("\n")
	if lines.size() > MAX_LINES:
		terminal_log.text = "\n".join(lines.slice(lines.size() - MAX_LINES))
	terminal_log.scroll_following = true


# ---------------------------------------------------------------------------
# LDL command panel (replaces the old right-click popup)
# ---------------------------------------------------------------------------

func _init_ldl_panel() -> void:
	# The LDL panel structure lives in the scene tree (HUDLayer/HUDOverlay/
	# LDLPanel). Here we only wire the signals and do the initial list
	# refresh; the list rebuilds on every _update_hud().
	if _ldl_enter_button != null:
		if not _ldl_enter_button.pressed.is_connected(_on_enter_button_pressed):
			_ldl_enter_button.pressed.connect(_on_enter_button_pressed)
	var jack_button: Button = get_node_or_null("HUDLayer/HUDOverlay/LDLPanel/LDLMargin/LDLVBox/LDLJackButton")
	if jack_button != null:
		if not jack_button.pressed.is_connected(_jack_out_to_hub):
			jack_button.pressed.connect(_jack_out_to_hub)
	if _ldl_list != null:
		if not _ldl_list.item_activated.is_connected(_on_ldl_item_activated):
			_ldl_list.item_activated.connect(_on_ldl_item_activated)
	_refresh_ldl_panel()


func _on_ldl_item_activated(index: int) -> void:
	if index < 0 or index >= _ldl_panel_hubs.size():
		return
	_hack_jump(_ldl_panel_hubs[index])


func _refresh_ldl_panel() -> void:
	if _ldl_list == null:
		return

	# ENTER button: visible only when the runner sits on a hub that has a
	# City Grid path assigned.
	var current_hub: Variant = _hub_at(runner_pos)
	if _ldl_enter_button != null:
		if current_hub != null and String(current_hub.get("city_grid_path", "")) != "":
			_ldl_enter_button.text = "ENTER %s" % current_hub.name.to_upper()
			_ldl_enter_button.visible = true
		else:
			_ldl_enter_button.visible = false

	_ldl_list.clear()
	_ldl_panel_hubs = _nearby_hubs(runner_pos)

	if _ldl_panel_hubs.is_empty():
		_ldl_list.add_item("(no LDLs available)")
		return

	for dest in _ldl_panel_hubs:
		_ldl_list.add_item("%s  (Sec %d, +Trace %d)" % [dest.name, int(dest.security_code), int(dest.trace_value)])


func _on_enter_button_pressed() -> void:
	var hub: Variant = _hub_at(runner_pos)
	if hub != null:
		_enter_city_grid(hub)


func _nearby_hubs(pos: Vector2i) -> Array:
	# All hubs except the runner's current one are hackable — LDL hacks are
	# remote signal traces, not movement, so range is not a constraint.
	var out: Array = []
	for hub in city_hubs:
		if hub.pos == pos:
			continue
		out.append(hub)
	return out


func _jack_out_to_hub() -> void:
	# End the run and return to the Workbench to fence loot/files and gear up.
	_log_terminal("JACK OUT // run trace reset.", COLOR_LOG_SYS)
	RunState.accumulated_trace = 0
	RunState.security_dispatch_turns = 0
	RunState.net_time_seconds = 0.0
	RunState.selected_subnet_path = ""
	RunState.selected_city_grid_path = ""
	RunState.selected_security_tier = 0
	get_tree().change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")


func _hack_jump(dest: Dictionary) -> void:
	# Hacking an LDL is a Net action — costs one action (1 minute of net
	# time). The action is spent on the attempt regardless of success.
	if turn_manager != null and not turn_manager.has_actions():
		_log_terminal("NO ACTIONS // cannot hack LDL this round.", COLOR_LOG_WARN)
		return
	if turn_manager != null and not turn_manager.consume_action():
		_log_terminal("NO ACTIONS // cannot hack LDL this round.", COLOR_LOG_WARN)
		return
	# CP2020 RAW LDL connection check: a raw 1D10 roll must meet or exceed the
	# LDL's Security Level to scam the connection. No STAT + Skill is added.
	var roll := randi_range(1, 10)
	_log_terminal("HACK LDL -> %s — 1D10 %d vs Sec %d." % [dest.name, roll, int(dest.security_code)], COLOR_LOG_SYS)
	if roll >= int(dest.security_code):
		var trace_reduction: int = RunState.selected_deck.effective_trace_reduction() if RunState.selected_deck != null else 0
		RunState.accumulated_trace += max(0, int(dest.trace_value) - trace_reduction)
		runner_pos = dest.pos
		_center_camera_on_runner()
		_log_terminal("JUMP OK -> %s // trace %d." % [dest.name, RunState.accumulated_trace], COLOR_LOG_OK)
		_update_hud()
		_check_actions_exhausted()
		queue_redraw()
		return
	# RAW failure: the connection simply fails — the line drops. No trace is
	# added, the runner does not move (signal stays at the last connected
	# node), and NetWatch is not automatically alerted. NetWatch/raids only
	# arise from in-datafort security programs or a sysop spotting you.
	_log_terminal("LINE DROPPED // hack failed, no trace.", COLOR_LOG_FAIL)
	_update_hud()
	_check_actions_exhausted()


func _enter_city_grid(hub: Dictionary) -> void:
	var grid_path: String = String(hub.get("city_grid_path", ""))
	if grid_path == "":
		_log_terminal("%s has no City Grid assigned." % hub.name, COLOR_LOG_WARN)
		_update_hud()
		return
	# Trace is built by inter-city LDL jumps; entering a city adds none.
	_log_terminal("ENTERING %s CITY GRID // trace %d." % [hub.name, RunState.accumulated_trace], COLOR_LOG_OK)
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
		if RunState.security_dispatch_turns > 0:
			trace_label.text += "  ⚠ RAID: %d turn(s)" % RunState.security_dispatch_turns
	_update_clock_label()
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
	_refresh_ldl_panel()


func _update_clock_label() -> void:
	if clock_label:
		clock_label.text = "NET: %s" % CP2020TimeScale.format_clock(RunState.net_time_seconds)
