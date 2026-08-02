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
	MODIFY_MU        # Modifies deck memory or speed[cite: 16]
}

@export var program_name: String = "Hammer"
@export var type: ProgramType = ProgramType.INTRUSION
@export var effect_type: EffectType = EffectType.BREACH_WALL
@export var memory_cost: int = 2 # MU required to equip
@export var strength: int = 4   # Added to attack/defense rolls[cite: 16]
@export var price: int = 600    # Cost in Eurodollars
@export var icon: Texture2D     # UI Icon[cite: 16]
