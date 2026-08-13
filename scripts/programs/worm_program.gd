class_name WormProgram
extends NetProgram

# Worm: a subtle intrusion program that emulates part of the invaded system's
# architecture. It slips behind a Data Wall or locked Code Gate and opens it
# from the inside over 2 turns with no alert (no trace increase, no ICE
# activation). Only used by the netrunner (not rezzed as ICE).

func execute_runner_action(session: CP2020GameSession, target_coord: Vector2i) -> bool:
	var tile: CP2020TileData = session.current_layout.get_tile(target_coord, session.current_floor)
	if tile == null:
		session.log_to_terminal("No tile at %s for Worm.\n" % target_coord)
		return false
	var is_wall: bool = tile.tile_type == CP2020DatafortLayout.TileType.DATAWALL
	var is_gate: bool = tile.tile_type == CP2020DatafortLayout.TileType.CODE_GATE and not tile.is_unlocked
	if not is_wall and not is_gate:
		session.log_to_terminal("Worm can only target Data Walls or locked Code Gates.\n")
		return false
	if tile.worm_turns_remaining > 0:
		session.log_to_terminal("A Worm is already working on this tile (%d turns remaining).\n" % tile.worm_turns_remaining)
		return false
	tile.worm_turns_remaining = 2
	# Seed the Worm's structural integrity from its strength — enemy DEREZ_ICE
	# (Killer) ICE attacks the Worm via an opposed roll; only the Killer can
	# deal damage on a win (Worms are passive defenders). At 0 integrity the
	# Worm is destroyed and the tile stays closed.
	tile.worm_integrity = strength
	tile.worm_max_integrity = strength
	var label := "data wall" if is_wall else "code gate"
	session.log_to_terminal("Worm '%s' deployed behind the %s at %s — opening from the inside in 2 turns. No alert triggered.\n" % [program_name, label, target_coord])
	if session.board_renderer:
		session.board_renderer.queue_redraw()
	return true
