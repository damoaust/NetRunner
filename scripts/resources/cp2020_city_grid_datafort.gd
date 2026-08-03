class_name CP2020CityGridDatafort
extends Resource

# A datafort icon on a City Grid. `pos` is the tile within the grid. The
# `subnet_path` points at the datafort interior (.tres). `security_tier` is
# the CP2020 classification (CP2020SecurityTier.Tier) and drives the icon
# colour/glyph + the default ICE loadout for BLACK_ICE tiles in the interior.
# `ldl_cost`/`security_code`/`trace_value` govern Hack/Pay LDL jumps between
# dataforts in the same city grid.

@export var name: String = "New Datafort"
@export var pos: Vector2i = Vector2i.ZERO
@export var subnet_path: String = "res://scenes/forts/night_city_subnet.tres"
@export var security_tier: int = CP2020SecurityTier.Tier.LEVEL_1
@export var ldl_cost: int = 50
@export var security_code: int = 4
@export var trace_value: int = 5