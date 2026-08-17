class_name CP2020Dice
extends RefCounted

# CP2020 opposed roll: attacker STR+1D10 vs defender STR+1D10.
# Ties go to the DEFENDER (the attacker must strictly exceed the defender).
# Returns a Dictionary with: atk_roll, def_roll, margin, attacker_wins, tie.
static func roll_opposed(atk_str: int, def_str: int) -> Dictionary:
	var atk_roll := randi_range(1, 10) + atk_str
	var def_roll := randi_range(1, 10) + def_str
	return {
		"atk_roll": atk_roll,
		"def_roll": def_roll,
		"margin": atk_roll - def_roll,
		"attacker_wins": atk_roll > def_roll,
		"tie": atk_roll == def_roll,
	}