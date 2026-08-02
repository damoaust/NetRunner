class_name CP2020SubnetLoader
extends Node

signal subnet_loaded(new_layout: CP2020DatafortLayout)
signal log_message(text: String)

func load_subnet(file_path: String) -> void:
	if ResourceLoader.exists(file_path):
		log_message.emit("Loading subnet: " + file_path)
		var new_layout = ResourceLoader.load(file_path) as CP2020DatafortLayout
		if new_layout:
			subnet_loaded.emit(new_layout)
			log_message.emit("Subnet successfully initialized.")
	else:
		log_message.emit("ERROR: Subnet path does not exist: " + file_path)
