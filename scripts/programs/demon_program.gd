class_name DemonProgram
extends NetProgram

# Demon: a CP2020 program shell that carries several other programs as
# subroutines (Imp=2, Afreet=3, Succubus=4, Balron=5). The runner loads
# subroutines into the Demon at the workbench (deck-prep), rezzes the Demon
# onto the net as a single node, then commands it to fire any loaded
# subroutine. Each subroutine executes its original effect but uses the
# Demon core's `strength` (not the subroutine's own) — the faithful CP2020
# multi-program-in-one tradeoff: one rezzed node, multiple effects, all
# capped at the Demon's STR.
#
# Subroutines are restricted to the executable combat/utility effect types
# the game already supports firing from a rezzed node (see ALLOWED_SUB_EFFECTS)
# so Demon commands map cleanly onto the existing rezzed-attack dispatch.

# Effect types a Demon may carry as subroutines. Kept in sync with the
# game session's rezzed-attack dispatch (DEREZ_ICE / DAMAGE_RUNNER / CRASH_CPU
# / SHIELD / ARMOR).
const ALLOWED_SUB_EFFECTS: Array[int] = [
	NetProgram.EffectType.DEREZ_ICE,
	NetProgram.EffectType.DAMAGE_RUNNER,
	NetProgram.EffectType.CRASH_CPU,
	NetProgram.EffectType.SHIELD,
	NetProgram.EffectType.ARMOR,
]

# Demon level: 1=Imp, 2=Afreet, 3=Succubus, 4=Balron. Purely descriptive —
# `max_subroutines` is what actually gates slot count.
@export var demon_level: int = 1

# Number of subroutine slots this Demon shell can carry (2/3/4/5 by level).
@export var max_subroutines: int = 2

# The programs loaded into the Demon at the workbench. Empty by default —
# the runner fills these via the "Configure Subroutines" workbench flow.
# These are references to installed-program copies (read for effect_type +
# STR-override at spawn); the Demon node duplicates them when rezzed.
@export var assigned_subroutines: Array[NetProgram] = []

# True if `prog` is a valid subroutine for this Demon: non-null, an allowed
# effect type, and the Demon still has a free slot.
func is_valid_subroutine(prog: NetProgram) -> bool:
	if prog == null:
		return false
	if prog.effect_type not in ALLOWED_SUB_EFFECTS:
		return false
	if prog is DemonProgram:
		return false # Demons cannot nest other Demons.
	return assigned_subroutines.size() < max_subroutines

# Convenience: how many slots are still open.
func free_slots() -> int:
	return max(0, max_subroutines - assigned_subroutines.size())

# Demons are never fired straight from the deck — they must be rezzed onto
# the net first. Guard the base dispatch with a clear message.
func execute_runner_action(session: CP2020GameSession, _target_coord: Vector2i) -> bool:
	session.log_to_terminal("Demons must be rezzed onto the net before they can act.\n")
	return false