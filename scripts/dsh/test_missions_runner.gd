extends Node

# Headless functional test for the Missions system, run as a scene (autoloads
# are available as globals in scene context, unlike --script mode). Backs up
# the user's run save, drives a fresh life through the full mission loop
# (seed -> accept -> objective -> hand-in) for each mission type, asserts the
# key invariants, then restores the original save and quits.

const RUN_SAVE := "user://run_state.tres"
const BACKUP := "user://run_state.tres.bak_missiontest"

func _ready() -> void:
	var ok := true
	if ResourceLoader.exists(RUN_SAVE):
		var dir := DirAccess.open("user://")
		if dir != null:
			if dir.copy(RUN_SAVE, BACKUP) != OK:
				print("FAIL: could not back up run save — aborting before mutation.")
				get_tree().quit(1)
				return
	# Drive a fresh life so the board is seeded deterministically.
	RunState.start_new_life()
	ok = ok and _test_board_seeded()
	ok = ok and _test_data_harvest_flow()
	ok = ok and _test_sabotage_flow()
	ok = ok and _test_recon_flow()
	ok = ok and _test_active_limit()
	# Board refresh: simulate net-time advancing past the refresh threshold.
	ok = ok and _test_refresh()
	_restore_save()
	if ok:
		print("MISSION TESTS: ALL PASS")
		get_tree().quit(0)
	else:
		print("MISSION TESTS: FAILURES (see above)")
		get_tree().quit(1)

func _restore_save() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists(BACKUP):
		dir.remove(RUN_SAVE)
		dir.rename(BACKUP, RUN_SAVE)
	else:
		dir.remove(RUN_SAVE)

func _test_board_seeded() -> bool:
	var n: int = RunState.available_missions.size()
	if n <= 0:
		print("  FAIL: board empty after start_new_life (library scan failed?).")
		return false
	print("  PASS: board seeded with %d mission(s)." % n)
	return true

func _find_mission_of_type(t: int) -> CP2020Mission:
	for m in RunState.available_missions:
		if m != null and m.mission_type == t:
			return m
	return null

func _test_data_harvest_flow() -> bool:
	var m := _find_mission_of_type(CP2020Mission.MissionType.DATA_HARVEST)
	if m == null:
		print("  SKIP: no DATA_HARVEST mission on the board.")
		return true
	if not RunState.accept_mission(m):
		print("  FAIL: could not accept DATA_HARVEST mission.")
		return false
	if RunState.active_mission != m:
		print("  FAIL: active_mission not set after accept.")
		return false
	var f := NetFile.new()
	f.file_name = m.target_file_name
	f.credit_value = 123
	f.mu_size = 1
	RunState.carried_files.append(f)
	RunState.notify_file_copied(f)
	if not RunState.mission_objective_met:
		print("  FAIL: DATA_HARVEST objective not met after copying target file.")
		return false
	if not RunState.can_hand_in_mission():
		print("  FAIL: can_hand_in_mission false after carrying target file.")
		return false
	var credits_before: int = RunState.credits
	var reward: int = RunState.hand_in_mission()
	if reward <= 0:
		print("  FAIL: hand_in_mission returned 0.")
		return false
	if RunState.credits != credits_before + reward:
		print("  FAIL: credits not increased by reward (%d vs %d+%d)." % [RunState.credits, credits_before, reward])
		return false
	if RunState.active_mission != null:
		print("  FAIL: active_mission not cleared after hand-in.")
		return false
	for cf in RunState.carried_files:
		if cf != null and cf.file_name == m.target_file_name:
			print("  FAIL: proof file still carried after hand-in.")
			return false
	print("  PASS: DATA_HARVEST flow (accept -> copy -> hand in -> %d eb)." % reward)
	return true

func _test_sabotage_flow() -> bool:
	var m := _find_mission_of_type(CP2020Mission.MissionType.SABOTAGE)
	if m == null:
		print("  SKIP: no SABOTAGE mission on the board.")
		return true
	if not RunState.accept_mission(m):
		print("  FAIL: could not accept SABOTAGE mission.")
		return false
	RunState.notify_action_at_coord("res://scenes/forts/wrong.tres", m.target_coord)
	if RunState.mission_objective_met:
		print("  FAIL: SABOTAGE objective met on wrong subnet.")
		return false
	RunState.notify_action_at_coord(m.target_subnet_path, Vector2i(-99, -99))
	if RunState.mission_objective_met:
		print("  FAIL: SABOTAGE objective met on wrong coord.")
		return false
	RunState.notify_action_at_coord(m.target_subnet_path, m.target_coord)
	if not RunState.mission_objective_met:
		print("  FAIL: SABOTAGE objective not met on correct coord.")
		return false
	var reward: int = RunState.hand_in_mission()
	if reward <= 0:
		print("  FAIL: SABOTAGE hand_in returned 0.")
		return false
	print("  PASS: SABOTAGE flow (accept -> hit coord -> hand in -> %d eb)." % reward)
	return true

func _test_recon_flow() -> bool:
	var m := _find_mission_of_type(CP2020Mission.MissionType.RECON)
	if m == null:
		print("  SKIP: no RECON mission on the board.")
		return true
	if not RunState.accept_mission(m):
		print("  FAIL: could not accept RECON mission.")
		return false
	RunState.notify_position(m.target_subnet_path, m.target_coord)
	if not RunState.mission_objective_met:
		print("  FAIL: RECON objective not met on correct coord.")
		return false
	var reward: int = RunState.hand_in_mission()
	if reward <= 0:
		print("  FAIL: RECON hand_in returned 0.")
		return false
	print("  PASS: RECON flow (accept -> reach coord -> hand in -> %d eb)." % reward)
	return true

func _test_active_limit() -> bool:
	var m := _find_mission_of_type(CP2020Mission.MissionType.RECON)
	if m == null:
		m = _find_mission_of_type(CP2020Mission.MissionType.SABOTAGE)
	if m == null:
		m = _find_mission_of_type(CP2020Mission.MissionType.DATA_HARVEST)
	if m == null:
		print("  SKIP: no mission available for active-limit test.")
		return true
	if not RunState.accept_mission(m):
		print("  FAIL: could not accept mission for active-limit test.")
		return false
	var second: CP2020Mission = null
	for m2 in RunState.available_missions:
		if m2 != null and m2 != m:
			second = m2
			break
	if second == null:
		print("  SKIP: only one mission left on board for active-limit test.")
		RunState.abandon_mission()
		return true
	if RunState.accept_mission(second):
		print("  FAIL: accepted a second mission while one was already active.")
		return false
	print("  PASS: active-mission limit enforced (second accept rejected).")
	# Abandon restores it to the board; verify board grew back by one.
	var before: int = RunState.available_missions.size()
	RunState.abandon_mission()
	if RunState.available_missions.size() != before + 1:
		print("  FAIL: board size did not grow after abandon.")
		return false
	print("  PASS: abandon returns the contract to the board.")
	return true

func _test_refresh() -> bool:
	# Advance net-time past the refresh threshold and verify a rotation.
	var before: int = RunState.available_missions.size()
	var first := RunState.available_missions[0] if not RunState.available_missions.is_empty() else null
	RunState.net_time_seconds = RunState.last_mission_refresh_time + RunState.MISSION_REFRESH_SECONDS + 1.0
	var rotated: bool = RunState.check_mission_refresh()
	if not rotated:
		print("  FAIL: check_mission_refresh did not rotate past the threshold.")
		return false
	if RunState.available_missions.size() != before:
		print("  FAIL: board size changed during refresh (expected same size).")
		return false
	if first != null and RunState.available_missions[0] == first:
		print("  NOTE: oldest entry unchanged after refresh (library may be small).")
	print("  PASS: board refresh rotates the oldest entry past the threshold.")
	return true