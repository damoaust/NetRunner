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
@onready var datafort_label: Label = $UI/PanelContainer/VBoxContainer/DatafortLabel
@onready var program_list_container: VBoxContainer = $UI/PanelContainer/VBoxContainer/ProgramListContainer
@onready var netrunner: CP2020Netrunner = $CP2020Netrunner
@onready var turn_manager: CP2020TurnManager = $TurnManager
@onready var camera: Camera2D = board_renderer.get_node_or_null("RunnerCamera") if board_renderer else null

const BlackIceScene := preload("res://scenes/ui/cp2020_blackice.tscn")
const NpcNetrunnerScene := preload("res://scenes/ui/cp2020_npc_netrunner.tscn")

# Permadeath: if accumulated trace reaches this threshold on jack-out, NetWatch
# arrests the runner and the run ends in a BUSTED game-over. Tunable — each
# LDL jump adds ~5 trace, so a deep run through several dataforts risks busting.
const BUSTED_THRESHOLD: int = 40
var ice_nodes: Array[BlackIce] = []
var npc_nodes: Array[CP2020NpcNetrunner] = []
var datafort: CP2020Datafort = null

var current_layout: CP2020DatafortLayout
# Resolved tier for the current datafort (set at dive time by the City Grid).
var _current_security_tier: int = CP2020SecurityTier.Tier.LEVEL_1

# Tier -> default ICE template. Used when a BLACK_ICE tile has no per-tile
# override (ice_has_override == false). Stats follow CP2020 progression:
# Grey = alarm/detection only (weak Watchdog), L1/L2 = anti-IC Killers,
# L3 = non-fatal anti-personnel (Hellhound, tracing), Black = fatal
# anti-personnel (Flatline, tracing).
const TIER_ICE_TEMPLATES: Dictionary = {
	CP2020SecurityTier.Tier.GREY:     {"name": "Watchdog",   "strength": 2, "max_ap": 2, "max_integrity": 3, "traces": false},
	CP2020SecurityTier.Tier.LEVEL_1:  {"name": "Killer 1.0", "strength": 3, "max_ap": 2, "max_integrity": 4, "traces": false},
	CP2020SecurityTier.Tier.LEVEL_2:  {"name": "Killer 2.0", "strength": 4, "max_ap": 3, "max_integrity": 5, "traces": false},
	CP2020SecurityTier.Tier.LEVEL_3:  {"name": "Hellhound",  "strength": 5, "max_ap": 3, "max_integrity": 6, "traces": true},
	CP2020SecurityTier.Tier.BLACK:    {"name": "Flatline",   "strength": 6, "max_ap": 4, "max_integrity": 8, "traces": true},
}

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
		if not turn_manager.initiative_rolled.is_connected(_on_initiative_rolled):
			turn_manager.initiative_rolled.connect(_on_initiative_rolled)
		turn_manager.start_netrunner_turn()

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
		if not netrunner.health_changed.is_connected(_on_health_changed):
			netrunner.health_changed.connect(_on_health_changed)
		if netrunner.position_changed.is_connected(_center_camera_on_runner) == false:
			netrunner.position_changed.connect(_center_camera_on_runner)

	# Apply the selected cyberdeck from the workbench (if any)
	if RunState.selected_deck:
		var deck := RunState.selected_deck
		netrunner.deck_name = deck.deck_name
		netrunner.max_memory_units = deck.max_mu
		netrunner.interface_rank = deck.interface_rank
		netrunner.installed_programs = deck.installed_programs.duplicate()

	# Load the subnet chosen on the world map (fall back to default)
	var subnet_path := RunState.selected_subnet_path if RunState.selected_subnet_path != "" else starting_subnet_path
	load_subnet(subnet_path)
	update_deck_info()
	_on_health_changed(netrunner.current_health, netrunner.max_health)
	_update_trace()
	log_to_terminal("JACKED IN. Connection established to matrix grid.\n")

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
		#reveal_entry_points()

		# Reset fog state on every tile. ResourceLoader returns a cached
		# instance, so a datafort visited on a previous run (or earlier in
		# this run via LDL travel) would otherwise retain is_explored=true
		# and show as already-revealed. A fresh run starts fully fogged.
		for raw_key in current_layout.grid_tiles.keys():
			var c: Vector2i
			if raw_key is String:
				var p = raw_key.split(",")
				c = Vector2i(p[0].to_int(), p[1].to_int())
			else:
				c = raw_key
			var t = current_layout.get_tile(c)
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
		board_renderer.queue_redraw()
	return true

func _update_trace() -> void:
	if trace_label:
		trace_label.text = "Trace: %d" % RunState.accumulated_trace

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

func _input(event: InputEvent) -> void:
	# Right-click is handled here in _input (NOT _unhandled_input) because the root
	# Control node's GUI system consumes mouse events before _unhandled_input fires.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		accept_event() # Prevent GUI system from re-processing this
		var mouse_pos: Vector2 = board_renderer.get_global_mouse_position() if board_renderer else get_viewport().get_mouse_position()
		var programs: Array[NetProgram] = netrunner.installed_programs if netrunner else []
		print("DEBUG [session] right-click at ", mouse_pos, " programs=", programs.size())
		if interaction_handler and current_layout:
			var cs: float = board_renderer.cell_size if board_renderer else 40.0
			var go_y: float = board_renderer.grid_offset_y if board_renderer else 90.0
			var nr_pos: Vector2i = netrunner.current_position if netrunner else Vector2i(-1, -1)
			interaction_handler.handle_input(event, mouse_pos, current_layout, programs, cs, go_y, ice_nodes, nr_pos, npc_nodes, netrunner)

	# --- KEYBOARD INPUT (Pass to Netrunner) ---
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_end_player_turn()
			return

		var dir = Vector2i.ZERO
		if event.keycode in [KEY_W, KEY_UP]: dir = Vector2i(0, -1)
		elif event.keycode in [KEY_S, KEY_DOWN]: dir = Vector2i(0, 1)
		elif event.keycode in [KEY_A, KEY_LEFT]: dir = Vector2i(-1, 0)
		elif event.keycode in [KEY_D, KEY_RIGHT]: dir = Vector2i(1, 0)
		
		if dir != Vector2i.ZERO and netrunner:
			if turn_manager and not turn_manager.has_actions():
				log_to_terminal("No actions remaining. End turn (Space) to let ICE move.\n")
				return
			var moved_successfully = netrunner.move(dir)
			if moved_successfully:
				if turn_manager:
					turn_manager.consume_action()
				recalculate_fog_of_war(netrunner.current_position)
				board_renderer.queue_redraw()
				_check_actions_exhausted()

func _on_action_triggered(action_name: String, target_coord: Vector2i, program = null) -> void:
	match action_name:
		"use_program":
			if program is NetProgram and current_layout:
				if turn_manager and not turn_manager.has_actions():
					log_to_terminal("No actions remaining. End turn (Space) to let ICE move.\n")
					return
				if program.effect_type == NetProgram.EffectType.BYPASS_GATE:
					execute_decryption(program, target_coord)
				elif program.effect_type == NetProgram.EffectType.BREACH_WALL:
					execute_wall_breach(program, target_coord)
				elif program.effect_type == NetProgram.EffectType.DEREZ_ICE:
					execute_ice_attack(program, target_coord)
				elif program.effect_type == NetProgram.EffectType.SHIELD:
					execute_shield(program)
				else:
					log_to_terminal("Program effect not implemented yet.\n")
					return
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
					log_to_terminal("Travelling LDL to %s (entry %s). Trace preserved.\n" % [dest_path, dest_coord])
					update_deck_info()
					_update_trace()
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
				get_tree().change_scene_to_file("res://scenes/ui/cp2020_world_net_map.tscn")
		"attack_npc":
			if program is NetProgram and current_layout:
				if turn_manager and not turn_manager.has_actions():
					log_to_terminal("No actions remaining. End turn (Space) to let adversaries move.\n")
					return
				execute_npc_attack(program, target_coord)
				if turn_manager:
					turn_manager.consume_action()
				_check_actions_exhausted()
		"talk_npc":
			_talk_to_npc(target_coord)
		"crash_cpu":
			if program is NetProgram and current_layout:
				if turn_manager and not turn_manager.has_actions():
					log_to_terminal("No actions remaining. End turn (Space) to let adversaries move.\n")
					return
				if is_instance_valid(datafort):
					datafort.crash_cpu(program, target_coord)
				if board_renderer:
					board_renderer.queue_redraw()
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
				var tile: CP2020TileData = current_layout.get_tile(target_coord)
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
				var free_mu: int = netrunner.max_memory_units - netrunner.get_used_memory() if netrunner else 999999
				if file.mu_size > free_mu:
					log_to_terminal("Not enough free deck memory for %s (need %d MU, have %d).\n" % [file.file_name, file.mu_size, free_mu])
					return
				RunState.copy_file(file)
				tile.copied_file_paths.append(str(idx))
				log_to_terminal("Copied %s to deck memory (%d MU).\n" % [file.file_name, file.mu_size])
				if board_renderer:
					board_renderer.queue_redraw()
		"copy_all_files":
			# Batch-copy every fitting file from a MEMORY_UNIT tile to the
			# deck. Like copy_file, this does NOT consume an action or end
			# the turn — it is a free data retrieval action.
			if current_layout:
				var tile: CP2020TileData = current_layout.get_tile(target_coord)
				if not tile:
					push_warning("copy_all_files: no tile at %s." % target_coord)
					return
				if tile.files.is_empty():
					return
				if netrunner:
					var free_mu := netrunner.max_memory_units - netrunner.get_used_memory()
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
					board_renderer.queue_redraw()
				log_to_terminal("Batch copy complete.\n")

func execute_decryption(program: NetProgram, target_coord: Vector2i) -> void:
	var tile = current_layout.get_tile(target_coord)
	if tile:
		log_to_terminal("Executing Bypass Program '%s' on Code Gate at %s...\n" % [program.program_name, target_coord])
		tile.is_unlocked = true
		if board_renderer:
			board_renderer.queue_redraw()

func execute_wall_breach(program: NetProgram, target_coord: Vector2i) -> void:
	var tile = current_layout.get_tile(target_coord)
	if tile:
		log_to_terminal("Executing Wall Breach '%s' on Datawall at %s...\n" % [program.program_name, target_coord])
		tile.is_visible = true
		tile.tile_type = CP2020DatafortLayout.TileType.EMPTY
		log_to_terminal("Datawall breached! Path cleared.\n")
		if board_renderer:
			board_renderer.queue_redraw()

func execute_ice_attack(program: NetProgram, target_coord: Vector2i) -> void:
	var target_ice: BlackIce = null
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.current_position == target_coord:
			target_ice = ice
			break

	if not target_ice:
		log_to_terminal("No Black ICE detected at %s.\n" % target_coord)
		return

	log_to_terminal("Executing Anti-ICE Program '%s' (STR %d) on %s at %s...\n" % [program.program_name, program.strength, target_ice.program_name, target_coord])

	# Opposed roll: 1d10 + STR for both attacker and defender (CP2020 anti-program combat)
	var prog_roll = (randi() % 10) + 1 + program.strength
	var ice_roll = (randi() % 10) + 1 + target_ice.strength
	log_to_terminal("Roll: you %d (1d10+%d) vs %s %d (1d10+%d)\n" % [prog_roll, program.strength, target_ice.program_name, ice_roll, target_ice.strength])

	if prog_roll > ice_roll:
		var damage = prog_roll - ice_roll
		log_to_terminal("Hit! %s takes %d damage.\n" % [target_ice.program_name, damage])
		if target_ice.take_damage(damage):
			ice_nodes.erase(target_ice)
	else:
		log_to_terminal("%s repelled the attack.\n" % target_ice.program_name)

	if board_renderer:
		board_renderer.queue_redraw()

func execute_shield(program: NetProgram) -> void:
	if not netrunner:
		return
	log_to_terminal("Activating Protection Program '%s'...\n" % program.program_name)
	netrunner.raise_shield(program)

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
	var prog_roll = (randi() % 10) + 1 + program.strength
	var npc_roll = (randi() % 10) + 1 + target_npc.strength
	log_to_terminal("Roll: you %d (1d10+%d) vs %s %d (1d10+%d)\n" % [prog_roll, program.strength, target_npc.npc_name, npc_roll, target_npc.strength])
	if prog_roll > npc_roll:
		var damage = prog_roll - npc_roll
		log_to_terminal("Hit! %s takes %d damage.\n" % [target_npc.npc_name, damage])
		# take_damage handles destruction (emits destroyed -> _on_npc_destroyed).
		target_npc.take_damage(damage)
	else:
		log_to_terminal("%s repelled the attack.\n" % target_npc.npc_name)
	if board_renderer:
		board_renderer.queue_redraw()

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
		memory_label.text = "Memory: %d / %d MU" % [netrunner.get_used_memory(), netrunner.max_memory_units]
	if program_list_container:
		for child in program_list_container.get_children():
			child.queue_free()
		for prog in netrunner.installed_programs:
			if not prog:
				continue
			var active := (netrunner.raised_shield == prog)
			var status_prefix = "[ACTIVE] " if active else ""
			var label := Label.new()
			label.text = "%s%s  (STR %d, %d MU)" % [status_prefix, prog.program_name, prog.strength, prog.memory_cost]
			if active:
				label.add_theme_color_override("font_color", Color.GREEN)
			program_list_container.add_child(label)

func spawn_black_ice() -> void:
	# Clear any previously spawned ICE nodes (e.g. on subnet reload)
	for ice in ice_nodes:
		if is_instance_valid(ice):
			ice.queue_free()
	ice_nodes.clear()

	if not current_layout:
		return

	var layout_size := Vector2i(current_layout.columns, current_layout.rows)
	var template: Dictionary = TIER_ICE_TEMPLATES.get(_current_security_tier, TIER_ICE_TEMPLATES[CP2020SecurityTier.Tier.LEVEL_1])
	for raw_key in current_layout.grid_tiles.keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key

		var tile = current_layout.get_tile(coord)
		if tile and tile.tile_type == CP2020DatafortLayout.TileType.BLACK_ICE:
			var ice: BlackIce = BlackIceScene.instantiate()
			add_child(ice)
			# Apply ICE stats BEFORE initialize (initialize copies max_integrity
			# into current_integrity). Per-tile override wins; otherwise use the
			# hub security-tier template.
			if tile.ice_has_override:
				if tile.ice_program_name != "":
					ice.program_name = tile.ice_program_name
				if tile.ice_strength > 0:
					ice.strength = tile.ice_strength
				if tile.ice_max_ap > 0:
					ice.max_ap = tile.ice_max_ap
				if tile.ice_max_integrity > 0:
					ice.max_integrity = tile.ice_max_integrity
				ice.traces = tile.ice_traces
			else:
				ice.program_name = String(template.get("name", "Black ICE"))
				ice.strength = int(template.get("strength", 4))
				ice.max_ap = int(template.get("max_ap", 2))
				ice.max_integrity = int(template.get("max_integrity", 4))
				ice.traces = bool(template.get("traces", false))
			ice.initialize(coord, layout_size)
			ice.message_logged.connect(log_to_terminal)
			ice.moved_to.connect(_on_ice_moved)
			ice.attacked_netrunner.connect(_on_ice_attacked)
			ice_nodes.append(ice)
			log_to_terminal("Black ICE '%s' deployed at %s.\n" % [ice.program_name, coord])


func spawn_npcs() -> void:
	# Clear any previously spawned NPC nodes (e.g. on subnet reload)
	for npc in npc_nodes:
		if is_instance_valid(npc):
			npc.queue_free()
	npc_nodes.clear()

	if not current_layout:
		return

	var layout_size := Vector2i(current_layout.columns, current_layout.rows)
	for raw_key in current_layout.grid_tiles.keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key

		var tile = current_layout.get_tile(coord)
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
			if tile.npc_disposition == CP2020NpcNetrunner.Disposition.HOSTILE or tile.npc_disposition == CP2020NpcNetrunner.Disposition.NEUTRAL:
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
		npc.message_logged.connect(log_to_terminal)
		npc.moved_to.connect(_on_ice_moved)
		npc.attacked_netrunner.connect(_on_ice_attacked)
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
	datafort.attacked_netrunner.connect(_on_ice_attacked)
	datafort.cpu_crashed.connect(_on_cpu_state_changed)
	datafort.cpu_rebooted.connect(_on_cpu_state_changed)
	datafort.state_changed.connect(update_datafort_info)
	datafort.initialize(current_layout)
	update_datafort_info()


func _on_cpu_state_changed(_coord: Vector2i) -> void:
	if board_renderer:
		board_renderer.queue_redraw()
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
	log_to_terminal("--- Netrunner turn ended. Adversaries activating... ---\n")
	var sys_int := datafort.total_int() if is_instance_valid(datafort) else 0
	turn_manager.execute_ice_turns(_all_adversaries(), netrunner.current_position, current_layout, netrunner.interface_rank, sys_int)

func _on_turn_ended(is_netrunner_turn: bool) -> void:
	if is_netrunner_turn:
		log_to_terminal("--- Netrunner turn begins. ---\n")

func _on_actions_changed(remaining: int, max_actions: int) -> void:
	if actions_label:
		actions_label.text = "Actions: %d / %d" % [remaining, max_actions]
	log_to_terminal("Actions: %d / %d\n" % [remaining, max_actions])

func _on_initiative_rolled(netrunner_roll: int, system_roll: int, netrunner_first: bool) -> void:
	if netrunner_first:
		log_to_terminal("Initiative: Netrunner %d vs System %d — Netrunner acts first!\n" % [netrunner_roll, system_roll])
	else:
		log_to_terminal("Initiative: Netrunner %d vs System %d — System acts first!\n" % [netrunner_roll, system_roll])

func _check_actions_exhausted() -> void:
	if turn_manager and turn_manager.actions_remaining <= 0:
		log_to_terminal("Out of actions. Adversaries activating...\n")
		var sys_int := datafort.total_int() if is_instance_valid(datafort) else 0
		turn_manager.execute_ice_turns(_all_adversaries(), netrunner.current_position, current_layout, netrunner.interface_rank, sys_int)

# Combined adversaries (Datafort + Black ICE + NPC netrunners) for the turn
# manager. The datafort is prepended so it acts first each round. The turn
# manager only requires each entry to have a take_turn(target, layout)
# method, which all three share.
func _all_adversaries() -> Array:
	var out: Array = []
	if is_instance_valid(datafort):
		out.append(datafort)
	out.append_array(ice_nodes)
	out.append_array(npc_nodes)
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
		board_renderer.queue_redraw()

func _on_ice_moved(_new_pos: Vector2i) -> void:
	if board_renderer:
		board_renderer.queue_redraw()

func _on_ice_attacked(strength: int) -> void:
	# Shared by Black ICE and NPC netrunners — both emit attacked_netrunner.
	log_to_terminal("WARNING: Adversary attacks for %d!\n" % strength)
	if netrunner:
		netrunner.apply_damage(strength, "Adversary")

func _on_flatlined() -> void:
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
	get_tree().change_scene_to_file("res://scenes/ui/GameOver.tscn")

func _on_jack_out_pressed() -> void:
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
		get_tree().change_scene_to_file("res://scenes/ui/GameOver.tscn")
		return
	# Successful jack-out — escape with loot intact to fence at the hub.
	# Ends the run: trace + run context cleared, back to the Workbench.
	log_to_terminal("Jacking out...\n")
	RunState.accumulated_trace = 0
	RunState.selected_subnet_path = ""
	RunState.selected_city_grid_path = ""
	RunState.selected_security_tier = 0
	get_tree().change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")
#func reveal_entry_points() -> void:
	#if not current_layout:
		#return
		#
	## Find all entry tiles and reveal them so the player can see where they start
	#for raw_key in current_layout.grid_tiles.keys():
		#var coord: Vector2i
		#if raw_key is String:
			#var parts = raw_key.split(",")
			#coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		#else:
			#coord = raw_key
			#
		#var tile = current_layout.get_tile(coord)
		#if tile and tile.tile_type == CP2020DatafortLayout.TileType.ENTRY:
			#tile.is_explored = true
			#tile.is_visible = true
			
			# Optional: Reveal immediate adjacent tiles (up, down, left, right)
			#var adjacent_coords = [
				#coord + Vector2i(0, -1), coord + Vector2i(0, 1),
				#coord + Vector2i(-1, 0), coord + Vector2i(1, 0)
			#]
			#for adj in adjacent_coords:
				#var adj_tile = current_layout.get_tile(adj)
				#if adj_tile:
					#adj_tile.is_explored = true
					# We leave is_visible = false here so they look like "Fog of War" shadows 
					# rather than fully lit active tiles!
func spawn_netrunner_at_entry() -> void:
	if not current_layout or not netrunner or not board_renderer:
		return
		
	for raw_key in current_layout.grid_tiles.keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
			
		var tile = current_layout.get_tile(coord)
		if tile and tile.tile_type == CP2020DatafortLayout.TileType.ENTRY:
			var cell_size = board_renderer.cell_size
			var offset_y = board_renderer.grid_offset_y
			
			# Calculate the exact pixel center of the entry tile
			var target_pixel_pos = Vector2(
				(coord.x * cell_size) + (cell_size / 2.0),
				offset_y + (coord.y * cell_size) + (cell_size / 2.0)
			)
			
			# Move the Netrunner icon
			netrunner.position = target_pixel_pos
			
			# If your Netrunner script has a variable keeping track of its grid coordinate, 
			# update it here (e.g., if it uses "grid_position")
			if "grid_position" in netrunner:
				netrunner.grid_position = coord
				
			log_to_terminal("Netrunner spawned at Entry Node %s.\n" % str(coord))
			return # Stop searching once we place the Netrunner
func recalculate_fog_of_war(player_pos: Vector2i) -> void:
	if not current_layout:
		return
		
	# 1. Reset visibility for all tiles (visibility changes dynamically every move)
	for raw_key in current_layout.grid_tiles.keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
			
		var tile = current_layout.get_tile(coord)
		if tile:
			tile.is_visible = false
			
	# 2. Vision radius defined in architecture reference
	var vision_radius = 10
	
	# 3. Scan square area around player and check line of sight
	for x in range(-vision_radius, vision_radius + 1):
		for y in range(-vision_radius, vision_radius + 1):
			var target_pos = player_pos + Vector2i(x, y)
			
			# Ensure target is within datafort bounds
			if target_pos.x < 0 or target_pos.x >= current_layout.columns or target_pos.y < 0 or target_pos.y >= current_layout.rows:
				continue
				
			# Check if within circular distance and has line of sight
			if player_pos.distance_to(Vector2(target_pos)) <= vision_radius:
				if _has_line_of_sight(player_pos, target_pos):
					var tile = current_layout.get_tile(target_pos)
					if tile:
						tile.is_visible = true
						tile.is_explored = true

	# Sync Black ICE skull visibility with the freshly computed fog state
	for ice in ice_nodes:
		if is_instance_valid(ice):
			var ice_tile = current_layout.get_tile(ice.current_position)
			if ice_tile:
				ice.update_visibility(ice_tile.is_explored, ice_tile.is_visible)

	# Sync NPC glyph visibility with the fog state too
	for npc in npc_nodes:
		if is_instance_valid(npc):
			var npc_tile = current_layout.get_tile(npc.current_position)
			if npc_tile:
				npc.update_visibility(npc_tile.is_explored, npc_tile.is_visible)


func _has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true
		
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	var x = from.x
	var y = from.y
	var n = 1 + dx + dy
	var x_inc = 1 if (to.x > from.x) else -1
	var y_inc = 1 if (to.y > from.y) else -1
	var error = dx - dy
	
	dx *= 2
	dy *= 2
	
	while n > 1:
		if x == to.x and y == to.y:
			break
			
		if error > 0:
			x += x_inc
			error -= dy
		else:
			y += y_inc
			error += dx
			
		n -= 1
		
		# If we reached the target destination, line of sight is clear
		if x == to.x and y == to.y:
			return true
			
		# Check intermediate tiles for obstacles (Datawalls or locked Code Gates)
		var intermediate_coord = Vector2i(x, y)
		var tile = current_layout.get_tile(intermediate_coord)
		if tile:
			if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
				return false
			if tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked:
				return false
				
	return true
