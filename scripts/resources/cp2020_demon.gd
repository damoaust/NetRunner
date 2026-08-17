class_name DemonNode
extends RezzedProgram

# DemonNode: a rezzed Demon on the net. It is-a RezzedProgram, so it inherits
# auto-follow (trails the runner each turn), integrity-derived-from-STR,
# take_damage, pathfinding, and visibility handling. What it adds over a plain
# rezzed attack program is a set of **subroutines**: duplicated copies of the
# programs the runner loaded into the Demon at the workbench, each with its
# `strength` overridden to the Demon core's STR (the faithful CP2020 rule —
# subroutines use the Demon's STR, not their own).
#
# The runner commands the Demon (1 action) to fire a chosen subroutine; the
# game session dispatches on that subroutine's effect_type to the existing
# rezzed-attack helpers. One DemonNode per installed Demon copy (reuses the
# RezzedProgram `source_program` one-node-per-copy rule).
#
# DemonNodes live in the same `rezzed_program_nodes` array as plain rezzed
# attack programs, so Killer ICE (which scans `ice.rezzed_programs`) targets
# them too. Demons are NOT worms — they are visible and targetable.

# The Demon's commandable subroutines: duplicated from the DemonProgram's
# `assigned_subroutines` at spawn, with each copy's `strength` set to the
# Demon core's STR. Firing a subroutine never mutates the installed copies.
var subroutines: Array[NetProgram] = []

# Populate the subroutine list from a DemonProgram's assigned subroutines.
# Each subroutine is duplicated and STR-overridden to the Demon core's STR
# (faithful "subroutines use the Demon's STR"). Called by the game session
# after spawning the node and before initialize().
func setup_subroutines(demon: DemonProgram) -> void:
	subroutines.clear()
	if demon == null:
		return
	var core_str: int = demon.strength
	for sub in demon.assigned_subroutines:
		if sub == null:
			continue
		var copy: NetProgram = sub.duplicate()
		copy.strength = core_str # Subroutines use the Demon core's STR.
		subroutines.append(copy)

# The subroutine list the command menu iterates (one entry per loaded slot).
func get_commandable_subroutines() -> Array[NetProgram]:
	return subroutines

# Return the subroutine at `index`, or null if out of range.
func get_subroutine(index: int) -> NetProgram:
	if index < 0 or index >= subroutines.size():
		return null
	return subroutines[index]

# Apply the Demon's own visual identity (glyph/color from get_visual()) rather
# than a per-subroutine look. Overrides RezzedProgram.apply_visual_from_program
# to make intent explicit and guard against a null program.
func apply_visual_from_program(p_program: NetProgram = null, p_glyph: String = "◆", p_color: Color = Color.CYAN) -> void:
	var target_program: NetProgram = p_program
	if target_program == null:
		target_program = self.program
		
	if target_program == null:
		return
		
	# Passes up to RezzedProgram's fixed implementation
	super.apply_visual_from_program(target_program, p_glyph, p_color)

# Damage reporting uses the Demon's name (not a subroutine's).
func take_damage(amount: int) -> bool:
	return super.take_damage(amount)
