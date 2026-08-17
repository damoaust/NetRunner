class_name CP2020WorldMapLayout
extends Resource

# Serializable world map layout authored by the world map designer and loaded
# at runtime by cp_2020_world_net_map.gd. Regions are categorising only
# (colour + HUD label); the runner may traverse any in-bounds tile including
# the blue open-ocean areas (tiles with no region assigned).

@export var grid_cols: int = 32
@export var grid_rows: int = 18

# Named regions used for categorising (colour + label). Index 0 is NOT a
# special "ocean" region — ocean is simply the absence of a region assignment.
@export var regions: Array[CP2020WorldRegion] = []

# Vector2i -> int region index (into `regions`). Tiles absent from this
# dictionary are open ocean.
@export var tile_region: Dictionary = {}

# City hubs: overlay markers on top of whichever region they sit in.
@export var hubs: Array[CP2020WorldHub] = []

# Name of the hub the runner spawns on at the start of a run.
@export var runner_spawn_hub: String = "Night City"


func get_region_index(pos: Vector2i) -> int:
	var key = pos
	if not tile_region.has(key):
		key = "%d,%d" % [pos.x, pos.y]
	if not tile_region.has(key):
		return -1
	return int(tile_region[key])


func get_region(pos: Vector2i) -> CP2020WorldRegion:
	var idx := get_region_index(pos)
	if idx < 0 or idx >= regions.size():
		return null
	return regions[idx]


func get_hub(pos: Vector2i) -> CP2020WorldHub:
	for hub in hubs:
		if hub is CP2020WorldHub and hub.pos == pos:
			return hub
	return null


func get_hub_by_name(hub_name: String) -> CP2020WorldHub:
	for hub in hubs:
		if hub is CP2020WorldHub and hub.name == hub_name:
			return hub
	return null
