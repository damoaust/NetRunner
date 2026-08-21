class_name CP2020Mission
extends Resource

# A single contract/bounty offered on the workbench Missions board. Missions are
# authored as static .tres files in res://data/missions/ (the "mission library")
# and rotated onto the available board over time by the world-clock refresh.
#
# The player may hold at most ONE active mission at a time. Mission progress is
# tracked per-life in RunState (active_mission + mission_objective_met); the
# resource itself is a read-only template and is never mutated at runtime.
#
# Completion is NOT automatic on jack-out — the runner must return to the
# workbench and click "Hand In" to receive the flat credit reward. Hand-in
# re-verifies the objective proof (carried file for DATA_HARVEST, or the
# RunState.mission_objective_met flag for SABOTAGE/RECON) before paying out.

enum MissionType { DATA_HARVEST, SABOTAGE, RECON }

# Unique identifier (stable across the library; used for de-duplication).
@export var mission_id: String = ""
# Display title, e.g. "City Hall Mainframe Sabotage".
@export var title: String = "Untitled Contract"
# Lore / briefing + target instructions shown in the detail card.
@export var description: String = ""
# Contract category.
@export var mission_type: int = MissionType.DATA_HARVEST
# Flat credit payout on hand-in (eb).
@export var reward_credits: int = 0

# --- Exact targeting fields ---
# Human-readable target location label, e.g. "Night City: City Hall". Shown in
# the active-mission status box so the runner knows where to go.
@export var target_location_label: String = ""
# Path to the destination subnet .tres the runner must dive into.
@export var target_subnet_path: String = ""
# Exact grid coordinate for SABOTAGE / RECON objectives. (-1,-1) = unset.
@export var target_coord: Vector2i = Vector2i(-1, -1)
# Exact file name required for DATA_HARVEST. The runner must copy a file whose
# file_name matches this string and carry it back to the hub.
@export var target_file_name: String = ""

# Brief one-line summary of the objective, e.g. "Steal the personnel roster".
@export var objective_summary: String = ""

# Resource path of the library .tres this mission was loaded from. Tagged on
# load/duplicate (same pattern as NetProgram / DeckModule) so save/load can
# reconstruct the board by path without mutating the cached library .tres.
# Not @export — it is a runtime tag, not authored content.
var source_path: String = ""

# Returns a short tag for the mission type (used by the workbench list rows).
static func type_tag(t: int) -> String:
	match t:
		MissionType.DATA_HARVEST:
			return "HARVEST"
		MissionType.SABOTAGE:
			return "SABOTAGE"
		MissionType.RECON:
			return "RECON"
		_:
			return "???"

# Returns a longer label for the detail card.
static func type_label(t: int) -> String:
	match t:
		MissionType.DATA_HARVEST:
			return "Data Harvest"
		MissionType.SABOTAGE:
			return "Sabotage"
		MissionType.RECON:
			return "Recon"
		_:
			return "Unknown"

# Returns a human-readable objective line for this mission (shown in the detail
# card + active status box).
func objective_text() -> String:
	match mission_type:
		MissionType.DATA_HARVEST:
			return "Steal file: \"%s\" from %s" % [target_file_name, target_location_label]
		MissionType.SABOTAGE:
			return "Sabotage target at grid %s in %s" % [str(target_coord), target_location_label]
		MissionType.RECON:
			return "Recon grid %s in %s" % [str(target_coord), target_location_label]
		_:
			return objective_summary