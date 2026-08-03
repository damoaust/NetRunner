class_name NetFile
extends Resource

# A data file stored on a MEMORY_UNIT tile. A netrunner copies files to their
# deck's memory (consuming MU alongside programs) during a dive, then fences
# them at the hub shop for `credit_value` eb. The value is NOT shown in the
# datafort right-click menu — it is discovered at the hub. Per-file lore /
# flavour lives in `description`.
#
# When a tile is copied, the file instance is duplicate()d into
# RunState.carried_files so cached .tres resources are never mutated across
# scenes (same pattern as loot_programs / NetProgram).

@export var file_name: String = "Untitled File"
@export var description: String = ""
@export var credit_value: int = 0  # Fence price at the hub shop (eb).
@export var mu_size: int = 1       # Deck memory consumed while carrying the file.

func get_used_mu() -> int:
	return mu_size