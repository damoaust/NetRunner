class_name CP2020GameSession
extends Control

@export var starting_subnet_path: String = "res://scenes/forts/night_city_subnet.tres"

@onready var board_renderer: CP2020BoardRenderer = $BoardRenderer
@onready var interaction_handler: CP2020InteractionHandler = $CP2020InteractionHandler
@onready var terminal_log: RichTextLabel = $UI/PanelContainer/VBoxContainer/TerminalLog
@onready var deck_name_label: Label = $UI/PanelContainer/VBoxContainer/DeckNameLabel
@onready var memory_label: Label = $UI/PanelContainer/VBoxContainer/MemoryLabel
@onready var actions_label: Label = $UI/PanelContainer/VBoxContainer/ActionsLabel
@onready var health_label: Label = $UI/PanelContainer/VBoxContainer/HealthLabel
@onready var health_bar: ProgressBar = $UI/PanelContainer/VBoxContainer/HealthBar
@onready var trace_label: Label = $UI/PanelContainer/VBoxContainer/TraceLabel
@onready var clock_label: Label = get_node_or_null("UI/PanelContainer/VBoxContainer/ClockLabel")
# Meatspace security-dispatch countdown HUD. Shown only while a Watchdog has
# traced the runner and a raid is en route (RunState.security_dispatch_turns > 0).
@onready var security_dispatch_label: Label = get_node_or_null("UI/PanelContainer/VBoxContainer/SecurityDispatchLabel")
@onready var datafort_label: Label = $UI/PanelContainer/VBoxContainer/DatafortLabel
@onready var floor_hud_label: Label = $UI/FloorHudLabel
@onready var program_list: ItemList = $UI/PanelContainer/VBoxContainer/ProgramList
@onready var netrunner: CP2020Netrunner = $CP2020Netrunner
@onready var turn_manager: CP2020TurnManager = $TurnManager
@onready var camera: Camera2D = board_renderer.get_node_or_null("RunnerCamera") if board_renderer else null

const BlackIceScene := preload("res://scenes/ui/cp2020_blackice.tscn")
const NpcNetrunnerScene := preload("res://scenes/ui/cp2020_npc_netrunner.tscn")
const RezzedProgramScene := preload("res://scenes/ui/cp2020_rezzed_program.tscn")
const DemonNodeScene := preload("res://scenes/ui/cp2020_demon.tscn")

# Permadeath: if accumulated trace reaches this threshold on jack-out, NetWatch
# arrests the runner and the run ends in a BUSTED game-over. Tunable — each
# LDL jump adds ~5 trace, so a deep run through several dataforts risks busting.
const BUSTED_THRESHOLD: int = 40
var ice_nodes: Array[BlackIce] = []
var npc_nodes: Array[CP2020NpcNetrunner] = []
var datafort: CP2020Datafort = null

# Runner-owned attack programs rezzed onto the net as active, visible nodes.
# Each node owns a duplicate of an installed program copy (one rezzed node per
# installed copy). Rezzed programs auto-follow the runner each turn and can be
# commanded to attack targets (Black ICE / NPC / CPU). Phase 1: attack programs
# only (DEREZ_ICE / DAMAGE_RUNNER / CRASH_CPU). See docs / plan.md.
var rezzed_program_nodes: Array[RezzedProgram] = []

# Combat effect animator — child of the board renderer. Fire-and-forget visual
# effects (attack beams, impact flashes) drawn on top of the grid. Idle/zero-
# cost until play_effect() is called. Visual config lives with each program
# (NetProgram.ATTACK_VISUALS / get_attack_visual()); this node only renders.
var combat_animator: CombatEffectAnimator = null

# 3D compositing layer — renders extruded walls, 3D ICE, beacons behind the
# 2D neon overlay. Created in _ready, synced on load_subnet / floor change.
var board_3d: CP2020Board3D = null

# One-shot guard for end-of-run scene transitions (flatline / busted). An
# adversary coroutine (notably the datafort's multi-action take_turn loop)
# can emit a fatal attack AFTER a prior action already flatlined the runner
# and queued the GameOver scene change — the deferred scene swap tears the
# session out of the tree between the datafort's `await` iterations, so a
# second flatline fires on a detached node (get_tree() == null). This flag
# makes _on_flatlined / _on_jack_out_pressed idempotent and null-safe.
var _game_over_queued: bool = false

# Default visual for enemy attacks that don't carry a NetProgram reference
# (NPC netrunners, datafort resident programs). See NetProgram.ATTACK_VISUALS
# for the per-effect-type config used by rezzed programs + ICE.
const ENEMY_ATTACK_VISUAL: Dictionary = {
	"color": Color(1.0, 0.3, 0.1),
	"width": 3.0,
	"duration": 0.5,
	"style": "beam",
}

var current_layout: CP2020DatafortLayout
# Resolved tier for the current datafort (set at dive time by the City Grid).
var _current_security_tier: int = CP2020SecurityTier.Tier.LEVEL_1

# Floor the runner is currently on (0-indexed). Authoritative source of
# truth — kept in sync with current_layout.current_floor and
# netrunner.current_floor via _set_current_floor. Adversaries stay on their
# home floor (home_floor); only those with home_floor == current_floor take
# turns or render. See docs/multi-floor-travel-plan.md §1/§2b.
var current_floor: int = 0

# Programs the netrunner has deployed as Watchdog beacons. Once deployed, a
# program file goes from "dormant" to "running" and cannot be re-deployed
# (one file, one instance). Filtered out of the available programs list
# before passing to the interaction handler.
var _deployed_programs: Array[NetProgram] = []
# Grid positions of active Watchdog beacons deployed by the netrunner.
var _watchdog_beacons: Array[Vector2i] = []
# Tracks which beacons have already fired an alert (key = "x,y", value = true)
# so each beacon only logs once per enemy detection.
var _watchdog_alerted: Dictionary = {}

# Tier -> default NPC netrunner template, per faction. Used when a NETWATCH /
# NETRUNNER tile has no per-tile override (npc_has_override == false). NetWatch
# leans anti-personnel + shield (law enforcement that hunts runners); random
# netrunners carry utility + a weak attack program. Programs are duplicated
# at spawn time so cached .tres resources are never mutated.
const TIER_NPC_TEMPLATES: Dictionary = {
	CP2020SecurityTier.Tier.GREY: {
		CP2020NpcNetrunner.Faction.NETWATCH:  {"name": "NetWatch Scout",   "deck": "Patrol Deck",     "strength": 3, "max_ap": 2, "max_integrity": 4, "max_health": 8,  "max_mu": 8,  "programs": ["res://data/killer2.tres", "res://data/aegis.tres"]},
		CP2020NpcNetrunner.Faction.NETRUNNER: {"name": "Street Runner",    "deck": "Custom Deck",     "strength": 2, "max_ap": 2, "max_integrity": 3, "max_health": 6,  "max_mu": 6,  "programs": ["res://data/codecracker.tres", "res://data/hammer.tres"]},
	},
	CP2020SecurityTier.Tier.LEVEL_1: {
		CP2020NpcNetrunner.Faction.NETWATCH:  {"name": "NetWatch Officer", "deck": "Issue Deck Mk1",  "strength": 4, "max_ap": 3, "max_integrity": 5, "max_health": 10, "max_mu": 10, "programs": ["res://data/killer4.tres", "res://data/aegis.tres", "res://data/codecracker.tres"]},
		CP2020NpcNetrunner.Faction.NETRUNNER: {"name": "Freelance Runner", "deck": "Hotrod Deck",     "strength": 3, "max_ap": 2, "max_integrity": 4, "max_health": 8,  "max_mu": 8,  "programs": ["res://data/hammer.tres", "res://data/codecracker.tres", "res://data/shield.tres"]},
	},
	CP2020SecurityTier.Tier.LEVEL_2: {
		CP2020NpcNetrunner.Faction.NETWATCH:  {"name": "NetWatch Sergeant", "deck": "Issue Deck Mk2",  "strength": 5, "max_ap": 3, "max_integrity": 6, "max_health": 12, "max_mu": 12, "programs": ["res://data/killer6.tres", "res://data/aegis.tres", "res://data/jackhammer.tres"]},
		CP2020NpcNetrunner.Faction.NETRUNNER: {"name": "Veteran Runner",   "deck": "Tuned Deck",      "strength": 4, "max_ap": 3, "max_integrity": 5, "max_health": 10, "max_mu": 10, "programs": ["res://data/jackhammer.tres", "res://data/killer2.tres", "res://data/shield.tres"]},
	},
	CP2020SecurityTier.Tier.LEVEL_3: {
		CP2020NpcNetrunner.Faction.NETWATCH:  {"name": "NetWatch Captain",  "deck": "Issue Deck Mk3",  "strength": 6, "max_ap": 3, "max_integrity": 7, "max_health": 14, "max_mu": 14, "programs": ["res://data/killer6.tres", "res://data/flatline.tres", "res://data/aegis.tres"]},
		CP2020NpcNetrunner.Faction.NETRUNNER: {"name": "Ace Runner",        "deck": "Race Deck",       "strength": 5, "max_ap": 3, "max_integrity": 6, "max_health": 12, "max_mu": 12, "programs": ["res://data/jackhammer.tres", "res://data/killer4.tres", "res://data/shield.tres"]},
	},
	CP2020SecurityTier.Tier.BLACK: {
		CP2020NpcNetrunner.Faction.NETWATCH:  {"name": "NetWatch Blackops", "deck": "Black Deck",      "strength": 7, "max_ap": 4, "max_integrity": 9, "max_health": 18, "max_mu": 18, "programs": ["res://data/flatline.tres", "res://data/killer6.tres", "res://data/aegis.tres"]},
		CP2020NpcNetrunner.Faction.NETRUNNER: {"name": "Legendary Runner",  "deck": "Master Deck",     "strength": 6, "max_ap": 3, "max_integrity": 7, "max_health": 14, "max_mu": 14, "programs": ["res://data/jackhammer.tres", "res://data/killer6.tres", "res://data/shield.tres"]},
	},
}

func _ready() -> void:
	RunState.net_time_seconds = 0.0
	if interaction_handler:
		if not interaction_handler.action_triggered.is_connected(_on_action_triggered):
			interaction_handler.action_triggered.connect(_on_action_triggered)

	if turn_manager:
		if not turn_manager.turn_ended.is_connected(_on_turn_ended):
			turn_manager.turn_ended.connect(_on_turn_ended)
		if not turn_manager.ice_movement_stepped.is_connected(_on_ice_stepped):
			turn_manager.ice_movement_stepped.connect(_on_ice_stepped)
		if not turn_manager.actions_changed.is_connected(_on_actions_changed):
			turn_manager.actions_changed.connect(_on_actions_changed)
		if not turn_manager.movement_changed.is_connected(_on_movement_changed):
			turn_manager.movement_changed.connect(_on_movement_changed)
		if not turn_manager.initiative_rolled.is_connected(_on_initiative_rolled):
			turn_manager.initiative_rolled.connect(_on_initiative_rolled)
		if not turn_manager.action_consumed.is_connected(_on_action_consumed):
			turn_manager.action_consumed.connect(_on_action_consumed)
		# Round 1: the runner just jacked in and acts first (no initiative roll
		# needed — no adversaries are active yet). The adversary phase is
		# deferred to after the runner's first turn; end_round then starts
		# round 2 with a real initiative roll.
		turn_manager.start_netrunner_turn()
		turn_manager.defer_post_round_adversary()

	if netrunner:
		if not netrunner.message_logged.is_connected(log_to_terminal):
			netrunner.message_logged.connect(log_to_terminal)
		if not netrunner.flatlined.is_connected(_on_flatlined):
			netrunner.flatlined.connect(_on_flatlined)
		if not netrunner.deck_updated.is_connected(update_deck_info):
			netrunner.deck_updated.connect(update_deck_info)
		if not netrunner.shield_raised.is_connected(update_deck_info):
			netrunner.shield_raised.connect(update_deck_info)
		if not netrunner.shield_consumed.is_connected(update_deck_info):
			netrunner.shield_consumed.connect(update_deck_info)
		# Invisibility cloak: refresh the trace/status label on raise/pierce
		# so the CLOAK indicator appears/disappears promptly.
		if not netrunner.cloak_raised.is_connected(_update_trace):
			netrunner.cloak_raised.connect(_update_trace)
		if not netrunner.cloak_pierced.is_connected(_update_trace):
			netrunner.cloak_pierced.connect(_update_trace)
		if not netrunner.health_changed.is_connected(_on_health_changed):
			netrunner.health_changed.connect(_on_health_changed)
		if netrunner.position_changed.is_connected(_center_camera_on_runner) == false:
			netrunner.position_changed.connect(_center_camera_on_runner)
		if not netrunner.stunned.is_connected(_on_stunned):
			netrunner.stunned.connect(_on_stunned)

	# Apply the selected cyberdeck from the workbench (if any)
	if RunState.selected_deck:
		var deck := RunState.selected_deck
		netrunner.deck_name = deck.deck_name
		netrunner.max_memory_units = deck.effective_max_mu()
		netrunner.interface_rank = deck.effective_interface_rank()
		netrunner.installed_programs = deck.installed_programs.duplicate()
		# installed_programs was assigned directly (bypassing install_program),
		# so seed the program_integrity HP tracker for every loaded program.
		netrunner.seed_program_integrity()

	# Apply the selected runner character's meat-space stat block. The
	# netrunner node's @export defaults are overwritten here so each character
	# plays differently. current_health must be set explicitly because
	# CP2020Netrunner._ready() (which runs before this session's _ready) already
	# set it to the old max_health default. intelligence_lost starts at 0.
	if RunState.selected_character:
		var ch := RunState.selected_character
		netrunner.reflex = ch.reflex
		netrunner.intelligence = ch.intelligence
		netrunner.body = ch.body
		netrunner.max_health = ch.max_health
		netrunner.current_health = ch.max_health
		netrunner.sight_range = ch.sight_range

	# Combat effect animator — child of the board renderer so its beams render
	# on top of the grid. Lives in the scene tree as a BoardRenderer child
	# (CombatAnimator node); we look it up and sync grid geometry from the
	# renderer. Stays idle until play_effect() is called.
	if board_renderer and combat_animator == null:
		combat_animator = board_renderer.get_node_or_null("CombatAnimator") as CombatEffectAnimator
		if combat_animator:
			combat_animator.cell_size = board_renderer.cell_size
			combat_animator.grid_offset_y = board_renderer.grid_offset_y

	# 3D terrain layer — the SubViewport, Camera3D and world are authored in
	# cp2020_gameplay.tscn inside Board3DContainer. The CP2020Board3D script
	# on the Board3D node controls them and spawns wall/CPU meshes.
	if board_3d == null:
		board_3d = get_node_or_null("Board3D") as CP2020Board3D
	if board_3d and board_renderer:
		board_3d.cell_size = board_renderer.cell_size
		board_3d.grid_offset_y = board_renderer.grid_offset_y
		# Render the 3D world to a SubViewport and display it via a TextureRect
		# on the background CanvasLayer (layer -1), behind the 2D neon overlay.
		var bg_layer := get_node_or_null("CanvasLayer") as CanvasLayer
		board_3d.setup_subviewport(bg_layer)
		# Make the 2D board an overlay: skip solid terrain fills so the 3D
		# geometry is visible behind the grid lines and fog.
		board_renderer.draw_terrain_fills = false
		# Bump the UI CanvasLayer above the 2D board so the HUD stays readable.
		var ui_layer := get_node_or_null("UI") as CanvasLayer
		if ui_layer:
			ui_layer.layer = 1

	# Load the subnet chosen on the world map (fall back to default)
	var subnet_path := RunState.selected_subnet_path if RunState.selected_subnet_path != "" else starting_subnet_path
	load_subnet(subnet_path)
	update_deck_info()
	_on_health_changed(netrunner.current_health, netrunner.max_health)
	_update_trace()
	_update_security_dispatch_hud()
	log_to_terminal("JACKED IN. Connection established to matrix grid.\n")
	# Apply F11 debug-3d flag from startup to the newly created 3D board.
	if OS.get_cmdline_args().has("--debug-3d") and board_3d:
		board_3d.set_debug_visible(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if board_3d and current_layout and board_renderer:
			var root_size := get_tree().root.size if get_tree() else Vector2i(1920, 1080)
			board_3d.resize_viewport(root_size.x, root_size.y)
			board_3d.sync_camera_2d(
				netrunner.position if netrunner else Vector2.ZERO,
				Vector2i(current_layout.columns, current_layout.rows),
				current_floor
			)

func _update_floor_hud_label() -> void:
	if floor_hud_label == null or current_layout == null:
		return
	var f := current_floor
	var count := current_layout.get_floor_count()
	var fname: String = ""
	if f >= 0 and f < current_layout.floors.size():
		fname = current_layout.floors[f].floor_name
	if fname == "":
		fname = "Floor %d" % f
	floor_hud_label.text = "Floor %d/%d — %s" % [f + 1, count, fname]

func load_subnet(path: String, entry_coord: Vector2i = Vector2i(-1, -1)) -> bool:
	if not ResourceLoader.exists(path):
		push_error("load_subnet: resource not found: %s" % path)
		return false
	var loaded := ResourceLoader.load(path) as CP2020DatafortLayout
	if loaded == null:
		push_error("load_subnet: %s is not a CP2020DatafortLayout." % path)
		return false
	current_layout = loaded
	if board_renderer and current_layout:
		board_renderer.current_layout = current_layout

		# Start on floor 0 of the freshly loaded datafort. Sync the layout
		# and netrunner so every floor-scoped read agrees.
		current_floor = 0
		_set_current_floor(0)

		# Reset fog state on every tile across ALL floors. ResourceLoader
		# returns a cached instance, so a datafort visited on a previous run
		# (or earlier in this run via LDL travel) would otherwise retain
		# is_explored=true and show as already-revealed. A fresh run starts
		# fully fogged. (Pre-multi-floor .tres migrate grid_tiles into
		# floors[0] on first access via _ensure_floors_migrated.)
		for f in range(current_layout.get_floor_count()):
			for raw_key in current_layout.get_floor_tiles(f).keys():
				var c := CP2020DatafortLayout.parse_coord(raw_key)
				var t = current_layout.get_tile(c, f)
				if t:
					t.is_explored = false
					t.is_visible = false
					# Reset any Krash-crashed CPUs from a prior visit so a fresh
					# dive starts with all CPUs active.
					t.cpu_crashed_turns = 0
					# Reset the loot flag so a revisited datafort can be looted
					# again on a fresh dive (cached ResourceLoader instance).
					t.is_looted = false
					# Reset per-file copied tracking so a revisited datafort's files can
					# be copied again on a fresh dive (cached ResourceLoader instance).
					t.copied_file_paths = PackedStringArray()
					# Reset any in-progress Worm programs from a prior visit so a
					# fresh dive starts with no worm-active tiles (cached
					# ResourceLoader instance retains the runtime counter).
					t.worm_turns_remaining = 0
					t.worm_integrity = 0
					t.worm_max_integrity = 0

		# Clear netrunner-deployed Watchdog beacons and deployed-program
		# tracking for a fresh dive (beacons don't persist across dataforts).
		_watchdog_beacons.clear()
		_watchdog_alerted.clear()
		_deployed_programs.clear()
		if board_renderer:
			board_renderer.watchdog_beacons = _watchdog_beacons
		if board_3d:
			board_3d.clear_beacons()
		# Clear any rezzed attack-program nodes from a prior dive — they do
		# not persist across dataforts (a fresh dive starts un-rezzed).
		_clear_rezzed_programs()

		# Let the Netrunner handle its own spawning!
		if netrunner:
			netrunner.initialize(current_layout, entry_coord)
		_current_security_tier = _resolve_security_tier(path)
		spawn_black_ice()
		spawn_npcs()
		spawn_datafort()
		recalculate_fog_of_war(netrunner.current_position)
		_update_camera_limits()
		_center_camera_on_runner()
		board_renderer.request_redraw()
		# Sync 3D extruded walls for the current floor. Size the SubViewport to
		# the root viewport resolution (the 2D render size), not the window
		# size, so the orthographic camera maps 1:1 with the 2D board before
		# the TextureRect scales to the display.
		if board_3d:
			var root_size := get_tree().root.size if get_tree() else Vector2i(1920, 1080)
			board_3d.resize_viewport(root_size.x, root_size.y)
			board_3d.sync_from_layout(current_layout, current_floor)
	return true

func _update_trace(_unused: Variant = null) -> void:
	if trace_label:
		var txt := "Trace: %d" % RunState.accumulated_trace
		if is_instance_valid(netrunner) and netrunner.cloak != null:
			txt += "  | CLOAK"
		trace_label.text = txt
	_update_clock_label()

func _update_camera_limits() -> void:
	if not camera or not current_layout or not board_renderer:
		return
	var cs: float = board_renderer.cell_size
	var go_y: float = board_renderer.grid_offset_y
	camera.limit_left = 0
	camera.limit_top = int(go_y)
	camera.limit_right = int(current_layout.columns * cs)
	camera.limit_bottom = int(go_y + current_layout.rows * cs)

func _center_camera_on_runner(_new_pos: Vector2i = Vector2i(-1, -1)) -> void:
	if not camera or not netrunner:
		return
	camera.position = netrunner.position
	# The 3D camera is synced every frame in _process to the 2D Camera2D's
	# actual screen center (which respects map-edge clamping + smoothing), so
	# the 3D tiles stay aligned with the 2D grid even near map edges.
	_sync_3d_camera()


# Keep the 3D camera locked to the 2D Camera2D's real view center every frame.
# The 2D camera clamps at the map edges (_update_camera_limits) and eases via
# position_smoothing, so syncing to netrunner.position would drift the 3D
# tiles bottom-right of the 2D cells near edges. camera.get_screen_center_position()
# returns the clamped+smoothed center the player actually sees.
func _sync_3d_camera() -> void:
	if board_3d and camera and current_layout:
		board_3d.sync_camera_2d(
			camera.get_screen_center_position(),
			Vector2i(current_layout.columns, current_layout.rows),
			current_floor
		)


func _process(_delta: float) -> void:
	_sync_3d_camera()

# Sets the current floor and propagates it to the layout + netrunner so every
# floor-scoped read (get_tile / line_of_sight / renderer / pathfinding) agrees.
# Called on dive (floor 0) and on every up/down travel. Does NOT move the
# runner — the caller sets netrunner.current_position separately.
func _set_current_floor(f: int) -> void:
	current_floor = f
	if current_layout:
		current_layout.current_floor = f
	if is_instance_valid(netrunner):
		netrunner.current_floor = f
	_update_floor_hud_label()

# Authoritative vertical-travel blocking check (mirrors the interaction
# handler's pre-check so the menu can grey out blocked directions). Returns
# true if `target_floor` exists and the arrival coord is a non-blocking tile
# (not a Datawall, not a locked Code Gate). See
# docs/multi-floor-travel-plan.md §2 blocking check.
func _can_travel_vertical(target_floor: int, target_coord: Vector2i) -> bool:
	if current_layout == null:
		return false
	if target_floor < 0 or target_floor >= current_layout.get_floor_count():
		return false
	if target_coord.x < 0 or target_coord.x >= current_layout.columns \
			or target_coord.y < 0 or target_coord.y >= current_layout.rows:
		return false
	var tile := current_layout.get_tile(target_coord, target_floor)
	if tile == null:
		return true
	if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
		return false
	if tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked:
		return false
	return true

# Keyboard Q/E entry point: travel up/down from the runner's current tile.
# Silent no-op when the runner isn't standing on a tile flagged for that
# direction (avoids log spam on every key press).
func _try_travel_vertical(up: bool) -> void:
	if current_layout == null or not is_instance_valid(netrunner):
		return
	var tile := current_layout.get_tile(netrunner.current_position, current_floor)
	if tile == null:
		return
	if up and not tile.can_go_up:
		return
	if not up and not tile.can_go_down:
		return
	_do_travel_vertical(up, netrunner.current_position)

# Perform the floor switch. `clicked_coord` is the tile the menu was built
# for (right-click flow); the runner must be standing on it to travel. The
# destination floor/coord come from the tile's up/down flags. Trace is
# preserved (the runner never left the datafort). See
# docs/multi-floor-travel-plan.md §2.
func _do_travel_vertical(up: bool, clicked_coord: Vector2i) -> void:
	if current_layout == null or not is_instance_valid(netrunner):
		return
	# Vertical travel is initiated from the runner's own tile.
	if clicked_coord != netrunner.current_position:
		log_to_terminal("You must be standing on the shaft tile to travel up/down.\n")
		return
	var tile := current_layout.get_tile(netrunner.current_position, current_floor)
	if tile == null:
		return
	var target_floor := current_floor + (1 if up else -1)
	var target_coord: Vector2i = tile.up_target_entry_coord if up else tile.down_target_entry_coord
	if not (tile.can_go_up if up else tile.can_go_down):
		log_to_terminal("No %s shaft here.\n" % ("upward" if up else "downward"))
		return
	if not _can_travel_vertical(target_floor, target_coord):
		if target_floor < 0 or target_floor >= current_layout.get_floor_count():
			log_to_terminal("No floor %s — cannot travel %s.\n" % [target_floor, "up" if up else "down"])
		elif target_coord.x < 0 or target_coord.x >= current_layout.columns \
				or target_coord.y < 0 or target_coord.y >= current_layout.rows:
			log_to_terminal("Vertical shaft leads nowhere (out of bounds).\n")
		else:
			log_to_terminal("The way %s is blocked by a Datawall or locked Code Gate.\n" % ("up" if up else "down"))
		return
	# Switch floor + position. Each floor retains its own fog state, so a
	# revisited floor shows as already-explored; recalculate_fog_of_war sets
	# is_visible around the new arrival.
	_set_current_floor(target_floor)
	netrunner.current_position = target_coord
	netrunner.update_visual_position()
	recalculate_fog_of_war(target_coord)
	_update_camera_limits()
	_center_camera_on_runner()
	if board_renderer:
		board_renderer.request_redraw()
		_flash_floor_label()
	# Re-sync 3D walls for the new floor.
	if board_3d and current_layout:
		board_3d.sync_from_layout(current_layout, current_floor)
	var floor_name := current_layout.floors[target_floor].floor_name if current_layout.floors[target_floor].floor_name != "" else "Floor %d" % target_floor
	log_to_terminal("Travelling %s to %s (entry %s). Trace preserved.\n" % ["up" if up else "down", floor_name, target_coord])

# Trigger the board renderer's centered floor-change flash + refresh the
# persistent HUD floor label. Safe to call when the renderer is absent.
func _flash_floor_label() -> void:
	if board_renderer and board_renderer.has_method("flash_floor_label"):
		board_renderer.flash_floor_label()

func _input(event: InputEvent) -> void:
	# Track mouse motion for the hover highlight outline. Computes the grid
	# coord under the cursor and checks whether that tile/entity offers a
	# right-click context menu; feeds the result to the board renderer.
	if event is InputEventMouseMotion and board_renderer and current_layout:
		var mouse_pos: Vector2 = board_renderer.get_global_mouse_position()
		var cs: float = float(board_renderer.cell_size)
		var go_y: float = float(board_renderer.grid_offset_y)
		var grid_x: int = floori(mouse_pos.x / cs)
		var grid_y: int = floori((mouse_pos.y - go_y) / cs)
		var coord := Vector2i(grid_x, grid_y)
		if grid_x >= 0 and grid_x < current_layout.columns and grid_y >= 0 and grid_y < current_layout.rows:
			board_renderer.hovered_coord = coord
			board_renderer.hover_interactable = _is_hover_interactable(coord)
		else:
			board_renderer.hovered_coord = Vector2i(-1, -1)
			board_renderer.hover_interactable = false

	# Right-click is handled here in _input (NOT _unhandled_input) because the root
	# Control node's GUI system consumes mouse events before _unhandled_input fires.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		accept_event() # Prevent GUI system from re-processing this
		var mouse_pos: Vector2 = board_renderer.get_global_mouse_position() if board_renderer else get_viewport().get_mouse_position()
		var programs: Array[NetProgram] = []
		if netrunner:
			for prog in netrunner.installed_programs:
				if prog and prog not in _deployed_programs and not _is_program_rezzed(prog):
					programs.append(prog)
		if interaction_handler and current_layout:
			var cs: float = float(board_renderer.cell_size) if board_renderer else 40.0
			var go_y: float = float(board_renderer.grid_offset_y) if board_renderer else 90.0
			var nr_pos: Vector2i = netrunner.current_position if netrunner else Vector2i(-1, -1)
			interaction_handler.handle_input(event, mouse_pos, current_layout, programs, cs, go_y, ice_nodes, nr_pos, npc_nodes, netrunner, rezzed_program_nodes)

	# --- KEYBOARD INPUT (Pass to Netrunner) ---
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			# Finishing a partial move spends the movement action; then end the
			# turn (forfeits any remaining actions/movement).
			if turn_manager and turn_manager.end_movement_action():
				pass
			_end_player_turn()
			return

		var dir = Vector2i.ZERO
		if event.keycode in [KEY_W, KEY_UP]: dir = Vector2i(0, -1)
		elif event.keycode in [KEY_S, KEY_DOWN]: dir = Vector2i(0, 1)
		elif event.keycode in [KEY_A, KEY_LEFT]: dir = Vector2i(-1, 0)
		elif event.keycode in [KEY_D, KEY_RIGHT]: dir = Vector2i(1, 0)
		# Q/E = go up / go down a floor (vertical travel). Consistent with
		# WASD so the player isn't forced to right-click for every transition.
		# Only acts when the runner stands on an ENTRY tile flagged
		# can_go_up / can_go_down; otherwise ignored (no feedback spam).
		elif event.keycode == KEY_Q:
			_try_travel_vertical(true)
			return
		elif event.keycode == KEY_E:
			_try_travel_vertical(false)
			return
		
		if dir != Vector2i.ZERO and netrunner:
			if netrunner.is_stunned:
				log_to_terminal("Stunned — cannot move.\n")
				return
			if turn_manager and not turn_manager.has_movement():
				if turn_manager.actions_remaining <= 0:
					log_to_terminal("No action remaining to move. End turn (Space) to let adversaries move.\n")
				else:
					log_to_terminal("No movement remaining this action. End turn (Space) to let adversaries move.\n")
				return
			var moved_successfully = netrunner.move(dir)
			if moved_successfully:
				if turn_manager:
					turn_manager.consume_movement_step()
				recalculate_fog_of_war(netrunner.current_position)
				board_renderer.request_redraw()
				_check_actions_exhausted()

## Check whether the tile at `coord` would produce a right-click context menu.
## Mirrors the logic in CP2020InteractionHandler.handle_right_click so the
## hover highlight only appears for genuinely interactable entities/tiles.
func _is_hover_interactable(coord: Vector2i) -> bool:
	if current_layout == null:
		return false
	var tile_data := current_layout.get_tile(coord, current_layout.current_floor)
	if tile_data == null or not tile_data.is_explored:
		return false

	# LDL link — always interactable (travel menu)
	if tile_data.is_ldl_link:
		return true

	# Vertical travel — always interactable
	if tile_data.can_go_up or tile_data.can_go_down:
		return true

	# Rezzed program on this tile (same floor) — requires visibility
	if tile_data.is_visible:
		for rez in rezzed_program_nodes:
			if is_instance_valid(rez) and rez.home_floor == current_layout.current_floor and rez.current_position == coord:
				return true

	# Black ICE on this tile (same floor) — requires visibility
	if tile_data.is_visible:
		for ice in ice_nodes:
			if is_instance_valid(ice) and ice.home_floor == current_layout.current_floor and ice.current_position == coord:
				return true

	# NPC netrunner on this tile (same floor) — requires visibility
	if tile_data.is_visible:
		for npc in npc_nodes:
			if is_instance_valid(npc) and npc.home_floor == current_layout.current_floor and npc.current_position == coord:
				return true

	# CONTROL_NODE — requires visibility
	if tile_data.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE and tile_data.is_visible:
		return true

	# Netrunner's own tile — requires visibility
	if netrunner and coord == netrunner.current_position and tile_data.is_visible:
		return true

	# CODE_GATE (locked) — explored is enough; menu only appears if the
	# runner has a matching BYPASS_GATE or WORM program available.
	if tile_data.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile_data.is_unlocked:
		if _has_available_program_of_type(NetProgram.EffectType.BYPASS_GATE) or _has_available_program_of_type(NetProgram.EffectType.WORM):
			return true

	# DATAWALL — explored is enough; menu only appears if the runner has a
	# matching BREACH_WALL or WORM program available.
	if tile_data.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
		if _has_available_program_of_type(NetProgram.EffectType.BREACH_WALL) or _has_available_program_of_type(NetProgram.EffectType.WORM):
			return true

	# MEMORY_UNIT — requires visibility, has files, and is adjacent to the
	# netrunner (same adjacency rule as the interaction handler).
	if tile_data.tile_type == CP2020DatafortLayout.TileType.MEMORY_UNIT and tile_data.is_visible and tile_data.files.size() > 0:
		if netrunner:
			var dx: int = abs(coord.x - netrunner.current_position.x)
			var dy: int = abs(coord.y - netrunner.current_position.y)
			if (dx + dy) <= 1:
				return true

	return false

## Check whether an installed program with the given effect type is available
## (not deployed, not rezzed). Used by _is_hover_interactable for CODE_GATE /
## DATAWALL interactability checks.
func _has_available_program_of_type(effect_type: NetProgram.EffectType) -> bool:
	if netrunner == null:
		return false
	for prog in netrunner.installed_programs:
		if prog and prog.effect_type == effect_type and prog not in _deployed_programs and not _is_program_rezzed(prog):
			return true
	return false

func _on_action_triggered(action_name: String, target_coord: Vector2i, program = null) -> void:
	match action_name:
		"use_program":
			if program is NetProgram and current_layout:
				if turn_manager and not turn_manager.can_use_programs():
					if turn_manager.programs_blocked:
						log_to_terminal("Cyberdeck crashed — programs unavailable this turn (movement only).\n")
					elif turn_manager._movement_action_active:
						log_to_terminal("Already moving this action — end movement (Space) first.\n")
					else:
						log_to_terminal("No actions remaining. End turn (Space) to let adversaries move.\n")
					return
				# Crashed (de-rezzed) programs clog MU but can't be used —
				# their integrity is 0. Block the action before consuming it.
				if is_instance_valid(netrunner) and netrunner.program_integrity_for(program) <= 0:
					log_to_terminal("Program '%s' is crashed (de-rezzed) — cannot use. Clear it to free MU.\n" % program.program_name)
					return
				# Delegate to the program's virtual execute_runner_action. The
				# base NetProgram dispatches by effect_type to the private
				# _execute_* helpers; subclasses (Worm, Watchdog) override it
				# entirely. Returns false if the use failed validation — in
				# that case do NOT consume an action.
				var ok: bool = program.execute_runner_action(self, target_coord)
				if ok:
					if turn_manager:
						turn_manager.consume_action()
					_check_actions_exhausted()
		"travel_ldl":
			# program carries the CP2020TileData of the LDL link tile.
			if program is CP2020TileData:
				var tile: CP2020TileData = program
				var dest_path: String = tile.target_subnet_path
				var dest_coord: Vector2i = tile.target_entry_coord
				if dest_path == "":
					log_to_terminal("LDL link has no target subnet set.\n")
					return
				if load_subnet(dest_path, dest_coord):
					# If a target_entry_coord was requested but the remote map
					# had no valid tile there, netrunner.initialize fell back to
					# the remote's primary/first entry. Surface that so the
					# player/designer isn't silently dropped somewhere unexpected.
					if dest_coord.x >= 0 and dest_coord.y >= 0 and netrunner and netrunner.current_position != dest_coord:
						log_to_terminal("LDL target entry %s invalid — arrived at remote entry %s instead.\n" % [dest_coord, netrunner.current_position])
					else:
						log_to_terminal("Travelling LDL to %s (entry %s). Trace preserved.\n" % [dest_path, netrunner.current_position if netrunner else dest_coord])
					update_deck_info()
					_update_trace()
					_update_security_dispatch_hud()
				else:
					log_to_terminal("LDL target '%s' could not be loaded.\n" % dest_path)
		"return_world_map":
			log_to_terminal("Returning to the City Grid via LDL. Connection preserved.\n")
			# Trace is preserved — the runner is still in the run, just back up
			# one map level (Datafort -> City Grid).
			if RunState.selected_city_grid_path != "":
				get_tree().change_scene_to_file("res://scenes/ui/cp2020_city_grid.tscn")
			else:
				# No city grid recorded (e.g. legacy entry) — fall back to world map.
				RunState.accumulated_trace = 0
				RunState.security_dispatch_turns = 0
				RunState.net_time_seconds = 0.0
				get_tree().change_scene_to_file("res://scenes/ui/cp2020_world_net_map.tscn")
		"travel_up":
			# Vertical travel within the same datafort (no load_subnet). The
			# program_resource carries the ENTRY tile the runner right-clicked
			# (may differ from the runner's own tile if clicked remotely, but
			# travel is only valid from the runner's tile — re-validated below).
			_do_travel_vertical(true, target_coord)
		"travel_down":
			_do_travel_vertical(false, target_coord)
		"talk_npc":
			_talk_to_npc(target_coord)
		"rez_program":
			# Rez an installed attack program onto the net as an active node.
			# `program` is the installed NetProgram copy to rez. Consumes 1
			# action. The node spawns at the runner's tile (or nearest walkable
			# adjacent tile) and auto-follows thereafter.
			if program is NetProgram:
				if turn_manager and not turn_manager.can_use_programs():
					log_to_terminal("No actions remaining. End turn (Space) to let adversaries move.\n")
					return
				if _rez_program(program as NetProgram):
					if turn_manager:
						turn_manager.consume_action()
					_check_actions_exhausted()
		"derez_program":
			# De-rez a rezzed attack-program node (free — no action cost).
			# `program` is the RezzedProgram node to remove.
			if program is RezzedProgram:
				_derez_program(program as RezzedProgram)
		"attack_with_rezzed":
			# Command a rezzed attack program to strike a target. `program` is
			# the RezzedProgram node; target_coord is the target tile. Consumes
			# 1 action. Dispatches by effect_type to the existing execute_*
			# helpers, sourcing stats from the rezzed node's program duplicate.
			if program is RezzedProgram and current_layout:
				var rez_node: RezzedProgram = program as RezzedProgram
				if turn_manager and not turn_manager.can_use_programs():
					log_to_terminal("No actions remaining. End turn (Space) to let adversaries move.\n")
					return
				if not is_instance_valid(rez_node) or rez_node.program == null:
					log_to_terminal("That rezzed program is no longer active.\n")
					return
				var ok := _attack_with_rezzed(rez_node, target_coord)
				if ok:
					if turn_manager:
						turn_manager.consume_action()
					_check_actions_exhausted()
		"command_demon":
				# Command a rezzed Demon to fire one of its subroutines. `program`
				# is a 2-element Array [DemonNode, subroutine_index] built by the
				# interaction handler's Demon command menu (id range 8500+i).
				# Consumes 1 action. Attack subroutines strike `target_coord`;
				# SHIELD/ARMOR subroutines self-buff the runner.
				if program is Array and current_layout:
					var payload: Array = program
					if payload.size() >= 2 and payload[0] is DemonNode:
						var demon_node: DemonNode = payload[0]
						var sub_idx: int = int(payload[1])
						if turn_manager and not turn_manager.can_use_programs():
							log_to_terminal("No actions remaining. End turn (Space) to let adversaries move.\n")
							return
						if not is_instance_valid(demon_node):
							log_to_terminal("That Demon is no longer active.\n")
							return
						var ok2 := _command_demon(demon_node, sub_idx, target_coord)
						if ok2:
							if turn_manager:
								turn_manager.consume_action()
							_check_actions_exhausted()
		"copy_file":
			# Copy a single file from a MEMORY_UNIT tile to the deck. File
			# retrieval is a "free" data action in CP2020 — it does NOT consume
			# an action or end the turn (unlike use_program / attack_npc above).
			if current_layout:
				var file := program as NetFile
				if file == null:
					push_warning("copy_file: program is not a NetFile.")
					return
				var tile: CP2020TileData = current_layout.get_tile(target_coord, current_floor)
				if not tile:
					push_warning("copy_file: no tile at %s." % target_coord)
					return
				# Find the file's index on the tile. Match by instance OR by
				# file_name, since program_resource may be a duplicate with
				# different identity than the tile's stored entry.
				var idx: int = -1
				for i in range(tile.files.size()):
					if tile.files[i] == file or tile.files[i].file_name == file.file_name:
						idx = i
						break
				if idx < 0:
					push_warning("copy_file: file not found on tile %s." % target_coord)
					return
				if str(idx) in tile.copied_file_paths:
					push_warning("copy_file: file already copied.")
					return
				# MU-fit check: free MU = max MU minus programs + carried files.
				var free_mu: int = netrunner.effective_max_memory() - netrunner.get_used_memory() if netrunner else 999999
				if file.mu_size > free_mu:
					log_to_terminal("Not enough free deck memory for %s (need %d MU, have %d).\n" % [file.file_name, file.mu_size, free_mu])
					return
				RunState.copy_file(file)
				tile.copied_file_paths.append(str(idx))
				log_to_terminal("Copied %s to deck memory (%d MU).\n" % [file.file_name, file.mu_size])
				update_deck_info()
				if board_renderer:
					board_renderer.request_redraw()
		"copy_all_files":
			# Batch-copy every fitting file from a MEMORY_UNIT tile to the
			# deck. Like copy_file, this does NOT consume an action or end
			# the turn — it is a free data retrieval action.
			if current_layout:
				var tile: CP2020TileData = current_layout.get_tile(target_coord, current_floor)
				if not tile:
					push_warning("copy_all_files: no tile at %s." % target_coord)
					return
				if tile.files.is_empty():
					return
				if netrunner:
					var free_mu := netrunner.effective_max_memory() - netrunner.get_used_memory()
					for i in range(tile.files.size()):
						if str(i) in tile.copied_file_paths:
							continue
						var f: NetFile = tile.files[i]
						if f == null:
							continue
						if f.mu_size <= free_mu:
							RunState.copy_file(f)
							tile.copied_file_paths.append(str(i))
							free_mu -= f.mu_size
							log_to_terminal("Copied %s to deck memory (%d MU).\n" % [f.file_name, f.mu_size])
						else:
							log_to_terminal("Skipped %s — not enough free deck memory.\n" % f.file_name)
				if board_renderer:
					board_renderer.request_redraw()
				update_deck_info()
				log_to_terminal("Batch copy complete.\n")
		"loot_tile":
			# Loot a CONTROL_NODE tile. A free data action — does NOT consume
			# a turn. Moves loot_programs into RunState.loot (each duplicate()d
			# so cached .tres files aren't mutated, via RunState.add_loot),
			# adds loot_credits to RunState.credits, picks up loot_modules via
			# RunState.add_module_loot, and marks the tile looted.
			if current_layout:
				var tile: CP2020TileData = current_layout.get_tile(target_coord, current_floor)
				if tile == null:
					push_warning("loot_tile: no tile at %s." % target_coord)
					return
				if tile.is_looted:
					log_to_terminal("Already looted.\n")
					return
				var looted_any: bool = false
				for prog in tile.loot_programs:
					if prog is NetProgram:
						RunState.add_loot(prog as NetProgram)
						log_to_terminal("Looted program: %s\n" % (prog as NetProgram).program_name)
						looted_any = true
				if tile.loot_credits > 0:
					RunState.add_loot_credits(tile.loot_credits)
					log_to_terminal("Looted %d credits.\n" % tile.loot_credits)
					looted_any = true
				if tile.loot_modules.size() > 0:
					for mod in tile.loot_modules:
						if mod is DeckModule:
							RunState.add_module_loot(mod as DeckModule)
							log_to_terminal("Looted module: %s\n" % (mod as DeckModule).module_name)
							looted_any = true
				if looted_any:
					tile.is_looted = true
					if board_renderer:
						board_renderer.request_redraw()
					update_deck_info()

func _execute_decryption(program: NetProgram, target_coord: Vector2i) -> void:
	var tile = current_layout.get_tile(target_coord, current_floor)
	if tile:
		log_to_terminal("Executing Bypass Program '%s' on Code Gate at %s...\n" % [program.program_name, target_coord])
		tile.is_unlocked = true
		if board_renderer:
			board_renderer.request_redraw()

func _execute_wall_breach(program: NetProgram, target_coord: Vector2i) -> void:
	var tile = current_layout.get_tile(target_coord, current_floor)
	if tile:
		log_to_terminal("Executing Wall Breach '%s' on Datawall at %s...\n" % [program.program_name, target_coord])
		tile.is_visible = true
		tile.tile_type = CP2020DatafortLayout.TileType.EMPTY
		log_to_terminal("Datawall breached! Path cleared.\n")
		if board_renderer:
			board_renderer.request_redraw()

func _execute_worm(program: NetProgram, target_coord: Vector2i) -> void:
	# Worm is a stealth opener: it slips behind a DATAWALL or locked CODE_GATE
	# and opens it from the inside over 2 turns with no alert (no trace
	# increase, no ICE activation). The tile gets worm_turns_remaining = 2;
	# the turn-start tick in _on_turn_ended decrements and opens at 0.
	var tile: CP2020TileData = current_layout.get_tile(target_coord, current_floor)
	if tile == null:
		log_to_terminal("No tile at %s for Worm.\n" % target_coord)
		return
	var is_wall: bool = tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL
	var is_gate: bool = tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked
	if not is_wall and not is_gate:
		log_to_terminal("Worm can only target Data Walls or locked Code Gates.\n")
		return
	if tile.worm_turns_remaining > 0:
		log_to_terminal("A Worm is already working on this tile (%d turns remaining).\n" % tile.worm_turns_remaining)
		return
	tile.worm_turns_remaining = 2
	var label := "data wall" if is_wall else "code gate"
	log_to_terminal("Worm '%s' deployed behind the %s at %s — opening from the inside in 2 turns. No alert triggered.\n" % [program.program_name, label, target_coord])
	if board_renderer:
		board_renderer.request_redraw()

func _execute_ice_attack(program: NetProgram, target_coord: Vector2i) -> void:
	var target_ice: BlackIce = null
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.current_position == target_coord:
			target_ice = ice
			break

	if not target_ice:
		log_to_terminal("No Black ICE detected at %s.\n" % target_coord)
		return

	log_to_terminal("Executing Anti-ICE Program '%s' (STR %d) on %s at %s...\n" % [program.program_name, program.strength, target_ice.program.program_name, target_coord])

	# Opposed roll (CP2020 anti-program combat): Attacker STR + 1D10 vs
	# Defender STR + 1D10. The roll determines whether the attack succeeds.
	# Attacker wins → defender takes 1D6 damage to STR. Defender wins or ties
	# → attack fails, no damage to either side (the defender does NOT
	# counterstrike). If the runner's program is reduced to 0 integrity by
	# other means (e.g. Killer ICE), it crashes and clogs MU.
	var result := CP2020Dice.roll_opposed(program.strength, target_ice.program.strength)
	log_to_terminal("Roll: you %d (1D10+%d) vs %s %d (1D10+%d)\n" % [result.atk_roll, program.strength, target_ice.program.program_name, result.def_roll, target_ice.program.strength])

	if result.attacker_wins:
		var dmg := randi_range(1, 6)
		log_to_terminal("Hit! %s takes %d damage.\n" % [target_ice.program.program_name, dmg])
		if target_ice.take_damage(dmg):
			ice_nodes.erase(target_ice)
			if board_3d:
				board_3d.remove_ice_proxy(target_coord)
	elif not result.tie:
		log_to_terminal("%s repels the attack — no damage.\n" % target_ice.program.program_name)
	else:
		log_to_terminal("Standoff — both sides hold, no damage.\n")

	if board_renderer:
		board_renderer.request_redraw()

func _execute_shield(program: NetProgram) -> void:
	if not netrunner:
		return
	log_to_terminal("Activating Protection Program '%s'...\n" % program.program_name)
	netrunner.raise_shield(program)

# Activate the Invisibility stealth cloak (UTILITY / INVISIBILITY effect).
# Consumes 1 action (the caller, NetProgram.execute_runner_action, returns
# this bool so the session's use_program handler consumes an action on true).
# While the cloak is up, each dormant adversary (ICE not yet _activated, hostile
# NPC not yet engaged) that gains LoS must win an opposed roll to detect the
# runner (see BlackIce.take_turn / CP2020NpcNetrunner.take_turn). A single
# seeker winning pierces the cloak globally (see _on_cloak_pierced). Already-
# active adversaries ignore the cloak. Returns false (no action consumed) if a
# cloak is already active, so the runner doesn't waste the action.
func _execute_invisibility(program: NetProgram) -> bool:
	if not netrunner:
		return false
	if netrunner.cloak != null:
		log_to_terminal("Invisibility already active — cloak still holding.\n")
		return false
	netrunner.raise_cloak(program)
	# Push the cloak reference onto every current adversary so their take_turn
	# can run the opposed roll. New adversaries are not spawned mid-run, so a
	# single pass at raise-time is sufficient.
	for ice in ice_nodes:
		if is_instance_valid(ice):
			ice.cloak_program = program
			if not ice.cloak_pierced.is_connected(_on_cloak_pierced):
				ice.cloak_pierced.connect(_on_cloak_pierced)
	for npc in npc_nodes:
		if is_instance_valid(npc):
			npc.cloak_program = program
			if not npc.cloak_pierced.is_connected(_on_cloak_pierced):
				npc.cloak_pierced.connect(_on_cloak_pierced)
	log_to_terminal("Activating Invisibility '%s' (Cloak STR %d) — overlaying false signal on your trace.\n" % [program.program_name, program.strength])
	if board_renderer:
		board_renderer.request_redraw()
	return true

# A dormant adversary won the opposed detection roll: the cloak is pierced.
# Clear the cloak on the netrunner and on every adversary (so subsequent
# detections proceed normally — Invisibility only prevents initial notice),
# log the breach, and refresh the HUD.
func _on_cloak_pierced() -> void:
	if is_instance_valid(netrunner) and netrunner.cloak != null:
		netrunner.pierce_cloak()
	for ice in ice_nodes:
		if is_instance_valid(ice):
			ice.cloak_program = null
	for npc in npc_nodes:
		if is_instance_valid(npc):
			npc.cloak_program = null
	log_to_terminal("Invisibility pierced — you are visible! Cloak burned out.\n")
	if board_renderer:
		board_renderer.request_redraw()

# Deploy a Watchdog beacon at the netrunner's current position. The beacon
# monitors a 20-space LoS radius each turn and alerts when enemies approach.
# The deployed program is marked as "running" (added to _deployed_programs)
# and cannot be deployed again — one file, one instance. This is the single
# source of beacon-deploy truth: the base NetProgram DETECTION dispatch (via
# _execute_detection) and the WatchdogProgram subclass both call it.
func deploy_watchdog_beacon(program: NetProgram, target_coord: Vector2i) -> void:
	if _watchdog_beacons.has(target_coord):
		log_to_terminal("A Watchdog beacon is already deployed at %s.\n" % target_coord)
		return
	_watchdog_beacons.append(target_coord)
	_deployed_programs.append(program)
	if board_renderer:
		board_renderer.watchdog_beacons = _watchdog_beacons
	log_to_terminal("Watchdog beacon '%s' deployed at %s — monitoring 20-space radius.\n" % [program.program_name, target_coord])
	if board_renderer:
		board_renderer.request_redraw()
	# Sync 3D beacon column for the watchdog trace.
	if board_3d:
		board_3d.sync_beacons(_watchdog_beacons)

func _execute_detection(program: NetProgram, target_coord: Vector2i) -> void:
	deploy_watchdog_beacon(program, target_coord)

# ─────────────────────────────────────────────────────────────────────────────
# REVEAL_NODES programs (Sensor / Probe). Detection utilities that lift the
# fog of war on a region without moving the runner. Sensor sweeps a radius
# around the runner (STR = radius in tiles, ignoring walls — a sensor ping
# maps structure behind barriers); Probe identifies a single targeted tile.
# Both set is_explored=true (persistent fog lift) but leave is_visible to the
# normal per-turn recalculation, so newly sensed tiles show as "explored not
# visible" unless the runner has current LoS. Neither consumes movement; both
# consume 1 action (caller returns true).
# ─────────────────────────────────────────────────────────────────────────────

func _execute_sensor(program: NetProgram, _target_coord: Vector2i) -> void:
	if not current_layout or not netrunner:
		return
	var radius: int = max(1, program.strength)
	var center: Vector2i = netrunner.current_position
	var revealed := 0
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			# Manhattan radius sweep — a sensor ping radiates outward, so we
			# use Chebyshev (square) coverage to map the full area, including
			# tiles diagonally adjacent. This intentionally ignores Data
			# Walls / Code Gates (a sensor maps structure behind barriers).
			var coord := center + Vector2i(x, y)
			if coord.x < 0 or coord.x >= current_layout.columns or coord.y < 0 or coord.y >= current_layout.rows:
				continue
			var tile = current_layout.get_tile(coord, current_floor)
			if tile and not tile.is_explored:
				tile.is_explored = true
				revealed += 1
	# Sync entity visibility with the freshly lifted fog on this floor.
	_sync_entity_visibility()
	log_to_terminal("Sensor '%s' sweep complete — revealed %d new tile(s) within %d spaces.\n" % [program.program_name, revealed, radius])
	if board_renderer:
		board_renderer.request_redraw()

func _execute_probe(program: NetProgram, target_coord: Vector2i) -> void:
	if not current_layout:
		return
	var tile = current_layout.get_tile(target_coord, current_floor)
	if tile == null:
		log_to_terminal("Probe '%s': no node detected at %s.\n" % [program.program_name, target_coord])
		return
	# Require LoS to the target (Probe is a focused scan, not a wall-piercing
	# ping like Sensor) — the runner must already see the tile to probe it.
	if not current_layout.line_of_sight(netrunner.current_position, target_coord, netrunner.sight_range, current_floor):
		log_to_terminal("Probe '%s': target at %s is out of line of sight.\n" % [program.program_name, target_coord])
		return
	var was_explored: bool = tile.is_explored
	tile.is_explored = true
	tile.is_visible = true
	# Report what the probe found at the node.
	var type_label: String = CP2020DatafortLayout.TileType.keys()[tile.tile_type] if tile.tile_type < CP2020DatafortLayout.TileType.size() else "UNKNOWN"
	var detail := ""
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.current_position == target_coord and ice.home_floor == current_floor:
			detail = " — ICE detected: %s (STR %d)" % [ice.program.program_name, ice.program.strength]
			break
	if detail.is_empty():
		for npc in npc_nodes:
			if is_instance_valid(npc) and npc.current_position == target_coord and npc.home_floor == current_floor:
				detail = " — Netrunner detected: %s" % npc.netrunner_name
				break
	_sync_entity_visibility()
	log_to_terminal("Probe '%s' locked onto %s (%s)%s%s\n" % [program.program_name, target_coord, type_label, " [newly revealed]" if not was_explored else "", detail])
	if board_renderer:
		board_renderer.request_redraw()

# Shared helper: refresh entity (ICE/NPC/rezzed) explored/visible flags from
# the current tile fog state on each entity's home floor. Called after Sensor/
# Probe lift fog so glyphs appear/disappear consistently with recalculate_fog.
func _sync_entity_visibility() -> void:
	for ice in ice_nodes:
		if is_instance_valid(ice):
			var ice_tile = current_layout.get_tile(ice.current_position, ice.home_floor)
			if ice_tile:
				ice.update_visibility(ice_tile.is_explored, ice_tile.is_visible)
	for npc in npc_nodes:
		if is_instance_valid(npc):
			var npc_tile = current_layout.get_tile(npc.current_position, npc.home_floor)
			if npc_tile:
				npc.update_visibility(npc_tile.is_explored, npc_tile.is_visible)
	for rez in rezzed_program_nodes:
		if is_instance_valid(rez):
			var rez_tile = current_layout.get_tile(rez.current_position, rez.home_floor)
			if rez_tile:
				rez.update_visibility(rez_tile.is_explored, rez_tile.is_visible)

# ─────────────────────────────────────────────────────────────────────────────
# MODIFY_MU programs (Toolbox / Speed). Per-run utility boosts. Toolbox raises
# the deck's effective MU ceiling (STR = bonus MU) so the runner can copy more
# files / equip more mid-run; Speed raises the initiative speed bonus (STR =
# bonus speed). Both last the whole run and are one-active-instance. The
# netrunner owns the boost state and emits deck_updated so the HUD refreshes.
# ─────────────────────────────────────────────────────────────────────────────

func _execute_toolbox(program: NetProgram) -> bool:
	if not netrunner:
		return false
	if not netrunner.activate_toolbox(program):
		log_to_terminal("A Toolbox is already running — boost still active.\n")
		return false
	if board_renderer:
		board_renderer.request_redraw()
	return true

func _execute_speed(program: NetProgram) -> bool:
	if not netrunner:
		return false
	if not netrunner.activate_speed(program):
		log_to_terminal("A Speed booster is already running — boost still active.\n")
		return false
	if board_renderer:
		board_renderer.request_redraw()
	return true

# Called when a DETECTION ICE (Watchdog) gains LoS to the netrunner and
# trips the alarm. Activates all other attack ICE in the datafort by
# calling activate_alarm() on each non-DETECTION ICE node.
func _on_ice_alarm_triggered() -> void:
	log_to_terminal("ALARM! Watchdog has detected an intruder — all attack ICE activated!\n")
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.program.effect_type != NetProgram.EffectType.DETECTION:
			ice.activate_alarm()
	if board_renderer:
		board_renderer.request_redraw()

# Called when a DETECTION ICE (Watchdog) succeeds at its CP2020 trace check
# (1D10 + program.strength >= RunState.accumulated_trace) on first LoS
# detection. The runner's physical location is pinpointed: the datafort's ICE
# is escalated (all attack ICE woken — no new NPCs are spawned) and a
# meatspace security-dispatch countdown is rolled by the datafort's security
# tier. The countdown ticks down each netrunner turn; at 0 the meatspace raid
# arrives and the runner is Busted (permadeath). Jacking out before 0 escapes
# the raid (timer cleared), though the existing accumulated_trace bust check
# still applies on jack-out. Only the first successful trace rolls the timer;
# later traces are no-ops (the raid is already en route).
func _on_ice_trace_succeeded(program: NetProgram) -> void:
	log_to_terminal("=== TRACE LOCKED: %s pinpointed your physical location! ===\n" % (program.program_name if program != null else "Watchdog"))
	# Escalate the datafort's ICE (idempotent — safe even if already alarmed).
	_on_ice_alarm_triggered()
	if RunState.security_dispatch_turns > 0:
		log_to_terminal("Meatspace security already dispatched — %d turn(s) to raid.\n" % RunState.security_dispatch_turns)
		_update_security_dispatch_hud()
		return
	# Roll the physical-response timer by corporate security zone classification.
	# Lower tiers take longer to scramble a meatspace team.
	var dispatch_turns: int = 0
	match _current_security_tier:
		CP2020SecurityTier.Tier.GREY, CP2020SecurityTier.Tier.LEVEL_1:
			dispatch_turns = randi_range(1, 6) + randi_range(1, 6)
		CP2020SecurityTier.Tier.LEVEL_2, CP2020SecurityTier.Tier.LEVEL_3:
			dispatch_turns = randi_range(1, 10)
		CP2020SecurityTier.Tier.BLACK:
			dispatch_turns = randi_range(1, 6)
		_:
			dispatch_turns = randi_range(1, 10)
	RunState.security_dispatch_turns = dispatch_turns
	log_to_terminal("MEATSPACE RAID DISPATCHED — corporate security ETA %d turn(s). Jack out before they arrive!\n" % dispatch_turns)
	_update_security_dispatch_hud()

# Updates the security-dispatch HUD label. Shown only while a raid is en route.
func _update_security_dispatch_hud() -> void:
	if security_dispatch_label == null:
		return
	if RunState.security_dispatch_turns > 0:
		security_dispatch_label.text = "⚠ SECURITY DISPATCH: %d turn(s) to raid" % RunState.security_dispatch_turns
		security_dispatch_label.visible = true
	else:
		security_dispatch_label.visible = false

# Meatspace raid arrived while the runner was still jacked in — Busted
# permadeath. Mirrors the busted path in _on_jack_out_pressed with a distinct
# death cause. Guarded by _game_over_queued so a deferred adversary coroutine
# can't double-fire it after the scene swap.
func _trigger_security_raid() -> void:
	if _game_over_queued:
		return
	_game_over_queued = true
	log_to_terminal("=== BUSTED — meatspace security raided your location while jacked in. They confiscated everything. ===\n")
	var summary: Dictionary = {
		"cause": "Traced",
		"trace": RunState.accumulated_trace,
		"credits": RunState.credits,
		"loot_count": RunState.loot.size(),
		"files_count": RunState.carried_files.size(),
		"datafort": RunState.selected_subnet_path,
		"security_tier": RunState.selected_security_tier,
	}
	MetaState.record_run(summary)
	RunState.last_death_cause = "Traced"
	RunState.last_run_summary = summary
	RunState.security_dispatch_turns = 0
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/ui/GameOver.tscn")

# ─────────────────────────────────────────────────────────────────────────────
# Rezzed attack programs (Phase 1). Attack programs (DEREZ_ICE / DAMAGE_RUNNER
# / CRASH_CPU) must be rezzed onto the net as active nodes before they can be
# commanded to attack. Rezzing consumes 1 action; attacking with a rezzed
# program consumes 1 action. Rezzed nodes auto-follow the runner each turn and
# can be de-rezzed for free. One rezzed node per installed program copy.
# ─────────────────────────────────────────────────────────────────────────────

# Attack-program effect types eligible for rezzing in Phase 1.
const REZZABLE_EFFECT_TYPES: Array[int] = [
	NetProgram.EffectType.DEREZ_ICE,
	NetProgram.EffectType.DAMAGE_RUNNER,
	NetProgram.EffectType.CRASH_CPU,
]

# True if an installed program copy already has a rezzed node on the net.
# Tracked by `source_program` identity (one node per installed copy).
func _is_program_rezzed(prog: NetProgram) -> bool:
	for rez in rezzed_program_nodes:
		if is_instance_valid(rez) and rez.source_program == prog:
			return true
	return false

# True if a program's effect_type is an attack type eligible for rezzing.
func _is_rezzable(prog: NetProgram) -> bool:
	if prog == null:
		return false
	if prog.effect_type in REZZABLE_EFFECT_TYPES:
		return true
	# Demons (EffectType.DEMON / DemonProgram) are rezzed as DemonNodes that
	# carry their assigned subroutines onto the net.
	if prog is DemonProgram:
		return true
	return false

# Rez an installed attack program onto the net. Spawns a RezzedProgram node at
# the runner's tile (or nearest walkable adjacent tile), wires its signals, and
# adds it to rezzed_program_nodes. Returns true on success (caller consumes an
# action), false on failure (no action consumed).
func _rez_program(prog: NetProgram) -> bool:
	if not is_instance_valid(netrunner) or current_layout == null:
		return false
	if not _is_rezzable(prog):
		log_to_terminal("'%s' is not an attack program — only anti-ICE / anti-personnel / anti-system programs can be rezzed.\n" % prog.program_name)
		return false
	if _is_program_rezzed(prog):
		log_to_terminal("'%s' is already rezzed onto the net.\n" % prog.program_name)
		return false
	# Crashed (de-rezzed, integrity 0) installed programs clog MU but can't be
	# used — block rezzing them until the runner clears the crash.
	if netrunner.program_integrity_for(prog) <= 0:
		log_to_terminal("'%s' is crashed (de-rezzed) — cannot rez. Clear it to free MU.\n" % prog.program_name)
		return false
	# Find a spawn tile: prefer the runner's tile, else the nearest walkable
	# adjacent tile (so multiple rezzed programs don't stack on one tile).
	var spawn_pos := _find_rez_spawn_tile(netrunner.current_position)
	if spawn_pos == Vector2i(-1, -1):
		log_to_terminal("No free tile near the netrunner to rez '%s' onto.\n" % prog.program_name)
		return false
	var layout_size := Vector2i(current_layout.columns, current_layout.rows)
	# Demons rezz as a DemonNode (a RezzedProgram subclass carrying its
	# assigned subroutines, each STR-overridden to the Demon core's STR).
	# Plain attack programs rezz as a RezzedProgram. Both live in
	# rezzed_program_nodes so Killer ICE targeting picks them up.
	if prog is DemonProgram:
		var demon: DemonNode = DemonNodeScene.instantiate()
		add_child(demon)
		var demon_prog: DemonProgram = prog.duplicate() as DemonProgram
		demon.program = demon_prog
		demon.source_program = prog
		demon.max_integrity = demon_prog.strength
		demon.home_floor = current_floor
		demon.cell_size = int(board_renderer.cell_size) if board_renderer else 40
		demon.grid_offset_y = int(board_renderer.grid_offset_y) if board_renderer else 90
		demon.setup_subroutines(prog as DemonProgram)
		demon.initialize(spawn_pos, layout_size)
		demon.apply_visual_from_program()
		demon.message_logged.connect(log_to_terminal)
		demon.moved_to.connect(_on_rezzed_program_moved)
		demon.destroyed.connect(_on_rezzed_program_destroyed.bind(demon))
		rezzed_program_nodes.append(demon)
		if board_renderer:
			board_renderer.rezzed_program_nodes = rezzed_program_nodes
			board_renderer.request_redraw()
		var sub_names: String = ""
		for s in demon.get_commandable_subroutines():
			sub_names += "%s%s" % ["" if sub_names.is_empty() else ", ", s.program_name]
		log_to_terminal("Rezzing Demon '%s' (STR %d) at %s — subroutines: %s.\n" % [demon_prog.program_name, demon_prog.strength, spawn_pos, sub_names if not sub_names.is_empty() else "(none assigned)"])
		update_deck_info()
		return true
	var rez: RezzedProgram = RezzedProgramScene.instantiate()
	add_child(rez)
	# Duplicate the program so the node owns its own instance (never mutate the
	# cached installed copy). source_program tracks the original for de-rez
	# bookkeeping and the one-node-per-copy rule.
	rez.program = prog.duplicate()
	rez.source_program = prog
	rez.max_integrity = rez.program.strength
	rez.home_floor = current_floor
	rez.cell_size = int(board_renderer.cell_size) if board_renderer else 40
	rez.grid_offset_y = int(board_renderer.grid_offset_y) if board_renderer else 90
	rez.initialize(spawn_pos, layout_size)
	rez.apply_visual_from_program()
	rez.message_logged.connect(log_to_terminal)
	rez.moved_to.connect(_on_rezzed_program_moved)
	rez.destroyed.connect(_on_rezzed_program_destroyed.bind(rez))
	rezzed_program_nodes.append(rez)
	if board_renderer:
		board_renderer.rezzed_program_nodes = rezzed_program_nodes
		board_renderer.request_redraw()
	log_to_terminal("Rezzing '%s' (STR %d) onto the net at %s.\n" % [rez.program.program_name, rez.program.strength, spawn_pos])
	update_deck_info()
	return true

# Find a tile to spawn a rezzed program on: the runner's tile if free, else the
# nearest walkable adjacent tile not occupied by another rezzed program / ICE /
# NPC. Returns Vector2i(-1,-1) if none found.
func _find_rez_spawn_tile(runner_pos: Vector2i) -> Vector2i:
	var occupied: Array[Vector2i] = []
	for rez in rezzed_program_nodes:
		if is_instance_valid(rez) and rez.home_floor == current_floor:
			occupied.append(rez.current_position)
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.home_floor == current_floor:
			occupied.append(ice.current_position)
	for npc in npc_nodes:
		if is_instance_valid(npc) and npc.current_position != Vector2i(-1, -1) and npc.home_floor == current_floor:
			occupied.append(npc.current_position)
	# Runner's own tile is a valid spawn (rezzed programs can share it).
	if runner_pos not in occupied:
		return runner_pos
	# Otherwise scan the 4 adjacent tiles.
	var offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for off in offsets:
		var cand := runner_pos + off
		if cand.x < 0 or cand.y < 0 or cand.x >= current_layout.columns or cand.y >= current_layout.rows:
			continue
		if cand in occupied:
			continue
		var tile = current_layout.get_tile(cand, current_floor)
		if tile == null:
			continue
		if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
			continue
		if tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked:
			continue
		return cand
	return Vector2i(-1, -1)

# De-rez a rezzed program node (free — no action cost). Frees the node and the
# installed copy is available for re-rezzing.
func _derez_program(rez: RezzedProgram) -> void:
	if not is_instance_valid(rez):
		return
	var prog_name := rez.program.program_name if rez.program else "program"
	# Explosion VFX — capture position + color before freeing the node.
	var rez_pos := rez.current_position
	var rez_color: Color = Color(1, 0.3, 0.1)
	if rez.program:
		rez_color = rez.program.get_visual().get("color", rez_color)
	_spawn_derez_explosion(rez_pos, rez_color)
	rezzed_program_nodes.erase(rez)
	rez.queue_free()
	if board_renderer:
		board_renderer.rezzed_program_nodes = rezzed_program_nodes
		board_renderer.request_redraw()
	log_to_terminal("De-rezzing '%s' — returned to deck memory.\n" % prog_name)
	update_deck_info()

# Spawn a fire-and-forget de-rez explosion effect at `grid_pos`. The effect
# node is added as a child of the BoardRenderer (same parent as the
# CombatAnimator), syncs grid geometry, plays the shader animation, and
# auto-frees when done. `base_color` should come from the program's visual.
func _spawn_derez_explosion(grid_pos: Vector2i, base_color: Color) -> void:
	if not board_renderer:
		return
	var fx := CP2020ExplosionEffect.new()
	fx.cell_size = int(board_renderer.cell_size)
	fx.grid_offset_y = int(board_renderer.grid_offset_y)
	board_renderer.add_child(fx)
	fx.play(grid_pos, base_color)

# Command a rezzed attack program to strike a target tile. Dispatches by
# effect_type to the existing execute_* helpers, sourcing stats from the
# rezzed node's program duplicate. Returns true if the attack resolved
# (caller consumes an action), false on invalid target (no action consumed).
func _attack_with_rezzed(rez: RezzedProgram, target_coord: Vector2i) -> bool:
	if not is_instance_valid(rez) or rez.program == null:
		return false
	var prog: NetProgram = rez.program
	# Visual feedback: beam from the rezzed program to the target. Fire-and-
	# forget; combat resolution proceeds immediately. Visual config lives with
	# the program (NetProgram.get_attack_visual()).
	if combat_animator:
		combat_animator.play_effect(rez.current_position, target_coord, prog.get_attack_visual())
	match prog.effect_type:
		NetProgram.EffectType.DEREZ_ICE:
			_execute_ice_attack(prog, target_coord)
			return true
		NetProgram.EffectType.DAMAGE_RUNNER:
			execute_npc_attack(prog, target_coord)
			return true
		NetProgram.EffectType.CRASH_CPU:
			if is_instance_valid(datafort):
				datafort.crash_cpu(prog, target_coord)
			if board_renderer:
				board_renderer.request_redraw()
			return true
		_:
			log_to_terminal("'%s' has no attack action implemented.\n" % prog.program_name)
			return false

# Command a rezzed Demon to fire one of its subroutines at `target_coord` (for
# attack subroutines) or on the runner (for SHIELD/ARMOR self-buffs). The
# subroutine's effect_type selects the dispatch; the subroutine's strength is
# already the Demon core's STR (overridden at spawn). Returns true if the
# command resolved (caller consumes 1 action), false on invalid target.
func _command_demon(demon: DemonNode, sub_index: int, target_coord: Vector2i) -> bool:
	if not is_instance_valid(demon):
		return false
	var sub: NetProgram = demon.get_subroutine(sub_index)
	if sub == null:
		log_to_terminal("That Demon subroutine is no longer loaded.\n")
		return false
	# Attack subroutines: beam from the Demon to the target tile. SHIELD/ARMOR
	# are self-targeted (no beam).
	if combat_animator and sub.effect_type in [NetProgram.EffectType.DEREZ_ICE, NetProgram.EffectType.DAMAGE_RUNNER, NetProgram.EffectType.CRASH_CPU]:
		combat_animator.play_effect(demon.current_position, target_coord, sub.get_attack_visual())
	match sub.effect_type:
		NetProgram.EffectType.DEREZ_ICE:
			_execute_ice_attack(sub, target_coord)
			return true
		NetProgram.EffectType.DAMAGE_RUNNER:
			execute_npc_attack(sub, target_coord)
			return true
		NetProgram.EffectType.CRASH_CPU:
			if is_instance_valid(datafort):
				datafort.crash_cpu(sub, target_coord)
			if board_renderer:
				board_renderer.request_redraw()
			return true
		NetProgram.EffectType.SHIELD:
			_execute_shield(sub)
			if board_renderer:
				board_renderer.request_redraw()
			return true
		NetProgram.EffectType.ARMOR:
			if is_instance_valid(netrunner):
				netrunner.raise_armor(sub)
				log_to_terminal("Demon '%s' raises Armor '%s' (Absorb STR %d).\n" % [demon.program.program_name, sub.program_name, sub.strength])
				if board_renderer:
					board_renderer.request_redraw()
				return true
			return false
		_:
			log_to_terminal("Demon subroutine '%s' has no command action.\n" % sub.program_name)
			return false

# Auto-follow: move each rezzed program on the runner's floor to stay adjacent
# to the runner. Called at the start of each netrunner turn. Uses AStarGrid2D
# pathfinding (like ICE). Does NOT consume the runner's movement points. If the
# runner is surrounded, the program holds position (no turn block).
func _tick_rezzed_programs() -> void:
	if current_layout == null or rezzed_program_nodes.is_empty():
		return
	if not is_instance_valid(netrunner):
		return
	var target := netrunner.current_position
	for rez in rezzed_program_nodes:
		if not is_instance_valid(rez):
			continue
		if rez.home_floor != current_floor:
			continue
		# Already adjacent (or on the runner's tile) — no move needed.
		if rez.current_position == target or _is_adjacent(rez.current_position, target):
			continue
		rez.refresh_pathfinding(current_layout)
		# Path to the runner; step one tile toward it (stop when adjacent).
		var path = rez.astar_grid.get_id_path(rez.current_position, target)
		if path.size() <= 1:
			continue
		# Walk the path until adjacent to the runner (don't step onto the
		# runner's tile — programs trail, they don't stack on the runner
		# unless that's where they spawned).
		var step_idx := 1
		while step_idx < path.size():
			var next_step: Vector2i = path[step_idx]
			if _is_adjacent(next_step, target) or next_step == target:
				# This step puts us adjacent — take it and stop.
				rez.current_position = next_step
				rez.update_visual_position()
				rez.moved_to.emit(next_step)
				break
			rez.current_position = next_step
			rez.update_visual_position()
			rez.moved_to.emit(next_step)
			step_idx += 1
	# No trailing request_redraw() here: every rez.moved_to.emit() above
	# synchronously fires _on_rezzed_program_moved -> request_redraw(), so
	# _needs_redraw is already set whenever a program actually moved. When
	# nothing moved the board is unchanged, so no redraw is needed either.
	# (Additionally, while any rezzed program exists the renderer's _process
	# gate already redraws each frame.)

func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var d := a - b
	return (abs(d.x) + abs(d.y)) == 1

func _on_rezzed_program_moved(_new_pos: Vector2i) -> void:
	if board_renderer:
		board_renderer.request_redraw()

func _on_rezzed_program_destroyed(rez: RezzedProgram) -> void:
	# The destroyed signal fires before queue_free() in take_damage(), so the
	# node is still valid here — capture position + color for the explosion.
	if is_instance_valid(rez):
		var rez_pos := rez.current_position
		var rez_color: Color = Color(1, 0.3, 0.1)
		if rez.program:
			rez_color = rez.program.get_visual().get("color", rez_color)
		_spawn_derez_explosion(rez_pos, rez_color)
		rezzed_program_nodes.erase(rez)
	if board_renderer:
		board_renderer.rezzed_program_nodes = rezzed_program_nodes
		board_renderer.request_redraw()
	update_deck_info()

# Free and clear all rezzed program nodes (called on load_subnet / fresh dive).
func _clear_rezzed_programs() -> void:
	for rez in rezzed_program_nodes:
		if is_instance_valid(rez):
			rez.queue_free()
	rezzed_program_nodes.clear()
	if board_renderer:
		board_renderer.rezzed_program_nodes = rezzed_program_nodes

# Attack an NPC netrunner occupying `target_coord` with `program`. Opposed
# 1d10+STR roll vs the NPC's strength (same convention as anti-ICE combat).
# The NPC's raised shield (if any) is resolved inside take_damage.
func execute_npc_attack(program: NetProgram, target_coord: Vector2i) -> void:
	var target_npc: CP2020NpcNetrunner = null
	for npc in npc_nodes:
		if is_instance_valid(npc) and npc.current_position == target_coord:
			target_npc = npc
			break
	if not target_npc:
		log_to_terminal("No NPC netrunner detected at %s.\n" % target_coord)
		return

	log_to_terminal("Executing '%s' (STR %d) on %s at %s...\n" % [program.program_name, program.strength, target_npc.npc_name, target_coord])
	var result := CP2020Dice.roll_opposed(program.strength, target_npc.strength)
	log_to_terminal("Roll: you %d (1d10+%d) vs %s %d (1d10+%d). Ties go to the defender.\n" % [result.atk_roll, program.strength, target_npc.npc_name, result.def_roll, target_npc.strength])
	# CP2020: ties go to the DEFENDER — hit on prog_roll > npc_roll only.
	if result.attacker_wins:
		# Damage amount: anti-personnel programs with damage_dice > 0 roll
		# flat 1D{damage_dice} per hit (e.g. Sword = 1D6); other programs use
		# the opposed-roll margin. Hit/miss is always decided by the opposed
		# roll above — only the damage amount differs here.
		var damage: int = 0
		if program.damage_dice > 0:
			damage = randi_range(1, program.damage_dice)
			log_to_terminal("Hit! %s takes %d damage (1D%d).\n" % [target_npc.npc_name, damage, program.damage_dice])
		else:
			damage = result.margin
			log_to_terminal("Hit! %s takes %d damage.\n" % [target_npc.npc_name, damage])
		# take_damage handles destruction (emits destroyed -> _on_npc_destroyed).
		target_npc.take_damage(damage)
	else:
		log_to_terminal("%s repelled the attack.\n" % target_npc.npc_name)
	if board_renderer:
		board_renderer.request_redraw()

# Placeholder talk interaction for neutral netrunners (flavour text for now;
# future hook for trading / dialogue). Provoking does NOT flip disposition —
# only damage does.
func _talk_to_npc(_coord: Vector2i) -> void:
	var npc: CP2020NpcNetrunner = null
	for n in npc_nodes:
		if is_instance_valid(n) and n.current_position == _coord:
			npc = n
			break
	if npc:
		if npc.disposition == CP2020NpcNetrunner.Disposition.NEUTRAL:
			log_to_terminal("%s: \"Busy. Don't start anything and we're cool.\"\n" % npc.npc_name)
		else:
			log_to_terminal("%s: \"You're not getting past me, choom.\"\n" % npc.npc_name)
	else:
		log_to_terminal("Nobody to talk to at %s.\n" % _coord)

func log_to_terminal(message: String) -> void:
	if terminal_log:
		terminal_log.text += message
	print(message)

func update_deck_info(_program: Variant = null) -> void:
	if not netrunner:
		return
	if deck_name_label:
		deck_name_label.text = "Deck: %s" % netrunner.deck_name
	if memory_label:
		memory_label.text = "Memory: %d / %d MU" % [netrunner.get_used_memory(), netrunner.effective_max_memory()]
	if program_list:
		program_list.clear()
		for prog in netrunner.installed_programs:
			if not prog:
				continue
			var integrity := netrunner.program_integrity_for(prog)
			var crashed := (integrity <= 0)
			var active := ((netrunner.raised_shield == prog or netrunner.active_armor == prog) and not crashed)
			var rezzed := _is_program_rezzed(prog)
			var status_prefix := ""
			if crashed:
				status_prefix = "[CRASHED] "
			elif rezzed:
				status_prefix = "[REZZED] "
			elif active:
				status_prefix = "[ACTIVE] "
			var item_text: String
			if crashed:
				item_text = "%s%s  (STR %d, %d MU) — de-rezzed, clogging MU" % [status_prefix, prog.program_name, prog.strength, prog.memory_cost]
			elif integrity < prog.strength:
				item_text = "%s%s  (STR %d/%d, %d MU)" % [status_prefix, prog.program_name, integrity, prog.strength, prog.memory_cost]
			else:
				item_text = "%s%s  (STR %d, %d MU)" % [status_prefix, prog.program_name, prog.strength, prog.memory_cost]
			program_list.add_item(item_text)
			var idx := program_list.item_count - 1
			if crashed:
				program_list.set_item_custom_fg_color(idx, CP2020Theme.COL_RED)
			elif rezzed:
				program_list.set_item_custom_fg_color(idx, CP2020Theme.COL_CYAN)
			elif active:
				program_list.set_item_custom_fg_color(idx, CP2020Theme.COL_GREEN)

func spawn_black_ice() -> void:
	# Clear any previously spawned ICE nodes (e.g. on subnet reload)
	for ice in ice_nodes:
		if is_instance_valid(ice):
			ice.queue_free()
	ice_nodes.clear()

	if not current_layout:
		return

	var layout_size := Vector2i(current_layout.columns, current_layout.rows)
	# Spawn BLACK_ICE on EVERY floor; each ICE remembers its home_floor so
	# the turn manager / renderer can gate it to its floor. Adversaries do
	# not follow the runner between floors.
	for f in range(current_layout.get_floor_count()):
		for raw_key in current_layout.get_floor_tiles(f).keys():
			var coord := CP2020DatafortLayout.parse_coord(raw_key)

			var tile = current_layout.get_tile(coord, f)
			if tile and tile.tile_type == CP2020DatafortLayout.TileType.BLACK_ICE:
				# Every BLACK_ICE tile must have an assigned program .tres
				# (tile.ice_program). The program defines effect_type, strength,
				# damage_dice, and program_name, and its script (base NetProgram
				# or a subclass like WatchdogProgram) drives behavior via
				# take_ice_turn. max_integrity is derived 1:1 from
				# program.strength. ICE movement is STR-based (see
				# NetProgram.take_ice_turn). Tracing behavior is deferred to
				# program-specific subclasses (Hellhound/Flatline — not yet
				# implemented).
				if tile.ice_program == null:
					push_warning("BLACK_ICE tile at %s has no assigned ice_program — skipping spawn." % coord)
					continue
				var ice: BlackIce = BlackIceScene.instantiate()
				add_child(ice)
				ice.program = tile.ice_program.duplicate()
				ice.max_integrity = ice.program.strength
				ice.home_floor = f
				ice.rezzed_programs = rezzed_program_nodes
				ice.initialize(coord, layout_size)
				ice.apply_visual_from_program(ice.program, "☠", Color.RED)
				ice.message_logged.connect(log_to_terminal)
				ice.moved_to.connect(_on_ice_moved)
				# Anti-personnel (DAMAGE_RUNNER) ICE attacks the runner's meat
				# stats (INT loss + Stun/Mortal saves). Anti-program (DEREZ_ICE)
				# ICE attacks an installed program instead. The flag is captured
				# via a lambda so the shared attacked_netrunner signal stays a
				# single-int emission.
				var is_anti_personnel := ice.program.effect_type == NetProgram.EffectType.DAMAGE_RUNNER
				var attacker_name := ice.program.program_name
				var prog_ref: NetProgram = ice.program
				ice.attacked_netrunner.connect(func(strength: int) -> void:
					if combat_animator and is_instance_valid(netrunner):
						var vis: Dictionary = prog_ref.get_attack_visual() if is_instance_valid(prog_ref) else ENEMY_ATTACK_VISUAL
						combat_animator.play_effect(ice.current_position, netrunner.current_position, vis)
					_on_ice_attacked(strength, attacker_name, is_anti_personnel, prog_ref))
				# Anti-program (DEREZ_ICE) ICE scans for rezzed attack programs in
				# LoS and emits attacked_program(attacker_str, tile_coord) when it
				# spots one. The game session resolves an opposed roll (Killer
				# STR + 1D10 vs rezzed program integrity + 1D10); only the Killer
				# can deal damage on a win.
				ice.attacked_program.connect(func(atk_str: int, target_coord: Vector2i) -> void:
					if combat_animator:
						var vis: Dictionary = prog_ref.get_attack_visual() if is_instance_valid(prog_ref) else ENEMY_ATTACK_VISUAL
						combat_animator.play_effect(ice.current_position, target_coord, vis)
					_on_ice_attacked_program(atk_str, target_coord, ice))
				# DETECTION ICE (Watchdog) emits alarm_triggered when it detects
				# the netrunner. The game session activates all other attack ICE.
				ice.alarm_triggered.connect(_on_ice_alarm_triggered)
				# DETECTION ICE (Watchdog) emits trace_succeeded when its CP2020
				# trace check (1D10+STR vs RunState.accumulated_trace) succeeds
				# on first detection. The game session starts the meatspace
				# security-dispatch countdown + escalates the datafort's ICE.
				if not ice.trace_succeeded.is_connected(_on_ice_trace_succeeded):
					ice.trace_succeeded.connect(_on_ice_trace_succeeded)
				ice_nodes.append(ice)
				log_to_terminal("Black ICE '%s' deployed at %s.\n" % [ice.program.program_name, coord])
				# Spawn a 3D glow proxy for this ICE in the compositing layer.
				if board_3d:
					board_3d.spawn_ice_proxy(coord, f)


func spawn_npcs() -> void:
	# Clear any previously spawned NPC nodes (e.g. on subnet reload)
	for npc in npc_nodes:
		if is_instance_valid(npc):
			npc.queue_free()
	npc_nodes.clear()

	if not current_layout:
		return

	var layout_size := Vector2i(current_layout.columns, current_layout.rows)
	# Spawn NPCs on EVERY floor; each NPC remembers its home_floor.
	for f in range(current_layout.get_floor_count()):
		for raw_key in current_layout.get_floor_tiles(f).keys():
			var coord := CP2020DatafortLayout.parse_coord(raw_key)

			var tile = current_layout.get_tile(coord, f)
			if tile == null:
				continue
			var faction: int = -1
			if tile.tile_type == CP2020DatafortLayout.TileType.NETWATCH:
				faction = CP2020NpcNetrunner.Faction.NETWATCH
			elif tile.tile_type == CP2020DatafortLayout.TileType.NETRUNNER:
				faction = CP2020NpcNetrunner.Faction.NETRUNNER
			else:
				continue

			var npc: CP2020NpcNetrunner = NpcNetrunnerScene.instantiate()
			add_child(npc)
			npc.faction = faction
			# Default disposition per faction; a tile override can force it.
			npc.disposition = CP2020NpcNetrunner.Disposition.HOSTILE if faction == CP2020NpcNetrunner.Faction.NETWATCH else CP2020NpcNetrunner.Disposition.NEUTRAL

			# Apply stats BEFORE initialize (initialize copies max_integrity /
			# max_health into current). Per-tile override wins; otherwise use the
			# tier NPC template for this faction.
			if tile.npc_has_override:
				if tile.npc_name != "":
					npc.npc_name = tile.npc_name
				if tile.npc_strength > 0:
					npc.strength = tile.npc_strength
				if tile.npc_max_ap > 0:
					npc.max_ap = tile.npc_max_ap
				if tile.npc_max_integrity > 0:
					npc.max_integrity = tile.npc_max_integrity
				if tile.npc_max_health > 0:
					npc.max_health = tile.npc_max_health
				if tile.npc_max_mu > 0:
					npc.max_memory_units = tile.npc_max_mu
				if tile.npc_deck_name != "":
					npc.deck_name = tile.npc_deck_name
				if tile.npc_disposition_override:
					npc.disposition = tile.npc_disposition
				npc.installed_programs = _duplicate_programs(tile.npc_programs)
				# Capture the original .tres paths of the authored override
				# programs so they can be catalogued on defeat (the duplicates
				# in installed_programs lose resource_path).
				npc.source_program_paths = _collect_program_paths(tile.npc_programs)
			else:
				var tier_key: int = _current_security_tier
				if not TIER_NPC_TEMPLATES.has(tier_key):
					tier_key = CP2020SecurityTier.Tier.LEVEL_1
				var tier_dict: Dictionary = TIER_NPC_TEMPLATES[tier_key]
				if not tier_dict.has(faction):
					tier_dict = TIER_NPC_TEMPLATES[CP2020SecurityTier.Tier.LEVEL_1]
				var tmpl: Dictionary = tier_dict[faction]
				npc.npc_name = String(tmpl.get("name", "NPC"))
				npc.deck_name = String(tmpl.get("deck", "Deck"))
				npc.strength = int(tmpl.get("strength", 4))
				npc.max_ap = int(tmpl.get("max_ap", 3))
				npc.max_integrity = int(tmpl.get("max_integrity", 5))
				npc.max_health = int(tmpl.get("max_health", 10))
				npc.max_memory_units = int(tmpl.get("max_mu", 10))
				npc.installed_programs = _load_template_programs(tmpl.get("programs", []))
				# Template "programs" is already an Array of .tres path strings;
				# keep them verbatim for catalogue unlocking on defeat.
				npc.source_program_paths = _collect_template_paths(tmpl.get("programs", []))

			npc.initialize(coord, layout_size)
			npc.home_floor = f
			npc.message_logged.connect(log_to_terminal)
			npc.moved_to.connect(_on_ice_moved)
			npc.attacked_netrunner.connect(func(strength: int) -> void:
				if combat_animator and is_instance_valid(netrunner):
					combat_animator.play_effect(npc.current_position, netrunner.current_position, ENEMY_ATTACK_VISUAL)
				_on_ice_attacked(strength, npc.npc_name, true, null))
			npc.destroyed.connect(_on_npc_destroyed.bind(npc))
			npc_nodes.append(npc)
			var faction_label = "NetWatch" if faction == CP2020NpcNetrunner.Faction.NETWATCH else "Netrunner"
			log_to_terminal("%s NPC '%s' (%s) deployed at %s.\n" % [faction_label, npc.npc_name, npc.deck_name, coord])


# Load + duplicate program resources listed by .tres path in a template, so
# cached resources are never mutated across runs. Missing paths are skipped.
func _load_template_programs(paths: Array) -> Array[NetProgram]:
	var out: Array[NetProgram] = []
	for p in paths:
		var path := String(p)
		if path != "" and ResourceLoader.exists(path):
			var prog = ResourceLoader.load(path) as NetProgram
			if prog:
				out.append(prog.duplicate())
	return out


func _duplicate_programs(programs: Array) -> Array[NetProgram]:
	var out: Array[NetProgram] = []
	for p in programs:
		if p is NetProgram:
			out.append(p.duplicate())
	return out


# Collect the original .tres resource paths from an array of authored
# NetProgram resources (per-tile override programs). Duplicates made later
# lose resource_path, so capture the paths here at spawn time.
func _collect_program_paths(programs: Array) -> Array[String]:
	var out: Array[String] = []
	for p in programs:
		if p is NetProgram:
			var rp := String(p.resource_path)
			if rp != "":
				out.append(rp)
	return out


# Collect .tres path strings from a tier template's "programs" entry.
func _collect_template_paths(paths: Array) -> Array[String]:
	var out: Array[String] = []
	for p in paths:
		var s := String(p)
		if s != "":
			out.append(s)
	return out


func _on_npc_destroyed(npc: CP2020NpcNetrunner) -> void:
	npc_nodes.erase(npc)
	if npc == null:
		return
	# Unlock the defeated NPC's programs into the persistent vendor catalogue.
	#
	# NPC programs are duplicate()d at spawn (see _load_template_programs /
	# _duplicate_programs) and Godot's Resource.duplicate() does NOT carry
	# over resource_path, so the live installed_programs entries have empty
	# paths and unlock_program_resource would skip them. Instead we unlock
	# the ORIGINAL .tres paths:
	#   1. From the tier template (TIER_NPC_TEMPLATES[_current_security_tier]
	#      [npc.faction]["programs"]) — always, for defeating a tier-faction
	#      NPC. This is the common path: template-spawned NPCs.
	#   2. From npc.source_program_paths — captured at spawn, this covers
	#      per-tile-override NPCs whose authored programs differ from the
	#      tier template, and also re-lists the template paths for template
	#      NPCs. Any installed program that still carries a real
	#      resource_path (i.e. was NOT duplicated) is unlocked too as a
	#      defensive catch-all.
	# The NPC carries no Cyberdeck resource (only a deck_name String), so
	# there is no deck to unlock via defeat — this remains a known limitation.
	var unlocked_count: int = 0

	# (1) Tier template paths.
	var tier_key: int = _current_security_tier
	if TIER_NPC_TEMPLATES.has(tier_key):
		var tier_dict: Dictionary = TIER_NPC_TEMPLATES[tier_key]
		if tier_dict.has(npc.faction):
			var tmpl: Dictionary = tier_dict[npc.faction]
			for p in tmpl.get("programs", []):
				var path := String(p)
				if path != "" and MetaState.unlock_program(path):
					unlocked_count += 1

	# (2) Source paths captured at spawn (override + template re-list) and
	#     any installed program that still has a real resource_path.
	for path in npc.source_program_paths:
		if path != "" and MetaState.unlock_program(path):
			unlocked_count += 1
	for prog in npc.installed_programs:
		if prog is NetProgram:
			var rp := String((prog as NetProgram).resource_path)
			if rp != "" and MetaState.unlock_program(rp):
				unlocked_count += 1

	log_to_terminal("Defeated %s — %d program(s) added to your catalogue.\n" % [npc.npc_name, unlocked_count])


# Spawn the datafort adversary node (the CPUs themselves). The datafort runs
# its own resident programs against the runner and tracks Krash-crashed CPUs.
func spawn_datafort() -> void:
	if is_instance_valid(datafort):
		datafort.queue_free()
	datafort = null

	if not current_layout:
		return

	datafort = CP2020Datafort.new()
	add_child(datafort)
	datafort.message_logged.connect(log_to_terminal)
	datafort.attacked_netrunner.connect(func(strength: int) -> void:
		_on_ice_attacked(strength, datafort.fort_name, true, null))
	if not datafort.attacked_runner_deck.is_connected(_on_runner_deck_attacked):
		datafort.attacked_runner_deck.connect(_on_runner_deck_attacked)
	datafort.cpu_crashed.connect(_on_cpu_state_changed)
	datafort.cpu_rebooted.connect(_on_cpu_state_changed)
	datafort.state_changed.connect(update_datafort_info)
	datafort.initialize(current_layout)
	update_datafort_info()


func _on_cpu_state_changed(_coord: Vector2i) -> void:
	if board_renderer:
		board_renderer.request_redraw()
	update_datafort_info()


func update_datafort_info(_unused: Variant = null) -> void:
	if not datafort_label or not datafort:
		return
	datafort_label.text = "Datafort: %s | CPUs %d/%d | INT %d | %d act/turn | MU %d/%d" % [
		datafort.fort_name,
		datafort.active_cpu_count(),
		datafort.cpus.size(),
		datafort.total_int(),
		datafort.actions_per_turn(),
		datafort.used_mu(),
		datafort.total_mu(),
	]


# Resolve the security tier for the current datafort. Set at dive time by the
# City Grid (RunState.selected_security_tier) based on the datafort icon's
# tier. Falls back to LEVEL_1 if unset (e.g. legacy direct entry).
func _resolve_security_tier(_subnet_path: String) -> int:
	var tier: int = int(RunState.selected_security_tier)
	if tier < 0 or tier >= CP2020SecurityTier.Tier.size():
		return CP2020SecurityTier.Tier.LEVEL_1
	return tier

func _end_player_turn() -> void:
	if not turn_manager or not current_layout or not netrunner:
		return
	if not turn_manager.is_netrunner_turn:
		return
	log_to_terminal("--- Netrunner turn ended. ---\n")
	var sys_int := datafort.total_int() if is_instance_valid(datafort) else 0
	var nr_init := _netrunner_initiative()
	turn_manager.end_round(_all_adversaries(), netrunner.current_position, current_layout, nr_init, sys_int)
	# DEREZ_ICE (Killer) ICE is stationary — it never moves, so the moved_to
	# signal never fires and the board wouldn't redraw after a Worm attack.
	# Force a redraw so worm damage / destruction visuals update immediately.
	if board_renderer:
		board_renderer.request_redraw()

func _on_turn_ended(is_netrunner_turn: bool) -> void:
	if is_netrunner_turn:
		log_to_terminal("--- Netrunner turn begins. ---\n")
		# Worm program tick: decrement the countdown on every worm-active
		# tile and open it when the counter reaches 0. This runs BEFORE the
		# deck-crash tick so a worm completing this turn opens the tile
		# regardless of deck state (the worm is autonomous once deployed).
		_tick_worm_programs()
		# Watchdog beacon tick: scan each deployed beacon for enemies (ICE or
		# NPC netrunners) within 20-space LoS and log an alert on first
		# detection. This gives the netrunner advance warning of flanking
		# enemies.
		_tick_watchdog_beacons()
		# Rezzed attack-program auto-follow: move each rezzed program on the
		# runner's floor to trail the runner (stay adjacent). Runs at the
		# start of the netrunner turn so the programs are positioned before
		# the player acts. Does not consume the runner's movement points.
		_tick_rezzed_programs()
		# Anti-system deck-crash tick: decrement the crash timer at the start
		# of each netrunner turn, then drop the action economy to 0 while the
		# deck is still crashed (movement remains available so the runner can
		# flee). tick_deck_crash is called first so a timer expiring this turn
		# frees the action budget immediately.
		if is_instance_valid(netrunner) and netrunner.deck_crashed_turns > 0:
			netrunner.tick_deck_crash()
		if is_instance_valid(netrunner) and netrunner.deck_crashed_turns > 0 and turn_manager:
			# Deck crash blocks programs but preserves a movement action so the
			# runner can flee (CP2020 RAW). actions_remaining stays at full so
			# movement works; programs_blocked gates program use.
			turn_manager.block_programs()
			log_to_terminal("Cyberdeck crashed — programs unavailable this turn (movement only).\n")
		# CP2020 Death Trap: a stunned (unconscious) runner cannot act OR
		# move. Both action and movement pools are zeroed. Black ICE will
		# auto-hit every turn until the runner flatlines or is rescued by a
		# meat-space ally pulling the plug (future feature).
		if is_instance_valid(netrunner) and netrunner.is_stunned and turn_manager:
			# Stun zeroes the action pool — movement now requires an action, so
			# this blocks both programs AND movement (Death Trap).
			turn_manager.apply_stun()
			log_to_terminal("STUNNED — unconscious! Cannot act, move, or jack out. Black ICE auto-hits!\n")
		# Meatspace security-dispatch tick: if a Watchdog traced the runner,
		# countdown the raid ETA each netrunner turn. At 0 the raid arrives
		# while the runner is still jacked in → Busted permadeath. Ticking at
		# the start of the turn gives the runner the full rolled window to
		# finish up and jack out (which clears the timer — escaping the raid).
		if RunState.security_dispatch_turns > 0:
			RunState.security_dispatch_turns -= 1
			if RunState.security_dispatch_turns > 0:
				log_to_terminal("⚠ SECURITY DISPATCH: %d turn(s) until meatspace raid arrives.\n" % RunState.security_dispatch_turns)
				_update_security_dispatch_hud()
			else:
				log_to_terminal("⚠ SECURITY DISPATCH: meatspace team is at your door!\n")
				_update_security_dispatch_hud()
				_trigger_security_raid()
				return

# Tick all worm-active tiles: decrement worm_turns_remaining and open the tile
# when the counter reaches 0 (DATAWALL -> EMPTY, CODE_GATE -> is_unlocked).
# Called at the start of each netrunner turn by _on_turn_ended.
func _tick_worm_programs() -> void:
	if current_layout == null:
		return
	var opened := false
	# Worms can be deployed on any floor; tick across all of them.
	for f in range(current_layout.get_floor_count()):
		for raw_key in current_layout.get_floor_tiles(f).keys():
			var c := CP2020DatafortLayout.parse_coord(raw_key)
			var t: CP2020TileData = current_layout.get_tile(c, f)
			if t == null or t.worm_turns_remaining <= 0:
				continue
			t.worm_turns_remaining -= 1
			if t.worm_turns_remaining > 0:
				log_to_terminal("Worm working on %s — %d turn(s) remaining.\n" % [c, t.worm_turns_remaining])
				continue
			# Counter reached 0 — open the tile from the inside.
			var is_wall: bool = t.tile_type == CP2020DatafortLayout.TileType.DATAWALL
			var label := "data wall" if is_wall else "code gate"
			if is_wall:
				t.tile_type = CP2020DatafortLayout.TileType.EMPTY
				t.is_visible = true
			else:
				t.is_unlocked = true
			log_to_terminal("Worm has opened the %s at %s from the inside!\n" % [label, c])
			# Worm completed successfully — clear its integrity alongside the
			# counter so a fresh deployment on the same tile starts at full.
			t.worm_integrity = 0
			t.worm_max_integrity = 0
			opened = true
	if opened:
		# Newly opened tiles may reveal previously-occluded grid — recalc fog.
		if is_instance_valid(netrunner):
			recalculate_fog_of_war(netrunner.current_position)
		if board_renderer:
			board_renderer.request_redraw()

# Tick all deployed Watchdog beacons: for each beacon, check LoS to all
# ICE nodes and NPC netrunners within 20 spaces. On first detection per
# beacon, log a WATCHDOG ALERT. Called at the start of each netrunner turn.
func _tick_watchdog_beacons() -> void:
	if current_layout == null or _watchdog_beacons.is_empty():
		return
	var any_alert := false
	for beacon in _watchdog_beacons:
		var key := "%d,%d" % [beacon.x, beacon.y]
		if _watchdog_alerted.get(key, false):
			continue
		# Check all ICE nodes within 20-space LoS of the beacon. Gate by
		# home_floor so a beacon on one floor never detects an entity on
		# another (LoS is computed on current_floor; matching an off-floor
		# entity would be a cross-floor detection leak).
		for ice in ice_nodes:
			if not is_instance_valid(ice) or ice.home_floor != current_floor:
				continue
			if current_layout.line_of_sight(beacon, ice.current_position, 20, current_floor):
				log_to_terminal("WATCHDOG ALERT: %s detected at %s!\n" % [ice.program.program_name, ice.current_position])
				_watchdog_alerted[key] = true
				any_alert = true
				break
		if _watchdog_alerted.get(key, false):
			continue
		# Check all NPC netrunner nodes within 20-space LoS of the beacon
		# (same home_floor gate as the ICE loop above).
		for npc in npc_nodes:
			if not is_instance_valid(npc) or npc.home_floor != current_floor:
				continue
			if current_layout.line_of_sight(beacon, npc.current_position, 20, current_floor):
				log_to_terminal("WATCHDOG ALERT: %s detected at %s!\n" % [npc.npc_name, npc.current_position])
				_watchdog_alerted[key] = true
				any_alert = true
				break
	if any_alert and board_renderer:
		board_renderer.request_redraw()

func _on_actions_changed(remaining: int, max_actions: int) -> void:
	if actions_label:
		actions_label.text = "Actions: %d / %d | Move: %d / %d" % [remaining, max_actions, turn_manager.movement_remaining if turn_manager else 0, turn_manager.max_movement if turn_manager else 0]
	_update_clock_label()
	log_to_terminal("Actions: %d / %d\n" % [remaining, max_actions])

func _on_movement_changed(remaining: int, max_movement: int) -> void:
	if actions_label and turn_manager:
		actions_label.text = "Actions: %d / %d | Move: %d / %d" % [turn_manager.actions_remaining, turn_manager.max_actions, remaining, max_movement]
	_update_clock_label()
	log_to_terminal("Move: %d / %d\n" % [remaining, max_movement])

func _on_action_consumed() -> void:
	RunState.net_time_seconds += CP2020TimeScale.DATAFORT_SECONDS
	_update_clock_label()

func _update_clock_label() -> void:
	if clock_label:
		clock_label.text = "NET: %s" % CP2020TimeScale.format_clock(RunState.net_time_seconds)

func _on_initiative_rolled(netrunner_roll: int, system_roll: int, netrunner_first: bool, is_tie: bool = false) -> void:
	if is_tie:
		log_to_terminal("Initiative: Netrunner %d vs System %d — TIE! Actions occur simultaneously.\n" % [netrunner_roll, system_roll])
	elif netrunner_first:
		log_to_terminal("Initiative: Netrunner %d vs System %d — Netrunner acts first!\n" % [netrunner_roll, system_roll])
	else:
		log_to_terminal("Initiative: Netrunner %d vs System %d — System acts first!\n" % [netrunner_roll, system_roll])

func _check_actions_exhausted() -> void:
	# The netrunner's turn ends only when both the action budget AND the
	# movement budget are exhausted (or they explicitly end the turn). This
	# lets a runner move freely after using their single program/Net action,
	# and vice versa, matching the CP2020 action economy.
	if turn_manager and turn_manager.actions_remaining <= 0:
		log_to_terminal("Out of actions — ending turn.\n")
		var sys_int := datafort.total_int() if is_instance_valid(datafort) else 0
		var nr_init := _netrunner_initiative()
		turn_manager.end_round(_all_adversaries(), netrunner.current_position, current_layout, nr_init, sys_int)

# Netrunner initiative = REF + cyberdeck speed bonus + temporary speed bonus.
# Centralised so every end-of-turn roll uses one definition.
func _netrunner_initiative() -> int:
	var speed_bonus := RunState.selected_deck.effective_speed_bonus() if RunState.selected_deck != null else 0
	return netrunner.reflex + speed_bonus + netrunner.temp_speed_bonus

# Combined adversaries (Datafort + Black ICE + NPC netrunners) for the turn
# manager. The datafort is prepended so it acts first each round. The turn
# manager only requires each entry to have a take_turn(target, layout)
# method, which all three share.
func _all_adversaries() -> Array:
	var out: Array = []
	if is_instance_valid(datafort):
		out.append(datafort)
	# Adversaries only act on their home floor — they never follow the
	# runner between floors. ICE/NPC on other floors sit idle this turn.
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.home_floor == current_floor:
			out.append(ice)
	for npc in npc_nodes:
		if is_instance_valid(npc) and npc.home_floor == current_floor:
			out.append(npc)
	return out

func _on_health_changed(current: int, max_hp: int) -> void:
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current
	if health_label:
		health_label.text = "Health: %d / %d" % [current, max_hp]
	if health_bar:
		if max_hp > 0 and float(current) / float(max_hp) <= 0.3:
			health_bar.modulate = Color.RED
		else:
			health_bar.modulate = Color.WHITE

func _on_ice_stepped() -> void:
	if board_renderer:
		board_renderer.request_redraw()

func _on_ice_moved(_new_pos: Vector2i) -> void:
	if board_renderer:
		board_renderer.request_redraw()

func _on_ice_attacked(strength: int, attacker_name: String, is_anti_personnel: bool, prog: NetProgram = null) -> void:
	# Shared by Black ICE, NPC netrunners, and datafort resident programs —
	# all emit attacked_netrunner. `is_anti_personnel` distinguishes
	# DAMAGE_RUNNER programs (INT loss + Stun/Mortal saves) from DEREZ_ICE
	# programs (which route through attacked_program instead and never
	# reach this handler). `prog` is the attacking program (used to roll
	# the payload after the interface defense roll); null for flat-STR
	# attacks from NPCs/dataforts.
	var label = "Adversary" if attacker_name.is_empty() else attacker_name
	log_to_terminal("WARNING: %s attacks for %d!\n" % [label, strength])
	if netrunner:
		netrunner.apply_damage(strength, label, is_anti_personnel, prog)

# Anti-program (DEREZ_ICE) Killer spotted a rezzed attack program in LoS.
# Resolve an opposed roll (CP2020 anti-program combat): Killer STR + 1D10 vs
# rezzed program integrity + 1D10. Only the Killer can deal damage on a win —
# rezzed programs are passive defenders during the adversary phase (they
# fight back via player command on the runner's turn). If the rezzed program
# wins or ties, no damage to either side. If the Killer wins, the rezzed
# program takes 1D6 damage; at 0 integrity it is de-rezzed (take_damage
# frees the node and _on_rezzed_program_destroyed erases it from the list).
# Shield does NOT block this.
func _on_ice_attacked_program(attacker_str: int, tile_coord: Vector2i, ice: BlackIce) -> void:
	var attacker_name := ice.program.program_name
	# Find the rezzed program at the target coord on the ICE's floor.
	var target_rez: RezzedProgram = null
	for rez in rezzed_program_nodes:
		if not is_instance_valid(rez):
			continue
		if rez.home_floor != ice.home_floor:
			continue
		if rez.current_position == tile_coord:
			target_rez = rez
			break
	if target_rez == null:
		log_to_terminal("%s's anti-program attack finds no target at %s.\n" % [attacker_name, tile_coord])
		return
	var result := CP2020Dice.roll_opposed(attacker_str, target_rez.current_integrity)
	log_to_terminal("WARNING: %s attacks '%s' at %s — opposed roll: Killer %d (1D10+%d) vs Program %d (1D10+%d).\n" % [attacker_name, target_rez.program.program_name, tile_coord, result.atk_roll, attacker_str, result.def_roll, target_rez.current_integrity])
	if result.attacker_wins:
		var dmg := randi_range(1, 6)
		log_to_terminal("Killer wins! '%s' takes %d damage.\n" % [target_rez.program.program_name, dmg])
		target_rez.take_damage(dmg)
	else:
		log_to_terminal("'%s' holds — no damage dealt (passive defender).\n" % target_rez.program.program_name)
	if board_renderer:
		board_renderer.request_redraw()

# Anti-system (CRASH_CPU / Krash) resident program from the datafort hit the
# runner's cyberdeck: crash it for 1D6+1 turns (mirroring crash_cpu's CPU
# crash duration), dropping the runner's action economy to 0 until reboot.
# `strength` is the program's STR — reserved for a future opposed-roll check;
# for now the deck crash lands when the datafort has LoS to fire the program.
func _on_runner_deck_attacked(strength: int) -> void:
	var attacker_name := datafort.fort_name if is_instance_valid(datafort) else "Datafort"
	log_to_terminal("WARNING: %s executes anti-system attack (STR %d) — cyberdeck targeted!\n" % [attacker_name, strength])
	if is_instance_valid(netrunner):
		netrunner.crash_deck(randi_range(1, 6) + 1, attacker_name)

func _on_stunned() -> void:
	# CP2020 Death Trap: stun takes effect immediately. The turn-start
	# handler in _on_turn_ended zeroes the runner's action AND movement
	# pools while is_stunned is true; jack-out and movement are blocked.
	# Redraw the deck panel to reflect the stunned state.
	update_deck_info()

func _on_flatlined() -> void:
	# Idempotent + null-safe: a deferred adversary attack (e.g. the datafort's
	# multi-action take_turn loop resuming after a 0.3s await that crossed the
	# GameOver scene swap) can re-emit flatlined once the session is detached
	# from the tree. Bail once the scene change is queued, and never touch
	# get_tree() when we're no longer in the scene tree.
	if _game_over_queued:
		return
	_game_over_queued = true
	log_to_terminal("=== GAME OVER: Netrunner flatlined. Jack out. ===\n")
	# Permadeath on flatline — record the run, route to the GameOver scene.
	# The GameOver scene's "New Life" button calls start_new_life().
	var summary: Dictionary = {
		"cause": "Flatlined",
		"trace": RunState.accumulated_trace,
		"credits": RunState.credits,
		"loot_count": RunState.loot.size(),
		"files_count": RunState.carried_files.size(),
		"datafort": RunState.selected_subnet_path,
		"security_tier": RunState.selected_security_tier,
	}
	MetaState.record_run(summary)
	RunState.last_death_cause = "Flatlined"
	RunState.last_run_summary = summary
	RunState.security_dispatch_turns = 0
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/ui/GameOver.tscn")

func _on_jack_out_pressed() -> void:
	# CP2020 Death Trap: a stunned (unconscious) runner cannot jack out.
	if is_instance_valid(netrunner) and netrunner.is_stunned:
		log_to_terminal("Cannot jack out while stunned — unconscious in meatspace!\n")
		return
	# Busted check FIRST — before clearing trace (the summary needs it). If the
	# runner's accumulated trace has hit the threshold, NetWatch arrests them
	# on jack-out: permadeath, run ends in a BUSTED game-over.
	if RunState.accumulated_trace >= BUSTED_THRESHOLD:
		log_to_terminal("BUSTED — NetWatch traced your signal and busted you on jack-out. They confiscated everything.\n")
		var summary: Dictionary = {
			"cause": "Busted",
			"trace": RunState.accumulated_trace,
			"credits": RunState.credits,
			"loot_count": RunState.loot.size(),
			"files_count": RunState.carried_files.size(),
			"datafort": RunState.selected_subnet_path,
			"security_tier": RunState.selected_security_tier,
			}
		MetaState.record_run(summary)
		RunState.last_death_cause = "Busted"
		RunState.last_run_summary = summary
		_game_over_queued = true
		if is_inside_tree():
			get_tree().change_scene_to_file("res://scenes/ui/GameOver.tscn")
		return
	# Successful jack-out — escape with loot intact to fence at the hub.
	# Ends the run: trace + run context cleared, back to the Workbench.
	log_to_terminal("Jacking out...\n")
	RunState.accumulated_trace = 0
	RunState.security_dispatch_turns = 0
	RunState.net_time_seconds = 0.0
	RunState.selected_subnet_path = ""
	RunState.selected_city_grid_path = ""
	RunState.selected_security_tier = 0
	get_tree().change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")
func recalculate_fog_of_war(player_pos: Vector2i) -> void:
	if not current_layout:
		return
		
	# 1. Reset visibility for all tiles on ALL floors (visibility changes
	# dynamically every move). Only is_visible is reset; is_explored is
	# preserved so previously-visited floors stay revealed when revisited.
	for f in range(current_layout.get_floor_count()):
		for raw_key in current_layout.get_floor_tiles(f).keys():
			var coord := CP2020DatafortLayout.parse_coord(raw_key)
			var tile = current_layout.get_tile(coord, f)
			if tile:
				tile.is_visible = false
			
	# 2. Vision radius comes from the netrunner's own sight_range (separate
	# from program sight ranges so future modifiers affect only one side).
	var vision_radius := netrunner.sight_range

	# 3. Scan square area around player and check line of sight
	for x in range(-vision_radius, vision_radius + 1):
		for y in range(-vision_radius, vision_radius + 1):
			var target_pos = player_pos + Vector2i(x, y)

			# Ensure target is within datafort bounds
			if target_pos.x < 0 or target_pos.x >= current_layout.columns or target_pos.y < 0 or target_pos.y >= current_layout.rows:
				continue

			# Shared helper does both the distance check and wall/gate blocking.
			if current_layout.line_of_sight(player_pos, target_pos, vision_radius, current_floor):
				var tile = current_layout.get_tile(target_pos, current_floor)
				if tile:
					tile.is_visible = true
					tile.is_explored = true

	# Sync Black ICE skull visibility with the freshly computed fog state.
	# Each ICE reads the fog of its OWN home floor — entities on other
	# floors stay hidden (their floor's tiles are dark this turn).
	for ice in ice_nodes:
		if is_instance_valid(ice):
			var ice_tile = current_layout.get_tile(ice.current_position, ice.home_floor)
			if ice_tile:
				ice.update_visibility(ice_tile.is_explored, ice_tile.is_visible)

	# Sync NPC glyph visibility with the fog state too (same per-floor rule).
	for npc in npc_nodes:
		if is_instance_valid(npc):
			var npc_tile = current_layout.get_tile(npc.current_position, npc.home_floor)
			if npc_tile:
				npc.update_visibility(npc_tile.is_explored, npc_tile.is_visible)

	# Sync rezzed program glyph visibility with the fog state (per-floor).
	for rez in rezzed_program_nodes:
		if is_instance_valid(rez):
			var rez_tile = current_layout.get_tile(rez.current_position, rez.home_floor)
			if rez_tile:
				rez.update_visibility(rez_tile.is_explored, rez_tile.is_visible)


# Thin wrapper around the shared CP2020DatafortLayout.line_of_sight helper,
# kept so existing README/ARCHITECTURE references and call sites stay valid.
# Uses the netrunner's own sight_range as the max range.
func _has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if not current_layout:
		return false
	return current_layout.line_of_sight(from, to, netrunner.sight_range, current_floor)
