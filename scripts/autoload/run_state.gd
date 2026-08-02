extends Node

# Autoload singleton holding cross-scene run state.
# Set at the workbench, read by the gameplay session.

var selected_deck: Cyberdeck = null
var selected_subnet_path: String = ""
var credits: int = 1000
# Total Trace Value of all LDLs passed through in the current Net run. Drives
# tracing-program rolls during the datafort session; reset per run.
var accumulated_trace: int = 0

func reset() -> void:
	selected_deck = null
	selected_subnet_path = ""
	credits = 1000
	accumulated_trace = 0