extends Node

# Autoload singleton holding the persistent meta-progression catalogue.
# Decks/programs discovered or looted during a run become permanently
# purchasable at the hub shop in future lives. The catalogue is saved to
# user://netrunner_meta.tres (Godot's per-user writable dir) — NEVER to res://.

const SAVE_PATH: String = "user://netrunner_meta.tres"
const MAX_RUN_HISTORY: int = 50

# Starting catalogue — the deck and programs every fresh life begins with.
const STARTING_DECK: String = "res://data/starting_deck.tres"
const STARTING_PROGRAMS: Array[String] = [
	"res://data/codecracker.tres",
	"res://data/shield.tres",
]

var data: MetaStateData = null


func _ready() -> void:
	_load()


func _load() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded: Resource = load(SAVE_PATH)
		if loaded is MetaStateData:
			data = loaded
			return
		push_warning("MetaState: saved catalogue was not a MetaStateData — falling back to default.")
	# No save (or load failed) — build a fresh default catalogue.
	_init_default_catalogue()


func save() -> void:
	if data == null:
		push_error("MetaState: cannot save — data is null.")
		return
	var err: int = ResourceSaver.save(data, SAVE_PATH)
	if err != OK:
		push_error("MetaState: ResourceSaver failed with error %d." % err)


func _init_default_catalogue() -> void:
	data = MetaStateData.new()
	data.unlocked_decks = [STARTING_DECK]
	data.unlocked_programs = STARTING_PROGRAMS.duplicate()
	data.run_history = []


func unlock_deck(path: String) -> void:
	if data == null:
		_init_default_catalogue()
	if MetaStateData.dedupe(data.unlocked_decks, path):
		save()


func unlock_program(path: String) -> bool:
	if data == null:
		_init_default_catalogue()
	if MetaStateData.dedupe(data.unlocked_programs, path):
		save()
		return true
	return false


func unlock_program_resource(prog: NetProgram) -> void:
	if prog == null:
		return
	if prog.resource_path != "":
		unlock_program(prog.resource_path)


func unlock_deck_resource(deck: Cyberdeck) -> void:
	if deck == null:
		return
	if deck.resource_path != "":
		unlock_deck(deck.resource_path)


func record_run(summary: Dictionary) -> void:
	if data == null:
		_init_default_catalogue()
	data.run_history.append(summary)
	while data.run_history.size() > MAX_RUN_HISTORY:
		data.run_history.pop_front()
	save()


func reset_catalogue() -> void:
	_init_default_catalogue()
	save()


func has_deck(path: String) -> bool:
	if data == null:
		return false
	return data.unlocked_decks.has(path)


func has_program(path: String) -> bool:
	if data == null:
		return false
	return data.unlocked_programs.has(path)