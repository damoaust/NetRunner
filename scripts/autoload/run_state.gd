extends Node

# Autoload singleton holding cross-scene run state.
# Set at the workbench, read by the gameplay session.

var selected_deck: Cyberdeck = null
var selected_subnet_path: String = ""
var credits: int = 1000
# Total Trace Value of all LDLs passed through in the current Net run. Drives
# tracing-program rolls during the datafort session; reset per run.
var accumulated_trace: int = 0
# City Grid currently in play (set by the world map ENTER action). The
# datafort LDL-return uses this to go back to the right city grid.
var selected_city_grid_path: String = ""
# Security tier of the datafort the runner dived into (set by the city grid
# DIVE action). Read by game_session for the ICE loadout template.
var selected_security_tier: int = 0

func reset() -> void:
	selected_deck = null
	selected_subnet_path = ""
	credits = 1000
	accumulated_trace = 0
	selected_city_grid_path = ""
	selected_security_tier = 0