class_name CP2020WorldNetMap
extends Node2D

signal sub_net_selected(subnet_resource_path: String, target_city: String)

@export var global_hubs: Dictionary = {
	"Night City": { "path": "res://scenes/forts/night_city_subnet.tres", "node_path": "HubButtonsContainer/NightCityButton" },
	"Tokyo": { "path": "res://scenes/forts/tokyo_subnet.tres", "node_path": "HubButtonsContainer/TokyoButton" },
	"London": { "path": "res://scenes/forts/london_subnet.tres", "node_path": "HubButtonsContainer/LondonButton" },
	"NYC/BosWash": { "path": "res://scenes/forts/boswash_subnet.tres", "node_path": "HubButtonsContainer/BosWashButton" }
}

var current_connected_city: String = "Night City"

@onready var location_label: Label = get_node_or_null("HUDOverlay/LocationLabel")

func _ready() -> void:
	setup_hub_buttons()
	update_hud()

func setup_hub_buttons() -> void:
	for city_name in global_hubs.keys():
		var hub_data = global_hubs[city_name]
		var btn = get_node_or_null(hub_data["node_path"]) as BaseButton
		if btn:
			# Connect each button press to select the specific city hub
			if not btn.pressed.is_connected(_on_hub_button_pressed.bind(city_name)):
				btn.pressed.connect(_on_hub_button_pressed.bind(city_name))

func _on_hub_button_pressed(city_name: String) -> void:
	select_hub_city(city_name)

func select_hub_city(city_name: String) -> void:
	if not global_hubs.has(city_name):
		print("ERROR: Unknown global hub city: ", city_name)
		return
		
	var hub_data = global_hubs[city_name]
	var subnet_path = hub_data["path"] as String
	
	print("DEBUG: Routing Long Distance Line (LDL) from %s to %s..." % [current_connected_city, city_name])
	
	calculate_ldl_trace_penalty(current_connected_city, city_name)
	
	current_connected_city = city_name
	update_hud()
	
	# Emit signal so your main game manager knows to load the new subnet resource
	sub_net_selected.emit(subnet_path, city_name)
	RunState.selected_subnet_path = subnet_path
	get_tree().change_scene_to_file("res://scenes/cp2020_gameplay.tscn")

func calculate_ldl_trace_penalty(origin: String, destination: String) -> void:
	if origin == destination:
		return
	print("DEBUG: Executing global grid matrix transition. Trace value updated.")

func update_hud() -> void:
	if location_label:
		location_label.text = "CONNECTED HUB: " + current_connected_city.to_upper()
