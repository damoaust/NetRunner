class_name CP2020WorldHub
extends Resource

# Datafort security classification (CP2020). Drives the world-map icon colour
# and the default ICE loadout for BLACK_ICE tiles. Distinct from
# `security_code`, which is the LDL hack difficulty (1D10 >= code).
enum SecurityTier { GREY, LEVEL_1, LEVEL_2, LEVEL_3, BLACK }

@export var name: String = "New Hub"
@export var pos: Vector2i = Vector2i.ZERO
@export var subnet_path: String = "res://scenes/forts/night_city_subnet.tres"
@export var ldl_cost: int = 50
@export var security_code: int = 4
@export var trace_value: int = 5
@export var security_tier: int = SecurityTier.LEVEL_1

# Tier metadata shared by the world map designer + runtime renderer.
const TIER_LABELS: Dictionary = {
	SecurityTier.GREY: "GREY",
	SecurityTier.LEVEL_1: "LEVEL 1",
	SecurityTier.LEVEL_2: "LEVEL 2",
	SecurityTier.LEVEL_3: "LEVEL 3",
	SecurityTier.BLACK: "BLACK",
}
const TIER_SHORT: Dictionary = {
	SecurityTier.GREY: "Grey",
	SecurityTier.LEVEL_1: "L1",
	SecurityTier.LEVEL_2: "L2",
	SecurityTier.LEVEL_3: "L3",
	SecurityTier.BLACK: "Black",
}
const TIER_COLORS: Dictionary = {
	SecurityTier.GREY: Color(0.62, 0.62, 0.62, 1.0),
	SecurityTier.LEVEL_1: Color(0.20, 0.90, 0.35, 1.0),
	SecurityTier.LEVEL_2: Color(1.00, 0.85, 0.20, 1.0),
	SecurityTier.LEVEL_3: Color(1.00, 0.55, 0.15, 1.0),
	SecurityTier.BLACK: Color(1.00, 0.22, 0.27, 1.0),
}
const TIER_GLYPHS: Dictionary = {
	SecurityTier.GREY: "G",
	SecurityTier.LEVEL_1: "1",
	SecurityTier.LEVEL_2: "2",
	SecurityTier.LEVEL_3: "3",
	SecurityTier.BLACK: "B",
}