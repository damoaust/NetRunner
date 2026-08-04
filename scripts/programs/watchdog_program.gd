class_name WatchdogProgram
extends NetProgram

# Watchdog: Detection/Alarm program. As ICE it sounds the alarm on first LoS
# detection (activating all attack ICE) and stays stationary — it never pursues,
# attacks, or traces. As a netrunner utility it deploys a tripwire beacon that
# alerts when enemies approach.

func take_ice_turn(ice: BlackIce, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	# Trip the alarm once on first activation, then stay stationary forever.
	# Watchdog detects via line of sight (already gated by BlackIce.take_turn),
	# so it does NOT roll the tracing check — this is intentional and fixes the
	# DETECTION+traces bug (a tracing Watchdog must still alarm on LoS).
	if not ice._activated:
		ice._activated = true
		ice.emit_log("ALARM: %s detects intruder! Sounding alarm!" % program_name)
		ice.emit_alarm()
	# No pursue, no attack: stay stationary for the rest of the run.

func execute_runner_action(session: CP2020GameSession, target_coord: Vector2i) -> bool:
	# Deploy a Watchdog beacon at the netrunner's current position. The session
	# tracks the beacon, marks this program as deployed (one file, one
	# instance), and ticks beacons each turn. Returns true to consume an action.
	session.deploy_watchdog_beacon(self, target_coord)
	return true