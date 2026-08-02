class_name CP2020GameSession
extends Control

@export var starting_subnet_path: String = "res://scenes/forts/night_city_subnet.tres"

@onready var board_renderer: CP2020BoardRenderer = $BoardRenderer
@onready var interaction_handler: CP2020InteractionHandler = $CP2020InteractionHandler
@onready var terminal_log: RichTextLabel = $UI/PanelContainer/VBoxContainer/TerminalLog
@onready var deck_name_label: Label = $UI/PanelContainer/VBoxContainer/DeckNameLabel
@onready var memory_label: Label = $UI/PanelContainer/VBoxContainer/MemoryLabel
@onready var actions_label: Label = $UI/PanelContainer/VBoxContainer/ActionsLabel
@onready var program_list_container: VBoxContainer = $UI/PanelContainer/VBoxContainer/ProgramListContainer
@onready var netrunner: CP2020Netrunner = $CP2020Netrunner
@onready var turn_manager: CP2020TurnManager = $TurnManager

const BlackIceScene := preload("res://scenes/ui/cp2020_blackice.tscn")
var ice_nodes: Array[BlackIce] = []

var current_layout: CP2020DatafortLayout

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

	load_subnet(starting_subnet_path)
	update_deck_info()
	log_to_terminal("JACKED IN. Connection established to matrix grid.\n")

func load_subnet(path: String) -> void:
	if ResourceLoader.exists(path):
		current_layout = ResourceLoader.load(path) as CP2020DatafortLayout
		if board_renderer and current_layout:
			board_renderer.current_layout = current_layout
			#reveal_entry_points() 
			
			# Let the Netrunner handle its own spawning!
			if netrunner:
				netrunner.initialize(current_layout)
			spawn_black_ice()
			recalculate_fog_of_war(netrunner.current_position)
			board_renderer.queue_redraw()

func _input(event: InputEvent) -> void:
	# Right-click is handled here in _input (NOT _unhandled_input) because the root
	# Control node's GUI system consumes mouse events before _unhandled_input fires.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		accept_event() # Prevent GUI system from re-processing this
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var programs: Array[NetProgram] = netrunner.installed_programs if netrunner else []
		print("DEBUG [session] right-click at ", mouse_pos, " programs=", programs.size())
		if interaction_handler and current_layout:
			var cs: float = board_renderer.cell_size if board_renderer else 40.0
			var go_y: float = board_renderer.grid_offset_y if board_renderer else 90.0
			var nr_pos: Vector2i = netrunner.current_position if netrunner else Vector2i(-1, -1)
			interaction_handler.handle_input(event, mouse_pos, current_layout, programs, cs, go_y, ice_nodes, nr_pos)

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
			ice.initialize(coord, layout_size)
			ice.message_logged.connect(log_to_terminal)
			ice.moved_to.connect(_on_ice_moved)
			ice.attacked_netrunner.connect(_on_ice_attacked)
			ice_nodes.append(ice)
			log_to_terminal("Black ICE '%s' deployed at %s.\n" % [ice.program_name, coord])

func _end_player_turn() -> void:
	if not turn_manager or not current_layout or not netrunner:
		return
	if not turn_manager.is_netrunner_turn:
		return
	log_to_terminal("--- Netrunner turn ended. ICE activating... ---\n")
	turn_manager.execute_ice_turns(ice_nodes, netrunner.current_position, current_layout)

func _on_turn_ended(is_netrunner_turn: bool) -> void:
	if is_netrunner_turn:
		log_to_terminal("--- Netrunner turn begins. ---\n")

func _on_actions_changed(remaining: int, max_actions: int) -> void:
	if actions_label:
		actions_label.text = "Actions: %d / %d" % [remaining, max_actions]
	log_to_terminal("Actions: %d / %d\n" % [remaining, max_actions])

func _check_actions_exhausted() -> void:
	if turn_manager and turn_manager.actions_remaining <= 0:
		log_to_terminal("Out of actions. ICE activating...\n")
		turn_manager.execute_ice_turns(ice_nodes, netrunner.current_position, current_layout)

func _on_ice_stepped() -> void:
	if board_renderer:
		board_renderer.queue_redraw()

func _on_ice_moved(_new_pos: Vector2i) -> void:
	if board_renderer:
		board_renderer.queue_redraw()

func _on_ice_attacked(strength: int) -> void:
	log_to_terminal("WARNING: Black ICE attacks for %d!\n" % strength)
	if netrunner:
		netrunner.apply_damage(strength, "Black ICE")

func _on_flatlined() -> void:
	log_to_terminal("=== GAME OVER: Netrunner flatlined. Jack out. ===\n")
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
