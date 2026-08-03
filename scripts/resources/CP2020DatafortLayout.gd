class_name CP2020DatafortLayout
extends Resource

@export var fort_name: String = "Unnamed Datafort"
@export var rows: int = 15
@export var columns: int = 15
@export var cpu: int = 5
@export var int_rating: int = 15
@export var datawall_strength: int = 5

# Layout-level resident programs the datafort's CPUs can run against an
# intruding netrunner (anti-system / anti-personnel). Assigned in the
# datafort designer. Must be duplicated at spawn time so cached .tres
# resources are never mutated across runs.
@export var resident_programs: Array[NetProgram] = []

# Enum for CP2020 tile types
enum TileType {
	EMPTY,
	WALL,
	DATAWALL,
	ENTRY,
	CODE_GATE,
	MEMORY_UNIT,
	CONTROL_NODE,
	BLACK_ICE,
	# NPC netrunner spawn points (full netrunner entities, not contact-attack
	# pathfinders like Black ICE). NETWATCH is hostile on sight; NETRUNNER is
	# neutral until provoked (takes damage -> turns hostile).
	NETWATCH,
	NETRUNNER
}

# Dictionary mapping Vector2i grid coordinates to a custom TileData structure or dictionary properties
# Example: { Vector2i(5, 5): { "type": TileType.CODE_GATE, "str": 4, "name": "Wall V1" } }
@export var grid_tiles: Dictionary = {}

# Helper function to safely fetch and auto-instantiate tile data objects
func get_tile(coord: Vector2i) -> CP2020TileData:
	var key = coord
	if not grid_tiles.has(key):
		key = "%d,%d" % [coord.x, coord.y] # Fallback for string keys
		if not grid_tiles.has(key):
			return null

	var raw_data = grid_tiles[key]
	
	# If it's already a CP2020TileData object, return it directly
	if raw_data is CP2020TileData:
		return raw_data
		
	# If it's still a raw Dictionary from the .tres file, convert it on the fly!
	if raw_data is Dictionary:
		var tile_obj = CP2020TileData.new()
		tile_obj.tile_type = raw_data.get("tile_type", 0)
		tile_obj.is_explored = raw_data.get("is_explored", false)
		tile_obj.is_visible = raw_data.get("is_visible", false)
		tile_obj.is_unlocked = raw_data.get("is_unlocked", true)
		
		# Replace the raw dictionary with the proper object so we only convert once
		grid_tiles[key] = tile_obj
		return tile_obj
		
	return null
	
