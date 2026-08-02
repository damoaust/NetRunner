extends Control

# All selectable cyberdecks (assigned in the Inspector).
@export var available_decks: Array[Cyberdeck] = []

# The complete library of programs the runner can choose to load.
@export var available_programs: Array[NetProgram] = []

# Currently active deck selected from the dropdown.
var active_deck: Cyberdeck

@onready var deck_selector: OptionButton = $MarginContainer/VBoxRoot/HBoxContainer/DeckStatsColumn/DeckSelector
@onready var model_label: Label = $MarginContainer/VBoxRoot/HBoxContainer/DeckStatsColumn/ModelLabel
@onready var speed_label: Label = $MarginContainer/VBoxRoot/HBoxContainer/DeckStatsColumn/SpeedLabel
@onready var mu_label: Label = $MarginContainer/VBoxRoot/HBoxContainer/DeckStatsColumn/MuLabel
@onready var mu_bar: ProgressBar = $MarginContainer/VBoxRoot/HBoxContainer/DeckStatsColumn/MUBar
@onready var strength_label: Label = $MarginContainer/VBoxRoot/HBoxContainer/DeckStatsColumn/StrengthLabel
@onready var interface_label: Label = $MarginContainer/VBoxRoot/HBoxContainer/DeckStatsColumn/InterfaceLabel
@onready var loaded_list: ItemList = $MarginContainer/VBoxRoot/HBoxContainer/LoadedProgramsColumn/LoadedList
@onready var library_list: ItemList = $MarginContainer/VBoxRoot/HBoxContainer/ProgramLibraryColumn/LibraryList

# Human-readable tags for each program effect type (for the library display).
const EFFECT_TAGS: Dictionary = {
	NetProgram.EffectType.BYPASS_GATE: "Intrusion",
	NetProgram.EffectType.BREACH_WALL: "Breach",
	NetProgram.EffectType.DEREZ_ICE: "Anti-ICE",
	NetProgram.EffectType.DAMAGE_RUNNER: "Anti-Personnel",
	NetProgram.EffectType.REVEAL_NODES: "Reveal",
	NetProgram.EffectType.MODIFY_MU: "Utility",
	NetProgram.EffectType.SHIELD: "Defense",
}

func _ready() -> void:
	deck_selector.clear()
	for deck in available_decks:
		deck_selector.add_item(deck.deck_name)
	if not available_decks.is_empty():
		active_deck = available_decks[0]
		deck_selector.select(0)
	update_deck_ui()

func update_deck_ui() -> void:
	if not active_deck:
		return
	model_label.text = "Model: " + active_deck.deck_name
	speed_label.text = "Speed Bonus: +" + str(active_deck.speed_bonus)
	var used_mu := active_deck.get_used_mu()
	mu_label.text = "Memory Units (MU): %d / %d" % [used_mu, active_deck.max_mu]
	mu_bar.max_value = active_deck.max_mu
	mu_bar.value = used_mu
	strength_label.text = "Data Wall STR: " + str(active_deck.data_wall_strength)
	interface_label.text = "Interface Rank: 6"
	_refresh_loaded()
	_refresh_library()

func _refresh_loaded() -> void:
	loaded_list.clear()
	for prog in active_deck.installed_programs:
		if prog:
			var tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
			loaded_list.add_item("%s  [%s]  (%d MU)" % [prog.program_name, tag, prog.memory_cost])

func _refresh_library() -> void:
	library_list.clear()
	for prog in available_programs:
		if not prog:
			library_list.add_item("(missing program)")
			continue
		var tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
		var loaded := _is_loaded(prog)
		var suffix := "  [LOADED]" if loaded else ""
		library_list.add_item("%s  [%s]  (%d MU)%s" % [prog.program_name, tag, prog.memory_cost, suffix])

func _is_loaded(prog: NetProgram) -> bool:
	for loaded in active_deck.installed_programs:
		if loaded == prog:
			return true
	return false

func _on_deck_selector_item_selected(index: int) -> void:
	if index >= 0 and index < available_decks.size():
		active_deck = available_decks[index]
		update_deck_ui()

func _on_library_item_selected(index: int) -> void:
	if index < 0 or index >= available_programs.size():
		return
	var prog := available_programs[index] as NetProgram
	if not prog or _is_loaded(prog):
		return
	if active_deck.get_used_mu() + prog.memory_cost > active_deck.max_mu:
		print("MEMORY FULL: Cannot load %s (%d MU). Only %d MU free." % [prog.program_name, prog.memory_cost, active_deck.max_mu - active_deck.get_used_mu()])
		return
	active_deck.installed_programs.append(prog)
	update_deck_ui()

func _on_loaded_item_selected(index: int) -> void:
	if index < 0 or index >= active_deck.installed_programs.size():
		return
	var prog := active_deck.installed_programs[index] as NetProgram
	if prog:
		active_deck.installed_programs.erase(prog)
		update_deck_ui()

func _on_button_pressed() -> void:
	if active_deck:
		print("Initiating neural link with %s... Jacking into the Net!" % active_deck.deck_name)
		RunState.selected_deck = active_deck
		get_tree().change_scene_to_file("res://scenes/ui/cp2020_world_net_map.tscn")
	else:
		print("Error: No active deck selected for neural link!")
