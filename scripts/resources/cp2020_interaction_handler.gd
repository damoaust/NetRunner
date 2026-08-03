class_name CP2020InteractionHandler
extends Node

signal action_triggered(action_name: String, target_coord: Vector2i, program_resource: Variant)

# Variable to hold our dynamically generated menu
var _dynamic_menu: PopupMenu = null

# Stores programs for lambda closure (survives after _gui_input returns)
var _current_programs: Array[NetProgram] = []

# The LDL-link tile the current popup was built for (so the menu callback can
# emit travel actions with the tile data).
var _ldl_tile: CP2020TileData = null

# The NPC the current popup was built for (so attack/talk callbacks can target
# the right node even if it moves before the menu is dismissed).
var _npc_target: CP2020NpcNetrunner = null

func handle_input(event: InputEvent, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram] = [], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1), npc_nodes: Array = []) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Cast the event to InputEventMouseButton so we can safely read event.position
		handle_right_click(event as InputEventMouseButton, current_mouse_pos, layout, available_programs, cell_size, grid_offset_y, ice_nodes, netrunner_pos, npc_nodes)

func handle_right_click(_event: InputEventMouseButton, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1), npc_nodes: Array = []) -> void:
	if not layout:
		print("DEBUG: Layout is missing!")
		return

	# --- DYNAMIC MENU CREATION ---
	if not _dynamic_menu:
		_dynamic_menu = PopupMenu.new()
		add_child(_dynamic_menu) # Add it to the scene tree so it can be drawn
	
	_dynamic_menu.clear()

	# Calculate grid coordinates using the World coordinates (current_mouse_pos)
	# cell_size and grid_offset_y are passed in from the board renderer to stay in sync
	var grid_x = floori(current_mouse_pos.x / cell_size)
	var grid_y = floori((current_mouse_pos.y - grid_offset_y) / cell_size)
	var target_coord = Vector2i(grid_x, grid_y)
	
	# Validate bounds
	if grid_x < 0 or grid_x >= layout.columns or grid_y < 0 or grid_y >= layout.rows:
		print("DEBUG: Clicked out of bounds at: ", target_coord)
		return
		
	# Get the specific tile data we clicked on
	# MUST use get_tile() — .tres files store keys as strings ("x,y"), so a direct
	# grid_tiles.get(Vector2i) always returns null. get_tile() handles both formats.
	var tile_data = layout.get_tile(target_coord)
	if not tile_data:
		print("DEBUG: No tile data found at coordinate: ", target_coord)
		return
		
	# FOG OF WAR CHECK
	if not tile_data.is_explored:
		print("DEBUG: Tile ", target_coord, " is UNEXPLORED. Blocking menu.")
		return

	# Disconnect previous connections so they don't stack up
	for conn in _dynamic_menu.id_pressed.get_connections():
		_dynamic_menu.id_pressed.disconnect(conn.callable)

	# Store programs as member var to avoid lambda capture issues
	_current_programs = available_programs
	
	print("DEBUG: handle_right_click tile=", target_coord, " type=", tile_data.tile_type, " explored=", tile_data.is_explored, " visible=", tile_data.is_visible)
	
	var _menu_id_pressed_fn = func(id: int) -> void:
		print("DEBUG: PopupMenu id_pressed fired with id=", id)
		_on_menu_action_selected(id, target_coord, _current_programs)

	_dynamic_menu.id_pressed.connect(_menu_id_pressed_fn)

	# Check if a BlackICE node is currently occupying this tile — target the ICE itself
	var ice_here: BlackIce = null
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.current_position == target_coord:
			ice_here = ice
			break

	# Check if an NPC netrunner (NetWatch / random runner) occupies this tile.
	var npc_here: CP2020NpcNetrunner = null
	for npc in npc_nodes:
		if is_instance_valid(npc) and npc.current_position == target_coord:
			npc_here = npc
			break

	# LDL-link tiles offer matrix travel to another datafort or back to the
	# world map. These appear even when no program matches the tile, so a
	# bare ENTRY/LDL tile right-click opens the travel menu.
	var options_added = false
	if tile_data.is_ldl_link:
		_ldl_tile = tile_data
		# Only offer outbound travel when a target subnet is configured; an
		# LDL link with an empty target is world-map-return-only.
		if tile_data.target_subnet_path != "":
			var dest_name := _ldl_target_name(tile_data.target_subnet_path)
			_dynamic_menu.add_item("Travel to %s" % dest_name, 3000)
		_dynamic_menu.add_item("Return to City Grid", 3001)
		options_added = true

	if ice_here and tile_data.is_visible:
		# Black ICE present and visible — offer anti-ICE (DEREZ) programs
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			if prog and prog.effect_type == NetProgram.EffectType.DEREZ_ICE:
				var menu_label = "%s (STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var prog_id = 1000 + i
				_dynamic_menu.add_item(menu_label, prog_id)
				options_added = true

	elif npc_here and tile_data.is_visible:
		# NPC netrunner (NetWatch / random runner) present and visible — offer
		# attack programs (anti-personnel DAMAGE_RUNNER or anti-ICE DEREZ) in
		# the 2000+i id range, plus a Talk option for neutral runners.
		_npc_target = npc_here
		var added_attack = false
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			if prog and prog.effect_type in [NetProgram.EffectType.DAMAGE_RUNNER, NetProgram.EffectType.DEREZ_ICE]:
				var menu_label = "Attack %s: %s (STR %d, %d MU)" % [npc_here.npc_name, prog.program_name, prog.strength, prog.memory_cost]
				var prog_id = 2000 + i
				_dynamic_menu.add_item(menu_label, prog_id)
				added_attack = true
		if added_attack:
			options_added = true
		# Neutral runners can be talked to (id 4000).
		if npc_here.disposition == CP2020NpcNetrunner.Disposition.NEUTRAL:
			_dynamic_menu.add_item("Talk to %s" % npc_here.npc_name, 4000)
			options_added = true

	elif target_coord == netrunner_pos and tile_data.is_visible:
		# Right-click on the Netrunner's own tile — offer protection (SHIELD) programs
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			if prog and prog.effect_type == NetProgram.EffectType.SHIELD:
				var menu_label = "%s (Block STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var prog_id = 1000 + i
				_dynamic_menu.add_item(menu_label, prog_id)
				options_added = true

	elif tile_data.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile_data.is_unlocked:
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			print("DEBUG: Checking program %s effect_type=%d BYPASS_GATE=0" % [prog.program_name, prog.effect_type])
			if prog and prog.effect_type == NetProgram.EffectType.BYPASS_GATE:
				print("DEBUG: Program %s matches BYPASS_GATE" % prog.program_name)
				var menu_label = "%s (%d MU)" % [prog.program_name, prog.memory_cost]
				var prog_id = 1000 + i # Positive ID offset for program actions
				_dynamic_menu.add_item(menu_label, prog_id)
				options_added = true

	elif tile_data.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			print("DEBUG: Checking program '%s' for BREACH_WALL. Type is: %d" % [prog.program_name, prog.effect_type])
			if prog and prog.effect_type == NetProgram.EffectType.BREACH_WALL:
				print("SUCCESS: Found matching wall breach program!")
				var menu_label = "%s (%d MU)" % [prog.program_name, prog.memory_cost]
				var prog_id = 1000 + i
				_dynamic_menu.add_item(menu_label, prog_id)
				options_added = true

	print("DEBUG: options_added=", int(options_added), " gate_STR=", tile_data.strength_str, " is_unlocked=", tile_data.is_unlocked)

	if not options_added:
		print("DEBUG: No valid programs found for this tile type. Aborting menu popup.")
		return

	print("DEBUG: Opening menu for tile: ", target_coord)

	# 1. Reset size so the menu fits its items
	_dynamic_menu.reset_size()
	
	# 2. popup_on_parent positions the menu at the click point relative to the
	#    game viewport. The zero-size Rect2i means "open right at this pixel"
	#    and Godot will auto-flip it if it would spill off the screen edge.
	var click_pos := Vector2i(get_viewport().get_mouse_position())
	_dynamic_menu.popup_on_parent(Rect2i(click_pos, Vector2i.ZERO))

func _on_menu_action_selected(id: int, target_coord: Vector2i, available_programs: Array[NetProgram]) -> void:
	# LDL travel actions take priority (their ids collide with the program
	# id range 1000+, so check them explicitly first).
	if id == 3000:
		action_triggered.emit("travel_ldl", target_coord, _ldl_tile)
		return
	if id == 3001:
		action_triggered.emit("return_world_map", target_coord, null)
		return
	# NPC talk (neutral runners) — id 4000.
	if id == 4000:
		action_triggered.emit("talk_npc", target_coord, _npc_target)
		return
	# NPC attack programs — id range 2000+i (checked before the 1000+i program
	# range to avoid collision).
	if id >= 2000 and id < 3000:
		var idx = id - 2000
		if idx >= 0 and idx < available_programs.size():
			var prog = available_programs[idx] as NetProgram
			action_triggered.emit("attack_npc", target_coord, prog)
		return
	if id >= 1000:
		var idx = id - 1000
		if idx >= 0 and idx < available_programs.size():
			var prog = available_programs[idx] as NetProgram
			print("DEBUG: Program menu item clicked: %s (idx: %d) on tile %s" % [prog.program_name, idx, target_coord])
			action_triggered.emit("use_program", target_coord, prog)


func _ldl_target_name(path: String) -> String:
	if path == "":
		return "target datafort"
	var fname := path.get_file().get_basename()
	return fname if fname != "" else "target datafort"
