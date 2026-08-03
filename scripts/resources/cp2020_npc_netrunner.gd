class_name CP2020NpcNetrunner
extends Node2D

# Full netrunner-entity NPC (unlike Black ICE, which is a contact-attack
# pathfinder). Carries a cyberdeck (MU + installed programs), health, and
# can use programs. Two factions share this one class:
#   NETWATCH  -> Disposition.HOSTILE on sight (corporate law enforcement).
#   NETRUNNER -> Disposition.NEUTRAL until provoked (idle/wander), then HOSTILE.
# Movement reuses the Black ICE AStarGrid2D pattern; the AI branch is selected
# by `disposition`, which a neutral NPC flips to HOSTILE the first time it
# takes damage.

signal message_logged(msg: String)
signal moved_to(new_pos: Vector2i)
signal attacked_netrunner(strength: int)
signal destroyed
signal took_damage(amount: int)

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

@export var cell_size: int = 40
@export var grid_offset_y: int = 90
@export var label_visual_offset: Vector2 = Vector2(-2, -4)

var current_position: Vector2i = Vector2i.ZERO
var current_integrity: int = 4
var current_health: int = 10
var astar_grid: AStarGrid2D
var _activated: bool = false
# Raised shield program (consumed on the next inbound hit), mirroring the
# player netrunner's raised_shield mechanic.
var raised_shield: NetProgram = null

@onready var glyph_label = $GlyphLabel


func initialize(start_pos: Vector2i, layout_size: Vector2i) -> void:
	current_position = start_pos
	current_integrity = max_integrity
	current_health = max_health

	if glyph_label:
		glyph_label.size = Vector2(cell_size, cell_size)
		glyph_label.position = Vector2(-cell_size / 2.0, -cell_size / 2.0) + label_visual_offset
		glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_glyph_style()

	update_visual_position()

	if astar_grid:
		astar_grid.free()
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, layout_size.x, layout_size.y)
	astar_grid.cell_size = Vector2(1, 1)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()

	moved_to.emit(current_position)


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


func update_visual_position() -> void:
	var center_x = (current_position.x * cell_size) + (cell_size / 2.0)
	var center_y = grid_offset_y + (current_position.y * cell_size) + (cell_size / 2.0)
	position = Vector2(center_x, center_y)


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
		return

	# HOSTILE: pursue + use programs.
	_update_obstacles(layout)

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
			update_visual_position()
			await get_tree().create_timer(0.3).timeout
			moved_to.emit(current_position)
		else:
			# Adjacent or unreachable: act from range if we can.
			_attack_player()
			break


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
		var tile = layout.get_tile(n)
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
	update_visual_position()
	await get_tree().create_timer(0.2).timeout
	moved_to.emit(current_position)


# Resolve an attack against the player. Prefer an anti-personnel program
# (DAMAGE_RUNNER) for its strength; fall back to the NPC's base strength.
# If hurt and a shield program is available, raise it instead of attacking.
func _attack_player() -> void:
	if current_health < max_health:
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


func _update_obstacles(layout: CP2020DatafortLayout) -> void:
	astar_grid.fill_solid_region(astar_grid.region, false)
	for raw_key in layout.grid_tiles.keys():
		var coord: Vector2i
		if raw_key is String:
			var parts = raw_key.split(",")
			coord = Vector2i(parts[0].to_int(), parts[1].to_int())
		else:
			coord = raw_key
		var tile = layout.get_tile(coord)
		if tile:
			if tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL or (tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked):
				astar_grid.set_point_solid(coord, true)


func update_visibility(is_explored: bool, is_visible: bool) -> void:
	if glyph_label:
		glyph_label.visible = is_visible


func take_damage(amount: int) -> bool:
	var damage: int = amount
	# A raised shield opposes the inbound hit (same opposed roll as the player).
	if raised_shield != null:
		var shield_roll := randi_range(1, 10) + raised_shield.strength
		var attack_roll := randi_range(1, 10) + amount
		message_logged.emit("%s shield opposes: %d vs attack %d." % [npc_name, shield_roll, attack_roll])
		if shield_roll >= attack_roll:
			message_logged.emit("%s's shield holds. No damage." % npc_name)
			damage = 0
		else:
			message_logged.emit("%s's shield breached! Full damage applies." % npc_name)
		raised_shield = null

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