class_name Cyberdeck
extends Resource

@export var deck_name: String = "Kendachi Cyberdeck"
@export var max_mu: int = 20
@export var speed_bonus: int = 2
@export var data_wall_strength: int = 6 # Added Data Wall Strength property
@export var interface_rank: int = 6 # Netrunner's interface skill when using this deck
@export var price: int = 0 # Cost in Eurodollars (hub shop)
@export var installed_programs: Array[NetProgram] = []
# Number of generic hardware upgrade slots this deck has. Variable by deck
# model (starter=2, mid=3, high-end=4). Slots accept any DeckModule type.
@export var upgrade_slots: int = 3
# Hardware modules currently installed in the deck's upgrade slots. One module
# per slot; order maps to slot index. Per-life (lost on death with the deck).
@export var installed_modules: Array[DeckModule] = []
# Path to the original .tres this deck was duplicated from. Used by run-state
# persistence to reconstruct owned decks after app restart.
@export var source_path: String = ""

func get_used_mu() -> int:
	var total = 0
	for prog in installed_programs:
		if prog:
			total += prog.memory_cost
	return total

# --- Effective-stat accessors (base + installed-module bonuses) ---
# All gameplay + UI stat reads MUST go through these, never the raw fields, so
# installed hardware modules actually take effect. Each sums the deck's base
# value plus the bonus_value of every installed DeckModule of the matching
# effect type.

func effective_max_mu() -> int:
	var total := max_mu
	for mod in installed_modules:
		if mod != null and mod.effect_type == DeckModule.ModuleEffect.MU:
			total += mod.bonus_value
	return total

func effective_speed_bonus() -> int:
	var total := speed_bonus
	for mod in installed_modules:
		if mod != null and mod.effect_type == DeckModule.ModuleEffect.SPEED:
			total += mod.bonus_value
	return total

func effective_data_wall_strength() -> int:
	var total := data_wall_strength
	for mod in installed_modules:
		if mod != null and mod.effect_type == DeckModule.ModuleEffect.DATA_WALL:
			total += mod.bonus_value
	return total

func effective_interface_rank() -> int:
	var total := interface_rank
	for mod in installed_modules:
		if mod != null and mod.effect_type == DeckModule.ModuleEffect.INTERFACE:
			total += mod.bonus_value
	return total

# Total trace-dampening bonus from installed Trace Dampener modules. Added to
# the Watchdog trace-check target (accumulated_trace + this) in
# WatchdogProgram.take_ice_turn, making the runner harder to pinpoint. LDL
# hops add the full trace_value (this no longer reduces LDL trace gain).
func effective_trace_reduction() -> int:
	var total := 0
	for mod in installed_modules:
		if mod != null and mod.effect_type == DeckModule.ModuleEffect.TRACE_REDUCTION:
			total += mod.bonus_value
	return total

# How many upgrade slots are still open.
func free_upgrade_slots() -> int:
	# installed_modules may contain trailing nulls after an uninstall; count
	# non-null entries as occupied.
	var occupied := 0
	for mod in installed_modules:
		if mod != null:
			occupied += 1
	return max(0, upgrade_slots - occupied)

# True if a module can be installed (a free slot exists).
func can_install_module() -> bool:
	return free_upgrade_slots() > 0

# Install a module into the next free slot. Returns true on success.
func install_module(mod: DeckModule) -> bool:
	if mod == null:
		return false
	if not can_install_module():
		return false
	installed_modules.append(mod)
	return true

# Remove a module from the deck (returns it, or null if not installed).
func uninstall_module(mod: DeckModule) -> DeckModule:
	var idx := installed_modules.find(mod)
	if idx < 0:
		return null
	var removed := installed_modules[idx]
	installed_modules.remove_at(idx)
	return removed

func get_used_mu_with_modules() -> int:
	return get_used_mu()
