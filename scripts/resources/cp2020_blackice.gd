class_name BlackIce
extends Node2D

signal message_logged(msg: String)
signal moved_to(new_pos: Vector2i)
signal attacked_netrunner(strength: int)
signal destroyed

enum State { IDLE, PURSUE }

@export var program_name: String = "Hellhound"
@export var max_ap: int = 3
@export var strength: int = 4
@export var max_integrity: int = 4

var current_position: Vector2i = Vector2i.ZERO
var current_state: State = State.IDLE
var astar_grid: AStarGrid2D
var current_integrity: int = 4

@export var cell_size: int = 40
@export var grid_offset_y: int = 90
@export var label_visual_offset: Vector2 = Vector2(-2, -4)

@onready var skull_label = $SkullLabel

func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	current_position = start_pos
	current_integrity = max_integrity
	
	if skull_label:
		skull_label.size = Vector2(cell_size, cell_size)
		skull_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + label_visual_offset
		skull_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skull_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	update_visual_position()
	
	if astar_grid:
		astar_grid.free()
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, layout_size.x, layout_size.y)
	astar_grid.cell_size = Vector2(1, 1)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()
	
	moved_to.emit(current_position)

func update_visual_position() -> void:
	var center_x = (current_position.x * cell_size) + (cell_size / 2.0)
	var center_y = grid_offset_y + (current_position.y * cell_size) + (cell_size / 2.0)
	position = Vector2(center_x, center_y)

func take_turn(target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	if current_state == State.IDLE:
		current_state = State.PURSUE
		message_logged.emit("WARNING: %s activated and is hunting!" % program_name)
		
	if current_state != State.PURSUE:
		return
		
	_update_obstacles(layout)
	
	var ap_remaining = max_ap
	while ap_remaining > 0:
		var path = astar_grid.get_id_path(current_position, target_pos)
		
		if path.size() > 1: 
			var next_step = path[1]
			
			if next_step == target_pos:
				message_logged.emit("CRITICAL: %s attacks Netrunner with STR %d!" % [program_name, strength])
				attacked_netrunner.emit(strength)
				break
				
			current_position = next_step
			ap_remaining -= 1
			update_visual_position()
			
			await get_tree().create_timer(0.3).timeout
			moved_to.emit(current_position)
		else:
			break

func _update_obstacles(layout: CP2020DatafortLayout) -> void:
	# Optimized to use AStarGrid2D's native region filling instead of iterating manually over every dictionary key
	astar_grid.fill_solid_region(astar_grid.region, false) 
	
	for coord in layout.grid_tiles.keys():
		var tile = layout.grid_tiles[coord] as CP2020TileData
		if tile:
			if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL or (tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked):
				astar_grid.set_point_solid(coord, true)

func update_visibility(is_explored: bool, is_visible: bool) -> void:
	if not skull_label:
		return
	skull_label.visible = is_visible

func take_damage(amount: int) -> bool:
	current_integrity -= amount
	message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [program_name, amount, max(0, current_integrity), max_integrity])
	if current_integrity <= 0:
		message_logged.emit("%s DEREZED! ICE destroyed." % program_name)
		destroyed.emit()
		queue_free()
		return true
	return false
