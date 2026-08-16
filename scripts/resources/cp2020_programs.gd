class_name NetProgram
extends Resource

enum ProgramType {
	INTRUSION,       # Breaches Datawalls (e.g., Hammer, Jackhammer)[cite: 16]
	DECRYPTION,      # Cracks Code Gates[cite: 16]
	DETECTION,       # Reveals hidden nodes / ICE[cite: 16]
	ANTI_PROGRAM,    # Destroys active ICE (e.g., Killer)[cite: 16]
	ANTI_PERSONNEL,  # Attacks runner directly (e.g., Hellhound, Flatline)[cite: 16]
	ANTI_SYSTEM,     # Crashes CPUs / erases memory[cite: 16]
	UTILITY,         # Cloak, Stealth, Speed boosters[cite: 16]
	ICE,             # Stationary defense programs running on nodes[cite: 16]
	Protection       # Shield
}

enum EffectType { 
	BYPASS_GATE,     # Cracks node security DV[cite: 16]
	BREACH_WALL,     # Hammers down datawalls
	DEREZ_ICE,       # Destroys target ICE program[cite: 16]
	DAMAGE_RUNNER,   # Black ICE attack on runner health[cite: 16]
	REVEAL_NODES,    # Maps connected graph nodes[cite: 16]
	MODIFY_MU,       # Modifies deck memory or speed[cite: 16]
	SHIELD,          # Protection program: recharges netrunner shield/armor (reduces ICE damage)
	CRASH_CPU,       # Anti-system: crashes a datafort CPU for 1D6+1 turns (Krash)[cite: 16]
	ARMOR,           # Defense program: absorbs damage point-for-point (Armor STR subtracts from incoming rolled damage; remainder hits HP).
	WORM,            # Stealth opener: slips behind data walls/code gates, opens from the inside over 2 turns. No alert.
	DETECTION,       # Detection/alarm: Watchdog detects intruders via LoS and trips an alarm activating all attack ICE. As a netrunner utility, deploys a tripwire beacon that alerts when enemies approach.
	INVISIBILITY,     # Stealth cloak: overlays a false signal on the runner's cybermodem trace. While active, each dormant adversary's first LoS detection is gated by an opposed roll (1D10+cloak.STR vs 1D10+seeker.STR); ties/holds -> seeker ignores you, seeker wins -> cloak pierced & adversary activates.
	DEMON,            # Demon: a program shell carrying N other programs as subroutines (Imp=2/Afreet=3/Succubus=4/Balron=5). Rezzed as one node; the runner commands it to fire any loaded subroutine, each using the Demon core's STR (not the subroutine's own). Faithful CP2020 multi-program-in-one tradeoff.
}

# Attack/defense visual config per effect type. Each entry describes the beam
# rendered when a program of that effect_type fires. Adding/customizing a
# program's attack visual is a one-file change here.
const ATTACK_VISUALS: Dictionary = {
	EffectType.DEREZ_ICE: {"color": Color(1.0, 0.15, 0.15), "width": 3.0, "duration": 0.5, "style": "beam"},
	EffectType.DAMAGE_RUNNER: {"color": Color(1.0, 0.3, 0.1), "width": 3.0, "duration": 0.5, "style": "beam"},
	EffectType.CRASH_CPU: {"color": Color(1.0, 0.5, 0.0), "width": 3.0, "duration": 0.5, "style": "beam"},
	EffectType.DEMON: {"color": Color(0.80, 0.25, 0.90), "width": 3.5, "duration": 0.5, "style": "beam"},
}

# Per-effect-type default on-map visual identity (glyph + color). Renderers
# (rezzed program nodes, Black ICE nodes, board overlay) resolve a program's
# look via get_visual(): a program's own `glyph`/`color` override these when
# set, so every program can carry a distinct visual stored in its .tres
# without forcing designers to author one. Glyphs use Unicode blocks already
# confirmed rendering in the default font (geometric shapes / misc symbols).
const DEFAULT_VISUALS: Dictionary = {
	EffectType.BYPASS_GATE: {"glyph": "◇", "color": Color(0.30, 0.90, 0.45, 1.0)},
	EffectType.BREACH_WALL: {"glyph": "▦", "color": Color(1.00, 0.60, 0.20, 1.0)},
	EffectType.DEREZ_ICE: {"glyph": "⚔", "color": Color(1.00, 0.20, 0.20, 1.0)},
	EffectType.DAMAGE_RUNNER: {"glyph": "☠", "color": Color(0.90, 0.15, 0.25, 1.0)},
	EffectType.REVEAL_NODES: {"glyph": "◉", "color": Color(0.30, 0.80, 1.00, 1.0)},
	EffectType.MODIFY_MU: {"glyph": "⚙", "color": Color(0.70, 0.70, 0.75, 1.0)},
	EffectType.SHIELD: {"glyph": "◈", "color": Color(0.30, 0.60, 1.00, 1.0)},
	EffectType.CRASH_CPU: {"glyph": "⚡", "color": Color(1.00, 0.50, 0.00, 1.0)},
	EffectType.ARMOR: {"glyph": "▣", "color": Color(0.60, 0.70, 0.80, 1.0)},
	EffectType.WORM: {"glyph": "◐", "color": Color(0.40, 0.90, 0.30, 1.0)},
	EffectType.DETECTION: {"glyph": "◎", "color": Color(1.00, 0.80, 0.20, 1.0)},
	EffectType.INVISIBILITY: {"glyph": "◌", "color": Color(0.80, 0.40, 1.00, 1.0)},
	EffectType.DEMON: {"glyph": "⚝", "color": Color(0.80, 0.25, 0.90, 1.0)},
}

@export var program_name: String = "Hammer"
@export var type: ProgramType = ProgramType.INTRUSION
@export var effect_type: EffectType = EffectType.BREACH_WALL
@export var memory_cost: int = 2 # MU required to equip
@export var strength: int = 4   # Added to attack/defense rolls[cite: 16]
@export var price: int = 600    # Cost in Eurodollars
@export var icon: Texture2D     # UI Icon (workbench list rows)[cite: 16]
@export var description: String = "" # One-line summary shown in the workbench detail card
# On-map visual identity for this program. `glyph` is the character drawn on
# the grid (rezzed program / Black ICE node + board overlay); `color` is its
# tint. Leave both at their defaults (empty glyph / alpha-0 color) to fall
# back to the per-effect-type DEFAULT_VISUALS — every program gets a distinct
# look with no authoring. Set them in a .tres to give a program a custom icon.
@export var glyph: String = ""
@export var color: Color = Color(0, 0, 0, 0)
# Per-program nudge to centre the glyph in its tile. Different Unicode glyphs
# render at different positions within their text box (baseline / em-square
# fill vary by block), so the node's global label_visual_offset can't centre
# them all. Designers set this in a .tres to fine-tune glyphs that sit off
# (e.g. ⚔, ⚡ which sit higher/lower than ◆). Default ZERO = global offset only.
@export var glyph_offset: Vector2 = Vector2.ZERO
# When true (default) the node auto-centres the glyph via TextServer bitmap metrics.
# When false the auto-offset is discarded and the designer positions the glyph
# entirely via `glyph_offset` — useful for glyphs whose metrics produce a bad
# auto-centre, or when the font lacks the glyph entirely. Toggle in the Inspector.
@export var glyph_auto_center: bool = true
# Optional on-map sprite (replaces the glyph on BlackICE / rezzed program
# nodes when set). Assign a PNG spritesheet in the Inspector. `sprite_frame`
# selects which square frame to display; `sprite_frame_size` is the frame
# dimension in pixels (most sheets use 128). Leave sprite_texture null to
# fall back to the glyph system.
@export var sprite_texture: Texture2D
@export var sprite_frame: int = 0
@export var sprite_frame_size: int = 128
# Per-program pixel nudge for the on-map sprite, applied on top of the
# Sprite2D's automatic tile-centring. Use this in the Inspector when a
# sprite's art sits off-centre within its frame (mirrors `glyph_offset`).
# In screen pixels: 1.0 = one pixel on the grid (cell_size = 40).
@export var sprite_offset: Vector2 = Vector2.ZERO
# Per-hit damage dice for attack programs (Black ICE). 0 = use flat `strength`
# as damage (existing behaviour for all current programs). >0 = roll
# 1D{damage_dice} per hit instead. e.g. Sword sets 6 to roll 1D6 per hit.
# `damage_dice_count` (default 1) multiplies the dice: Hellhound sets
# damage_dice=10 + damage_dice_count=2 to roll 2D10 per hit.
@export var damage_dice: int = 0
@export var damage_dice_count: int = 1
# Path to the original .tres this program was duplicated from. Used by run-state
# persistence to reconstruct owned programs after app restart.
@export var source_path: String = ""

# ─────────────────────────────────────────────────────────────────────────────
# Program behavior (virtual). Subclasses override these to define program-
# specific logic; the base provides default hunt-attack ICE behavior and
# effect-dispatch runner behavior. BlackICE and the game session delegate to
# these instead of branching on effect_type.
# ─────────────────────────────────────────────────────────────────────────────

# Default ICE turn behavior (hunt-attack). Runs AFTER line-of-sight gating is
# already done by the BlackICE wrapper — LoS to `target_pos` is assumed this
# turn. Subclasses override to define specialized ICE behavior (e.g. trace-only,
# ranged, or stationary programs). This is a coroutine (it awaits a Node method).
func take_ice_turn(ice: BlackIce, target_pos: Vector2i, layout: CP2020DatafortLayout) -> void:
	# DEREZ_ICE (Killer) is a stationary anti-program sentry: it does NOT
	# pursue or attack the netrunner. Instead it scans for Worm-active tiles
	# within line of sight and, if one is found, emits attacked_program so the
	# game session resolves an opposed roll (Killer STR + 1D10 vs Worm
	# integrity + 1D10). Only the Killer can deal damage on a win — Worms are
	# passive defenders. No movement, no activation/LoS-to-runner gating.
	if effect_type == NetProgram.EffectType.DEREZ_ICE:
		_take_killer_turn(ice, layout)
		return
	# First-activation handling. Tracing-type activation (Hellhound/Flatline
	# must accumulate a trace before attacking) is deferred to program-specific
	# subclasses — no such subclasses exist yet, so all ICE attacks on LoS.
	if not ice._activated:
		ice._activated = true
	# State transition: idle → pursue.
	if ice.current_state == BlackIce.State.IDLE:
		ice.current_state = BlackIce.State.PURSUE
		ice.emit_log("WARNING: %s activated and is hunting!" % program_name)
	if ice.current_state != BlackIce.State.PURSUE:
		return
	ice.refresh_pathfinding(layout)
	# ICE action economy mirrors the netrunner: up to `program.strength`
	# movement steps per turn (CP2020: ICE moves at STR speed), plus one
	# attack action delivered when the ICE reaches the runner's tile (the
	# attack does not consume movement). Stationary ICE (e.g. Watchdog)
	# override take_ice_turn and never move.
	var movement_remaining: int = ice.program.strength
	while movement_remaining > 0:
		var path = ice.astar_grid.get_id_path(ice.current_position, target_pos)
		if path.size() > 1:
			var next_step = path[1]
			if next_step == target_pos:
				match effect_type:
					NetProgram.EffectType.DEREZ_ICE:
						# Unreachable: DEREZ_ICE branches to _take_killer_turn
						# above and never enters the pursue loop. Kept as a
						# safety no-op.
						return
					_:
						# Anti-personnel: emit the program's STR for the
						# interface defense roll. The payload damage is
						# rolled inside apply_damage AFTER the defense roll
						# resolves (CP2020 RAW).
						ice.emit_log("CRITICAL: %s attacks Netrunner (STR %d)!" % [program_name, strength])
						ice.emit_attack_netrunner(strength)
				return
			else:
				ice.current_position = next_step
				await ice.move_to_step(next_step)
				movement_remaining -= 1
		else:
			return

# Stationary Killer (DEREZ_ICE) turn: scan for rezzed attack programs within
# line of sight of this ICE's position on the same floor. If one is found,
# emit attacked_program so the game session resolves the opposed roll. The
# Killer does not move and does not target the netrunner. Worms are stealth
# code breakers — invisible to ICE and never targeted. One attack per turn
# (first rezzed program in LoS wins).
func _take_killer_turn(ice: BlackIce, layout: CP2020DatafortLayout) -> void:
	for rez in ice.rezzed_programs:
		if not is_instance_valid(rez):
			continue
		if rez.home_floor != ice.home_floor:
			continue
		if rez.current_integrity <= 0:
			continue
		if not ice.has_los_to(rez.current_position, layout):
			continue
		ice.emit_log("%s spots a rezzed program '%s' at %s — executing anti-program attack!" % [program_name, rez.program.program_name, rez.current_position])
		ice.emit_attack_program(strength, rez.current_position)
		return
	# No rezzed program in LoS — hold position silently.

# Default netrunner-side program behavior. Dispatches to the game session's
# private execute_* helpers based on `effect_type`. Returns `true` if the
# action was performed (consume an action), `false` if it should NOT consume
# an action (e.g. not implemented / invalid). Subclasses override to define
# custom runner-side logic.
func execute_runner_action(session: CP2020GameSession, target_coord: Vector2i) -> bool:
	match effect_type:
		NetProgram.EffectType.BYPASS_GATE:
			session._execute_decryption(self, target_coord)
			return true
		NetProgram.EffectType.BREACH_WALL:
			session._execute_wall_breach(self, target_coord)
			return true
		NetProgram.EffectType.DEREZ_ICE:
			session._execute_ice_attack(self, target_coord)
			return true
		NetProgram.EffectType.SHIELD:
			session._execute_shield(self)
			return true
		NetProgram.EffectType.WORM:
			session._execute_worm(self, target_coord)
			return true
		NetProgram.EffectType.DETECTION:
			session._execute_detection(self, target_coord)
			return true
		NetProgram.EffectType.INVISIBILITY:
			return session._execute_invisibility(self)
		NetProgram.EffectType.REVEAL_NODES:
			# Default REVEAL_NODES behavior is a Sensor-style radius sweep
			# (STR = radius). Probe (single-target) overrides this method.
			session._execute_sensor(self, target_coord)
			return true
		NetProgram.EffectType.MODIFY_MU:
			# Default MODIFY_MU behavior is a Toolbox-style MU ceiling boost
			# (STR = bonus MU). Speed (initiative boost) overrides this method.
			return session._execute_toolbox(self)
		NetProgram.EffectType.DEMON:
			# Demons are rezzed onto the net and commanded via the rezzed-program
			# menu — they are never fired straight from the deck.
			session.log_to_terminal("Demons must be rezzed onto the net before they can act.\n")
			return false
		_:
			session.log_to_terminal("Program effect not implemented yet.\n")
			return false

# Roll per-hit damage for this program. Flat `strength` when `damage_dice <= 0`
# (legacy default), otherwise roll `damage_dice_count` × 1D{damage_dice}.
# e.g. Sword (damage_dice=6, count=1) → 1D6; Hellhound (10, 2) → 2D10.
func _roll_damage() -> int:
	if damage_dice <= 0:
		return strength
	var total := 0
	for _i in range(max(1, damage_dice_count)):
		total += randi_range(1, damage_dice)
	return total

# Returns the visual config for this program's effect_type, or a default red beam.
func get_attack_visual() -> Dictionary:
	if ATTACK_VISUALS.has(effect_type):
		return ATTACK_VISUALS[effect_type]
	return {"color": Color(1.0, 0.2, 0.2), "width": 3.0, "duration": 0.5, "style": "beam"}

# Resolves this program's on-map visual identity: {"glyph": String, "color":
# Color}. A program's own `glyph` (non-empty) / `color` (alpha > 0) override
# the per-effect-type DEFAULT_VISUALS, so a custom look can be authored per
# .tres; otherwise every program gets a distinct-by-effect-type default.
func get_visual() -> Dictionary:
	var g := glyph
	var c := color
	if g.is_empty() or c.a == 0.0:
		var def: Dictionary = DEFAULT_VISUALS.get(effect_type, {})
		if g.is_empty():
			g = def.get("glyph", "◆")
		if c.a == 0.0:
			c = def.get("color", Color.CYAN)
	return {"glyph": g, "color": c}

# Returns the on-map sprite texture if one is assigned, else null (caller
# falls back to the glyph system). The caller (BlackICE / RezzedProgram) uses
# `sprite_frame` + `sprite_frame_size` to extract the correct frame as an
# AtlasTexture at runtime.
func get_sprite() -> Texture2D:
	return sprite_texture

# Auto-centres a glyph within its tile by measuring the glyph's actual bitmap
# metrics via the TextServer. Returns the offset to add to a Label's position
# (on top of the base -cell_size/2 centre) so the glyph bitmap sits centred.
# Returns Vector2.ZERO if metrics are unavailable (glyph not in font) — the
# caller should fall back to its manual label_visual_offset in that case.
# `glyph_offset` (per-program manual nudge) is applied by the caller on top.
static func compute_glyph_centering(glyph_char: String, font: Font, font_size: int, cell_size: int) -> Vector2:
	if glyph_char.is_empty() or font == null or font_size <= 0:
		return Vector2.ZERO
	var ts: TextServer = TextServerManager.get_primary_interface()
	if ts == null:
		return Vector2.ZERO
	var rids: Array = font.get_rids()
	if rids.is_empty():
		return Vector2.ZERO
	var font_rid: RID = rids[0]
	var char_code: int = glyph_char.unicode_at(0)
	var glyph_index: int = ts.font_get_glyph_index(font_rid, font_size, char_code, 0)
	var g_size: Vector2 = ts.font_get_glyph_size(font_rid, Vector2i(font_size, 0), glyph_index)
	var g_offset: Vector2 = ts.font_get_glyph_offset(font_rid, Vector2i(font_size, 0), glyph_index)
	if g_size.x <= 0.0 or g_size.y <= 0.0:
		return Vector2.ZERO
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	# The Label centres the text line (ascent + descent) in cell_size, so the
	# text-box top is at (cell_size - ascent - descent) / 2 and the baseline is
	# at text_box_top + ascent. The glyph bitmap sits at baseline + g_offset,
	# so its vertical centre is at baseline + g_offset.y + g_size.y / 2.
	var text_box_top: float = (float(cell_size) - ascent - descent) / 2.0
	var baseline: float = text_box_top + ascent
	var glyph_center_y: float = baseline + g_offset.y + g_size.y / 2.0
	var auto_y: float = float(cell_size) / 2.0 - glyph_center_y
	# Horizontal: the Label centres the advance width, so pen_x is at
	# (cell_size - advance) / 2. The glyph bitmap left is at pen_x + g_offset.x.
	var advance_v: Vector2 = ts.font_get_glyph_advance(font_rid, font_size, glyph_index)
	var advance: float = advance_v.x
	if advance <= 0.0:
		advance = font.get_char_size(char_code, font_size).x
	var pen_x: float = (float(cell_size) - advance) / 2.0
	var glyph_center_x: float = pen_x + g_offset.x + g_size.x / 2.0
	var auto_x: float = float(cell_size) / 2.0 - glyph_center_x
	return Vector2(auto_x, auto_y)
