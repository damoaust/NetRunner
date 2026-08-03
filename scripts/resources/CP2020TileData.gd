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

# --- Per-tile ICE overrides (BLACK_ICE tiles). Zero/empty = use the hub
# security-tier template from cp2020_game_session. Non-zero values here take
# precedence and let designers hand-tune individual ICE. ---
@export var ice_program_name: String = ""
@export var ice_strength: int = 0
@export var ice_max_ap: int = 0
@export var ice_max_integrity: int = 0
@export var ice_traces: bool = false
@export var ice_has_override: bool = false

# --- Per-tile NPC overrides (NETWATCH / NETRUNNER tiles). Zero/empty = use the
# tier NPC template from cp2020_game_session.TIER_NPC_TEMPLATES. Non-zero
# values take precedence and let designers hand-tune individual NPCs, exactly
# like the ice_* override pattern above. ---
@export var npc_name: String = ""
@export var npc_strength: int = 0
@export var npc_max_ap: int = 0
@export var npc_max_integrity: int = 0
@export var npc_max_health: int = 0
@export var npc_max_mu: int = 0
@export var npc_deck_name: String = ""
# CP2020NpcNetrunner.Disposition as int (0 = HOSTILE, 1 = NEUTRAL).
# NetWatch tiles default hostile; Netrunner tiles default neutral. A designer
# override of 0/1 forces the disposition regardless of faction.
@export var npc_disposition: int = -1
@export var npc_has_override: bool = false
# Optional hand-authored program loadout (empty = use the tier template loadout).
# Must be duplicated at spawn time to avoid mutating cached .tres resources.
@export var npc_programs: Array[NetProgram] = []

# --- Per-CPU fields (CONTROL_NODE tiles). cpu_int = 0 means "use the layout
# default" (layout.cpu). cpu_crashed_turns > 0 means the CPU is currently
# crashed by a Krash anti-system program and contributes no INT / extra
# actions until it reboots. Reset to 0 on every load_subnet (fog reset loop).---
@export var cpu_int: int = 0
@export var cpu_crashed_turns: int = 0
