class_name CP2020WorldHub
extends Resource

# A city marker on the World Map. Entering a city loads its City Grid
# (`city_grid_path`), where datafort icons carry the security tier. The
# `security_tier` field here is kept for save compatibility but no longer
# drives world-map icons.

@export var name: String = "New Hub"
@export var pos: Vector2i = Vector2i.ZERO
@export var subnet_path: String = "res://scenes/forts/night_city_subnet.tres"
# ldl_cost is deprecated: the Pay LDL option has been removed (paying gives
# away the runner's location). Kept for save compatibility; no longer read at
# runtime.
@export var ldl_cost: int = 50
@export var security_code: int = 4
@export var trace_value: int = 5
@export var security_tier: int = CP2020SecurityTier.Tier.LEVEL_1
@export var city_grid_path: String = ""