class_name WatchdogProgram
extends NetProgram

# Watchdog: Detection/Alarm + tracing program. As ICE it sounds the alarm on
# first LoS detection (activating all attack ICE) and rolls a CP2020 trace
# check (1D10+STR vs RunState.accumulated_trace) to pinpoint the runner's
# physical location — on success the game session starts the meatspace
# security-dispatch countdown. It stays stationary — it never pursues or
# attacks. As a netrunner utility it deploys a tripwire beacon that alerts
# when enemies approach.

func take_ice_turn(ice: BlackIce, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	# Trip the alarm once on first activation, then stay stationary forever.
	# Watchdog detects via line of sight (already gated by BlackIce.take_turn),
	# so it does NOT roll the tracing check — this is intentional and fixes the
	# DETECTION+traces bug (a tracing Watchdog must still alarm on LoS).
	if not ice._activated:
		ice._activated = true
		ice.emit_log("ALARM: %s detects intruder! Sounding alarm!" % program_name)
		ice.emit_alarm()
		# CP2020 trace check: on first detection the Watchdog tries to trace the
		# runner's signal back to its physical location. Roll 1D10 + STR vs the
		# runner's total LDL Trace Value (RunState.accumulated_trace — the
		# defensive target number built from bouncing through LDLs) PLUS any
		# Trace Dampener options module on the runner's deck (its bonus is added
		# to the target, making the trace harder — the dampener no longer
		# reduces LDL trace gain). Success emits trace_succeeded so the game
		# session starts the meatspace security-dispatch countdown + escalates
		# the datafort's ICE. A runner who didn't bounce through any LDLs
		# (trace 0) and has no dampener is trivially pinpointed.
		var trace_roll := randi_range(1, 10) + strength
		var dampening: int = 0
		if RunState.selected_deck != null:
			dampening = RunState.selected_deck.effective_trace_reduction()
		var trace_target: int = RunState.accumulated_trace + dampening
		if dampening > 0:
			ice.emit_log("TRACE CHECK: %s rolls 1D10+%d = %d vs your LDL Trace Value %d (+%d dampener) = %d." % [program_name, strength, trace_roll, RunState.accumulated_trace, dampening, trace_target])
		else:
			ice.emit_log("TRACE CHECK: %s rolls 1D10+%d = %d vs your LDL Trace Value %d." % [program_name, strength, trace_roll, trace_target])
		# Ties go to the runner (defender) — matches the project-wide
		# defender-favored opposed-roll convention. The trace only succeeds on
		# a strictly higher roll. A trace value of 0 (no LDL bounces, no
		# dampener) is still trivially pinpointed by any roll.
		if trace_roll > trace_target:
			ice.emit_log("TRACE SUCCESS — %s has pinpointed your physical location! Meatspace team dispatched." % program_name)
			ice.emit_trace_succeeded(self)
		else:
			ice.emit_log("TRACE FAILED — %s could not lock onto your signal. Stay moving." % program_name)
	# No pursue, no attack: stay stationary for the rest of the run.

func execute_runner_action(session: CP2020GameSession, target_coord: Vector2i) -> bool:
	# Deploy a Watchdog beacon at the netrunner's current position. The session
	# tracks the beacon, marks this program as deployed (one file, one
	# instance), and ticks beacons each turn. Returns true to consume an action.
	session.deploy_watchdog_beacon(self, target_coord)
	return true