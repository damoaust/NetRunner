class_name CP2020InteractionHandler
extends Node

signal action_triggered(action_name: String, target_coord: Vector2i, program_resource: Variant)

const POPUP_THEME := preload("res://scripts/resources/cp2020_popup_theme.gd")

# Variable to hold our dynamically generated menu
var _dynamic_menu: PopupMenu = null

# Stores programs for lambda closure (survives after _gui_input returns)
var _current_programs: Array[NetProgram] = []

# Stores the files authored on the MEMORY_UNIT tile the current popup was
# built for (so the copy-file callback can resolve a file by menu id index).
var _current_files: Array[NetFile] = []

# The LDL-link tile the current popup was built for (so the menu callback can
# emit travel actions with the tile data).
var _ldl_tile: CP2020TileData = null

# The NPC the current popup was built for (so attack/talk callbacks can target
# the right node even if it moves before the menu is dismissed).
var _npc_target: CP2020NpcNetrunner = null

# The netrunner node the current popup was built for (so the Armor-raise
# callback can call netrunner.raise_armor directly without round-tripping
# through the game session — Armor is a persistent passive buff, not an
# action-consuming program use).
var _netrunner_node: CP2020Netrunner = null

func handle_input(event: InputEvent, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram] = [], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1), npc_nodes: Array = [], netrunner_node: CP2020Netrunner = null) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Cast the event to InputEventMouseButton so we can safely read event.position
		handle_right_click(event as InputEventMouseButton, current_mouse_pos, layout, available_programs, cell_size, grid_offset_y, ice_nodes, netrunner_pos, npc_nodes, netrunner_node)

func handle_right_click(_event: InputEventMouseButton, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1), npc_nodes: Array = [], netrunner_node: CP2020Netrunner = null) -> void:
	if not layout:
		print("DEBUG: Layout is missing!")
		return

	# --- DYNAMIC MENU CREATION ---
	if not _dynamic_menu:
		_dynamic_menu = PopupMenu.new()
		add_child(_dynamic_menu) # Add it to the scene tree so it can be drawn
		POPUP_THEME.apply_cyberpunk_theme(_dynamic_menu, 16)

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
	# Reset the per-file list for this popup; set when a MEMORY_UNIT branch
	# builds its menu below.
	_current_files.clear()
	# Remember the netrunner node for the Armor-raise callback (set whether or
	# not the runner-tile branch runs this click; cleared each popup).
	_netrunner_node = netrunner_node
	
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

	elif tile_data.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE and tile_data.is_visible:
		# CPU tile visible — offer anti-system (CRASH_CPU) programs to crash the
		# datafort's CPU. id range 5000+i (checked before the 1000+i program
		# range in _on_menu_action_selected).
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			if prog and prog.effect_type == NetProgram.EffectType.CRASH_CPU:
				var menu_label = "Krash CPU: %s (STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var prog_id = 5000 + i
				_dynamic_menu.add_item(menu_label, prog_id)
				options_added = true

	elif target_coord == netrunner_pos and tile_data.is_visible:
		# Right-click on the Netrunner's own tile — offer protection programs.
		# SHIELD programs use the 1000+i program-use range (dispatched via the
		# "use_program" action to the game session, which consumes an action).
		# ARMOR programs use the 7000+i range and call netrunner.raise_armor
		# directly here (Armor is a persistent passive absorber, not a
		# one-shot action-consuming defense). 7000+i is chosen because 5000+i
		# is already taken by CRASH_CPU and 6000+i by file-copy actions.
		for i in range(available_programs.size()):
			var prog = available_programs[i] as NetProgram
			if prog and prog.effect_type == NetProgram.EffectType.SHIELD:
				var menu_label = "%s (Block STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var prog_id = 1000 + i
				_dynamic_menu.add_item(menu_label, prog_id)
				options_added = true
			elif prog and prog.effect_type == NetProgram.EffectType.ARMOR:
				var armor_label = "%s (Absorb STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var armor_id = 7000 + i
				_dynamic_menu.add_item(armor_label, armor_id)
				options_added = true
			elif prog and prog.effect_type == NetProgram.EffectType.DETECTION:
				var detect_label = "%s (Deploy STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var detect_id = 1000 + i
				_dynamic_menu.add_item(detect_label, detect_id)
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
			elif prog and prog.effect_type == NetProgram.EffectType.WORM:
				var worm_label = "%s (Stealth, 2 turns, %d MU)" % [prog.program_name, prog.memory_cost]
				var worm_id = 1000 + i
				_dynamic_menu.add_item(worm_label, worm_id)
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
			elif prog and prog.effect_type == NetProgram.EffectType.WORM:
				var worm_label = "%s (Stealth, 2 turns, %d MU)" % [prog.program_name, prog.memory_cost]
				var worm_id = 1000 + i
				_dynamic_menu.add_item(worm_label, worm_id)
				options_added = true

	elif tile_data.tile_type == CP2020DatafortLayout.TileType.MEMORY_UNIT:
		# Lootable memory unit — offer a PER-FILE copy-to-deck menu when the
		# tile is visible, has authored files, and is adjacent to (or the same
		# as) the netrunner's tile. Each file gets its own menu item (id
		# 6000+i) showing name + MU cost (NOT credit_value — value is
		# discovered at the hub). Already-copied files show a ✓ checkmark and
		# are disabled. A "Copy All" item (id 6999) is appended last.
		# Adjacency is enforced ONLY for this branch.
		if tile_data.is_visible and tile_data.files.size() > 0:
			var dx: int = abs(target_coord.x - netrunner_pos.x)
			var dy: int = abs(target_coord.y - netrunner_pos.y)
			var is_adjacent: bool = (dx + dy) <= 1
			if is_adjacent:
				# Remember the authored files so the menu callback can resolve
				# a file by its menu id index (6000+i).
				_current_files = tile_data.files
				# Free deck memory for the MU-fit check. When the netrunner
				# node is provided (gameplay caller), used memory already
				# includes carried files + installed programs. When null
				# (e.g. designer/legacy callers) we skip the fit check and
				# assume every file fits.
				var free_mu: int = -1
				if netrunner_node != null and is_instance_valid(netrunner_node):
					free_mu = netrunner_node.max_memory_units - netrunner_node.get_used_memory()
				var any_copyable: bool = false
				for i in range(tile_data.files.size()):
					var file := tile_data.files[i] as NetFile
					if file == null:
						continue
					var already_copied: bool = tile_data.copied_file_paths.has(str(i))
					var fits: bool = true
					if free_mu >= 0:
						fits = file.mu_size <= free_mu
					var label = "%s (%d MU)" % [file.file_name, file.mu_size]
					var item_id = 6000 + i
					if already_copied:
						label = "✓ " + label
					_dynamic_menu.add_item(label, item_id)
					var item_idx = _dynamic_menu.get_item_index(item_id)
					if already_copied or not fits:
						_dynamic_menu.set_item_disabled(item_idx, true)
					else:
						any_copyable = true
					# "Copy All" — disabled when no copyable+fitting file remains.
					_dynamic_menu.add_item("Copy All", 6999)
					var copy_all_idx = _dynamic_menu.get_item_index(6999)
					_dynamic_menu.set_item_disabled(copy_all_idx, not any_copyable)
				# Always open the menu here so the player sees the ✓ state /
				# visual indicator even when every file is already copied.
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
	# Special-id ordering (checked BEFORE the 1000+i program range to avoid
	# collision): LDL travel (3000/3001) → NPC talk (4000) → NPC attack
	# (2000+i) → CPU crash (5000+i) → copy file (6000+i) / copy all (6999)
	# → Armor-raise (7000+i) → program use (1000+i). The old single 6000
	# loot_tile id is removed.
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
	# CPU crash (Krash anti-system) — id range 5000+i.
	if id >= 5000 and id < 6000:
		var idx = id - 5000
		if idx >= 0 and idx < available_programs.size():
			var prog = available_programs[idx] as NetProgram
			action_triggered.emit("crash_cpu", target_coord, prog)
		return
	# Armor-raise (defensive program) — id range 7000+i. Calls
	# netrunner.raise_armor directly (Armor is a persistent passive absorber,
	# not an action-consuming program use). Checked before the 1000+i program
	# range to avoid collision.
	if id >= 7000 and id < 8000:
		var idx = id - 7000
		if idx >= 0 and idx < available_programs.size():
			var prog = available_programs[idx] as NetProgram
			if prog and prog.effect_type == NetProgram.EffectType.ARMOR \
					and _netrunner_node != null and is_instance_valid(_netrunner_node):
				_netrunner_node.raise_armor(prog)
		return
	# Copy all files from a MEMORY_UNIT tile — single fixed id 6999 (checked
	# before the 1000+i program range to avoid collision).
	if id == 6999:
		action_triggered.emit("copy_all_files", target_coord, null)
		return
	# Copy a single file from a MEMORY_UNIT tile — id range 6000+i. Resolve
	# the file via the member-var list populated when the popup was built.
	if id >= 6000 and id < 7000:
		var idx = id - 6000
		if idx >= 0 and idx < _current_files.size():
			var file = _current_files[idx] as NetFile
			action_triggered.emit("copy_file", target_coord, file)
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
