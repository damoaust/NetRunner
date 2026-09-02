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

# Parse a tile-dictionary key into a Vector2i. Serialised .tres files store
# grid-tile keys as "x,y" strings; runtime code uses Vector2i. This handles
# both forms so call sites don't repeat the inline split/branch pattern.
static func parse_coord(raw_key: Variant) -> Vector2i:
	if raw_key is String:
		var parts: PackedStringArray = raw_key.split(",")
		return Vector2i(parts[0].to_int(), parts[1].to_int())
	return raw_key

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
		floors = [f]
		return
	# Legacy .tres: wrap grid_tiles into a single CP2020Floor (floor 0).
	var f0 := CP2020Floor.new()
	f0.tiles = grid_tiles
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

	# If it's still a raw Dictionary from a legacy .tres file, convert it on
	# the fly into a proper CP2020TileData, copying EVERY @export field so
	# nothing is silently dropped. Normalise the storage key to Vector2i
	# (erasing the legacy "x,y" string key) so subsequent reads are direct
	# lookups and we never convert the same tile twice.
	if raw_data is Dictionary:
		push_error("Unexpected raw Dictionary tile at %s — migration may be incomplete" % coord)
		var tile_obj := _convert_raw_tile(raw_data)
		tile_dict.erase(key)
		tile_dict[coord] = tile_obj
		return tile_obj

	return null

# Converts a legacy raw Dictionary tile (from a pre-typed .tres file) into a
# proper CP2020TileData, copying every @export field. Any field missing from
# the dictionary falls back to the CP2020TileData default. Used by get_tile
# for on-the-fly migration of legacy tiles so no authored data is lost.
func _convert_raw_tile(raw_data: Dictionary) -> CP2020TileData:
	var t := CP2020TileData.new()
	t.tile_type = raw_data.get("tile_type", CP2020DatafortLayout.TileType.EMPTY)
	t.tile_name = raw_data.get("tile_name", "")
	t.strength_str = raw_data.get("strength_str", 0)
	t.memory_units_mu = raw_data.get("memory_units_mu", 0)
	t.reward_credits = raw_data.get("reward_credits", 0)
	t.is_unlocked = raw_data.get("is_unlocked", false)
	t.ldl_links = raw_data.get("ldl_links", {})
	t.is_visible = raw_data.get("is_visible", false)
	t.is_explored = raw_data.get("is_explored", false)
	t.is_ldl_link = raw_data.get("is_ldl_link", false)
	t.target_subnet_path = raw_data.get("target_subnet_path", "")
	t.target_entry_coord = raw_data.get("target_entry_coord", Vector2i(-1, -1))
	t.is_primary_entry = raw_data.get("is_primary_entry", false)
	t.can_go_up = raw_data.get("can_go_up", false)
	t.up_target_entry_coord = raw_data.get("up_target_entry_coord", Vector2i(-1, -1))
	t.can_go_down = raw_data.get("can_go_down", false)
	t.down_target_entry_coord = raw_data.get("down_target_entry_coord", Vector2i(-1, -1))
	t.ice_program = raw_data.get("ice_program", null)
	t.npc_name = raw_data.get("npc_name", "")
	t.npc_strength = raw_data.get("npc_strength", 0)
	t.npc_max_ap = raw_data.get("npc_max_ap", 0)
	t.npc_max_integrity = raw_data.get("npc_max_integrity", 0)
	t.npc_max_health = raw_data.get("npc_max_health", 0)
	t.npc_max_mu = raw_data.get("npc_max_mu", 0)
	t.npc_deck_name = raw_data.get("npc_deck_name", "")
	t.npc_disposition = raw_data.get("npc_disposition", CP2020NpcNetrunner.Disposition.HOSTILE)
	t.npc_disposition_override = raw_data.get("npc_disposition_override", false)
	t.npc_has_override = raw_data.get("npc_has_override", false)
	t.npc_programs = raw_data.get("npc_programs", [])
	t.cpu_int = raw_data.get("cpu_int", 0)
	t.cpu_crashed_turns = raw_data.get("cpu_crashed_turns", 0)
	t.loot_programs = raw_data.get("loot_programs", [])
	t.loot_modules = raw_data.get("loot_modules", [])
	t.loot_credits = raw_data.get("loot_credits", 0)
	t.is_looted = raw_data.get("is_looted", false)
	t.files = raw_data.get("files", [])
	t.copied_file_paths = raw_data.get("copied_file_paths", PackedStringArray())
	t.worm_turns_remaining = raw_data.get("worm_turns_remaining", 0)
	t.worm_integrity = raw_data.get("worm_integrity", 0)
	t.worm_max_integrity = raw_data.get("worm_max_integrity", 0)
	return t

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


# Single source of truth for vertical (up/down floor) travel blocking — used by
# the game session when executing travel and by the interaction handler to grey
# out blocked directions (CODE_REVIEW §7.10; see docs/multi-floor-travel-plan.md
# §2 blocking check). Returns "" when the move is allowed, otherwise one of:
# "no_floor", "out_of_bounds", "datawall", "locked_gate".
func vertical_travel_block(target_coord: Vector2i, target_floor: int) -> String:
	if target_floor < 0 or target_floor >= get_floor_count():
		return "no_floor"
	if target_coord.x < 0 or target_coord.x >= columns \
			or target_coord.y < 0 or target_coord.y >= rows:
		return "out_of_bounds"
	var tile := get_tile(target_coord, target_floor)
	# Empty / no-tile = open floor (allowed). Only walls / locked gates block.
	if tile == null:
		return ""
	if tile.tile_type == TileType.DATAWALL:
		return "datawall"
	if tile.tile_type == TileType.CODE_GATE and not tile.is_unlocked:
		return "locked_gate"
	return ""


# Convenience boolean wrapper over vertical_travel_block().
func can_travel_vertical(target_coord: Vector2i, target_floor: int) -> bool:
	return vertical_travel_block(target_coord, target_floor) == ""


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
	
