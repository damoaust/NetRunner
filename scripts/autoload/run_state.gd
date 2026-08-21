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
# Cumulative net time (seconds) spent jacked in this run, scaled by grid level
# (world map action = 60 s, city grid = 1 s, datafort = 1 ns). Advanced by the
# turn manager's `action_consumed` signal in each scene. Reset per run like
# accumulated_trace; persisted across app restarts via RunStateData.
var net_time_seconds: float = 0.0
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

# --- Missions system (per-life) ---
# The currently accepted contract (at most one). null = no active mission.
# Held as a duplicated template so runtime never mutates the library .tres.
var active_mission: CP2020Mission = null
# The rotating board of available contracts shown on the workbench Missions
# tab. A subset of the static library (res://data/missions/*.tres). Refreshed
# over time by check_mission_refresh() against net_time_seconds.
var available_missions: Array[CP2020Mission] = []
# True once the active mission's objective has been satisfied this run. Set by
# the game session when a target file is copied (DATA_HARVEST), an offensive
# action hits the exact target coord (SABOTAGE), or the runner steps onto the
# target coord (RECON). Re-verified at hand-in.
var mission_objective_met: bool = false
# net_time_seconds snapshot at the last board refresh. The workbench rotates
# one new mission onto the board when net_time_seconds - last_mission_refresh_time
# >= MISSION_REFRESH_SECONDS. Resets on new life alongside the clock.
var last_mission_refresh_time: float = 0.0

# One new mission is rotated onto the board every hour of net-time. The board
# only ticks while the runner is jacked in (net_time_seconds advances on
# action_consumed); it does not advance at the hub.
const MISSION_REFRESH_SECONDS: float = 3600.0
# How many contracts the board holds at once. Seeded from the static library
# on new life; refresh swaps the oldest for a fresh one.
const MISSION_BOARD_SIZE: int = 4

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
	net_time_seconds = 0.0
	selected_city_grid_path = ""
	selected_security_tier = 0
	loot.clear()
	owned_decks.clear()
	owned_programs.clear()
	owned_modules.clear()
	carried_files.clear()
	active_mission = null
	available_missions.clear()
	mission_objective_met = false
	last_mission_refresh_time = 0.0
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
		char_path = "res://data/characters/character_shadow.tres"
	var character: NetrunnerCharacter = load(char_path) as NetrunnerCharacter
	if character:
		selected_character = character
	else:
		push_error("RunState: failed to load starting character '%s'." % char_path)

	# Seed the mission board with a random subset of the static library so a
	# fresh life has contracts available immediately. The board rotates over
	# time via check_mission_refresh() once the runner starts jacking in.
	_seed_mission_board()

	# Persist the fresh state immediately so a crash/quit before the workbench
	# saves doesn't leave a stale (or missing) save file. GameOver clears the
	# old save BEFORE calling this, so the fresh state becomes the saved state.
	save_run()

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
	data.net_time_seconds = net_time_seconds
	data.selected_subnet_path = selected_subnet_path
	data.selected_city_grid_path = selected_city_grid_path
	data.selected_security_tier = selected_security_tier
	data.last_death_cause = last_death_cause
	data.last_run_summary = last_run_summary.duplicate(true)
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
	# Missions: store the available board + active mission by resource path so
	# they survive app restarts within a life. The templates are reloaded and
	# duplicated on load (never mutating the library .tres).
	for mission: CP2020Mission in available_missions:
		if mission == null:
			continue
		var m_path: String = mission.resource_path if mission.resource_path != "" else mission.source_path
		if m_path != "":
			data.available_mission_paths.append(m_path)
	if active_mission != null:
		var am_path: String = active_mission.resource_path if active_mission.resource_path != "" else active_mission.source_path
		data.active_mission_path = am_path
	data.mission_objective_met = mission_objective_met
	data.last_mission_refresh_time = last_mission_refresh_time
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
	net_time_seconds = data.net_time_seconds
	selected_subnet_path = data.selected_subnet_path
	selected_city_grid_path = data.selected_city_grid_path
	selected_security_tier = data.selected_security_tier
	last_death_cause = data.last_death_cause
	last_run_summary = data.last_run_summary.duplicate(true)
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
	# Migrate stale paths: character .tres moved from res://data/ to
	# res://data/characters/. Older run saves still store the old location.
	var saved_char_path := data.selected_character_path
	if saved_char_path.begins_with("res://data/character_"):
		saved_char_path = "res://data/characters/%s" % saved_char_path.get_file()
	if saved_char_path != "":
		var ch: NetrunnerCharacter = load(saved_char_path) as NetrunnerCharacter
		if ch != null:
			selected_character = ch
		else:
			# Stale or missing saved path — fall back to the default roster
			# entry so a run never starts without a character.
			var fallback: NetrunnerCharacter = load(MetaState.STARTING_CHARACTER) as NetrunnerCharacter
			if fallback != null:
				selected_character = fallback
				push_warning("RunState: saved character '%s' could not be loaded — using default." % saved_char_path)
			else:
				push_warning("RunState: saved character '%s' could not be loaded." % saved_char_path)
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
	# Missions: rebuild the available board + active mission from saved paths.
	# If the save predates the missions system (empty arrays) or a library
	# path no longer exists, we silently skip and re-seed at the workbench.
	available_missions.clear()
	for m_path: String in data.available_mission_paths:
		var mission: CP2020Mission = _load_mission_template(m_path)
		if mission != null:
			available_missions.append(mission)
	active_mission = null
	if data.active_mission_path != "":
		active_mission = _load_mission_template(data.active_mission_path)
	mission_objective_met = data.mission_objective_met
	last_mission_refresh_time = data.last_mission_refresh_time
	# Older saves (pre-missions) load with an empty board and no active
	# mission — seed a fresh board so the Missions tab isn't blank on upgrade.
	# Only seed when truly empty so an in-progress board is preserved.
	if available_missions.is_empty() and active_mission == null:
		_seed_mission_board()

# ---------------------------------------------------------------------------
# Missions system
# ---------------------------------------------------------------------------
# Scans res://data/missions/ for the static mission library and returns the
# sorted list of .tres paths. The library is authored content (no procedural
# generation for now); drop a new mission_*.tres in the folder to extend it.
func _mission_library_paths() -> Array[String]:
	var dir: DirAccess = DirAccess.open("res://data/missions")
	if dir == null:
		push_warning("RunState: could not open res://data/missions — mission board empty.")
		return []
	var paths: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			paths.append("res://data/missions/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths

# Loads a mission template from a library path and returns a duplicate so the
# runtime never mutates the cached .tres. Tags source_path for save/load.
# Returns null if the path is missing or not a CP2020Mission.
func _load_mission_template(path: String) -> CP2020Mission:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is CP2020Mission:
		var dup := (res as CP2020Mission).duplicate()
		dup.source_path = path
		return dup
	return null

# Seeds the available board with a random subset of the static library. Called
# on new life. If the library is smaller than MISSION_BOARD_SIZE, takes all.
func _seed_mission_board() -> void:
	available_missions.clear()
	var lib := _mission_library_paths()
	if lib.is_empty():
		return
	# Shuffle a copy of the path list and take the first N for the board.
	var pool: Array[String] = lib.duplicate()
	pool.shuffle()
	var count := mini(MISSION_BOARD_SIZE, pool.size())
	for i in range(count):
		var m: CP2020Mission = _load_mission_template(pool[i])
		if m != null:
			available_missions.append(m)
	last_mission_refresh_time = net_time_seconds

# Rotates the mission board if at least MISSION_REFRESH_SECONDS of net-time has
# elapsed since the last refresh: drops the oldest entry and appends a fresh
# mission from the library that isn't already on the board. Called by the
# workbench on entry. Returns true if a rotation happened.
func check_mission_refresh() -> bool:
	if net_time_seconds - last_mission_refresh_time < MISSION_REFRESH_SECONDS:
		return false
	# Only rotate if there's something to rotate in.
	var lib := _mission_library_paths()
	if lib.is_empty():
		return false
	# Build the set of paths currently on the board (and the active mission) so
	# we don't add a duplicate.
	var present := {}
	for m in available_missions:
		if m != null and m.resource_path != "":
			present[m.resource_path] = true
	if active_mission != null and active_mission.resource_path != "":
		present[active_mission.resource_path] = true
	var candidates: Array[String] = []
	for path in lib:
		if not present.has(path):
			candidates.append(path)
	if candidates.is_empty():
		# Library exhausted (everything already on the board / active) — reset
		# the timer so we don't re-check every frame, but change nothing.
		last_mission_refresh_time = net_time_seconds
		return false
	candidates.shuffle()
	var fresh: CP2020Mission = _load_mission_template(candidates[0])
	if fresh == null:
		last_mission_refresh_time = net_time_seconds
		return false
	# Drop the oldest (front) entry and append the fresh one at the back so the
	# board reads newest-last / oldest-first.
	if not available_missions.is_empty():
		available_missions.pop_front()
	available_missions.append(fresh)
	last_mission_refresh_time = net_time_seconds
	save_run()
	return true

# Accepts a mission from the available board. At most one active mission at a
# time. Removes it from the available list. Returns true on success.
func accept_mission(mission: CP2020Mission) -> bool:
	if mission == null or active_mission != null:
		return false
	var idx: int = available_missions.find(mission)
	if idx < 0:
		return false
	available_missions.remove_at(idx)
	active_mission = mission
	mission_objective_met = false
	save_run()
	return true

# Abandons the active mission (returns it to the board). No penalty. Returns
# true if there was an active mission to abandon.
func abandon_mission() -> bool:
	if active_mission == null:
		return false
	# Only return to the board if its objective wasn't already met (a met
	# mission should be handed in, not recycled). Either way clear it.
	if not mission_objective_met:
		available_missions.append(active_mission)
	active_mission = null
	mission_objective_met = false
	save_run()
	return true

# Returns true if the active mission's objective proof is currently in hand and
# the mission can be handed in for its reward.
func can_hand_in_mission() -> bool:
	if active_mission == null:
		return false
	match active_mission.mission_type:
		CP2020Mission.MissionType.DATA_HARVEST:
			# Proof: the target file must currently be carried. (The runner
			# could have fenced it after copying — in that case they must go
			# fetch another copy before hand-in.)
			return _carries_target_file()
		CP2020Mission.MissionType.SABOTAGE, CP2020Mission.MissionType.RECON:
			# Proof: the objective flag was set this run (coordinate hit /
			# reached). The flag is reset on new life, so it is a valid proof
			# that the runner did the job this life.
			return mission_objective_met
	return false

# Returns true if a file matching the active mission's target_file_name is
# currently in carried_files.
func _carries_target_file() -> bool:
	if active_mission == null or active_mission.target_file_name == "":
		return false
	for f: NetFile in carried_files:
		if f != null and f.file_name == active_mission.target_file_name:
			return true
	return false

# Hands in the active mission: pays the flat reward into credits, clears the
# active mission (and, for DATA_HARVEST, removes the proof file from carried
# files — the file is "delivered" to the fixer). Returns the reward paid, or 0
# on failure.
func hand_in_mission() -> int:
	if not can_hand_in_mission():
		return 0
	var reward: int = active_mission.reward_credits
	credits += reward
	# DATA_HARVEST: remove one copy of the target file from carried_files (it
	# is handed over to the fixer, not fenced separately).
	if active_mission.mission_type == CP2020Mission.MissionType.DATA_HARVEST:
		var target_name: String = active_mission.target_file_name
		for i in range(carried_files.size()):
			if carried_files[i] != null and carried_files[i].file_name == target_name:
				carried_files.remove_at(i)
				break
	active_mission = null
	mission_objective_met = false
	save_run()
	return reward

# --- Objective notification hooks (called by the game session) ---
# Called after a file is copied to the deck. Sets mission_objective_met if the
# active mission is DATA_HARVEST and the copied file matches the target name.
func notify_file_copied(file: NetFile) -> void:
	if active_mission == null or file == null:
		return
	if active_mission.mission_type == CP2020Mission.MissionType.DATA_HARVEST \
			and file.file_name == active_mission.target_file_name:
		mission_objective_met = true

# Called when an offensive/interact action targets a grid coord in the current
# subnet. Sets mission_objective_met if the active mission is SABOTAGE, the
# current subnet is the target subnet, and the coord matches the target.
func notify_action_at_coord(current_subnet_path: String, coord: Vector2i) -> void:
	if active_mission == null:
		return
	if active_mission.mission_type != CP2020Mission.MissionType.SABOTAGE:
		return
	if current_subnet_path != active_mission.target_subnet_path:
		return
	if coord == active_mission.target_coord:
		mission_objective_met = true

# Called when the netrunner moves. Sets mission_objective_met if the active
# mission is RECON, the current subnet is the target, and the runner is on the
# target coord.
func notify_position(current_subnet_path: String, coord: Vector2i) -> void:
	if active_mission == null:
		return
	if active_mission.mission_type != CP2020Mission.MissionType.RECON:
		return
	if current_subnet_path != active_mission.target_subnet_path:
		return
	if coord == active_mission.target_coord:
		mission_objective_met = true

func clear_run_save() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.remove(RUN_SAVE_PATH.get_file())
