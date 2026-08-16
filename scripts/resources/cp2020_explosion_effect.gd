# Fire-and-forget explosion effect rendered via a CanvasItem shader.
# Spawned by the game session when a rezzed program is de-rezzed (manually
# or destroyed by Killer ICE). Positions itself at the program's grid coord,
# animates the shader's `progress` uniform 0→1, and auto-frees when done.
#
# The node draws a 3×3 tile rect (centered on the target tile) so the shader
# has pixels to shade — the shader's UV space maps onto this rect. Grid
# geometry (cell_size, grid_offset_y) is synced from the BoardRenderer, same
# convention as CombatEffectAnimator.
class_name CP2020ExplosionEffect
extends Node2D

@export var cell_size: int = 40
@export var grid_offset_y: int = 90
@export var duration: float = 0.6

var _elapsed: float = 0.0
var _material: ShaderMaterial = null
# How many tiles (in each direction from center) the drawn rect covers.
const _radius_tiles: int = 2

static var _shader: Shader = null


func _ready() -> void:
	set_process(false)
	if _shader == null:
		_shader = load("res://scripts/effects/derez_explosion.gdshader") as Shader
	if _shader:
		_material = ShaderMaterial.new()
		_material.shader = _shader
		material = _material


func play(grid_pos: Vector2i, base_color: Color) -> void:
	# Position at the tile center (same formula as RezzedProgram / BlackIce).
	var center_x: float = grid_pos.x * cell_size + cell_size / 2.0
	var center_y: float = grid_offset_y + grid_pos.y * cell_size + cell_size / 2.0
	position = Vector2(center_x, center_y)

	if _material:
		_material.set_shader_parameter("base_color", base_color)
		_material.set_shader_parameter("seed", randf())
		_material.set_shader_parameter("progress", 0.0)

	_elapsed = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	var p: float = clampf(_elapsed / duration, 0.0, 1.0)
	if _material:
		_material.set_shader_parameter("progress", p)
	queue_redraw()
	if _elapsed >= duration:
		set_process(false)
		queue_free()


func _draw() -> void:
	# Draw a rect covering (2*_radius_tiles+1)² tiles centered on origin.
	# The node's position is already at the tile center, so we offset by
	# half the rect size to centre the rect on the position.
	var half: float = float(_radius_tiles) * cell_size + cell_size / 2.0
	var rect: Rect2 = Rect2(-half, -half, half * 2.0, half * 2.0)
	draw_rect(rect, Color.WHITE, true)