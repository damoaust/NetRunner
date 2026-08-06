extends Node

const RunStateData := preload("res://scripts/autoload/run_state_data.gd")

# Autoload singleton holding cross-scene PER-LIFE state. All of this is lost
# on permadeath. Set at the workbench, read by the gameplay session.

# --- Starting gear constants (mirror MetaState's starting catalogue) ---
# 0 eb: credits must be earned from runs (sell loot/files) before buying
# unlocks/upgrades, so a fresh life can't farm persistent MetaState unlocks.
const STARTING_CREDITS: int = 0
const STARTING_DECK_PATH: String = "res://data/starting_deck.tres"
const STARTING_PROGRAM_PATHS: Array[String] = [
	"res://data/codecracker.tres",
	"res://data/shield.tres",
]

const RUN_SAVE_PATH: String = "user://run_state.tres"

var selected_deck: Cyberdeck = null
var selected_subnet_path: String = ""
var credits: int = STARTING_CREDITS
# Total Trace Value of all LDLs passed through in the current Net run. Drives
# tracing-program rolls during the datafort session; reset per run.
var accumulated_trace: int = 0
# City Grid currently in play (set by the world map ENTER action). The
# datafort LDL-return uses this to go back to the right city grid.
var selected_city_grid_path: String = ""
# Security tier of the datafort the runner dived into (set by the city grid
# DIVE action). Read by game_session for the ICE loadout template.
var selected_security_tier: int = 0

# --- Transient death-cause fields (set by game_session before routing to
# GameOver, read by GameOver, cleared on new life / reset). NOT per-life
# inventory — purely a scene-change handoff. ---
var last_death_cause: String = ""
var last_run_summary: Dictionary = {}

# --- Per-life inventory (lost on death) ---
# Programs looted from datafort tiles during the current run, carried back to
# the hub to sell. Lost on death.
var loot: Array[NetProgram] = []
# Decks the runner owns this life (purchased at the hub shop). The currently
# equipped deck is `selected_deck`.
var owned_decks: Array[Cyberdeck] = []
# Programs the runner owns this life (purchased or starting), available to
# load into the deck at the workbench.
var owned_programs: Array[NetProgram] = []
# Files copied from datafort MEMORY_UNIT tiles during the current run, carried
# to the hub to fence for their credit_value. Consume deck MU alongside
# programs while carried. Lost on death.
var carried_files: Array[NetFile] = []

func _ready() -> void:
	_load_run()

# Full wipe — clears every field to defaults. Called by start_new_life() and
# by any explicit hard-reset path.
func reset() -> void:
	selected_deck = null
	selected_subnet_path = ""
	credits = STARTING_CREDITS
	accumulated_trace = 0
	selected_city_grid_path = ""
	selected_security_tier = 0
	loot.clear()
	owned_decks.clear()
	owned_programs.clear()
	carried_files.clear()
	last_death_cause = ""
	last_run_summary.clear()

# Called when a new life begins (after permadeath, or the very first life).
# Wipes state then populates the starting gear.
func start_new_life() -> void:
	reset()
	# Starting deck — duplicate so installed_programs is a unique mutable
	# instance the player can modify at the workbench.
	var deck: Cyberdeck = load(STARTING_DECK_PATH) as Cyberdeck
	if deck:
		deck = deck.duplicate()
		owned_decks.append(deck)
		selected_deck = deck
	else:
		push_error("RunState: failed to load starting deck '%s'." % STARTING_DECK_PATH)
	# Starting programs — keep as resource references (match the catalogue
	# references the workbench uses).
	for path: String in STARTING_PROGRAM_PATHS:
		var prog: NetProgram = load(path) as NetProgram
		if prog:
			owned_programs.append(prog)
		else:
			push_error("RunState: failed to load starting program '%s'." % path)

# --- Loot helpers (used by the loot interaction) ---
# Appends a duplicate of prog to loot (duplicate to avoid mutating cached
# .tres). Also discovers the program in the persistent MetaState catalogue.
func add_loot(prog: NetProgram) -> void:
	if prog == null:
		return
	loot.append(prog.duplicate())
	if prog.resource_path != "":
		MetaState.unlock_program(prog.resource_path)

# Adds amount to credits (for loot_credits pickups).
func add_loot_credits(amount: int) -> void:
	credits += amount

# --- Sell helper (used by the hub shop) ---
# Sells a loot program at fence_factor of its price. Adds proceeds to credits,
# removes the program from loot, returns the sell price. Returns 0 if the
# program is not in loot.
func sell_loot_program(prog: NetProgram, fence_factor: float = 0.5) -> int:
	if prog == null:
		return 0
	var idx: int = loot.find(prog)
	if idx < 0:
		# prog may be a different instance with the same resource_path —
		# fall back to matching by resource_path.
		for i: int in range(loot.size()):
			if loot[i] != null and loot[i].resource_path != "" \
					and loot[i].resource_path == prog.resource_path:
				idx = i
				break
	if idx < 0:
		return 0
	var sell_price: int = int(loot[idx].price * fence_factor)
	credits += sell_price
	loot.remove_at(idx)
	return sell_price

# --- Carried-file helpers (used by the memory-tile copy + hub fence) ---
# Appends a duplicate of file to carried_files (duplicate to avoid mutating
# cached .tres, matching add_loot). Does NOT check MU — the caller is
# responsible for the free-MU check via get_carried_files_mu. Returns false if
# file is null.
func copy_file(file: NetFile) -> bool:
	if file == null:
		return false
	carried_files.append(file.duplicate())
	return true

# Sums mu_size over carried_files (skipping null entries). Used by the
# netrunner / game_session for the free-MU check before copying a file.
func get_carried_files_mu() -> int:
	var total: int = 0
	for f: NetFile in carried_files:
		if f != null:
			total += f.mu_size
	return total

# Sells a carried file at its FULL credit_value (no fence factor — value is a
# fixed authored price). Adds proceeds to credits, removes the file from
# carried_files, returns the sell price. Returns 0 if the file is not carried.
# Matches by instance first, then falls back to file_name (duplicate() may
# clear instance identity but file_name is stable).
func sell_file(file: NetFile) -> int:
	if file == null:
		return 0
	var idx: int = carried_files.find(file)
	if idx < 0:
		# file may be a different instance with the same file_name —
		# fall back to matching by file_name.
		for i: int in range(carried_files.size()):
			if carried_files[i] != null and carried_files[i].file_name == file.file_name:
				idx = i
				break
	if idx < 0:
		return 0
	var sell_price: int = carried_files[idx].credit_value
	credits += sell_price
	carried_files.remove_at(idx)
	return sell_price

# --- Owned-gear purchase helpers (used by the hub shop) ---
# Purchases a deck: subtracts price from credits, appends a duplicate to
# owned_decks, returns true. Returns false if deck is null or insufficient
# credits.
func buy_deck(deck: Cyberdeck) -> bool:
	if deck == null:
		return false
	if credits < deck.price:
		return false
	credits -= deck.price
	owned_decks.append(deck.duplicate())
	return true

# Purchases a program: subtracts price from credits, appends a duplicate to
# owned_programs, returns true. Returns false if prog is null or insufficient
# credits.
func buy_program(prog: NetProgram) -> bool:
	if prog == null:
		return false
	if credits < prog.price:
		return false
	credits -= prog.price
	owned_programs.append(prog.duplicate())
	return true

# Equips a deck the runner already owns.
func equip_deck(deck: Cyberdeck) -> void:
	selected_deck = deck

# --- Run-state persistence (survives app restarts, lost on permadeath) ---
func save_run() -> void:
	var data := RunStateData.new()
	data.credits = credits
	data.accumulated_trace = accumulated_trace
	data.selected_subnet_path = selected_subnet_path
	data.selected_city_grid_path = selected_city_grid_path
	data.selected_security_tier = selected_security_tier
	data.last_death_cause = last_death_cause
	data.last_run_summary = last_run_summary.duplicate()
	if selected_deck != null and selected_deck.resource_path != "":
		data.selected_deck_path = selected_deck.resource_path
	for deck: Cyberdeck in owned_decks:
		if deck == null:
			continue
		var entry: Dictionary = {
			"path": deck.resource_path if deck.resource_path != "" else "",
			"installed_program_paths": []
		}
		for prog: NetProgram in deck.installed_programs:
			if prog == null:
				continue
			entry["installed_program_paths"].append(prog.resource_path if prog.resource_path != "" else "")
		data.owned_deck_entries.append(entry)
	for prog: NetProgram in owned_programs:
		if prog != null and prog.resource_path != "":
			data.owned_program_paths.append(prog.resource_path)
	for prog: NetProgram in loot:
		if prog != null and prog.resource_path != "":
			data.loot_paths.append(prog.resource_path)
	for file: NetFile in carried_files:
		if file == null:
			continue
		data.carried_file_entries.append({
			"file_name": file.file_name,
			"description": file.description,
			"credit_value": file.credit_value,
			"mu_size": file.mu_size,
		})
	var err: int = ResourceSaver.save(data, RUN_SAVE_PATH)
	if err != OK:
		push_error("RunState: failed to save run state (error %d)." % err)

func _load_run() -> void:
	if not ResourceLoader.exists(RUN_SAVE_PATH):
		return
	var loaded: Resource = ResourceLoader.load(RUN_SAVE_PATH)
	if not loaded is RunStateData:
		push_warning("RunState: saved run is not RunStateData — starting fresh.")
		return
	var data: RunStateData = loaded as RunStateData
	credits = data.credits
	accumulated_trace = data.accumulated_trace
	selected_subnet_path = data.selected_subnet_path
	selected_city_grid_path = data.selected_city_grid_path
	selected_security_tier = data.selected_security_tier
	last_death_cause = data.last_death_cause
	last_run_summary = data.last_run_summary.duplicate()
	owned_programs.clear()
	for path: String in data.owned_program_paths:
		var prog: NetProgram = load(path) as NetProgram
		if prog != null:
			owned_programs.append(prog.duplicate())
	owned_decks.clear()
	for entry: Variant in data.owned_deck_entries:
		if entry is not Dictionary:
			continue
		var deck_path: String = entry.get("path", "")
		if deck_path == "":
			continue
		var deck_src: Cyberdeck = load(deck_path) as Cyberdeck
		if deck_src == null:
			continue
		var deck: Cyberdeck = deck_src.duplicate()
		deck.installed_programs.clear()
		var installed_paths: Array = entry.get("installed_program_paths", [])
		for prog_path: Variant in installed_paths:
			var prog_src: NetProgram = load(prog_path) as NetProgram
			if prog_src != null:
				deck.installed_programs.append(prog_src.duplicate())
		owned_decks.append(deck)
	selected_deck = null
	if data.selected_deck_path != "":
		for deck: Cyberdeck in owned_decks:
			if deck.resource_path == data.selected_deck_path:
				selected_deck = deck
				break
	loot.clear()
	for path: String in data.loot_paths:
		var prog: NetProgram = load(path) as NetProgram
		if prog != null:
			loot.append(prog.duplicate())
	carried_files.clear()
	for entry: Variant in data.carried_file_entries:
		if entry is not Dictionary:
			continue
		var file: NetFile = NetFile.new()
		file.file_name = entry.get("file_name", "Untitled File")
		file.description = entry.get("description", "")
		file.credit_value = entry.get("credit_value", 0)
		file.mu_size = entry.get("mu_size", 1)
		carried_files.append(file)

func clear_run_save() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.remove(RUN_SAVE_PATH.get_file())
