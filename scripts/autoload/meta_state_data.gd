class_name MetaStateData
extends Resource

# Persistent meta-progression catalogue. Survives permadeath — saved to
# user://netrunner_meta.tres and reloaded by the MetaState autoload on startup.
# RunState holds per-life state that is LOST on death; this resource is the
# ONLY thing that persists across deaths.

@export var unlocked_decks: Array[String] = []
@export var unlocked_programs: Array[String] = []
@export var unlocked_modules: Array[String] = []
@export var run_history: Array = []

# Resource path of the runner's last-chosen character .tres. A persistent meta
# preference — survives permadeath so the player keeps their chosen runner face
# across lives. Seeded by MetaState._init_default_catalogue on first launch.
@export var selected_character_path: String = ""

# Add `path` to `arr` if it is not already present. Returns true if added.
static func dedupe(arr: Array[String], path: String) -> bool:
	if arr.has(path):
		return false
	arr.append(path)
	return true