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

# Add `path` to `arr` if it is not already present. Returns true if added.
static func dedupe(arr: Array[String], path: String) -> bool:
	if arr.has(path):
		return false
	arr.append(path)
	return true