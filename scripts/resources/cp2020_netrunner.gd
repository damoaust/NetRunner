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
# Anti-personnel neural shock forced a failed Stun save: the runner is
# stunned (unconscious). While stunned, the runner cannot act, move, or
# jack out, and all Black ICE auto-hit every turn (CP2020 Stunned Runner
# Death Trap). The stun persists until the runner flatlines or a meat-space
# ally pulls the plug (future feature). See apply_damage / is_stunned.
signal stunned

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

# Stunned Runner Death Trap (CP2020). When a Stun save fails, the runner is
# unconscious: cannot act, move, or jack out. All Black ICE auto-hit every
# turn (no defense roll — protection programs can't be raised while stunned,
# and existing Shield/Armor are consumed). The stun persists until the runner
# flatlines or a meat-space ally pulls the plug (future feature).
var is_stunned: bool = false

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

# Animation state for the cyberpunk diamond avatar (matches world-map runner).
var _pulse_time: float = 0.0

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

func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()

func _draw() -> void:
	var pulse := 0.5 * (1.0 + sin(_pulse_time * 3.0))
	var center := Vector2.ZERO
	var size := cell_size * 0.32 * (0.9 + 0.1 * pulse)

	# Outer rotating targeting ring.
	var ring_alpha := 0.5 + 0.3 * pulse
	draw_arc(center, cell_size * 0.48, -_pulse_time * 3.0, -_pulse_time * 3.0 + TAU * 0.9, 32, Color(Color.CYAN.r, Color.CYAN.g, Color.CYAN.b, ring_alpha), 2.0)

	# Neon glow layers.
	for i in range(3):
		var glow_size := size + i * 4.0
		var glow_alpha := 0.25 - i * 0.07
		_draw_diamond(center, glow_size, Color(Color.CYAN.r, Color.CYAN.g, Color.CYAN.b, glow_alpha), true)

	# Solid diamond avatar.
	_draw_diamond(center, size, Color.CYAN, true)
	_draw_diamond(center, size * 0.7, Color(0.0, 0.0, 0.0, 0.6), true)

func _draw_diamond(center: Vector2, size: float, color: Color, filled: bool) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(size, 0),
		center + Vector2(0, size),
		center + Vector2(-size, 0),
	])
	if filled:
		draw_polygon(points, PackedColorArray([color, color, color, color]))
	else:
		points.append(points[0])
		draw_polyline(points, color, 2.0)

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

# CP2020 Anti-Personnel Combat Resolution (Step 1–4).
#
# `attack_strength` is the attacking program's STR (used for the Interface
# Defense Roll). `prog` is the attacking NetProgram (used to roll the payload
# damage via prog._roll_damage() after the defense roll succeeds); null for
# NPC/datafort direct attacks → payload = attack_strength (flat).
#
# Step 1 — Interface Defense Roll:
#   Attacker rolls 1D10 + attack_strength. Defender rolls 1D10 + protection
#   program STR (Shield first, then Armor — both use the SAME opposed roll).
#   Ties → DEFENDER (safe). If no protection program is loaded & active →
#   AUTO-HIT (no defense roll, full payload applies).
# Step 2 — Apply Payload:
#   damage = prog._roll_damage() (per-program: Hellhound 2D10, Sword 1D6,
#   Flatline flat STR). Physical body armor = zero protection.
# Step 3 — Meat-Space Saves (anti-personnel only):
#   Stun/Shock save: roll 1D10 UNDER BOD minus wound penalty. Mortal/Death
#   save: if HP ≤ 0, roll 1D10 + BODY vs 15 — success = survive at 1 HP.
# Step 4 — Stunned Runner Death Trap:
#   Failed Stun save → unconscious (is_stunned = true). Cannot act, move,
#   or jack out. All Black ICE auto-hit every turn until flatline.
func apply_damage(attack_strength: int, attacker_name: String, is_anti_personnel: bool = false, prog: NetProgram = null) -> int:
	# Step 1: Interface Defense Roll.
	var damage: int = 0
	var attack_roll := randi_range(1, 10) + attack_strength
	var has_shield: bool = raised_shield != null
	var has_armor: bool = active_armor != null

	# CP2020 Death Trap: a stunned (unconscious) runner cannot defend —
	# all attacks auto-hit, ignoring any loaded protection programs.
	if is_stunned:
		message_logged.emit("STUNNED — %s auto-hits (no defense)!" % attacker_name)
		damage = _roll_payload(prog, attack_strength)
		# Skip straight to payload application (Step 2 onward).
		current_health -= damage
		message_logged.emit("%s hits for %d damage (Health %d/%d)." % [attacker_name, damage, current_health, max_health])
		health_changed.emit(current_health, max_health)
		if current_health <= 0:
			current_health = 0
			if _roll_death_save():
				current_health = 1
				message_logged.emit("DEATH SAVE SUCCEEDED — clinging to life at 1 HP!")
				health_changed.emit(current_health, max_health)
			else:
				message_logged.emit("DEATH SAVE FAILED — FLATLINED. Netrunner jacked out.")
				flatlined.emit()
				return damage
		if is_anti_personnel and damage > 0:
			_apply_anti_personnel_effects(attacker_name)
		return damage

	if not has_shield and not has_armor:
		# No protection program loaded → auto-hit. Full payload applies.
		message_logged.emit("No protection program — %s auto-hits!" % attacker_name)
		damage = _roll_payload(prog, attack_strength)
	elif has_shield:
		# Shield is resolved first (one-shot, consumed regardless of outcome).
		var shield_roll := randi_range(1, 10) + raised_shield.strength
		message_logged.emit("Shield opposes: %d vs %s %d." % [shield_roll, attacker_name, attack_roll])
		if shield_roll >= attack_roll:
			# Ties → defender. Shield blocks the attack entirely.
			message_logged.emit("Shield thwarts the attack (tie goes to defender). No damage taken.")
			damage = 0
		else:
			message_logged.emit("Shield breached! Full damage applies.")
			damage = _roll_payload(prog, attack_strength)
		# Shield is one-shot — consumed on use.
		raised_shield = null
		shield_consumed.emit()
		# If shield failed and Armor is active, Armor gets a second chance.
		if damage > 0 and has_armor:
			damage = _try_armor(attack_roll, damage, attacker_name, prog, attack_strength)
	elif has_armor:
		# No shield, but Armor is active — Armor gets the defense roll.
		damage = _try_armor(attack_roll, 0, attacker_name, prog, attack_strength)

	# Step 2: Apply payload to HP.
	if damage > 0:
		current_health -= damage
		message_logged.emit("%s hits for %d damage (Health %d/%d)." % [attacker_name, damage, current_health, max_health])
		health_changed.emit(current_health, max_health)

	# Step 3: Mortal/Death save (if HP ≤ 0).
	if current_health <= 0:
		current_health = 0
		if _roll_death_save():
			current_health = 1
			message_logged.emit("DEATH SAVE SUCCEEDED — clinging to life at 1 HP!" )
			health_changed.emit(current_health, max_health)
		else:
			message_logged.emit("DEATH SAVE FAILED — FLATLINED. Netrunner jacked out.")
			flatlined.emit()
			return damage

	# Step 3b: Anti-personnel after-effects (INT loss + Stun save).
	if is_anti_personnel and damage > 0:
		_apply_anti_personnel_effects(attacker_name)

	return damage

# Roll the payload damage for a successful hit. Uses the attacking program's
# _roll_damage() (per-program dice), or falls back to flat attack_strength
# for NPC/datafort direct attacks (prog == null).
func _roll_payload(prog: NetProgram, fallback: int) -> int:
	if prog != null:
		return prog._roll_damage()
	return fallback

# Armor opposed roll (same mechanic as Shield). Returns the damage that
# still gets through (0 if Armor blocks). Armor is one-shot (consumed on use).
# `incoming_damage` is the payload already rolled; if Armor wins the opposed
# roll, damage is 0; if Armor loses, `incoming_damage` applies (or is rolled
# if not yet rolled).
func _try_armor(attack_roll: int, incoming_damage: int, attacker_name: String, prog: NetProgram, attack_strength: int) -> int:
	var armor_roll := randi_range(1, 10) + active_armor.strength
	message_logged.emit("Armor opposes: %d vs %s %d." % [armor_roll, attacker_name, attack_roll])
	var damage: int = 0
	if armor_roll >= attack_roll:
		# Ties → defender. Armor blocks the attack entirely.
		message_logged.emit("Armor blocks the attack (tie goes to defender). No damage taken.")
	else:
		message_logged.emit("Armor breached! Full damage applies.")
		# If the payload was already rolled (Shield failed first), use it;
		# otherwise roll it now.
		damage = incoming_damage if incoming_damage > 0 else _roll_payload(prog, attack_strength)
	# Armor is one-shot — consumed on use.
	active_armor = null
	armor_consumed.emit()
	return damage

# Wound state based on cumulative damage (CP2020 meat-space wound tracks).
# Returns a dictionary with the wound label and Stun save penalty.
func _wound_state() -> Dictionary:
	var cumulative: int = max_health - current_health
	if cumulative <= 0:
		return {"label": "Healthy", "penalty": 0}
	elif cumulative <= 4:
		return {"label": "Light", "penalty": 0}
	elif cumulative <= 8:
		return {"label": "Serious", "penalty": 2}
	elif cumulative <= 12:
		return {"label": "Critical", "penalty": 4}
	else:
		return {"label": "Mortal", "penalty": 6}

# CP2020 Stun/Shock save: roll 1D10 UNDER (BOD - wound penalty). If the
# adjusted BOD is 0 or less, auto-fail. Returns true if the save succeeds
# (runner stays conscious), false if stunned.
func _roll_stun_save() -> bool:
	var wound := _wound_state()
	var adjusted_bod: int = body - int(wound["penalty"])
	if adjusted_bod <= 0:
		message_logged.emit("Stun save: BOD %d - %s wound penalty %d = %d → AUTO-FAIL." % [body, wound["label"], wound["penalty"], adjusted_bod])
		return false
	var roll: int = randi_range(1, 10)
	var success := roll < adjusted_bod
	message_logged.emit("Stun save: rolled %d vs BOD %d (-%d %s) = need under %d → %s." % [roll, body, wound["penalty"], wound["label"], adjusted_bod, "SUCCESS" if success else "FAIL"])
	return success

# CP2020 Death Save: when HP reaches 0, roll 1D10 + BODY vs 15. Success =
# stabilize at 1 HP; failure = flatline.
func _roll_death_save() -> bool:
	var roll: int = randi_range(1, 10) + body
	var target: int = 15
	var success := roll >= target
	message_logged.emit("Death Save: 1D10+BODY = %d vs target %d → %s." % [roll, target, "SUCCESS" if success else "FAIL"])
	return success

# Applies the CP2020 anti-personnel after-effects (Step 3b–4): INT-stat loss
# and a meat-space Stun save. Called only from apply_damage when
# is_anti_personnel is true and the hit reached HP. Assumes the runner is
# still alive (current_health > 0) — flatline/Death Save is handled by the
# caller.
func _apply_anti_personnel_effects(attacker_name: String) -> void:
	# 1. INT-stat loss: 1 INT per anti-personnel hit, cumulative, floor at 0.
	if intelligence - intelligence_lost > 0:
		intelligence_lost += 1
		var cur_int: int = intelligence - intelligence_lost
		message_logged.emit("%s's neural shock — INT reduced by 1 (now %d)." % [attacker_name, cur_int])
		int_changed.emit(cur_int, intelligence)
	else:
		message_logged.emit("%s's neural shock — INT already drained to 0." % attacker_name)

	# 2. Stun/Shock save: roll 1D10 UNDER BOD minus wound penalty.
	if not _roll_stun_save():
		is_stunned = true
		message_logged.emit("STUNNED by neural shock! Death Trap — cannot act, move, or jack out. Black ICE auto-hits every turn!")
		stunned.emit()
	else:
		message_logged.emit("Fighting through the shock — remaining conscious.")

# Returns true if the runner can act (not stunned, not flatlined).
func can_act() -> bool:
	return not is_stunned and current_health > 0

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
