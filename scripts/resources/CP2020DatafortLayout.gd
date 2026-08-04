class_name CP2020DatafortLayout
extends Resource

@export var fort_name: String = "Unnamed Datafort"
@export var rows: int = 15
@export var columns: int = 15
@export var cpu: int = 5   # DEPRECATED: per-CPU INT is now fixed at 3 (CP2020 PnP). Kept for .tres compat.
@export var int_rating: int = 15  # DEPRECATED: total INT is now 3 * active CPU count. Kept for .tres compat.
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

# Writes a tile at coord using a Vector2i key, first erasing any existing
# entry under either the Vector2i or "x,y" string key form. Serialised .tres
# files can store keys as strings; runtime paint/drag uses Vector2i. Without
# this, repainting a string-keyed tile left a dangling string entry alongside
# the new Vector2i one (duplicate keys). Use this instead of writing
# grid_tiles[coord] directly.
func set_tile(coord: Vector2i, tile: CP2020TileData) -> void:
	erase_tile(coord)
	grid_tiles[coord] = tile

# Removes the tile at coord, clearing both possible key forms (Vector2i and
# "x,y" string). Safe to call even if no tile exists at the coord.
func erase_tile(coord: Vector2i) -> void:
	grid_tiles.erase(coord)
	grid_tiles.erase("%d,%d" % [coord.x, coord.y])


# Shared line-of-sight helper used by both the netrunner's fog-of-war vision
# and the adversaries' sight gating. Combines a Euclidean distance check
# (matching the existing fog radius) with the Bresenham raycast that blocks on
# DATAWALLs and locked CODE_GATEs.
#
# `max_range` is REQUIRED (no shared default): the runner and each program
# keep separate sight-range values (see @export sight_range on each entity)
# so future modifiers (deck/gear/program upgrades) can affect one side without
# touching the other. Each caller passes its own entity's sight range.
#
# The target tile itself is never treated as a blocker (the netrunner's tile
# is the target), even if the target sits on a wall/gate.
func line_of_sight(from: Vector2i, to: Vector2i, max_range: int) -> bool:
	if from == to:
		return true
	if from.distance_to(Vector2(to)) > max_range:
		return false

	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var x := from.x
	var y := from.y
	var n := 1 + dx + dy
	var x_inc := 1 if (to.x > from.x) else -1
	var y_inc := 1 if (to.y > from.y) else -1
	var error := dx - dy

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

		# Reaching the target tile means the ray is clear.
		if x == to.x and y == to.y:
			return true

		# Intermediate tiles block sight on Datawalls or locked Code Gates.
		var intermediate_coord := Vector2i(x, y)
		var tile = get_tile(intermediate_coord)
		if tile:
			if tile.tile_type == TileType.DATAWALL:
				return false
			if tile.tile_type == TileType.CODE_GATE and not tile.is_unlocked:
				return false

	return true
	
