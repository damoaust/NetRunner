extends Control

# GameOver screen — shown when a run ends in permadeath (Flatlined or Busted).
# The death cause + run summary are passed in via RunState transient fields
# (set by cp2020_game_session just before the scene change). The "New Life"
# button is the ONLY place that calls RunState.start_new_life() for the
# permadeath flow (besides first-life init in the workbench).
#
# Layout lives in GameOver.tscn (styled by themes/cyberpunk_theme.tres). This
# script only fills in the cause-dependent text/colour + run-summary numbers;
# the button's pressed signal is connected in the scene file.

const THEME := preload("res://scripts/resources/cp2020_theme.gd")

@onready var _header: Label = get_node_or_null("%Header")
@onready var _flavour_label: Label = get_node_or_null("%FlavourLabel")
@onready var _trace_label: Label = get_node_or_null("%TraceLabel")
@onready var _credits_label: Label = get_node_or_null("%CreditsLabel")
@onready var _loot_label: Label = get_node_or_null("%LootLabel")
@onready var _datafort_label: Label = get_node_or_null("%DatafortLabel")


func _ready() -> void:
	var cause: String = RunState.last_death_cause
	var summary: Dictionary = RunState.last_run_summary

	# Resolve header + flavour text from the death cause.
	var header_text: String = "GAME OVER"
	var flavour_text: String = "The run ended."
	if cause == "Flatlined":
		header_text = "FLATLINED"
		flavour_text = "Your neural link flatlined in the datafort. The Net claims another runner."
	elif cause == "Busted":
		header_text = "BUSTED"
		flavour_text = "NetWatch traced your signal and busted you on jack-out. They confiscated everything."

	if _header:
		_header.text = "◢ %s ◣" % header_text
	if _flavour_label:
		_flavour_label.text = flavour_text

	var trace_val: int = int(summary.get("trace", 0))
	var credits_val: int = int(summary.get("credits", 0))
	var loot_val: int = int(summary.get("loot_count", 0))
	var datafort_val: String = String(summary.get("datafort", ""))
	if datafort_val == "":
		datafort_val = "—"
	if _trace_label:
		_trace_label.text = "Trace reached: %d" % trace_val
	if _credits_label:
		_credits_label.text = "Credits lost: %d eb" % credits_val
	if _loot_label:
		_loot_label.text = "Loot lost: %d program(s)" % loot_val
	if _datafort_label:
		_datafort_label.text = "Datafort: %s" % datafort_val


func _on_new_life_pressed() -> void:
	RunState.start_new_life()
	RunState.clear_run_save()
	get_tree().change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")
