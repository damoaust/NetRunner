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
# Anti-system (CRASH_CPU) resident program targeting the runner's cyberdeck
# (not its health). Wired in cp2020_game_session.gd to netrunner.crash_deck.
signal attacked_runner_deck(strength: int)
signal cpu_crashed(coord: Vector2i)
signal cpu_rebooted(coord: Vector2i)
signal state_changed

# A single CPU within the datafort. Per CP2020 PnP rules each CPU contributes
# a flat 3 INT, 1 action/turn, and 10 MU of storage capacity — there are no
# per-CPU INT overrides.
class Cpu:
	var coord: Vector2i
	var tile: CP2020TileData
	var floor_index: int = 0
	func _init(c: Vector2i, t: CP2020TileData, f: int = 0) -> void:
		coord = c
		tile = t
		floor_index = f

const INT_PER_CPU := 3
const ACTIONS_PER_CPU := 1
const MU_PER_CPU := 10

var fort_name: String = "Datafort"
var cpus: Array = []
# Duplicated copies of layout.resident_programs so cached .tres are never mutated.
var resident_programs: Array[NetProgram] = []
var current_layout: CP2020DatafortLayout

# Program sight radius (separate from the runner's sight_range). Resident
# programs only fire when at least one active CPU has line of sight to the
# netrunner within this range. Defaults to 10.
@export var sight_range: int = 10

# Tracks the previous turn's LoS state so transition messages log only on
# the seen<->lost change.
var _had_los: bool = false


func initialize(layout: CP2020DatafortLayout) -> void:
	current_layout = layout
	cpus.clear()
	if layout:
		fort_name = layout.fort_name
		# Collect CPUs across ALL floors; each CPU remembers its home floor so
		# sight gating / line_of_sight can use the correct floor.
		for f in range(layout.get_floor_count()):
			for raw_key in layout.get_floor_tiles(f).keys():
				var coord: Vector2i
				if raw_key is String:
					var parts = raw_key.split(",")
					coord = Vector2i(parts[0].to_int(), parts[1].to_int())
				else:
					coord = raw_key
				var tile = layout.get_tile(coord, f)
				if tile and tile.tile_type == CP2020DatafortLayout.TileType.CONTROL_NODE:
					cpus.append(Cpu.new(coord, tile, f))
		# Duplicate resident programs (avoid mutating cached .tres resources).
		resident_programs.clear()
		for p in layout.resident_programs:
			if p is NetProgram:
				resident_programs.append(p.duplicate())
	message_logged.emit("Datafort '%s' online: %d CPU(s), INT %d, %d action(s)/turn, %d MU." % [fort_name, cpus.size(), total_int(), actions_per_turn(), total_mu()])


func total_int() -> int:
	return INT_PER_CPU * active_cpu_count()


func active_cpu_count() -> int:
	var count := 0
	for cpu in cpus:
		if is_instance_valid(cpu.tile) and cpu.tile.cpu_crashed_turns <= 0:
			count += 1
	return count


# CP2020 rule: 1 action per turn per active CPU.
func actions_per_turn() -> int:
	return ACTIONS_PER_CPU * active_cpu_count()


# Total MU capacity: 10 per active CPU. Crashed CPUs contribute no MU.
func total_mu() -> int:
	return MU_PER_CPU * active_cpu_count()


# MU used by resident programs (sum of memory_cost).
func used_mu() -> int:
	var total := 0
	for p in resident_programs:
		if p is NetProgram:
			total += p.memory_cost
	return total


func available_mu() -> int:
	return total_mu() - used_mu()


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

	var system_int := total_int()
	var prog_roll = (randi() % 10) + 1 + program.strength
	var cpu_roll = (randi() % 10) + 1 + system_int
	message_logged.emit("Roll: you %d (1d10+%d) vs System %d (1d10+%d)\n" % [prog_roll, program.strength, cpu_roll, system_int])
	if prog_roll > cpu_roll:
		var duration := randi_range(1, 6) + 1
		cpu.tile.cpu_crashed_turns = duration
		message_logged.emit("CPU at %s CRASHED for %d turns. Datafort INT now %d, %d action(s)/turn, %d MU.\n" % [target_coord, duration, total_int(), actions_per_turn(), total_mu()])
		cpu_crashed.emit(target_coord)
		state_changed.emit()
		return true
	else:
		message_logged.emit("CPU at %s repelled Krash.\n" % target_coord)
		return false


# Turn-manager entry point. Decrements reboot timers (unconditional — CPUs
# reboot whether or not the fort sees the runner), then runs resident
# anti-runner programs up to actions_per_turn() — but only when at least one
# active CPU has line of sight to the netrunner within `sight_range`.
func take_turn(target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	# 1. Reboot crashed CPUs whose timer has elapsed (unconditional).
	for cpu in cpus:
		if is_instance_valid(cpu.tile) and cpu.tile.cpu_crashed_turns > 0:
			cpu.tile.cpu_crashed_turns -= 1
			if cpu.tile.cpu_crashed_turns <= 0:
				message_logged.emit("CPU at %s rebooted. Datafort INT now %d, %d MU.\n" % [cpu.coord, total_int(), total_mu()])
				cpu_rebooted.emit(cpu.coord)
				state_changed.emit()

	# 2. Sight gating: resident programs only fire when at least one active
	# CPU has line of sight to the netrunner within `sight_range`.
	var can_see := false
	for cpu in cpus:
		if is_instance_valid(cpu.tile) and cpu.tile.cpu_crashed_turns <= 0 \
				and layout.line_of_sight(cpu.coord, target_pos, sight_range, cpu.floor_index):
			can_see = true
			break
	if not can_see:
		if _had_los:
			message_logged.emit("Datafort '%s' loses sight of the netrunner — resident programs idle.\n" % fort_name)
		_had_los = false
		return
	if not _had_los:
		message_logged.emit("Datafort '%s' reacquires the netrunner — engaging!\n" % fort_name)
	_had_los = true

	# 3. Run resident programs against the runner (up to actions_per_turn).
	var actions := actions_per_turn()
	if actions <= 0 or resident_programs.is_empty() or active_cpu_count() == 0:
		message_logged.emit("Datafort '%s' idle (no active CPUs / programs).\n" % fort_name)
		return

	var attack_programs: Array[NetProgram] = []
	var crash_programs: Array[NetProgram] = []
	for p in resident_programs:
		if not p:
			continue
		if p.effect_type == NetProgram.EffectType.DAMAGE_RUNNER:
			attack_programs.append(p)
		elif p.effect_type == NetProgram.EffectType.CRASH_CPU:
			# Anti-system resident program: crashes the runner's cyberdeck
			# (mirrors the runner's Krash crashing a datafort CPU).
			crash_programs.append(p)
	if attack_programs.is_empty() and crash_programs.is_empty():
		message_logged.emit("Datafort '%s' has no anti-runner programs loaded.\n" % fort_name)
		return

	for i in range(actions):
		# Alternate between damage and anti-system attacks when both are
		# loaded; each action runs exactly one program. Indexing by i keeps
		# the per-action cadence stable across turns.
		var prog: NetProgram = null
		if not attack_programs.is_empty():
			prog = attack_programs[i % attack_programs.size()]
			message_logged.emit("Datafort '%s' runs %s (STR %d) at the netrunner!\n" % [fort_name, prog.program_name, prog.strength])
			attacked_netrunner.emit(prog.strength)
		else:
			prog = crash_programs[i % crash_programs.size()]
			message_logged.emit("Datafort '%s' runs %s (STR %d) — anti-system attack on your cyberdeck!\n" % [fort_name, prog.program_name, prog.strength])
			attacked_runner_deck.emit(prog.strength)
		state_changed.emit()
		# Pace the turn like ICE movement so the player can follow the log.
		if is_inside_tree():
			await get_tree().create_timer(0.3).timeout
		# The scene may have been torn down during the await (e.g. a prior
		# action flatlined the netrunner and the deferred GameOver scene
		# swap completed). Bail before the next action attacks a freed
		# runner / session.
		if not is_inside_tree():
			return
