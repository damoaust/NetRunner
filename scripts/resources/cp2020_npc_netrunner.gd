class_name CP2020NpcNetrunner
extends GridEntityBase

# Full netrunner-entity NPC (unlike Black ICE, which is a contact-attack
# pathfinder). Carries a cyberdeck (MU + installed programs), health, and
# can use programs. Two factions share this one class:
#   NETWATCH  -> Disposition.HOSTILE on sight (corporate law enforcement).
#   NETRUNNER -> Disposition.NEUTRAL until provoked (idle/wander), then HOSTILE.
# Movement reuses the Black ICE AStarGrid2D pattern; the AI branch is selected
# by `disposition`, which a neutral NPC flips to HOSTILE the first time it
# takes damage.

signal message_logged(msg: String)
signal attacked_netrunner(strength: int)
signal destroyed
signal took_damage(amount: int)
# Emitted when a dormant hostile NPC's opposed roll pierces the netrunner's
# active Invisibility cloak. The game session clears the cloak globally.
signal cloak_pierced

enum Faction { NETWATCH, NETRUNNER }
enum Disposition { HOSTILE, NEUTRAL }

@export var faction: int = Faction.NETWATCH
@export var disposition: int = Disposition.HOSTILE

@export var npc_name: String = "NetWatch Agent"
@export var deck_name: String = "Standard Issue Deck"
@export var max_ap: int = 3
@export var strength: int = 4
@export var max_integrity: int = 4
@export var max_health: int = 10
@export var max_memory_units: int = 10
@export var installed_programs: Array[NetProgram] = []

# Program sight radius (separate from the runner's sight_range). HOSTILE NPCs
# gate pursue/attack on line of sight within this range; NEUTRAL NPCs wander
# regardless of LoS. Defaults to 10.
@export var sight_range: int = 10

# Original .tres resource paths of the programs this NPC was spawned with,
# captured at spawn time (see CP2020GameSession.spawn_npcs). The live
# installed_programs entries are duplicate()d at spawn and lose their
# resource_path, so this array preserves the authored paths needed to unlock
# the programs into the persistent vendor catalogue on defeat.
var source_program_paths: Array[String] = []

var current_integrity: int = 4
var current_health: int = 10
var _activated: bool = false
# Tracks the previous turn's LoS state so transition messages log only on
# the seen<->lost change.
var _had_los: bool = false
# The netrunner's active Invisibility cloak, or null. Set by the game session
# on every npc_nodes entry when the runner raises the cloak, and cleared (on
# all entries) when a seeker pierces it. While set, a hostile NPC that just
# gained LoS (not yet engaged, _had_los == false) must win an opposed roll
# (1D10+cloak.strength vs 1D10+this.strength) to detect the runner; hold ->
# hold position this turn, pierce -> pursue/attack and break the cloak
# globally. An NPC already engaged (_had_los == true) ignores the cloak.
var cloak_program: NetProgram = null
# Raised shield program (consumed on the next inbound hit), mirroring the
# player netrunner's raised_shield mechanic.
var raised_shield: NetProgram = null
# Shield cooldown: after a shield is consumed (breached or held), the NPC
# cannot raise another for one turn. Prevents the infinite-shield exploit
# where a hurt NPC re-raises a fresh shield every turn.
var _shield_cooldown: bool = false

func _ready() -> void:
	glyph_label = $GlyphLabel


func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	super.initialize(start_pos, layout_size)
	current_integrity = max_integrity
	current_health = max_health
	_apply_glyph_style()


func _apply_glyph_style() -> void:
	if not glyph_label:
		return
	match faction:
		Faction.NETWATCH:
			glyph_label.text = "N"
			glyph_label.add_theme_color_override("font_color", Color.RED)
		Faction.NETRUNNER:
			glyph_label.text = "R"
			glyph_label.add_theme_color_override("font_color", Color.YELLOW)


# Turn driver. The turn manager calls this on every adversary each ICE turn.
# `target_pos` is the player netrunner's current grid coordinate.
func take_turn(target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	if not _activated:
		_activated = true
		if disposition == Disposition.NEUTRAL:
			message_logged.emit("%s is here, minding their own business." % npc_name)
		else:
			message_logged.emit("WARNING: %s (%s) is hunting you!" % [npc_name, deck_name])

	if disposition == Disposition.NEUTRAL:
		_wander(layout)
		_shield_cooldown = false
		return

	# HOSTILE: sight gating. A hostile NPC can only pursue/attack when it has
	# line of sight to the netrunner within `sight_range` (walls/locked gates
	# block). Without LoS it holds position this turn.
	var los := layout.line_of_sight(current_position, target_pos, sight_range, home_floor)
	if not los:
		if _had_los:
			message_logged.emit("%s loses sight of the netrunner — holding position." % npc_name)
		_had_los = false
		_shield_cooldown = false
		return

	# Invisibility cloak gate: a hostile NPC that just gained LoS (not yet
	# engaged) must beat the cloak in an opposed roll to detect the runner.
	# An NPC that already has the runner (was engaged before this turn) bypasses
	# the cloak — Invisibility only prevents initial notice. Hold -> hold
	# position this turn (re-roll next LoS turn); pierce -> pursue/attack and
	# break the cloak globally.
	var was_engaged := _had_los
	if not _had_los and _activated:
		message_logged.emit("%s reacquires the netrunner!" % npc_name)
	_had_los = true
	if cloak_program != null and not was_engaged:
		var result := CP2020Dice.roll_opposed(strength, cloak_program.strength)
		message_logged.emit("Invisibility check: runner %d (1D10+%d) vs %s %d (1D10+%d)." % [result.def_roll, cloak_program.strength, npc_name, result.atk_roll, strength])
		if not result.attacker_wins:
			message_logged.emit("Invisibility holds — %s registers you as static and ignores you." % npc_name)
			_had_los = false
			_shield_cooldown = false
			return
		message_logged.emit("Invisibility pierced by %s! Cloak burned out." % npc_name)
		cloak_program = null
		cloak_pierced.emit()
		# Fall through: this NPC now pursues/attacks normally.

	# HOSTILE: pursue + use programs.
	refresh_pathfinding(layout)

	var ap_remaining = max_ap
	while ap_remaining > 0:
		var path = astar_grid.get_id_path(current_position, target_pos)
		if path.size() > 1:
			var next_step = path[1]
			if next_step == target_pos:
				_attack_player()
				break
			current_position = next_step
			ap_remaining -= 1
			await _guarded_step_timer(0.3)
		else:
			# Adjacent or unreachable: act from range if we can.
			_attack_player()
			break
	# Shield cooldown expires at end of the NPC's turn — prevents re-raising
	# the same round a shield was consumed (see take_damage).
	_shield_cooldown = false


func _wander(layout: CP2020DatafortLayout) -> void:
	# ~50% idle; otherwise step to a random walkable neighbour. Neutral NPCs
	# do not path toward the player.
	if randf() < 0.5:
		return
	var candidates: Array[Vector2i] = []
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n = current_position + dir
		if n.x < 0 or n.y < 0 or not layout or n.x >= layout.columns or n.y >= layout.rows:
			continue
		var tile = layout.get_tile(n, home_floor)
		# Don't wander into walls/locked gates; empty/entry/code-gate-unlocked are fine.
		if tile == null:
			candidates.append(n)
		elif tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL:
			continue
		elif tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked:
			continue
		else:
			candidates.append(n)
	if candidates.is_empty():
		return
	current_position = candidates[randi() % candidates.size()]
	await _guarded_step_timer(0.2)


# Resolve an attack against the player. Prefer an anti-personnel program
# (DAMAGE_RUNNER) for its strength; fall back to the NPC's base strength.
# If hurt and a shield program is available, raise it instead of attacking.
func _attack_player() -> void:
	# Raise a shield when hurt (integrity below max), not on cooldown, and
	# no shield already raised. The shield is consumed on the next inbound
	# hit, and the cooldown prevents re-raising every turn.
	if raised_shield == null and not _shield_cooldown and current_integrity < max_integrity:
		var shield_prog = _pick_program(NetProgram.EffectType.SHIELD)
		if shield_prog:
			raised_shield = shield_prog
			message_logged.emit("%s raises a shield (%s, Block STR %d)." % [npc_name, shield_prog.program_name, shield_prog.strength])
			return

	var attack_prog = _pick_program(NetProgram.EffectType.DAMAGE_RUNNER)
	var dmg: int = attack_prog.strength if attack_prog else strength
	var label = attack_prog.program_name if attack_prog else "direct attack"
	message_logged.emit("CRITICAL: %s hits you with %s for STR %d!" % [npc_name, label, dmg])
	attacked_netrunner.emit(dmg)


func _pick_program(effect: int) -> NetProgram:
	var best: NetProgram = null
	for prog in installed_programs:
		if prog and prog.effect_type == effect:
			if best == null or prog.strength > best.strength:
				best = prog
	return best


func update_visibility(_is_explored: bool, p_visible: bool) -> void:
	if glyph_label:
		glyph_label.visible = p_visible and not visual_3d_mode


func take_damage(amount: int) -> bool:
	var damage: int = amount
	# A raised shield opposes the inbound hit (same opposed roll as the player).
	if raised_shield != null:
		var result := CP2020Dice.roll_opposed(amount, raised_shield.strength)
		message_logged.emit("%s shield opposes: %d vs attack %d." % [npc_name, result.def_roll, result.atk_roll])
		if not result.attacker_wins:
			message_logged.emit("%s's shield holds. No damage." % npc_name)
			damage = 0
		else:
			message_logged.emit("%s's shield breached! Full damage applies." % npc_name)
		raised_shield = null
		# The shield was consumed (held or breached): start the one-turn
		# cooldown so the NPC can't immediately re-raise a fresh shield.
		_shield_cooldown = true

	if damage > 0:
		current_integrity -= damage
		# A neutral NPC who is attacked becomes hostile for the rest of the run.
		if disposition == Disposition.NEUTRAL:
			disposition = Disposition.HOSTILE
			message_logged.emit("%s is provoked and turns hostile!" % npc_name)
		message_logged.emit("%s takes %d damage (Integrity %d/%d)." % [npc_name, damage, max(0, current_integrity), max_integrity])
		took_damage.emit(damage)

	if current_integrity <= 0:
		message_logged.emit("%s flatlined and jacked out." % npc_name)
		destroyed.emit()
		queue_free()
		return true
	return false
