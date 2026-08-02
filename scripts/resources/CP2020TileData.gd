class_name CP2020TileData
extends Resource

@export var tile_type: CP2020DatafortLayout.TileType = CP2020DatafortLayout.TileType.EMPTY
@export var tile_name: String = ""
@export var strength_str: int = 0          # Used for Code Gates / Datawalls
@export var memory_units_mu: int = 0       # MU storage size
@export var reward_credits: int = 0        # Credits or file value stored here
@export var is_unlocked: bool = false       # Breach state
@export var ldl_links: Dictionary = {}
# Fog of War properties
@export var is_visible: bool = false
@export var is_explored: bool = false

# --- NEW: Authentic CP2020 LDL Routing Properties ---
@export var is_ldl_link: bool = false      # Marks this tile as a Long Distance Line connection point
@export var target_subnet_path: String = "" # Resource path (.tres) to the linked remote subnet/datafort
@export var target_entry_coord: Vector2i = Vector2i(-1, -1) # Arrival coordinate in the remote subnet
