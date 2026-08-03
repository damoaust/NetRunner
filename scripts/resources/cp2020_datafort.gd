class_name CP2020Datafort
extends Node

# The datafort itself is the adversary: its CPUs grant INT, extra actions per
# turn, and the ability to run resident programs against an intruding
# netrunner. CPUs are authored on CONTROL_NODE tiles. A netrunner crashes
# individual CPUs with the Krash anti-system program (see crash_cpu); a
# crashed CPU contributes no INT / extra actions until it reboots.
#
# The datafort does NOT command the Black ICE / NPC netrunners — those stay
# independent turn-manager adversaries. The datafort only runs its own
# resident programs.

signal message_logged(msg: String)
signal attacked_netrunner(strength: int)
signal cpu_crashed(coord: Vector2i)
signal cpu_rebooted(coord: Vector2i)
signal state_changed

# A single CPU within the datafort.
class Cpu:
	var coord: Vector2i
	var tile: CP2020TileData
	var int_rating: int
	func _init(c: Vector2i, t: CP2020TileData, i: int) -> void:
		coord = c
		tile = t
		int_rating = i

var fort_name: String = "Datafort"
var cpus: Array = []
# Duplicated copies of layout.resident_programs so cached .tres are never mutated.
var resident_programs: Array[NetProgram] = []
var current_layout: CP2020DatafortLayout


func initialize(layout: CP2020DatafortLayout) -> void:
	current_layout = layout
	cpus.clear()
	if layout:
		fort_name = layout.fort_name
		# Default INT per CPU when a tile has no override (cpu_int == 0).
		var default_int: int = layout.cpu if layout.cpu > 0 else 5
		for raw_key in layout.grid_tiles.keys():
			var coord: Vector2i
			if raw_key is String:
				var parts = raw_key.split(",")
				coord = Vector2i(parts[0].to_int(), parts[1].to_int())
			else:
				coord = raw_key
			var tile = layout.get_tile(coord)
			if tile and tile.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE:
				var cpu_int: int = tile.cpu_int if tile.cpu_int > 0 else default_int
				cpus.append(Cpu.new(coord, tile, cpu_int))
		# Duplicate resident programs (avoid mutating cached .tres resources).
		resident_programs.clear()
		for p in layout.resident_programs:
			if p is NetProgram:
				resident_programs.append(p.duplicate())
	message_logged.emit("Datafort '%s' online: %d CPU(s), INT %d, %d action(s)/turn." % [fort_name, cpus.size(), total_int(), actions_per_turn()])


func total_int() -> int:
	var total := 0
	for cpu in cpus:
		if is_instance_valid(cpu.tile) and cpu.tile.cpu_crashed_turns <= 0:
			total += cpu.int_rating
	return total


func active_cpu_count() -> int:
	var count := 0
	for cpu in cpus:
		if is_instance_valid(cpu.tile) and cpu.tile.cpu_crashed_turns <= 0:
			count += 1
	return count


# CP2020 rule: one extra action per two additional active CPUs, plus the base.
func actions_per_turn() -> int:
	return 1 + int(active_cpu_count() / 2)


# Player-facing Krash: opposed 1d10+program.STR vs 1d10+CPU INT. On a hit the
# CPU is crashed for 1D6+1 turns. `target_coord` selects the specific CPU the
# netrunner right-clicked; if it's already crashed, nothing happens.
func crash_cpu(program: NetProgram, target_coord: Vector2i) -> bool:
	var cpu: Cpu = null
	for c in cpus:
		if c.coord == target_coord:
			cpu = c
			break
	if cpu == null or not is_instance_valid(cpu.tile):
		message_logged.emit("No CPU detected at %s.\n" % target_coord)
		return false
	if cpu.tile.cpu_crashed_turns > 0:
		message_logged.emit("CPU at %s is already crashed.\n" % target_coord)
		return false

	var prog_roll = (randi() % 10) + 1 + program.strength
	var cpu_roll = (randi() % 10) + 1 + cpu.int_rating
	message_logged.emit("Roll: you %d (1d10+%d) vs CPU %d (1d10+%d)\n" % [prog_roll, program.strength, cpu_roll, cpu.int_rating])
	if prog_roll > cpu_roll:
		var duration := randi_range(1, 6) + 1
		cpu.tile.cpu_crashed_turns = duration
		message_logged.emit("CPU at %s CRASHED for %d turns. Datafort INT now %d, %d action(s)/turn.\n" % [target_coord, duration, total_int(), actions_per_turn()])
		cpu_crashed.emit(target_coord)
		state_changed.emit()
		return true
	else:
		message_logged.emit("CPU at %s repelled Krash.\n" % target_coord)
		return false


# Turn-manager entry point. Decrements reboot timers, then runs resident
# anti-runner programs up to actions_per_turn(). Programs follow their own
# programming — the datafort only triggers them.
func take_turn(_target_pos: Vector2i, _layout: CP2020DatafortLayout) -> void:
	# 1. Reboot crashed CPUs whose timer has elapsed.
	for cpu in cpus:
		if is_instance_valid(cpu.tile) and cpu.tile.cpu_crashed_turns > 0:
			cpu.tile.cpu_crashed_turns -= 1
			if cpu.tile.cpu_crashed_turns <= 0:
				message_logged.emit("CPU at %s rebooted. Datafort INT now %d.\n" % [cpu.coord, total_int()])
				cpu_rebooted.emit(cpu.coord)
				state_changed.emit()

	# 2. Run resident programs against the runner (up to actions_per_turn).
	var actions := actions_per_turn()
	if actions <= 0 or resident_programs.is_empty() or active_cpu_count() == 0:
		message_logged.emit("Datafort '%s' idle (no active CPUs / programs).\n" % fort_name)
		return

	var attack_programs: Array[NetProgram] = []
	for p in resident_programs:
		if p and p.effect_type == NetProgram.EffectType.DAMAGE_RUNNER:
			attack_programs.append(p)
	if attack_programs.is_empty():
		message_logged.emit("Datafort '%s' has no anti-runner programs loaded.\n" % fort_name)
		return

	for i in range(actions):
		var prog: NetProgram = attack_programs[i % attack_programs.size()]
		message_logged.emit("Datafort '%s' runs %s (STR %d) at the netrunner!\n" % [fort_name, prog.program_name, prog.strength])
		attacked_netrunner.emit(prog.strength)
		state_changed.emit()
		# Pace the turn like ICE movement so the player can follow the log.
		if is_inside_tree():
			await get_tree().create_timer(0.3).timeout

