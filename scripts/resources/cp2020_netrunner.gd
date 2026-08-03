class_name CP2020Netrunner
extends Node2D

signal position_changed(new_pos: Vector2i)
signal interacted_with_tile(tile_data: CP2020TileData, pos: Vector2i)
signal deck_updated()
signal message_logged(msg: String)
signal health_changed(current_health: int, max_health: int)
signal shield_raised(program: NetProgram)
signal shield_consumed
signal flatlined

@export var cell_size: int = 40
@export var grid_offset_y: int = 90

@export var deck_name: String = "Kendachi Cyberdeck"
@export var max_memory_units: int = 20
@export var installed_programs: Array[NetProgram] = []

@export var max_health: int = 20

var current_health: int = 20
var raised_shield: NetProgram = null
var interface_rank: int = 6  # Netrunner's INT for initiative (set from cyberdeck)

var current_position: Vector2i = Vector2i.ZERO
var current_layout: CP2020DatafortLayout

func get_used_memory() -> int:
	var total_mu = 0
	for prog in installed_programs:
		if prog:
			total_mu += prog.memory_cost
	return total_mu

func _ready() -> void:
	current_health = max_health
	message_logged.emit("Netrunner ready. Current memory used: %d / %d MU" % [get_used_memory(), max_memory_units])

func initialize(layout: CP2020DatafortLayout, entry_coord: Vector2i = Vector2i(-1, -1)) -> void:
	current_layout = layout
	if current_layout:
		# Spawn at a specific entry coord if one was supplied and is valid
		# (used by mid-run LDL travel to arrive at a designated tile).
		if entry_coord.x >= 0 and entry_coord.y >= 0 \
				and entry_coord.x < current_layout.columns and entry_coord.y < current_layout.rows \
				and current_layout.get_tile(entry_coord) != null:
			current_position = entry_coord
		else:
			for raw_key in current_layout.grid_tiles.keys():
				# 1. Safely parse the key
				var coord: Vector2i
				if raw_key is String:
					var parts = raw_key.split(",")
					coord = Vector2i(parts[0].to_int(), parts[1].to_int())
				else:
					coord = raw_key

				# 2. Use our safe helper
				var tile = current_layout.get_tile(coord)
				if tile and tile.tile_type == CP2020DatafortLayout.TileType.ENTRY:
					current_position = coord
					break

	update_visual_position()
	queue_redraw()
	position_changed.emit(current_position)
	message_logged.emit("Initialized in datafort at position %s" % current_position)

func update_visual_position() -> void:
	var center_x = (current_position.x * cell_size) + (cell_size / 2.0)
	var center_y = grid_offset_y + (current_position.y * cell_size) + (cell_size / 2.0)
	position = Vector2(center_x, center_y)

func _draw() -> void:
	# Glowing Cyan Netrunner Avatar
	draw_circle(Vector2.ZERO, 10, Color.CYAN)
	draw_arc(Vector2.ZERO, 12, 0, TAU, 16, Color.CYAN, 2.0)
	draw_circle(Vector2.ZERO, 4, Color.WHITE)

func install_program(prog: NetProgram) -> bool:
	if not prog:
		return false
	if get_used_memory() + prog.memory_cost <= max_memory_units:
		installed_programs.append(prog)
		message_logged.emit("Installed program: %s (%d MU)" % [prog.program_name, prog.memory_cost])
		deck_updated.emit()
		return true
	else:
		message_logged.emit("Memory full! Cannot install %s" % prog.program_name)
		return false

func uninstall_program(prog: NetProgram) -> void:
	if prog in installed_programs:
		installed_programs.erase(prog)
		message_logged.emit("Uninstalled program: %s" % prog.program_name)
		deck_updated.emit()

func move(direction: Vector2i) -> bool:
	if not current_layout:
		message_logged.emit("Error: No datafort layout loaded for movement!")
		return false
		
	var target_pos = current_position + direction
	
	if target_pos.x < 0 or target_pos.x >= current_layout.columns or target_pos.y < 0 or target_pos.y >= current_layout.rows:
		message_logged.emit("Movement blocked: Out of datafort bounds.")
		return false
		
	# Safely get the tile
	var tile_data = current_layout.get_tile(target_pos)
	
	if tile_data:
		if tile_data.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
			message_logged.emit("Movement blocked: Datawall encountered at %s." % target_pos)
			return false
			
		if tile_data.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile_data.is_unlocked:
			message_logged.emit("Movement blocked: Locked Code Gate encountered at %s." % target_pos)
			return false
				
	current_position = target_pos
	update_visual_position()
	queue_redraw()
	position_changed.emit(current_position)
	message_logged.emit("Netrunner relocated to %s" % current_position)
	
	if tile_data:
		interacted_with_tile.emit(tile_data, current_position)
			
	return true

func apply_damage(attack_strength: int, attacker_name: String) -> void:
	var damage: int = attack_strength
	if raised_shield != null:
		var shield_roll := randi_range(1, 10) + raised_shield.strength
		var attack_roll := randi_range(1, 10) + attack_strength
		message_logged.emit("Shield opposes: %d vs ICE %d." % [shield_roll, attack_roll])
		if shield_roll >= attack_roll:
			message_logged.emit("Shield thwarts the attack. No damage taken.")
			damage = 0
		else:
			message_logged.emit("Shield breached! Full damage applies.")
		raised_shield = null
		shield_consumed.emit()

	if damage > 0:
		current_health -= damage
		message_logged.emit("%s hits for %d damage (Health %d/%d)." % [attacker_name, damage, current_health, max_health])
		health_changed.emit(current_health, max_health)

	if current_health <= 0:
		current_health = 0
		message_logged.emit("FLATLINED. Netrunner jacked out.")
		flatlined.emit()

func raise_shield(program: NetProgram) -> void:
	raised_shield = program
	message_logged.emit("Shield raised (Block STR %d). Will thwart next attack on success." % program.strength)
	shield_raised.emit(program)
