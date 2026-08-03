class_name Cyberdeck
extends Resource

@export var deck_name: String = "Kendachi Cyberdeck"
@export var max_mu: int = 20
@export var speed_bonus: int = 2
@export var data_wall_strength: int = 6 # Added Data Wall Strength property
@export var interface_rank: int = 6 # Netrunner's interface skill when using this deck
@export var installed_programs: Array[NetProgram] = []

func get_used_mu() -> int:
	var total = 0
	for prog in installed_programs:
		if prog:
			total += prog.memory_cost
	return total
