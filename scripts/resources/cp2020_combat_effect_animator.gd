# Fire-and-forget combat effect renderer.
# Drawn on top of the BoardRenderer grid as a child Node2D.
# Receives pixel-ready visual configs from the caller and is fully self-contained.
class_name CombatEffectAnimator
extends Node2D

# Grid geometry — synced by the parent BoardRenderer at runtime.
@export var cell_size: int = 40
@export var grid_offset_y: int = 90

# Fallback beam color when the caller's visual config omits a color. The
# per-program visual (NetProgram.ATTACK_VISUALS) takes precedence.
@export var default_color: Color = Color(1, 0.2, 0.2)

# Active effect instances. Each Dictionary keys:
#   from: Vector2 (pixel), to: Vector2 (pixel), color: Color, width: float,
#   duration: float, style: String, elapsed: float
var _active_effects: Array[Dictionary] = []


func _ready() -> void:
	# Idle and zero-cost until play_effect is called.
	set_process(false)


func _grid_to_pixel(grid: Vector2i) -> Vector2:
	return Vector2(
		grid.x * cell_size + cell_size / 2.0,
		grid_offset_y + grid.y * cell_size + cell_size / 2.0
	)


func play_effect(from_grid: Vector2i, to_grid: Vector2i, visual: Dictionary) -> void:
	var effect: Dictionary = {
		"from": _grid_to_pixel(from_grid),
		"to": _grid_to_pixel(to_grid),
		"color": visual.get("color", default_color),
		"width": float(visual.get("width", 3.0)),
		"duration": float(visual.get("duration", 0.5)),
		"style": String(visual.get("style", "beam")),
		"elapsed": 0.0,
	}
	_active_effects.append(effect)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var i: int = _active_effects.size() - 1
	while i >= 0:
		var e: Dictionary = _active_effects[i]
		e["elapsed"] = float(e["elapsed"]) + delta
		if float(e["elapsed"]) >= float(e["duration"]):
			_active_effects.remove_at(i)
		i -= 1

	if _active_effects.is_empty():
		set_process(false)
	else:
		queue_redraw()


func _draw() -> void:
	for e in _active_effects:
		_draw_effect(e)


func _draw_effect(e: Dictionary) -> void:
	var style: String = e.get("style", "beam")
	match style:
		"beam":
			_draw_beam(e)
		"pulse":
			_draw_pulse(e)
		"flash":
			_draw_flash(e)
		_:
			# Unknown style falls back to beam.
			_draw_beam(e)


func _draw_beam(e: Dictionary) -> void:
	var from: Vector2 = e["from"]
	var to: Vector2 = e["to"]
	var color: Color = e["color"]
	var width: float = e["width"]
	var duration: float = e["duration"]
	var elapsed: float = e["elapsed"]

	var p: float = clampf(elapsed / duration, 0.0, 1.0)

	# Alpha envelope: fade-in 0–15%, hold 15–75%, fade-out 75–100%.
	var alpha: float
	if p < 0.15:
		alpha = clampf(p / 0.15, 0.0, 1.0)
	elif p <= 0.75:
		alpha = 1.0
	else:
		alpha = clampf((1.0 - p) / 0.25, 0.0, 1.0)

	# Wide semi-transparent glow underlay.
	var glow_color: Color = Color(color.r, color.g, color.b, alpha * 0.4)
	draw_line(from, to, glow_color, width * 3.0)

	# Narrow core line.
	var core_color: Color = Color(color.r, color.g, color.b, alpha)
	draw_line(from, to, core_color, width)

	# Impact flash near the midpoint of the effect lifetime (40–60%).
	if p >= 0.4 and p <= 0.6:
		# Fade based on distance from the 50% mark.
		var flash_alpha: float = 1.0 - absf(p - 0.5) / 0.1
		flash_alpha = clampf(flash_alpha, 0.0, 1.0)
		var flash_color: Color = Color(
			lerpf(color.r, 1.0, 0.6),
			lerpf(color.g, 1.0, 0.6),
			lerpf(color.b, 1.0, 0.6),
			flash_alpha
		)
		draw_circle(to, 8.0, flash_color)


# Future stub — expanding ring at target.
func _draw_pulse(e: Dictionary) -> void:
	var to: Vector2 = e["to"]
	var color: Color = e["color"]
	var duration: float = e["duration"]
	var elapsed: float = e["elapsed"]
	var p: float = clampf(elapsed / duration, 0.0, 1.0)
	var radius: float = p * 20.0
	var ring_color: Color = Color(color.r, color.g, color.b, 1.0 - p)
	draw_circle(to, radius, ring_color)


# Future stub — radial flash at target.
func _draw_flash(e: Dictionary) -> void:
	var to: Vector2 = e["to"]
	var color: Color = e["color"]
	var duration: float = e["duration"]
	var elapsed: float = e["elapsed"]
	var p: float = clampf(elapsed / duration, 0.0, 1.0)
	var flash_color: Color = Color(color.r, color.g, color.b, 1.0 - p)
	draw_circle(to, 12.0, flash_color)