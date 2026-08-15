class_name NetrunnerCharacter
extends Resource

# A playable netrunner character: identity (callsign/role/portrait/flavor) plus
# the CP2020 meat-space stat block that drives gameplay. Authored as .tres files
# in data/ and selected at the workbench; the chosen character is equipped into
# RunState and applied to the CP2020Netrunner node at jack-in by the game session.
#
# Stats wired into gameplay:
#   - reflex:        initiative (1D10 + REF + deck speed)
#   - intelligence:  meat-space INT; anti-personnel hits reduce current INT
#   - body:          Death Save + Stun save bonus
#   - max_health:    netrunner HP
#   - sight_range:   fog-of-war vision radius
#   - luck:          stored + displayed; not yet wired into combat (future)
# interface_rank is NOT here — it comes from the equipped cyberdeck (deck
# software level), separate from the runner's meat-space intelligence.

@export var character_name: String = ""
@export var callsign: String = "SHADOW"
@export var role: String = "NETRUNNER"
@export_multiline var description: String = ""

@export var reflex: int = 8
@export var intelligence: int = 8
@export var body: int = 8
@export var luck: int = 6
@export var max_health: int = 20
@export var sight_range: int = 20

@export var portrait_texture: Texture2D = null