class_name CP2020InteractionHandler
extends Node

signal action_triggered(action_name: String, target_coord: Vector2i, program_resource: Variant)

# Variable to hold our dynamically generated menu
var _dynamic_menu: PopupMenu = null

# Stores programs for lambda closure (survives after _gui_input returns)
var _current_programs: Array[NetProgram] = []

func handle_input(event: InputEvent, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram] = [], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1)) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Cast the event to InputEventMouseButton so we can safely read event.position
		handle_right_click(event as InputEventMouseButton, current_mouse_pos, layout, available_programs, cell_size, grid_offset_y, ice_nodes, netrunner_pos)

func handle_right_click(_event: InputEventMouseButton, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1)) -> void:
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

	# Tile is explored (already checked above) — show relevant program actions
	var options_added = false
	if ice_here and tile_data.is_visible:
		# Black ICE present and visible — offer anti-ICE (DEREZ) programs
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			if prog and prog.effect_type == NetProgram.EffectType.DEREZ_ICE:
				var menu_label = "%s (STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var prog_id = 1000 + i
				_dynamic_menu.add_item(menu_label, prog_id)
				options_added = true

	elif target_coord == netrunner_pos and tile_data.is_visible:
		# Right-click on the Netrunner's own tile — offer protection (SHIELD) programs
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			if prog and prog.effect_type == NetProgram.EffectType.SHIELD:
				var menu_label = "%s (Shield +%d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
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
	if id >= 1000:
		var idx = id - 1000
		if idx >= 0 and idx < available_programs.size():
			var prog = available_programs[idx] as NetProgram
			print("DEBUG: Program menu item clicked: %s (idx: %d) on tile %s" % [prog.program_name, idx, target_coord])
			action_triggered.emit("use_program", target_coord, prog)
