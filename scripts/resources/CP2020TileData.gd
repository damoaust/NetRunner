class_name CP2020TileData
extends Resource

# Give each instance its own fresh arrays/dictionaries. Godot shares the
# default value [] / {} across all new() instances, so without this every
# tile would share the same files / loot_programs / npc_programs / ldl_links
# collection — adding a file to one tile would appear on all tiles.
func _init() -> void:
	files = []
	loot_programs = []
	loot_modules = []
	npc_programs = []
	ldl_links = {}

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
# Marks this ENTRY tile as the map's primary arrival point. The initial
# city-grid dive and inbound LDL travel (when no target_entry_coord is set)
# arrive here. At most one ENTRY tile per map should have this set; the
# datafort designer enforces one-primary-at-most on toggle and auto-sets it
# on the first plain (non-LDL) Entry painted. Defaults false so existing
# .tres files keep the previous first-ENTRY fallback (now preferring non-LDL
# entry tiles). See netrunner.initialize for the full arrival ordering.
@export var is_primary_entry: bool = false

# --- Multi-floor up/down travel (see docs/multi-floor-travel-plan.md §1) ---
# Marks this ENTRY tile as allowing vertical travel to the floor above/below
# within the SAME layout (no separate .tres). The target coord is the arrival
# position on the destination floor. A tile can have both up AND down
# (independent target coords). These are distinct from the horizontal LDL
# fields above (is_ldl_link / target_subnet_path / target_entry_coord) which
# cross dataforts.
@export var can_go_up: bool = false
@export var up_target_entry_coord: Vector2i = Vector2i(-1, -1)
@export var can_go_down: bool = false
@export var down_target_entry_coord: Vector2i = Vector2i(-1, -1)

# --- Per-tile ICE config (BLACK_ICE tiles). A program .tres is REQUIRED —
# every BLACK_ICE tile must have an assigned ice_program. The program
# supplies the ICE's program_name / strength / effect_type / damage_dice
# (driving take_turn behavior via the program's script). max_integrity is
# derived 1:1 from program.strength at spawn; movement is STR-based
# (program.strength spaces per turn, per CP2020). The program is
# duplicate()d at spawn time so the cached .tres is never mutated. Tracing
# behavior is deferred to program-specific subclasses (Hellhound/Flatline).
# There are no tier templates — tiles without an assigned program are
# skipped at spawn with a warning. ---
@export var ice_program: NetProgram = null

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
# Per-tile NPC disposition override. Only read when npc_disposition_override
# is true (mirroring the npc_has_override pattern); otherwise the game session
# uses the faction default (NetWatch hostile, Netrunner neutral). Typed as the
# Disposition enum so the inspector shows a dropdown.
@export var npc_disposition: CP2020NpcNetrunner.Disposition = CP2020NpcNetrunner.Disposition.HOSTILE
@export var npc_disposition_override: bool = false
@export var npc_has_override: bool = false
# Optional hand-authored program loadout (empty = use the tier template loadout).
# Must be duplicated at spawn time to avoid mutating cached .tres resources.
@export var npc_programs: Array[NetProgram] = []

# --- Per-CPU fields (CONTROL_NODE tiles). DEPRECATED: per CP2020 PnP rules
# each CPU contributes a flat 3 INT (see CP2020Datafort.INT_PER_CPU). The
# cpu_int field is kept for backward compatibility with existing .tres files
# but is no longer used in logic. cpu_crashed_turns > 0 means the CPU is
# currently crashed by a Krash anti-system program and contributes no INT /
# actions / MU until it reboots. Reset to 0 on every load_subnet (fog reset).---
@export var cpu_int: int = 0
@export var cpu_crashed_turns: int = 0

# --- Loot (MEMORY_UNIT tiles) ---
# Programs stored on this tile that a netrunner can download/loot during a
# dive. Entries are shared cached .tres references; the consumer (run
# inventory) is responsible for duplicate()ing them when moving them into the
# runner's deck so cached resources aren't mutated across scenes.
@export var loot_programs: Array[NetProgram] = []
# Lootable hardware modules (DeckModule) stashed on this tile. Like
# loot_programs, entries are shared cached .tres references; the consumer
# (RunState.add_module_loot) duplicates them when moving them into the
# runner's inventory so cached resources aren't mutated. Picked up via the
# same loot_tile interaction as loot_programs / loot_credits.
@export var loot_modules: Array[DeckModule] = []
# Lootable bonus credits stashed on this tile. This is distinct from
# reward_credits above, which is legacy/dead data that no live logic reads.
# loot_credits is the authoritative "lootable credits" value for the
# rogue-like loot-and-sell loop; reward_credits is kept only for backward
# compatibility with existing .tres files.
@export var loot_credits: int = 0
# Runtime flag: true once the runner has looted this tile. Reset to false on
# every load_subnet (same fog-reset pattern as is_explored / is_visible /
# cpu_crashed_turns) because ResourceLoader returns a cached instance.
@export var is_looted: bool = false

# --- Files (MEMORY_UNIT tiles) ---
# files REPLACE the loot_credits / loot_programs model for MEMORY_UNIT tiles.
# MEMORY_UNIT tiles now store discrete NetFile data the netrunner copies into
# deck memory during a dive (each file has its own name / description /
# credit_value / mu_size). CONTROL_NODE tiles keep using loot_programs above
# for their program loot, so the legacy loot_* / is_looted fields are retained
# and must not be removed.
@export var files: Array[NetFile] = []
# Runtime per-file "already copied this dive" tracking. Each entry is the
# INDEX (as a string) of a file within the `files` array that has already been
# copied this dive (e.g. "0", "2"). Index-based rather than resource_path-based
# because files may be inline-created NetFile instances with no resource path
# and may be duplicate()d. Reset to an empty array on every load_subnet (same
# fog-reset pattern as is_explored / is_visible / cpu_crashed_turns) because
# ResourceLoader returns a cached instance; cp2020_game_session performs that
# reset.
@export var copied_file_paths: PackedStringArray = []

# --- Worm program (runtime, DATAWALL / locked CODE_GATE tiles) ---
# Set to 2 by execute_worm when a Worm program is deployed on this tile.
# Ticked down at the start of each netrunner turn in _on_turn_ended; when it
# reaches 0 the tile opens (DATAWALL -> EMPTY, CODE_GATE -> is_unlocked = true).
# Always 0 in authored .tres layouts — only set during gameplay. Reset to 0 on
# every load_subnet (same fog-reset pattern as cpu_crashed_turns / is_looted /
# copied_file_paths) because ResourceLoader returns a cached instance.
@export var worm_turns_remaining: int = 0
# Worm structural integrity (runtime). Set to the Worm program's `strength`
# when a Worm is deployed on this tile (alongside worm_turns_remaining), and
# decremented by enemy DEREZ_ICE (Killer) attacks — a Worm is a passive
# defender that can only damage walls/gates, so only the attacking Killer can
# deal damage on a winning opposed roll. When integrity reaches 0 the Worm is
# destroyed (worm_turns_remaining is reset to 0 and the tile stays closed —
# the intrusion failed). Always 0 in authored .tres layouts — only set during
# gameplay. Reset to 0 on every load_subnet alongside worm_turns_remaining.
@export var worm_integrity: int = 0
# Worm max integrity (runtime). Set alongside worm_integrity when a Worm is
# deployed — equals the Worm program's `strength`. Used for the board
# renderer's "current/max" integrity display and the damage log. Reset to 0
# on load_subnet alongside worm_integrity.
@export var worm_max_integrity: int = 0
