extends Control

# An array of cyberdeck resources you can drag and drop right in the Inspector!
@export var available_decks: Array[Cyberdeck] = []

# Currently active deck selected from the list
var active_deck: Cyberdeck

# Grab references to our visual UI nodes
@onready var stats_column = $MarginContainer/HBoxContainer/DeckStatsColumn
@onready var program_list = $MarginContainer/HBoxContainer/ProgramListColumn/ItemList

# Optional: Add an OptionButton in your scene tree for deck selection and reference it here
# @onready var deck_selector: OptionButton = $MarginContainer/HBoxContainer/DeckStatsColumn/DeckSelector

func _ready() -> void:
	if available_decks.is_empty():
		print("WARNING: No cyberdecks assigned in the available_decks array!")
	else:
		# Default to the first deck in the list
		active_deck = available_decks[0]
		update_deck_ui()

func update_deck_ui() -> void:
	if not active_deck:
		return
		
	# Safe child lookups based on your node tree size
	var model_label = stats_column.get_child(1) as Label if stats_column.get_child_count() > 1 else null
	var speed_label = stats_column.get_child(2) as Label if stats_column.get_child_count() > 2 else null
	var mu_label = stats_column.get_child(3) as Label if stats_column.get_child_count() > 3 else null
	var strength_label = stats_column.get_child(4) as Label if stats_column.get_child_count() > 4 else null
	var interface_label = stats_column.get_child(5) as Label if stats_column.get_child_count() > 5 else null
	
	if model_label:
		model_label.text = "Model: " + active_deck.deck_name
	if speed_label:
		speed_label.text = "Speed Bonus: +" + str(active_deck.speed_bonus)
	
	if mu_label:
		var used_mu = active_deck.get_used_mu()
		mu_label.text = "Memory Units (MU): %d / %d" % [used_mu, active_deck.max_mu]
		
	if strength_label:
		strength_label.text = "Data Wall STR: " + str(active_deck.data_wall_strength)
		
	if interface_label:
		interface_label.text = "Interface Rank: 6"
	
	program_list.clear()
	for program in active_deck.installed_programs:
		if program:
			var item_text = "%s (%d MU)" % [program.program_name, program.memory_cost]
			program_list.add_item(item_text)

# Hook this up to an OptionButton if you add one to your scene
func _on_deck_selector_item_selected(index: int) -> void:
	if index >= 0 and index < available_decks.size():
		active_deck = available_decks[index]
		update_deck_ui()

func _on_button_pressed() -> void:
	if active_deck:
		print("Initiating neural link with %s... Jacking into the Net!" % active_deck.deck_name)
		# Pass active_deck data to your game session script before changing scenes.
	else:
		print("Error: No active deck selected for neural link!")
