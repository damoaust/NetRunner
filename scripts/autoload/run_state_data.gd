extends Resource

# Serializable snapshot of RunState's per-life state. Saved to
# user://run_state.tres when the player is at the hub and reloaded on startup.
# Wiped by GameOver -> New Life so permadeath still resets progress.

@export var credits: int = 0
@export var accumulated_trace: int = 0
# Meatspace security-dispatch countdown (turns until a raid arrives while the
# runner is jacked in). Set when a Watchdog trace check succeeds; ticks down
# each netrunner turn during datafort gameplay. 0 = no active dispatch.
@export var security_dispatch_turns: int = 0
# Cumulative net time (seconds) spent jacked in this run, scaled by grid level
# (world map action = 60 s, city grid = 1 s, datafort = 1 ns). Reset per run.
@export var net_time_seconds: float = 0.0
# Life-accumulative net time (seconds): same advancement as net_time_seconds
# but persists across runs within a life (only cleared on new life). Used for
# the workbench header display; does NOT drive mission refresh.
@export var life_net_time_seconds: float = 0.0

@export var selected_deck_path: String = ""
@export var selected_subnet_path: String = ""
@export var selected_city_grid_path: String = ""
@export var selected_security_tier: int = 0
# Resource path of the equipped NetrunnerCharacter .tres for this life. Saved/
# restored across app restarts like selected_deck_path (the character resource
# is read-only at runtime, so we store the path directly, no duplication).
@export var selected_character_path: String = ""

# Each owned deck is stored as a dictionary: { "path": deck_resource_path,
# "installed_program_paths": [path, ...], "installed_module_paths":
# [path, ...] }. The original resource is duplicated on load and the listed
# programs/modules are duplicated and installed.
@export var owned_deck_entries: Array = []

@export var owned_program_paths: Array[String] = []
@export var owned_module_paths: Array[String] = []
@export var loot_paths: Array[String] = []

# Carried files are often runtime duplicates, so we store them inline.
@export var carried_file_entries: Array[Dictionary] = []

@export var last_death_cause: String = ""
@export var last_run_summary: Dictionary = {}

# --- Missions system (per-life) ---
# The available mission board is a rotating subset of the static mission
# library (res://data/missions/*.tres). It persists across app restarts
# within a life and resets on new life (alongside net_time_seconds, which
# drives the refresh clock). Stored as resource paths; reloaded + duplicated
# by RunState._load_run.
@export var available_mission_paths: Array[String] = []
# Resource path of the currently accepted mission ("" = none). Reloaded as a
# read-only template by path.
@export var active_mission_path: String = ""
# True once the active mission's objective has been satisfied in the Net this
# run (file copied / coordinate sabotaged / coordinate reconned). Reset on new
# life. Re-verified at hand-in time (DATA_HARVEST also requires the file still
# carried).
@export var mission_objective_met: bool = false
# net_time_seconds snapshot at the last board refresh. The workbench compares
# the current net_time_seconds against this to decide if an hour has elapsed
# and a new mission should be rotated in. Resets on new life.
@export var last_mission_refresh_time: float = 0.0

# Schema version for forward-compatible save migrations. Increment when the
# RunStateData layout changes; _load_run / meta_state._migrate_paths branch on
# this to upgrade older saves in place. Defaults to 1 (the version at which the
# field was introduced); older saves without the field load as 1.
@export var schema_version: int = 1
