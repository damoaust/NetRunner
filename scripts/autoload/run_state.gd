extends Node

# Autoload singleton holding cross-scene PER-LIFE state. All of this is lost
# on permadeath. Set at the workbench, read by the gameplay session.

# --- Starting gear constants (mirror MetaState's starting catalogue) ---
const STARTING_CREDITS: int = 1000
const STARTING_DECK_PATH: String = "res://data/starting_deck.tres"
const STARTING_PROGRAM_PATHS: Array[String] = [
	"res://data/codecracker.tres",
	"res://data/shield.tres",
]

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