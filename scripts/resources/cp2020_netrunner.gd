class_name CP2020Netrunner
extends Node2D

signal position_changed(new_pos: Vector2i)
signal interacted_with_tile(tile_data: CP2020TileData, pos: Vector2i)
signal deck_updated()
signal message_logged(msg: String)
signal health_changed(current_health: int, max_health: int)
signal shield_raised(program: NetProgram)
signal shield_consumed
signal armor_raised(program: NetProgram)
signal armor_consumed
signal flatlined
# Anti-system (CRASH_CPU / Krash) attack hit the runner's cyberdeck: the deck
# crashes for `duration` turns, dropping the runner's action economy to 0
# (movement only) until it reboots. See crash_deck / tick_deck_crash.
signal deck_crashed(duration: int)
# Anti-personnel (DAMAGE_RUNNER, e.g. Sword/Hellhound) attack struck the
# runner's nervous system: INT permanently reduced. Emitted alongside
# health_changed so the GUI can display the runner's current INT.
signal int_changed(int_current: int, int_max: int)
# Anti-personnel neural shock forced a failed Mortal/Stun save: the runner is
# stunned for `duration` turns (action economy impaired). See
# apply_damage(..., is_anti_personnel := true).
signal stunned(duration: int)

@export var cell_size: int = 40
@export var grid_offset_y: int = 90

@export var deck_name: String = "Kendachi Cyberdeck"
@export var max_memory_units: int = 20
@export var installed_programs: Array[NetProgram] = []

@export var max_health: int = 20

# The netrunner's own vision radius (fog-of-war sight). Owned by the runner so
# future deck/gear modifiers can adjust it independently of program sight
# ranges (programs have their own per-entity `sight_range`). Defaults to 20
# per CP2020 (Line of Sight within 20 spaces, blocked by Data Walls / closed
# Code Gates).
@export var sight_range: int = 20

var current_health: int = 20
var raised_shield: NetProgram = null
var active_armor: NetProgram = null
var interface_rank: int = 6  # Netrunner's INT for initiative (set from cyberdeck)

# Anti-system crash state. While > 0 the runner's cyberdeck is crashed: the
# turn manager forces actions_remaining to 0 (movement still allowed) so the
# runner can flee but cannot run programs. Decremented by tick_deck_crash at
# the start of each netrunner turn.
var deck_crashed_turns: int = 0

# Meat-space Reflexes stat. Per the CP2020 netrunning initiative formula,
# runner initiative = 1D10 + REF + cyberdeck speed. Kept @export so it can be
# tuned on the runner node in the scene; CP2020 netrunners typically have a
# high REF, hence the default of 8.
@export var reflex: int = 8

# Meat-space stats for anti-personnel (DAMAGE_RUNNER) resolution. Per CP2020,
# anti-personnel programs bypass the virtual world and strike the runner's
# nervous system directly: the runner loses INT and must make a Mortal/Stun
# save in meat-space based on cumulative damage.
#   - `intelligence`: the runner's INT stat. Anti-personnel hits reduce the
#     *current* INT (intelligence - intelligence_lost), capped at 0.
#   - `body`: the runner's BODY stat, used as the save bonus on the Mortal/
#     Stun roll (1D10 + BODY vs a target that scales with cumulative damage).
@export var intelligence: int = 8
@export var body: int = 8
# Cumulative INT lost to anti-personnel neural shock. current_int =
# intelligence - intelligence_lost. Kept separate from the base stat so the
# GUI can show both the max and current values (mirrors health model).
var intelligence_lost: int = 0

# Program integrity (HP) model. A program's `strength` is also its max health,
# so anti-program (DEREZ_ICE) ICE can damage and destroy installed programs.
# NetProgram is a shared cached Resource, so we can't mutate `strength` on it
# directly; this Dictionary maps each installed program instance -> its
# current integrity. Seeded on install, erased on uninstall. Destroyed
# programs (integrity reaches 0) are uninstalled, freeing their MU.
var program_integrity: Dictionary = {}

var current_position: Vector2i = Vector2i.ZERO
var current_layout: CP2020DatafortLayout

func get_used_memory() -> int:
	var total_mu = 0
	for prog in installed_programs:
		if prog:
			total_mu += prog.memory_cost
	# Carried data files also consume deck MU alongside installed programs, so
	# the free-MU check (max_memory_units - get_used_memory()) stays accurate
	# when files are copied to the deck during a dive.
	total_mu += RunState.get_carried_files_mu()
	return total_mu

func _ready() -> void:
	current_health = max_health
	message_logged.emit("Netrunner ready. Current memory used: %d / %d MU" % [get_used_memory(), max_memory_units])

func initialize(layout: CP2020DatafortLayout, entry_coord: Vector2i = Vector2i(-1, -1)) -> void:
	current_layout = layout
	if current_layout:
		# Spawn at a specific entry coord if one was supplied and is valid
		# (used by mid-run LDL travel to arrive at a designated tile).
		if entry_coord.x >= 0 and entry_coord.y >= 0 \
				and entry_coord.x < current_layout.columns and entry_coord.y < current_layout.rows \
				and current_layout.get_tile(entry_coord) != null:
			current_position = entry_coord
		else:
			for raw_key in current_layout.grid_tiles.keys():
				# 1. Safely parse the key
				var coord: Vector2i
				if raw_key is String:
					var parts = raw_key.split(",")
					coord = Vector2i(parts[0].to_int(), parts[1].to_int())
				else:
					coord = raw_key

				# 2. Use our safe helper
				var tile = current_layout.get_tile(coord)
				if tile and tile.tile_type == CP2020DatafortLayout.TileType.ENTRY:
					current_position = coord
					break

	update_visual_position()
	queue_redraw()
	position_changed.emit(current_position)
	message_logged.emit("Initialized in datafort at position %s" % current_position)

func update_visual_position() -> void:
	var center_x = (current_position.x * cell_size) + (cell_size / 2.0)
	var center_y = grid_offset_y + (current_position.y * cell_size) + (cell_size / 2.0)
	position = Vector2(center_x, center_y)

func _draw() -> void:
	# Glowing Cyan Netrunner Avatar
	draw_circle(Vector2.ZERO, 10, Color.CYAN)
	draw_arc(Vector2.ZERO, 12, 0, TAU, 16, Color.CYAN, 2.0)
	draw_circle(Vector2.ZERO, 4, Color.WHITE)

func install_program(prog: NetProgram) -> bool:
	if not prog:
		return false
	if get_used_memory() + prog.memory_cost <= max_memory_units:
		installed_programs.append(prog)
		# Seed program HP from its strength (a program's STR is its max health).
		program_integrity[prog] = prog.strength
		message_logged.emit("Installed program: %s (%d MU)" % [prog.program_name, prog.memory_cost])
		deck_updated.emit()
		return true
	else:
		message_logged.emit("Memory full! Cannot install %s" % prog.program_name)
		return false

func uninstall_program(prog: NetProgram) -> void:
	if prog in installed_programs:
		installed_programs.erase(prog)
		program_integrity.erase(prog)
		message_logged.emit("Uninstalled program: %s" % prog.program_name)
		deck_updated.emit()

# Read a program's current integrity for the HUD (returns 0 if not tracked).
func program_integrity_for(prog: NetProgram) -> int:
	if program_integrity.has(prog):
		return int(program_integrity[prog])
	return 0

# Anti-program (DEREZ_ICE) attack. The raised shield does NOT block
# anti-program attacks (shields protect the runner's persona/health, not
# programs), so this bypasses the shield entirely. Picks a random installed
# program with integrity > 0, reduces it by `amount`, and destroys
# (uninstalls) it at 0 integrity. Logs a "no programs to target" message and
# does nothing if the runner has no installed programs (no fallback to health
# damage).
func damage_program(amount: int, attacker_name: String) -> void:
	var candidates: Array[NetProgram] = []
	for prog in installed_programs:
		if prog and program_integrity.get(prog, 0) > 0:
			candidates.append(prog)
	if candidates.is_empty():
		message_logged.emit("%s's DEREZ_ICE finds no programs to target." % attacker_name)
		return
	var target: NetProgram = candidates[randi_range(0, candidates.size() - 1)]
	var cur: int = int(program_integrity[target])
	var new_int: int = max(0, cur - amount)
	program_integrity[target] = new_int
	message_logged.emit("%s's DEREZ_ICE hits %s for %d (Integrity %d/%d)." % [attacker_name, target.program_name, amount, new_int, target.strength])
	if new_int <= 0:
		message_logged.emit("%s DEREZED! Program destroyed." % target.program_name)
		uninstall_program(target)

func move(direction: Vector2i) -> bool:
	if not current_layout:
		message_logged.emit("Error: No datafort layout loaded for movement!")
		return false
		
	var target_pos = current_position + direction
	
	if target_pos.x < 0 or target_pos.x >= current_layout.columns or target_pos.y < 0 or target_pos.y >= current_layout.rows:
		message_logged.emit("Movement blocked: Out of datafort bounds.")
		return false
		
	# Safely get the tile
	var tile_data = current_layout.get_tile(target_pos)
	
	if tile_data:
		if tile_data.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
			message_logged.emit("Movement blocked: Datawall encountered at %s." % target_pos)
			return false
			
		if tile_data.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile_data.is_unlocked:
			message_logged.emit("Movement blocked: Locked Code Gate encountered at %s." % target_pos)
			return false
				
	current_position = target_pos
	update_visual_position()
	queue_redraw()
	position_changed.emit(current_position)
	message_logged.emit("Netrunner relocated to %s" % current_position)
	
	if tile_data:
		interacted_with_tile.emit(tile_data, current_position)
			
	return true

# Anti-personnel (DAMAGE_RUNNER) attacks bypass the virtual world and strike
# the runner's nervous system directly. After the normal HP reduction, a hit
# that reached HP (damage > 0) and left the runner alive triggers:
#   1. INT-stat loss: 1 INT per anti-personnel hit (cumulative, capped at 0).
#   2. Mortal/Stun save: 1D10 + BODY vs a target that scales with the
#      runner's cumulative damage (max_health - current_health). On a failed
#      save the runner is stunned (signal `stunned`); on a success they
#      fight through the shock. Flatline is still governed by the
#      current_health <= 0 check above — a failed save at low damage stuns,
#      it does not kill.
# Existing 2-arg callers get is_anti_personnel = false → no behavior change.
func apply_damage(attack_strength: int, attacker_name: String, is_anti_personnel: bool = false) -> int:
	# Armor absorbs damage point-for-point FIRST (before the Shield opposed
	# roll). Armor is persistent — it is NOT consumed on a hit. Any remainder
	# proceeds to the Shield (if raised) and then to HP.
	if active_armor != null:
		var absorbed: int = min(attack_strength, active_armor.strength)
		attack_strength -= absorbed
		message_logged.emit("Armor absorbs %d (STR %d). Remaining: %d." % [absorbed, active_armor.strength, attack_strength])
		if attack_strength <= 0:
			message_logged.emit("Armor fully absorbs the attack.")
			return 0

	var damage: int = attack_strength
	if raised_shield != null:
		var shield_roll := randi_range(1, 10) + raised_shield.strength
		var attack_roll := randi_range(1, 10) + attack_strength
		message_logged.emit("Shield opposes: %d vs ICE %d." % [shield_roll, attack_roll])
		# CP2020: ties go to the ATTACKER — shield blocks only on a strict win.
		if shield_roll > attack_roll:
			message_logged.emit("Shield thwarts the attack. No damage taken.")
			damage = 0
		elif shield_roll == attack_roll:
			message_logged.emit("Shield ties the attack — attacker wins, full damage applies.")
		else:
			message_logged.emit("Shield breached! Full damage applies.")
		raised_shield = null
		shield_consumed.emit()

	if damage > 0:
		current_health -= damage
		message_logged.emit("%s hits for %d damage (Health %d/%d)." % [attacker_name, damage, current_health, max_health])
		health_changed.emit(current_health, max_health)

	if current_health <= 0:
		current_health = 0
		message_logged.emit("FLATLINED. Netrunner jacked out.")
		flatlined.emit()
		return damage

	# --- Anti-personnel neural shock (INT loss + Mortal/Stun save) --------
	if is_anti_personnel and damage > 0:
		_apply_anti_personnel_effects(attacker_name)

	return damage

# Applies the CP2020 anti-personnel after-effects: INT-stat loss and a
# meat-space Mortal/Stun save. Called only from apply_damage when
# is_anti_personnel is true and the hit reached HP. Assumes the runner is
# still alive (current_health > 0) — flatline is handled by the caller.
func _apply_anti_personnel_effects(attacker_name: String) -> void:
	# 1. INT-stat loss: 1 INT per anti-personnel hit, cumulative, floor at 0.
	if intelligence - intelligence_lost > 0:
		intelligence_lost += 1
		var cur_int: int = intelligence - intelligence_lost
		message_logged.emit("%s's neural shock \u2014 INT reduced by 1 (now %d)." % [attacker_name, cur_int])
		int_changed.emit(cur_int, intelligence)
	else:
		message_logged.emit("%s's neural shock \u2014 INT already drained to 0." % attacker_name)

	# 2. Mortal/Stun save: 1D10 + BODY vs a target scaled to cumulative damage.
	var cumulative: int = max_health - current_health
	var save_target: int
	if cumulative <= 3:
		save_target = 8
	elif cumulative <= 7:
		save_target = 12
	else:
		save_target = 15
	var save_roll: int = randi_range(1, 10) + body
	message_logged.emit("Mortal/Stun save: 1D10+BODY = %d vs target %d (cumulative damage %d)." % [save_roll, save_target, cumulative])
	if save_roll >= save_target:
		message_logged.emit("Mortal save succeeded \u2014 fighting through the shock.")
	else:
		message_logged.emit("STUNNED by neural shock! Actions impaired.")
		stunned.emit(1)

func raise_shield(program: NetProgram) -> void:
	raised_shield = program
	message_logged.emit("Shield raised (Block STR %d). Will thwart next attack on success." % program.strength)
	shield_raised.emit(program)

func raise_armor(program: NetProgram) -> void:
	active_armor = program
	message_logged.emit("Armor activated (absorb STR %d)." % program.strength)
	armor_raised.emit(program)

# --- Anti-system (Krash / CRASH_CPU) runner-deck crash ----------------------
# An anti-system attack that targets the runner's cyberdeck instead of a
# datafort CPU. The deck crashes for `duration` turns, dropping the runner's
# action economy (programs unavailable, movement only) until it reboots.
# Mirrors the datafort's crash_cpu duration (1D6+1).
func crash_deck(duration: int, attacker_name: String) -> void:
	deck_crashed_turns = max(deck_crashed_turns, duration)
	message_logged.emit("%s crashes your cyberdeck for %d turns! Action economy reduced." % [attacker_name, duration])
	deck_crashed.emit(duration)

# Called at the start of each netrunner turn by the game session. Decrements
# the crash timer and logs when the deck reboots (reaches 0). Returns nothing;
# the game session reads deck_crashed_turns after this to decide whether to
# force actions_remaining to 0.
func tick_deck_crash() -> void:
	if deck_crashed_turns <= 0:
		return
	deck_crashed_turns -= 1
	if deck_crashed_turns <= 0:
		deck_crashed_turns = 0
		message_logged.emit("Cyberdeck rebooted. Programs available again.")
