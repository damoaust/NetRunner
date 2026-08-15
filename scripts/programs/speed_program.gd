class_name SpeedProgram
extends NetProgram

# Speed: a MODIFY_MU utility that boosts the cyberdeck's initiative speed
# bonus by the program's STR for the rest of the run (runner initiative =
# 1D10 + REF + deck.speed_bonus + temp_speed_bonus). One active instance;
# re-activation is a no-op (the boost is already running). Only used by the
# netrunner (not rezzed as ICE).

func execute_runner_action(session: CP2020GameSession, _target_coord: Vector2i) -> bool:
	return session._execute_speed(self)