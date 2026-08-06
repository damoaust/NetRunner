extends Resource

# Serializable snapshot of RunState's per-life state. Saved to
# user://run_state.tres when the player is at the hub and reloaded on startup.
# Wiped by GameOver -> New Life so permadeath still resets progress.

@export var credits: int = 0
@export var accumulated_trace: int = 0

@export var selected_deck_path: String = ""
@export var selected_subnet_path: String = ""
@export var selected_city_grid_path: String = ""
@export var selected_security_tier: int = 0

# Each owned deck is stored as a dictionary: { "path": deck_resource_path,
# "installed_program_paths": [path, ...] }. The original resource is duplicated
# on load and the listed programs are duplicated and installed.
@export var owned_deck_entries: Array = []

@export var owned_program_paths: Array[String] = []
@export var loot_paths: Array[String] = []

# Carried files are often runtime duplicates, so we store them inline.
@export var carried_file_entries: Array[Dictionary] = []

@export var last_death_cause: String = ""
@export var last_run_summary: Dictionary = {}
