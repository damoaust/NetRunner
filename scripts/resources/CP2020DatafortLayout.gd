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
# DEPRECATED: kept for backward compat with pre-multi-floor .tres files. On
# first access the layout migrates grid_tiles into floors[0].tiles (see
# _ensure_floors_migrated). New layouts author floors directly.
@export var grid_tiles: Dictionary = {}

# Multi-floor storage: one CP2020Floor per floor. Floor 0 = floors[0],
# floor 1 = floors[1], etc. Array index IS the floor index. See
# docs/multi-floor-travel-plan.md §1.
@export var floors: Array[CP2020Floor] = []

# Runtime-only: which floor the runner / designer is currently viewing.
# Set by the game session and the designer before any floor-scoped read/write.
var current_floor: int = 0

# Lazily migrates legacy grid_tiles into floors[0] on first access. Safe to
# call repeatedly — short-circuits once floors is populated. Handles both
# truly-new layouts (empty grid_tiles, empty floors) and legacy .tres files
# (populated grid_tiles, empty floors).
func _ensure_floors_migrated() -> void:
	if floors.size() > 0:
		return
	if grid_tiles.is_empty():
		# New layout with no tiles yet — seed a single empty floor so the
		# designer has something to paint on.
		var f := CP2020Floor.new()
		f.floor_index = 0
		floors = [f]
		return
	# Legacy .tres: wrap grid_tiles into a single CP2020Floor (floor 0).
	var f0 := CP2020Floor.new()
	f0.tiles = grid_tiles
	f0.floor_index = 0
	floors = [f0]

# Helper function to safely fetch and auto-instantiate tile data objects.
# `floor` is REQUIRED (no default) — callers must pass the floor index
# explicitly (usually `layout.current_floor`). This makes floor awareness
# impossible to silently forget. See docs/multi-floor-travel-plan.md §1.
func get_tile(coord: Vector2i, floor: int) -> CP2020TileData:
	_ensure_floors_migrated()
	if floor < 0 or floor >= floors.size():
		return null
	var tile_dict: Dictionary = floors[floor].tiles
	var key = coord
	if not tile_dict.has(key):
		key = "%d,%d" % [coord.x, coord.y] # Fallback for string keys
		if not tile_dict.has(key):
			return null

	var raw_data = tile_dict[key]
	
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
		tile_dict[key] = tile_obj
		return tile_obj
		
	return null

# Writes a tile at coord using a Vector2i key, first erasing any existing
# entry under either the Vector2i or "x,y" string key form. Serialised .tres
# files can store keys as strings; runtime paint/drag uses Vector2i. Without
# this, repainting a string-keyed tile left a dangling string entry alongside
# the new Vector2i one (duplicate keys). Use this instead of writing
# floors[floor].tiles[coord] directly. `floor` is REQUIRED.
func set_tile(coord: Vector2i, tile: CP2020TileData, floor: int) -> void:
	_ensure_floors_migrated()
	if floor < 0 or floor >= floors.size():
		return
	erase_tile(coord, floor)
	floors[floor].tiles[coord] = tile

# Removes the tile at coord, clearing both possible key forms (Vector2i and
# "x,y" string). Safe to call even if no tile exists at the coord. `floor` is
# REQUIRED.
func erase_tile(coord: Vector2i, floor: int) -> void:
	_ensure_floors_migrated()
	if floor < 0 or floor >= floors.size():
		return
	floors[floor].tiles.erase(coord)
	floors[floor].tiles.erase("%d,%d" % [coord.x, coord.y])

# Returns the raw tiles Dictionary for the given floor. `floor` is REQUIRED.
func get_floor_tiles(floor: int) -> Dictionary:
	_ensure_floors_migrated()
	if floor < 0 or floor >= floors.size():
		return {}
	return floors[floor].tiles

# Convenience: returns the tiles dict for the current floor. Use this for the
# common "current floor" case so call sites read clearly without passing
# current_floor explicitly.
func get_current_floor_tiles() -> Dictionary:
	return get_floor_tiles(current_floor)

# Returns the number of floors (floors.size()). Derived, not stored.
func get_floor_count() -> int:
	_ensure_floors_migrated()
	return floors.size()


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
func line_of_sight(from: Vector2i, to: Vector2i, max_range: int, floor: int) -> bool:
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
		var tile = get_tile(intermediate_coord, floor)
		if tile:
			if tile.tile_type == TileType.DATAWALL:
				return false
			if tile.tile_type == TileType.CODE_GATE and not tile.is_unlocked:
				return false

	return true
	
