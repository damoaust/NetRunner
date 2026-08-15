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
# The netrunner character equipped for this life (selected at the workbench).
# Read by the game session at jack-in to apply REF/INT/BODY/HP/sight to the
# netrunner node. Per-life like selected_deck; defaults from the MetaState
# preferred character on a new life. The resource is read-only at runtime so
# we store/restore it by path (no duplication needed).
var selected_character: NetrunnerCharacter = null
var selected_subnet_path: String = ""
var credits: int = STARTING_CREDITS
# Total Trace Value of all LDLs passed through in the current Net run. Drives
# tracing-program rolls during the datafort session; reset per run.
var accumulated_trace: int = 0
# Meatspace security-dispatch countdown (turns until a raid arrives while the
# runner is jacked in). Set when a Watchdog's trace check succeeds; ticks down
# each netrunner turn during datafort gameplay. Preserved across in-datafort
# LDL travel + the datafort->City Grid return (mid-run); cleared on run-end,
# flatline, and successful jack-out (escaping the raid). 0 = no active raid.
var security_dispatch_turns: int = 0
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
# Deck modules the runner owns this life (purchased or looted) but has not
# installed into a deck. Installed modules live on the deck's
# `installed_modules` and are saved per-deck. Lost on death.
var owned_modules: Array[DeckModule] = []
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
	selected_character = null
	selected_subnet_path = ""
	credits = STARTING_CREDITS
	accumulated_trace = 0
	security_dispatch_turns = 0
	selected_city_grid_path = ""
	selected_security_tier = 0
	loot.clear()
	owned_decks.clear()
	owned_programs.clear()
	owned_modules.clear()
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
		var deck_src_path := deck.resource_path
		deck = deck.duplicate()
		deck.source_path = deck_src_path
		owned_decks.append(deck)
		selected_deck = deck
	else:
		push_error("RunState: failed to load starting deck '%s'." % STARTING_DECK_PATH)
	# Starting programs — duplicate and tag with source path so they survive
	# save/load cycles without mutating the cached .tres files.
	for path: String in STARTING_PROGRAM_PATHS:
		var prog: NetProgram = load(path) as NetProgram
		if prog:
			var prog_dup := prog.duplicate()
			prog_dup.source_path = path
			owned_programs.append(prog_dup)
		else:
			push_error("RunState: failed to load starting program '%s'." % path)
	# Default character — the player's last-chosen runner (persisted in
	# MetaState across deaths), falling back to the first roster entry so a
	# fresh life always has a runner equipped. Can be swapped at the workbench.
	var char_path := MetaState.data.selected_character_path if MetaState.data != null else ""
	if char_path == "":
		char_path = "res://data/character_shadow.tres"
	var character: NetrunnerCharacter = load(char_path) as NetrunnerCharacter
	if character:
		selected_character = character
	else:
		push_error("RunState: failed to load starting character '%s'." % char_path)

# --- Loot helpers (used by the loot interaction) ---
# Appends a duplicate of prog to loot (duplicate to avoid mutating cached
# .tres). Also discovers the program in the persistent MetaState catalogue.
func add_loot(prog: NetProgram) -> void:
	if prog == null:
		return
	var source_path := prog.resource_path if prog.resource_path != "" else ""
	var dup := prog.duplicate()
	dup.source_path = source_path
	loot.append(dup)
	if source_path != "":
		MetaState.unlock_program(source_path)

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

# Sells all carried files at once, returns total proceeds.
func sell_all_files() -> int:
	if carried_files.is_empty():
		return 0
	var total: int = 0
	for f in carried_files:
		if f != null:
			total += f.credit_value
	credits += total
	carried_files.clear()
	return total

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
	var deck_dup := deck.duplicate()
	deck_dup.source_path = deck.resource_path
	owned_decks.append(deck_dup)
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
	var prog_dup := prog.duplicate()
	prog_dup.source_path = prog.resource_path
	owned_programs.append(prog_dup)
	return true

# Equips a deck the runner already owns.
func equip_deck(deck: Cyberdeck) -> void:
	selected_deck = deck

# --- Deck-module helpers (used by the hub shop + workbench) ---
# Purchases a module: subtracts price from credits, appends a duplicate to
# owned_modules, returns true. Returns false if mod is null or insufficient
# credits.
func buy_module(mod: DeckModule) -> bool:
	if mod == null:
		return false
	if credits < mod.price:
		return false
	credits -= mod.price
	var mod_dup := mod.duplicate()
	mod_dup.source_path = mod.resource_path
	owned_modules.append(mod_dup)
	return true

# Loot helper: appends a duplicate of mod to owned_modules (duplicate to avoid
# mutating cached .tres). Also discovers the module in the persistent
# MetaState catalogue.
func add_module_loot(mod: DeckModule) -> void:
	if mod == null:
		return
	var source_path := mod.resource_path if mod.resource_path != "" else ""
	var dup := mod.duplicate()
	dup.source_path = source_path
	owned_modules.append(dup)
	if source_path != "":
		MetaState.unlock_module(source_path)

# Installs an owned module into a deck's upgrade slot. Removes the module from
# owned_modules (by instance match) and delegates to the deck. Returns false
# if mod/deck is null or the deck has no free slot.
func install_module_to_deck(mod: DeckModule, deck: Cyberdeck) -> bool:
	if mod == null or deck == null:
		return false
	if not deck.can_install_module():
		return false
	var idx: int = owned_modules.find(mod)
	if idx >= 0:
		owned_modules.remove_at(idx)
	deck.install_module(mod)
	return true

# Uninstalls a module from a deck and returns it to owned_modules. Returns
# false if mod/deck is null or the module was not installed on the deck.
func uninstall_module_from_deck(mod: DeckModule, deck: Cyberdeck) -> bool:
	if mod == null or deck == null:
		return false
	var removed: DeckModule = deck.uninstall_module(mod)
	if removed == null:
		return false
	owned_modules.append(removed)
	return true

# --- Run-state persistence (survives app restarts, lost on permadeath) ---
func save_run() -> void:
	var data := RunStateData.new()
	data.credits = credits
	data.accumulated_trace = accumulated_trace
	data.security_dispatch_turns = security_dispatch_turns
	data.selected_subnet_path = selected_subnet_path
	data.selected_city_grid_path = selected_city_grid_path
	data.selected_security_tier = selected_security_tier
	data.last_death_cause = last_death_cause
	data.last_run_summary = last_run_summary.duplicate()
	if selected_deck != null:
		data.selected_deck_path = selected_deck.resource_path if selected_deck.resource_path != "" else selected_deck.source_path
	if selected_character != null and selected_character.resource_path != "":
		data.selected_character_path = selected_character.resource_path
	for deck: Cyberdeck in owned_decks:
		if deck == null:
			continue
		var deck_path: String = deck.resource_path if deck.resource_path != "" else deck.source_path
		var entry: Dictionary = {
			"path": deck_path,
			"installed_program_paths": [],
			"installed_module_paths": []
		}
		for prog: NetProgram in deck.installed_programs:
			if prog == null:
				continue
			entry["installed_program_paths"].append(prog.resource_path if prog.resource_path != "" else prog.source_path)
		for mod: DeckModule in deck.installed_modules:
			if mod == null:
				continue
			entry["installed_module_paths"].append(mod.resource_path if mod.resource_path != "" else mod.source_path)
		data.owned_deck_entries.append(entry)
	for prog: NetProgram in owned_programs:
		if prog == null:
			continue
		var prog_path: String = prog.resource_path if prog.resource_path != "" else prog.source_path
		if prog_path != "":
			data.owned_program_paths.append(prog_path)
	for mod: DeckModule in owned_modules:
		if mod == null:
			continue
		var mod_path: String = mod.resource_path if mod.resource_path != "" else mod.source_path
		if mod_path != "":
			data.owned_module_paths.append(mod_path)
	for prog: NetProgram in loot:
		if prog == null:
			continue
		var loot_path: String = prog.resource_path if prog.resource_path != "" else prog.source_path
		if loot_path != "":
			data.loot_paths.append(loot_path)
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
	security_dispatch_turns = data.security_dispatch_turns
	selected_subnet_path = data.selected_subnet_path
	selected_city_grid_path = data.selected_city_grid_path
	selected_security_tier = data.selected_security_tier
	last_death_cause = data.last_death_cause
	last_run_summary = data.last_run_summary.duplicate()
	owned_programs.clear()
	for path: String in data.owned_program_paths:
		var prog: NetProgram = load(path) as NetProgram
		if prog != null:
			var prog_dup := prog.duplicate()
			prog_dup.source_path = path
			owned_programs.append(prog_dup)
	owned_modules.clear()
	for path: String in data.owned_module_paths:
		var mod: DeckModule = load(path) as DeckModule
		if mod != null:
			var mod_dup := mod.duplicate()
			mod_dup.source_path = path
			owned_modules.append(mod_dup)
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
		deck.source_path = deck_path
		deck.installed_programs.clear()
		var installed_paths: Array = entry.get("installed_program_paths", [])
		for prog_path: Variant in installed_paths:
			var prog_src: NetProgram = load(prog_path) as NetProgram
			if prog_src != null:
				var prog_dup := prog_src.duplicate()
				prog_dup.source_path = prog_path
				deck.installed_programs.append(prog_dup)
		var installed_module_paths: Array = entry.get("installed_module_paths", [])
		for mod_path: Variant in installed_module_paths:
			var mod_src: DeckModule = load(mod_path) as DeckModule
			if mod_src != null:
				var mod_dup := mod_src.duplicate()
				mod_dup.source_path = mod_path
				deck.installed_modules.append(mod_dup)
		owned_decks.append(deck)
	selected_deck = null
	if data.selected_deck_path != "":
		for deck: Cyberdeck in owned_decks:
			if deck.source_path == data.selected_deck_path:
				selected_deck = deck
				break
	# Restore the equipped character by path (read-only resource, no duplicate).
	selected_character = null
	if data.selected_character_path != "":
		var ch: NetrunnerCharacter = load(data.selected_character_path) as NetrunnerCharacter
		if ch != null:
			selected_character = ch
		else:
			push_warning("RunState: saved character '%s' could not be loaded." % data.selected_character_path)
	loot.clear()
	for path: String in data.loot_paths:
		var prog: NetProgram = load(path) as NetProgram
		if prog != null:
			var prog_dup := prog.duplicate()
			prog_dup.source_path = path
			loot.append(prog_dup)
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
