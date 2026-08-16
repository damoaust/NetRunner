class_name CP2020TimeScale

# Net time per action consumed at each grid scale (CP2020 sourcebook — deeper
# grids are exponentially faster). Canonical unit: seconds (float). The turn
# manager emits `action_consumed` for every action spent; each scene adds its
# scale's constant to RunState.net_time_seconds.
const WORLD_MAP_SECONDS: float = 60.0       # 1 action = 1 minute
const CITY_GRID_SECONDS: float = 1.0        # 1 action = 1 second
const DATAFORT_SECONDS: float = 1.0e-9      # 1 action = 1 nanosecond

# Format a cumulative net-time (seconds) as a scale-appropriate clock string:
#   >= 60 s  -> "Xm Ys"   (minutes + remaining whole seconds)
#   >= 1 s   -> "X.XXs"
#   < 1 s    -> "X ns"    (nanoseconds, integer)
static func format_clock(seconds: float) -> String:
	if seconds >= 60.0:
		var mins := int(seconds / 60.0)
		var rem := int(seconds) - mins * 60
		return "%dm %ds" % [mins, rem]
	elif seconds >= 1.0:
		return "%.2fs" % seconds
	else:
		return "%d ns" % int(seconds * 1.0e9)