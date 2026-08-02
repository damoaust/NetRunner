extends Node

# Autoload singleton holding cross-scene run state.
# Set at the workbench, read by the gameplay session.

var selected_deck: Cyberdeck = null
var selected_subnet_path: String = ""
var credits: int = 1000

func reset() -> void:
	selected_deck = null
	selected_subnet_path = ""
	credits = 1000