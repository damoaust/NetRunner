class_name CP2020InteractionHandler
extends Node

signal action_triggered(action_name: String, target_coord: Vector2i, program_resource: Variant)

const POPUP_THEME := preload("res://scripts/resources/cp2020_theme.gd")

# Variable to hold our dynamically generated menu
var _dynamic_menu: PopupMenu = null

# Screen-space host for the right-click PopupMenu. Kept separate from the
# board's World2D canvas so the RunnerCamera2D zoom does not scale the menu
# (children of a Node2D that shares the board's canvas are zoomed by the
# Camera2D; a CanvasLayer renders in its own screen-space layer, like the UI
# HUD, and is immune to camera zoom). Created lazily on first right-click
# (see handle_right_click). Mirrors the city-grid HUDLayer popup pattern
# (cp2020_city_grid.gd _open_return_popup).
var _popup_layer: CanvasLayer = null

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

# Rezzed attack-program nodes active on the net (set per popup so the attack
# and de-rez menus can reference them by index).
var _current_rezzed_nodes: Array[RezzedProgram] = []

# Demon command menu entries built per popup. Each entry is a 2-element Array
# [DemonNode, subroutine_index] referenced by menu id 8500+index. Rebuilt every
# popup (cleared before construction).
var _current_demon_commands: Array = []

func handle_input(event: InputEvent, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram] = [], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1), npc_nodes: Array = [], netrunner_node: CP2020Netrunner = null, rezzed_program_nodes: Array = []) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Cast the event to InputEventMouseButton so we can safely read event.position
		handle_right_click(event as InputEventMouseButton, current_mouse_pos, layout, available_programs, cell_size, grid_offset_y, ice_nodes, netrunner_pos, npc_nodes, netrunner_node, rezzed_program_nodes)

func handle_right_click(_event: InputEventMouseButton, current_mouse_pos: Vector2, layout: CP2020DatafortLayout, available_programs: Array[NetProgram], cell_size: float = 40.0, grid_offset_y: float = 90.0, ice_nodes: Array = [], netrunner_pos: Vector2i = Vector2i(-1, -1), npc_nodes: Array = [], netrunner_node: CP2020Netrunner = null, rezzed_program_nodes: Array = []) -> void:
	if not layout:
		print("DEBUG: Layout is missing!")
		return

	# --- DYNAMIC MENU CREATION ---
	# Host the PopupMenu in a dedicated CanvasLayer (screen-space, like the HUD)
	# instead of as a child of this Node2D. Children of a Node2D that shares the
	# board's World2D canvas are scaled by the RunnerCamera2D zoom, which made
	# the right-click menu grow/shrink with the camera. A CanvasLayer renders
	# in its own screen-space layer, independent of the Camera2D — matching how
	# the UI CanvasLayer stays fixed.
	if not _popup_layer:
		_popup_layer = CanvasLayer.new()
		_popup_layer.layer = 10  # above the UI HUD so the menu is never hidden
		add_child(_popup_layer)
	if not _dynamic_menu:
		_dynamic_menu = PopupMenu.new()
		_popup_layer.add_child(_dynamic_menu)
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
	var tile_data = layout.get_tile(target_coord, layout.current_floor)
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
	# Store the rezzed-program nodes for this popup (attack / de-rez menus
	# reference them by index). Filter to the current floor.
	_current_rezzed_nodes.clear()
	for rez in rezzed_program_nodes:
		if is_instance_valid(rez) and rez.home_floor == layout.current_floor:
			_current_rezzed_nodes.append(rez)
	# Reset the Demon command menu for this popup; rebuilt as Demon command
	# items are added below (id range 8500+i over this list).
	_current_demon_commands.clear()
	
	print("DEBUG: handle_right_click tile=", target_coord, " type=", tile_data.tile_type, " explored=", tile_data.is_explored, " visible=", tile_data.is_visible)
	
	var _menu_id_pressed_fn = func(id: int) -> void:
		print("DEBUG: PopupMenu id_pressed fired with id=", id)
		_on_menu_action_selected(id, target_coord, _current_programs)

	_dynamic_menu.id_pressed.connect(_menu_id_pressed_fn)

	# Check if a BlackICE node is currently occupying this tile — target the ICE itself.
	# MUST match on home_floor too: ice_nodes is the FULL unfiltered list across
	# every floor, so without the floor check an ICE on the floor below (same
	# coord) would match here and — because this is the first branch of the
	# elif chain below — suppress every other menu (e.g. copy files from a
	# MEMORY_UNIT on this floor). Entities never leave their home floor.
	var ice_here: BlackIce = null
	for ice in ice_nodes:
		if is_instance_valid(ice) and ice.home_floor == layout.current_floor and ice.current_position == target_coord:
			ice_here = ice
			break

	# Check if an NPC netrunner (NetWatch / random runner) occupies this tile.
	# Same home_floor gate as ice_here — npc_nodes spans all floors.
	var npc_here: CP2020NpcNetrunner = null
	for npc in npc_nodes:
		if is_instance_valid(npc) and npc.home_floor == layout.current_floor and npc.current_position == target_coord:
			npc_here = npc
			break

	# Check if a rezzed attack-program node occupies this tile (for the de-rez
	# menu). Same current-floor gate — _current_rezzed_nodes is already
	# floor-filtered, but this guards against stale entries.
	var rezzed_here: RezzedProgram = null
	for rez in _current_rezzed_nodes:
		if is_instance_valid(rez) and rez.current_position == target_coord:
			rezzed_here = rez
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

	# Vertical-travel menu items (ids 3002/3003). Checked BEFORE the 4000
	# NPC-talk / 1000+i program ranges to avoid id collision, immediately
	# after the 3000/3001 LDL items. Each is greyed out (disabled) when its
	# destination floor is missing or blocked by a Datawall / locked Code
	# Gate — the player sees at a glance whether up/down is available.
	# See docs/multi-floor-travel-plan.md §4.
	if tile_data.can_go_up:
		_ldl_tile = tile_data
		var up_ok := _can_travel_vertical(layout, tile_data.up_target_entry_coord, layout.current_floor + 1)
		var idx := _dynamic_menu.get_item_count()
		_dynamic_menu.add_item("Go Up", 3002)
		_dynamic_menu.set_item_disabled(idx, not up_ok)
		options_added = true
	if tile_data.can_go_down:
		_ldl_tile = tile_data
		var down_ok := _can_travel_vertical(layout, tile_data.down_target_entry_coord, layout.current_floor - 1)
		var idx := _dynamic_menu.get_item_count()
		_dynamic_menu.add_item("Go Down", 3003)
		_dynamic_menu.set_item_disabled(idx, not down_ok)
		options_added = true

	# Rezzed attack-program node on this tile — offer de-rez (id 8100+i over
	# _current_rezzed_nodes). Checked before ice_here/npc_here so a rezzed
	# program sitting on an entity tile still gets its own menu.
	if rezzed_here and tile_data.is_visible:
		var rez_idx := _current_rezzed_nodes.find(rezzed_here)
		if rez_idx >= 0:
			var rez_name := rezzed_here.program.program_name if rezzed_here.program else "program"
			_dynamic_menu.add_item("De-rez %s" % rez_name, 8100 + rez_idx)
			options_added = true

	if ice_here and tile_data.is_visible:
		# Black ICE present and visible — offer REZZED anti-ICE (DEREZ)
		# programs to attack it. Attack programs must be rezzed onto the net
		# before they can strike (Phase 1). id range 8200+i over
		# _current_rezzed_nodes. If none are rezzed, show a hint.
		var added_rezzed = false
		for i in range(_current_rezzed_nodes.size()):
			var rez = _current_rezzed_nodes[i]
			if is_instance_valid(rez) and rez.program and rez.program.effect_type == NetProgram.EffectType.DEREZ_ICE:
				var menu_label = "Attack %s: %s (STR %d)" % [ice_here.program.program_name, rez.program.program_name, rez.program.strength]
				_dynamic_menu.add_item(menu_label, 8200 + i)
				added_rezzed = true
		# Demon subroutines: any rezzed Demon carrying a DEREZ_ICE subroutine
		# can be commanded to attack this ICE (id 8500+i over
		# _current_demon_commands). Subroutines use the Demon core's STR.
		for rez in _current_rezzed_nodes:
			if is_instance_valid(rez) and rez is DemonNode:
				var demon: DemonNode = rez as DemonNode
				for si in range(demon.get_commandable_subroutines().size()):
					var sub: NetProgram = demon.get_subroutine(si)
					if sub and sub.effect_type == NetProgram.EffectType.DEREZ_ICE:
						_add_demon_command_item("Attack %s: %s → %s (STR %d)" % [ice_here.program.program_name, demon.program.program_name, sub.program_name, sub.strength], demon, si)
						added_rezzed = true
		if not added_rezzed:
			_dynamic_menu.add_item("Rez an anti-ICE program first", 0)
			_dynamic_menu.set_item_disabled(_dynamic_menu.get_item_count() - 1, true)
		options_added = true

	elif npc_here and tile_data.is_visible:
		# NPC netrunner (NetWatch / random runner) present and visible — offer
		# REZZED attack programs (anti-personnel DAMAGE_RUNNER or anti-ICE
		# DEREZ) in the 8300+i id range over _current_rezzed_nodes, plus a
		# Talk option for neutral runners.
		_npc_target = npc_here
		var added_attack = false
		for i in range(_current_rezzed_nodes.size()):
			var rez = _current_rezzed_nodes[i]
			if is_instance_valid(rez) and rez.program and rez.program.effect_type in [NetProgram.EffectType.DAMAGE_RUNNER, NetProgram.EffectType.DEREZ_ICE]:
				var menu_label = "Attack %s: %s (STR %d)" % [npc_here.npc_name, rez.program.program_name, rez.program.strength]
				_dynamic_menu.add_item(menu_label, 8300 + i)
				added_attack = true
		# Demon subroutines: any rezzed Demon carrying a DAMAGE_RUNNER or
		# DEREZ_ICE subroutine can be commanded to attack this NPC.
		for rez in _current_rezzed_nodes:
			if is_instance_valid(rez) and rez is DemonNode:
				var demon: DemonNode = rez as DemonNode
				for si in range(demon.get_commandable_subroutines().size()):
					var sub: NetProgram = demon.get_subroutine(si)
					if sub and sub.effect_type in [NetProgram.EffectType.DAMAGE_RUNNER, NetProgram.EffectType.DEREZ_ICE]:
						_add_demon_command_item("Attack %s: %s → %s (STR %d)" % [npc_here.npc_name, demon.program.program_name, sub.program_name, sub.strength], demon, si)
						added_attack = true
		if not added_attack:
			_dynamic_menu.add_item("Rez an attack program first", 0)
			_dynamic_menu.set_item_disabled(_dynamic_menu.get_item_count() - 1, true)
		options_added = true
		# Neutral runners can be talked to (id 4000).
		if npc_here.disposition == CP2020NpcNetrunner.Disposition.NEUTRAL:
			_dynamic_menu.add_item("Talk to %s" % npc_here.npc_name, 4000)

	elif tile_data.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE and tile_data.is_visible:
		# CPU tile visible — offer REZZED anti-system (CRASH_CPU) programs to
		# crash the datafort's CPU. id range 8400+i over _current_rezzed_nodes
		# (checked before the 1000+i program range in _on_menu_action_selected).
		var added_cpu = false
		for i in range(_current_rezzed_nodes.size()):
			var rez = _current_rezzed_nodes[i]
			if is_instance_valid(rez) and rez.program and rez.program.effect_type == NetProgram.EffectType.CRASH_CPU:
				var menu_label = "Krash CPU: %s (STR %d)" % [rez.program.program_name, rez.program.strength]
				_dynamic_menu.add_item(menu_label, 8400 + i)
				added_cpu = true
		# Demon subroutines: any rezzed Demon carrying a CRASH_CPU subroutine
		# can be commanded to crash this CPU.
		for rez in _current_rezzed_nodes:
			if is_instance_valid(rez) and rez is DemonNode:
				var demon: DemonNode = rez as DemonNode
				for si in range(demon.get_commandable_subroutines().size()):
					var sub: NetProgram = demon.get_subroutine(si)
					if sub and sub.effect_type == NetProgram.EffectType.CRASH_CPU:
						_add_demon_command_item("Krash CPU: %s → %s (STR %d)" % [demon.program.program_name, sub.program_name, sub.strength], demon, si)
						added_cpu = true
		if not added_cpu:
			_dynamic_menu.add_item("Rez an anti-system program first", 0)
			_dynamic_menu.set_item_disabled(_dynamic_menu.get_item_count() - 1, true)
		# Loot option — offer when the tile has unlooted loot_programs /
		# loot_credits / loot_modules. id 5000 (single fixed id, checked
		# after 8500+i and before 1000+i in _on_menu_action_selected).
		if not tile_data.is_looted:
			var has_loot: bool = (tile_data.loot_programs.size() > 0 \
					or tile_data.loot_credits > 0 \
					or tile_data.loot_modules.size() > 0)
			if has_loot:
				_dynamic_menu.add_item("▼ Loot Node", 5000)
		options_added = true

	elif target_coord == netrunner_pos and tile_data.is_visible:
		# Right-click on the Netrunner's own tile — offer:
		#  - Rez attack programs (DEREZ_ICE / DAMAGE_RUNNER / CRASH_CPU) that
		#    are installed but not yet rezzed (id 8000+i over available_programs).
		#  - De-rez any currently rezzed program (id 8100+i over
		#    _current_rezzed_nodes).
		#  - Defense/utility programs (SHIELD/ARMOR/DETECTION/INVISIBILITY) which
		#    keep their direct-from-deck behavior (Phase 1).
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
			elif prog and prog.effect_type == NetProgram.EffectType.INVISIBILITY:
				var cloak_label = "%s (Cloak STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var cloak_id = 1000 + i
				_dynamic_menu.add_item(cloak_label, cloak_id)
				options_added = true
			elif prog and prog.effect_type in [NetProgram.EffectType.DEREZ_ICE, NetProgram.EffectType.DAMAGE_RUNNER, NetProgram.EffectType.CRASH_CPU]:
				# Attack program — offer to rez it onto the net (id 8000+i).
				var rez_label = "Rez %s (STR %d, %d MU)" % [prog.program_name, prog.strength, prog.memory_cost]
				var rez_id = 8000 + i
				_dynamic_menu.add_item(rez_label, rez_id)
				options_added = true
			elif prog and prog is DemonProgram:
				# Demon — offer to rez it onto the net (id 8000+i). Its
				# subroutines are assigned at the workbench; rezzing spawns a
				# DemonNode carrying them (STR overridden to the Demon's).
				var demon_prog: DemonProgram = prog as DemonProgram
				var rez_label = "Rez %s (Demon, %d subroutines, STR %d, %d MU)" % [demon_prog.program_name, demon_prog.max_subroutines, demon_prog.strength, demon_prog.memory_cost]
				var rez_id = 8000 + i
				_dynamic_menu.add_item(rez_label, rez_id)
				options_added = true
		# De-rez any currently rezzed program (id 8100+i).
		for j in range(_current_rezzed_nodes.size()):
			var rez = _current_rezzed_nodes[j]
			if is_instance_valid(rez) and rez.program:
				var derez_label = "De-rez %s (STR %d)" % [rez.program.program_name, rez.program.strength]
				_dynamic_menu.add_item(derez_label, 8100 + j)
				options_added = true
		# Command a rezzed Demon to fire a SHIELD/ARMOR subroutine as a
		# self-buff (id 8500+i over _current_demon_commands). Attack
		# subroutines are commanded from target-tile context (ICE/NPC/CPU);
		# defense subroutines are self-targeted so they live here.
		for rez in _current_rezzed_nodes:
			if is_instance_valid(rez) and rez is DemonNode:
				var demon: DemonNode = rez as DemonNode
				for si in range(demon.get_commandable_subroutines().size()):
					var sub: NetProgram = demon.get_subroutine(si)
					if sub and sub.effect_type in [NetProgram.EffectType.SHIELD, NetProgram.EffectType.ARMOR]:
						var kind := "Block" if sub.effect_type == NetProgram.EffectType.SHIELD else "Absorb"
						_add_demon_command_item("%s → %s (%s STR %d)" % [demon.program.program_name, sub.program_name, kind, sub.strength], demon, si)
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
					free_mu = netrunner_node.effective_max_memory() - netrunner_node.get_used_memory()
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
				# "Copy All" — added once (outside the per-file loop) so a tile
				# with N files shows exactly one Copy All row. Disabled when no
				# copyable+fitting file remains.
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

# Append a Demon command entry: stores [DemonNode, subroutine_index] and adds
# a menu item at id 8500 + index over _current_demon_commands. Used by the
# ICE / NPC / CPU / runner-tile contexts to let the runner command a rezzed
# Demon to fire one of its subroutines.
func _add_demon_command_item(label: String, demon: DemonNode, sub_index: int) -> void:
	_current_demon_commands.append([demon, sub_index])
	var cmd_id := 8500 + (_current_demon_commands.size() - 1)
	_dynamic_menu.add_item(label, cmd_id)

func _on_menu_action_selected(id: int, target_coord: Vector2i, available_programs: Array[NetProgram]) -> void:
	# Special-id ordering (checked BEFORE the 1000+i program range to avoid
	# collision): LDL travel (3000/3001) → vertical travel (3002/3003) → NPC
	# talk (4000) → copy file (6000+i) / copy all (6999) → Armor-raise
	# (7000+i) → rez program (8000+i) → de-rez (8100+i) → rezzed anti-ICE
	# attack (8200+i) → rezzed NPC attack (8300+i) → rezzed CPU crash
	# (8400+i) → Demon command subroutine (8500+i) → CONTROL_NODE loot
	# (5000) → program use (1000+i).
	# LDL travel actions take priority (their ids collide with the program
	# id range 1000+, so check them explicitly first).
	if id == 3000:
		action_triggered.emit("travel_ldl", target_coord, _ldl_tile)
		return
	if id == 3001:
		action_triggered.emit("return_world_map", target_coord, null)
		return
	# Vertical travel within the same datafort (ids 3002/3003). Checked right
	# after the LDL items and before the 4000/2000+i ranges. The game session
	# re-validates the destination before switching floors.
	if id == 3002:
		action_triggered.emit("travel_up", target_coord, _ldl_tile)
		return
	if id == 3003:
		action_triggered.emit("travel_down", target_coord, _ldl_tile)
		return
	# NPC talk (neutral runners) — id 4000.
	if id == 4000:
		action_triggered.emit("talk_npc", target_coord, _npc_target)
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
	# Rez an attack program onto the net — id range 8000+i over
	# available_programs (installed, not yet rezzed). The game session spawns
	# a RezzedProgram node and consumes 1 action.
	if id >= 8000 and id < 8100:
		var idx = id - 8000
		if idx >= 0 and idx < available_programs.size():
			var prog = available_programs[idx] as NetProgram
			action_triggered.emit("rez_program", target_coord, prog)
		return
	# De-rez a rezzed program — id range 8100+i over _current_rezzed_nodes.
	# Free (no action cost). The program is passed as the RezzedProgram node.
	if id >= 8100 and id < 8200:
		var idx = id - 8100
		if idx >= 0 and idx < _current_rezzed_nodes.size():
			var rez = _current_rezzed_nodes[idx]
			action_triggered.emit("derez_program", target_coord, rez)
		return
	# Command a rezzed anti-ICE program to attack Black ICE — id range
	# 8200+i over _current_rezzed_nodes.
	if id >= 8200 and id < 8300:
		var idx = id - 8200
		if idx >= 0 and idx < _current_rezzed_nodes.size():
			var rez = _current_rezzed_nodes[idx]
			action_triggered.emit("attack_with_rezzed", target_coord, rez)
		return
	# Command a rezzed attack program to attack an NPC — id range 8300+i.
	if id >= 8300 and id < 8400:
		var idx = id - 8300
		if idx >= 0 and idx < _current_rezzed_nodes.size():
			var rez = _current_rezzed_nodes[idx]
			action_triggered.emit("attack_with_rezzed", target_coord, rez)
		return
	# Command a rezzed anti-system program to crash a CPU — id range 8400+i.
	if id >= 8400 and id < 8500:
		var idx = id - 8400
		if idx >= 0 and idx < _current_rezzed_nodes.size():
			var rez = _current_rezzed_nodes[idx]
			action_triggered.emit("attack_with_rezzed", target_coord, rez)
		return
	# Command a rezzed Demon to fire a subroutine — id range 8500+i over
	# _current_demon_commands (each entry is [DemonNode, subroutine_index]).
	# Checked AFTER the 8400+i rezzed-CPU range and BEFORE the 1000+i program
	# range to avoid collision. The payload Array is unpacked by the session's
	# "command_demon" handler. Consumes 1 action.
	if id >= 8500 and id < 8600:
		var idx = id - 8500
		if idx >= 0 and idx < _current_demon_commands.size():
			var cmd = _current_demon_commands[idx]
			action_triggered.emit("command_demon", target_coord, cmd)
		return
	# Loot a CONTROL_NODE tile — single fixed id 5000 (the old CPU-crash
	# 5000+i range was removed in Phase 1, so 5000 is free). Checked after
	# 8500+i and before 1000+i per the collision-ordering rules. Free action
	# (no turn consumed). The game session's "loot_tile" handler picks up
	# loot_programs / loot_credits / loot_modules.
	if id == 5000:
		action_triggered.emit("loot_tile", target_coord, null)
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

# Pre-check for vertical travel: returns true if `target_floor` exists and the
# arrival coord on it is a non-blocking tile (not a Datawall, not a locked Code
# Gate). Mirrors the game session's authoritative _can_travel_vertical so the
# menu can grey out a blocked Go Up / Go Down. See
# docs/multi-floor-travel-plan.md §2 blocking check.
func _can_travel_vertical(layout: CP2020DatafortLayout, target_coord: Vector2i, target_floor: int) -> bool:
	if target_floor < 0 or target_floor >= layout.get_floor_count():
		return false
	if target_coord.x < 0 or target_coord.x >= layout.columns \
			or target_coord.y < 0 or target_coord.y >= layout.rows:
		return false
	var tile := layout.get_tile(target_coord, target_floor)
	# Empty / no-tile = open floor (allowed). Only walls / locked gates block.
	if tile == null:
		return true
	if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
		return false
	if tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked:
		return false
	return true
