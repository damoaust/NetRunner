class_name ProbeProgram
extends NetProgram

# Probe: a focused REVEAL_NODES detection utility. Unlike Sensor (which sweeps
# a radius around the runner, ignoring walls), Probe identifies a single
# targeted node within line of sight — revealing it and reporting any ICE or
# netrunner stationed there. Lower MU / cheaper than a full Sensor sweep.
# Only used by the netrunner (not rezzed as ICE).

func execute_runner_action(session: CP2020GameSession, target_coord: Vector2i) -> bool:
	session._execute_probe(self, target_coord)
	return true