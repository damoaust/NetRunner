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
	WORM,            # Stealth opener: slips behind data walls/code gates, opens from the inside over 2 turns. No alert.
	DETECTION        # Detection/alarm: Watchdog detects intruders via LoS and trips an alarm activating all attack ICE. As a netrunner utility, deploys a tripwire beacon that alerts when enemies approach.
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
# `damage_dice_count` (default 1) multiplies the dice: Hellhound sets
# damage_dice=10 + damage_dice_count=2 to roll 2D10 per hit.
@export var damage_dice: int = 0
@export var damage_dice_count: int = 1
# Path to the original .tres this program was duplicated from. Used by run-state
# persistence to reconstruct owned programs after app restart.
@export var source_path: String = ""

# ─────────────────────────────────────────────────────────────────────────────
# Program behavior (virtual). Subclasses override these to define program-
# specific logic; the base provides default hunt-attack ICE behavior and
# effect-dispatch runner behavior. BlackICE and the game session delegate to
# these instead of branching on effect_type.
# ─────────────────────────────────────────────────────────────────────────────

# Default ICE turn behavior (hunt-attack). Runs AFTER line-of-sight gating is
# already done by the BlackICE wrapper — LoS to `target_pos` is assumed this
# turn. Subclasses override to define specialized ICE behavior (e.g. trace-only,
# ranged, or stationary programs). This is a coroutine (it awaits a Node method).
func take_ice_turn(ice: BlackIce, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	# First-activation handling. Tracing-type activation (Hellhound/Flatline
	# must accumulate a trace before attacking) is deferred to program-specific
	# subclasses — no such subclasses exist yet, so all ICE attacks on LoS.
	if not ice._activated:
		ice._activated = true
	# State transition: idle → pursue.
	if ice.current_state == BlackIce.State.IDLE:
		ice.current_state = BlackIce.State.PURSUE
		ice.emit_log("WARNING: %s activated and is hunting!" % program_name)
	if ice.current_state != BlackIce.State.PURSUE:
		return
	ice.refresh_pathfinding(layout)
	# ICE action economy mirrors the netrunner: up to `program.strength`
	# movement steps per turn (CP2020: ICE moves at STR speed), plus one
	# attack action delivered when the ICE reaches the runner's tile (the
	# attack does not consume movement). Stationary ICE (e.g. Watchdog)
	# override take_ice_turn and never move.
	var movement_remaining: int = ice.program.strength
	while movement_remaining > 0:
		var path = ice.astar_grid.get_id_path(ice.current_position, target_pos)
		if path.size() > 1:
			var next_step = path[1]
			if next_step == target_pos:
				match effect_type:
					NetProgram.EffectType.DEREZ_ICE:
						# Anti-program: damage = STR (rolled here, no runner
						# defense roll — routes to attacked_program).
						var derez_dmg := _roll_damage()
						ice.emit_log("CRITICAL: %s executes DEREZ_ICE attack for %d damage!" % [program_name, derez_dmg])
						ice.emit_attack_program(derez_dmg)
					_:
						# Anti-personnel: emit the program's STR for the
						# interface defense roll. The payload damage is
						# rolled inside apply_damage AFTER the defense roll
						# resolves (CP2020 RAW).
						ice.emit_log("CRITICAL: %s attacks Netrunner (STR %d)!" % [program_name, strength])
						ice.emit_attack_netrunner(strength)
				return
			else:
				ice.current_position = next_step
				await ice.move_to_step(next_step)
				movement_remaining -= 1
		else:
			return

# Default netrunner-side program behavior. Dispatches to the game session's
# private execute_* helpers based on `effect_type`. Returns `true` if the
# action was performed (consume an action), `false` if it should NOT consume
# an action (e.g. not implemented / invalid). Subclasses override to define
# custom runner-side logic.
func execute_runner_action(session: CP2020GameSession, target_coord: Vector2i) -> bool:
	match effect_type:
		NetProgram.EffectType.BYPASS_GATE:
			session._execute_decryption(self, target_coord)
			return true
		NetProgram.EffectType.BREACH_WALL:
			session._execute_wall_breach(self, target_coord)
			return true
		NetProgram.EffectType.DEREZ_ICE:
			session._execute_ice_attack(self, target_coord)
			return true
		NetProgram.EffectType.SHIELD:
			session._execute_shield(self)
			return true
		NetProgram.EffectType.WORM:
			session._execute_worm(self, target_coord)
			return true
		NetProgram.EffectType.DETECTION:
			session._execute_detection(self, target_coord)
			return true
		_:
			session.log_to_terminal("Program effect not implemented yet.\n")
			return false

# Roll per-hit damage for this program. Flat `strength` when `damage_dice <= 0`
# (legacy default), otherwise roll `damage_dice_count` × 1D{damage_dice}.
# e.g. Sword (damage_dice=6, count=1) → 1D6; Hellhound (10, 2) → 2D10.
func _roll_damage() -> int:
	if damage_dice <= 0:
		return strength
	var total := 0
	for _i in range(max(1, damage_dice_count)):
		total += randi_range(1, damage_dice)
	return total
