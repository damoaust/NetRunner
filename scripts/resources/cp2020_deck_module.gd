class_name DeckModule
extends Resource

# DeckModule: a piece of cyberdeck hardware the runner buys at the hub shop or
# loots from dataforts, then installs into a deck's generic upgrade slots at
# the workbench. Modules are swappable (free to install/uninstall) and per-life
# (lost on death with the deck). A deck has N generic slots (variable by deck
# model — see Cyberdeck.upgrade_slots) that accept any module type.
#
# This is the CP2020 "deck construction" layer: instead of buying a whole new
# deck to raise one stat, the runner slots hardware modules that each boost a
# single stat. Five effect types are supported at launch (see ModuleEffect).
#
# NOT a NetProgram subclass — modules are hardware, not software. They do not
# occupy deck MU and are never rezzed/fired. They are pure passive stat
# bonuses read via Cyberdeck.effective_*() accessors at gameplay start and in
# the workbench UI.

enum ModuleEffect {
	MU,             # +N to effective max MU (feeds netrunner.max_memory_units)
	SPEED,          # +N to effective speed bonus (feeds initiative)
	DATA_WALL,      # +N to effective Data Wall STR (display-only for now)
	INTERFACE,      # +N to effective Interface Rank (feeds netrunner.interface_rank)
	TRACE_REDUCTION, # Reduces accumulated trace gained on LDL travel by N (min 0 per jump)
}

@export var module_name: String = "MU Expansion"
@export var effect_type: ModuleEffect = ModuleEffect.MU
@export var bonus_value: int = 2
@export var price: int = 500
@export var description: String = ""
@export var glyph: String = "▣"
@export var color: Color = Color(0.4, 0.9, 0.6, 1.0)
# Path to the original .tres this module was duplicated from. Used by run-state
# persistence to reconstruct owned modules after app restart (same pattern as
# NetProgram.source_path).
@export var source_path: String = ""

# Human-readable short tag for the effect type (used in the workbench/shop).
static func effect_tag(effect: ModuleEffect) -> String:
	match effect:
		ModuleEffect.MU:
			return "MU"
		ModuleEffect.SPEED:
			return "SPD"
		ModuleEffect.DATA_WALL:
			return "WALL"
		ModuleEffect.INTERFACE:
			return "INT"
		ModuleEffect.TRACE_REDUCTION:
			return "TRACE"
	return "???"

# Full label for detail cards.
static func effect_label(effect: ModuleEffect) -> String:
	match effect:
		ModuleEffect.MU:
			return "MU Expansion"
		ModuleEffect.SPEED:
			return "Speed Booster"
		ModuleEffect.DATA_WALL:
			return "Data Wall Hardening"
		ModuleEffect.INTERFACE:
			return "Interface Coprocessor"
		ModuleEffect.TRACE_REDUCTION:
			return "Trace Dampener"
	return "Unknown"

# Sign string for display ("+N" for boosts, "-N" for trace reduction).
func bonus_sign() -> String:
	if effect_type == ModuleEffect.TRACE_REDUCTION:
		return "-%d" % bonus_value
	return "+%d" % bonus_value