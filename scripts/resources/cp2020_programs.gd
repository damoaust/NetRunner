class_name NetProgram
extends Resource

enum ProgramType {
	INTRUSION,       # Breaches Datawalls (e.g., Hammer, Jackhammer)[cite: 16]
	DECRYPTION,      # Cracks Code Gates[cite: 16]
	DETECTION,       # Reveals hidden nodes / ICE[cite: 16]
	ANTI_PROGRAM,    # Destroys active ICE (e.g., Killer)[cite: 16]
	ANTI_PERSONNEL,  # Attacks runner directly (e.g., Hellhound, Flatline)[cite: 16]
	ANTI_SYSTEM,     # Crashes CPUs / erases memory[cite: 16]
	UTILITY,         # Cloak, Stealth, Speed boosters[cite: 16]
	ICE              # Stationary defense programs running on nodes[cite: 16]
}

enum EffectType { 
	BYPASS_GATE,     # Cracks node security DV[cite: 16]
	BREACH_WALL,     # Hammers down datawalls
	DEREZ_ICE,       # Destroys target ICE program[cite: 16]
	DAMAGE_RUNNER,   # Black ICE attack on runner health[cite: 16]
	REVEAL_NODES,    # Maps connected graph nodes[cite: 16]
	MODIFY_MU,       # Modifies deck memory or speed[cite: 16]
	SHIELD,          # Protection program: recharges netrunner shield/armor (reduces ICE damage)
	CRASH_CPU,       # Anti-system: crashes a datafort CPU for 1D6+1 turns (Krash)[cite: 16]
	ARMOR,           # Defense program: absorbs damage point-for-point (Armor STR subtracts from incoming rolled damage; remainder hits HP).
	WORM             # Stealth opener: slips behind data walls/code gates, opens from the inside over 2 turns. No alert.
}

@export var program_name: String = "Hammer"
@export var type: ProgramType = ProgramType.INTRUSION
@export var effect_type: EffectType = EffectType.BREACH_WALL
@export var memory_cost: int = 2 # MU required to equip
@export var strength: int = 4   # Added to attack/defense rolls[cite: 16]
@export var price: int = 600    # Cost in Eurodollars
@export var icon: Texture2D     # UI Icon[cite: 16]
@export var description: String = "" # One-line summary shown in the workbench detail card
# Per-hit damage dice for attack programs (Black ICE). 0 = use flat `strength`
# as damage (existing behaviour for all current programs). >0 = roll
# 1D{damage_dice} per hit instead. e.g. Sword sets 6 to roll 1D6 per hit.
@export var damage_dice: int = 0
