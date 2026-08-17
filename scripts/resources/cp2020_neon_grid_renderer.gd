@tool
class_name CP2020NeonGridRenderer
extends Node2D

# Shared procedural neon-grid renderer used by both the runtime City Grid
# (cp2020_city_grid.gd, which instantiates this as a child node) and the
# @tool City Grid designer renderer (cp2020_city_grid_renderer.gd, which
# extends this class). Draws the cyberpunk grid, scanlines, vignette, LDL
# entry, datafort chips, an optional runner avatar and the header + tier
# legend via CanvasItem draw_* calls. Owners push normalised data into the
# fields below; this node owns all rendering, the pulse animation and the
# cached theme/webdings fonts (so nothing is allocated per frame).

const CELL: int = 40

# Webdings "C" glyph = tier-colored cityscape silhouette. The bundled
# webdings.ttf was regenerated with a Windows-platform (3,1) cmap (see
# tools/add_windows_cmap.py) so Godot/HarfBuzz can resolve U+0043.
const BUILDING_CHAR := "C"
const BUILDING_FONT_PATH := "res://data/webdings.ttf"

@export_group("Palette")
@export var color_bg: Color = Color(0.02, 0.03, 0.06, 1.0)
@export var color_grid: Color = Color(0.0, 0.78, 0.92, 0.22)
@export var color_grid_bright: Color = Color(0.0, 0.9, 1.0, 0.55)
@export var color_runner: Color = Color(0.0, 1.0, 1.0, 1.0)
@export var color_scanline: Color = Color(0.0, 0.0, 0.0, 0.12)
@export var color_text_label: Color = Color(0.7, 0.9, 1.0, 0.9)
@export var color_text_header: Color = Color(0.85, 0.95, 1.0, 0.95)

# --- Data pushed by the owner (runtime city grid or designer renderer) ---
var grid_cols: int = 20
var grid_rows: int = 12
var grid_offset: Vector2 = Vector2(20, 90)
var dataforts: Array = []          # [{name:String, pos:Vector2i, security_tier:int}]
var ldl_entry: Vector2i = Vector2i.ZERO
var city_name: String = ""
var header_label: String = "CITY GRID"
var selected_datafort_pos: Variant = null  # Vector2i or null
var runner_pos: Variant = null             # Vector2i or null (runtime only)

var _pulse_time: float = 0.0
var _datafort_font: FontFile = null
var _font_cache: Font = null


func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()


func _draw() -> void:
	if grid_cols <= 0 or grid_rows <= 0:
		return
	var total_w := grid_cols * CELL
	var total_h := grid_rows * CELL
	var font := _theme_font()
	var pulse := _pulse_value()

	_draw_background(total_w, total_h)
	_draw_scanlines()
	_draw_grid(total_w, total_h, pulse)
	_draw_ldl_entry(font, pulse)
	_draw_dataforts(font, pulse)
	if runner_pos != null:
		_draw_runner(pulse)
	_draw_header(font, pulse)


func _pulse_value() -> float:
	return 0.5 + 0.5 * sin(_pulse_time * 3.0)


func _create_datafort_font() -> FontFile:
	if _datafort_font != null:
		return _datafort_font
	var f := load(BUILDING_FONT_PATH) as FontFile
	if f == null:
		push_warning("NEON GRID: webdings.ttf missing — falling back to theme font for datafort glyph.")
		_datafort_font = _theme_font() as FontFile
	else:
		_datafort_font = f
	return _datafort_font


func _draw_background(total_w: int, total_h: int) -> void:
	var canvas_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, canvas_size), color_bg, true)

	var vignette := Color(0.0, 0.0, 0.0, 0.3)
	var ox := grid_offset.x
	var oy := grid_offset.y
	draw_rect(Rect2(ox, oy, total_w, 100), vignette, true)
	draw_rect(Rect2(ox, oy + total_h - 100, total_w, 100), vignette, true)
	draw_rect(Rect2(ox, oy, 100, total_h), vignette, true)
	draw_rect(Rect2(ox + total_w - 100, oy, 100, total_h), vignette, true)


func _draw_scanlines() -> void:
	var canvas_size := get_viewport_rect().size
	var y: float = 0.0
	while y < canvas_size.y:
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), color_scanline, 1.0)
		y += 4.0


func _draw_grid(total_w: int, total_h: int, pulse: float) -> void:
	var bright_alpha := color_grid_bright.a * (0.5 + 0.5 * pulse)
	var origin := grid_offset
	for x in range(grid_cols + 1):
		var line_color := color_grid
		if x % 5 == 0:
			line_color = Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, bright_alpha)
		draw_line(origin + Vector2(x * CELL, 0), origin + Vector2(x * CELL, total_h), line_color, 1.0 if x % 5 != 0 else 1.5)
	for y in range(grid_rows + 1):
		var line_color := color_grid
		if y % 5 == 0:
			line_color = Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, bright_alpha)
		draw_line(origin + Vector2(0, y * CELL), origin + Vector2(total_w, y * CELL), line_color, 1.0 if y % 5 != 0 else 1.5)
	_draw_tech_frame(origin, Vector2(total_w, total_h), color_grid_bright, 2.0)


func _draw_ldl_entry(font: Font, pulse: float) -> void:
	var center := grid_offset + Vector2(ldl_entry.x * CELL + CELL / 2.0, ldl_entry.y * CELL + CELL / 2.0)
	var ring_alpha := 0.6 + 0.4 * pulse
	draw_arc(center, CELL * 0.42, _pulse_time * 2.0, _pulse_time * 2.0 + TAU * 0.85, 24, Color(color_runner.r, color_runner.g, color_runner.b, ring_alpha), 2.0)
	var label := "LDL"
	var label_size := 10
	var label_dims := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
	var label_pos := center - label_dims * 0.5 + Vector2(0, label_size * 0.35)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, Color(color_runner.r, color_runner.g, color_runner.b, 0.9))


func _draw_dataforts(label_font: Font, pulse: float) -> void:
	for df in dataforts:
		var tier: int = clampi(int(df.security_tier), 0, CP2020SecurityTier.Tier.size() - 1)
		var tier_color: Color = CP2020SecurityTier.COLORS.get(tier, Color(0.0, 1.0, 0.9, 1.0))
		var pos: Vector2i = df.pos
		var center := grid_offset + Vector2(pos.x * CELL + CELL / 2.0, pos.y * CELL + CELL / 2.0)

		# Selection highlight overrides tier color.
		var df_color := tier_color
		if selected_datafort_pos != null and pos == selected_datafort_pos:
			df_color = Color(1.0, 1.0, 0.0, 1.0)

		# Neon glow.
		for i in range(3):
			var glow_radius := CELL * (0.55 + i * 0.18)
			var glow_alpha := (0.18 - i * 0.05) * (0.7 + 0.3 * pulse)
			draw_arc(center, glow_radius, 0, TAU, 32, Color(df_color.r, df_color.g, df_color.b, glow_alpha), 3.0)

		# Corner brackets.
		_draw_corner_brackets(center, CELL * 0.55, df_color, 2.0)

		# Cityscape glyph centered in the tile (tier-colored).
		var glyph_font := _create_datafort_font()
		var glyph_size := 30
		var glyph_dims := glyph_font.get_string_size(BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size)
		var glyph_pos := center - glyph_dims * 0.5 + Vector2(0, glyph_size * 0.35 + 10.0)
		draw_string(glyph_font, glyph_pos, BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size, df_color)

		# Datafort label centered below the tile.
		var label_size := 11
		var label_dims := label_font.get_string_size(df.name, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
		var label_pos := Vector2(
			grid_offset.x + pos.x * CELL + (CELL - label_dims.x) * 0.5,
			grid_offset.y + pos.y * CELL + CELL + 12
		)
		draw_string(label_font, label_pos, df.name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, color_text_label)


func _draw_runner(pulse: float) -> void:
	var pos: Vector2i = runner_pos
	var center := grid_offset + Vector2(pos.x * CELL + CELL / 2.0, pos.y * CELL + CELL / 2.0)
	# Rotating targeting ring.
	var ring_alpha := 0.6 + 0.4 * pulse
	draw_arc(center, CELL * 0.52, _pulse_time * 3.0, _pulse_time * 3.0 + TAU * 0.85, 32, Color(color_runner.r, color_runner.g, color_runner.b, ring_alpha), 2.0)
	# Neon glow.
	for i in range(3):
		var glow_radius := CELL * (0.35 + i * 0.12)
		var glow_alpha := (0.2 - i * 0.05) * (0.7 + 0.3 * pulse)
		draw_arc(center, glow_radius, 0, TAU, 32, Color(color_runner.r, color_runner.g, color_runner.b, glow_alpha), 2.5)
	# Diamond avatar.
	_draw_diamond(center, CELL * 0.28, color_runner, 2.0)
	# Inner core.
	draw_circle(center, CELL * 0.1, Color(color_runner.r, color_runner.g, color_runner.b, 0.8))


func _draw_header(font: Font, pulse: float) -> void:
	const LEGEND_ICON_SIZE := 12
	var title := "%s // %s" % [header_label, city_name.to_upper()]
	var header_y := 48.0
	var bracket_alpha := 0.7 + 0.3 * pulse
	draw_string(font, Vector2(18, header_y), "[", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, bracket_alpha))
	draw_string(font, Vector2(30, header_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color_text_header)
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(34 + title_width, header_y), "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, bracket_alpha))
	var line_y := header_y + 8
	var pulse_x := 30 + fmod(_pulse_time * 80.0, title_width + 20)
	draw_line(Vector2(18, line_y), Vector2(36 + title_width, line_y), color_grid_bright, 1.0)
	draw_circle(Vector2(30 + pulse_x, line_y), 3.0, color_runner)

	# Tier legend (vertical, right of the grid, flush with the map edge).
	var grid_right := grid_offset.x + grid_cols * CELL + 8
	var legend_x := grid_right
	var legend_y := grid_offset.y + 4
	for i in range(CP2020SecurityTier.Tier.size()):
		var tier_color: Color = CP2020SecurityTier.COLORS[i]
		var short := String(CP2020SecurityTier.SHORT[i])
		var legend_font := _create_datafort_font()
		var icon_dims := legend_font.get_string_size(BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, LEGEND_ICON_SIZE)
		var icon_pos := Vector2(legend_x + (LEGEND_ICON_SIZE - icon_dims.x) * 0.5, legend_y + LEGEND_ICON_SIZE - 1)
		draw_string(legend_font, icon_pos, BUILDING_CHAR, HORIZONTAL_ALIGNMENT_CENTER, -1, LEGEND_ICON_SIZE, tier_color)
		draw_string(font, Vector2(legend_x + LEGEND_ICON_SIZE + 4, legend_y + 11), short, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85, 0.9))
		legend_y += 16


func _draw_corner_brackets(center: Vector2, half_size: float, color: Color, width: float) -> void:
	var inset := half_size * 0.55
	var tl := center + Vector2(-half_size, -half_size)
	var top_r := center + Vector2(half_size, -half_size)
	var bl := center + Vector2(-half_size, half_size)
	var bottom_r := center + Vector2(half_size, half_size)
	draw_line(tl, tl + Vector2(inset, 0), color, width)
	draw_line(tl, tl + Vector2(0, inset), color, width)
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width)
	draw_line(top_r, top_r + Vector2(0, inset), color, width)
	draw_line(bl, bl + Vector2(inset, 0), color, width)
	draw_line(bl, bl + Vector2(0, -inset), color, width)
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width)


func _draw_tech_frame(origin: Vector2, frame_size: Vector2, color: Color, width: float) -> void:
	var tl := origin
	var top_r := origin + Vector2(frame_size.x, 0)
	var bl := origin + Vector2(0, frame_size.y)
	var bottom_r := origin + frame_size
	var inset := 18.0
	draw_rect(Rect2(origin, frame_size), color, false, width)
	draw_line(tl, tl + Vector2(inset, 0), color, width + 1.0)
	draw_line(tl, tl + Vector2(0, inset), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(0, inset), color, width + 1.0)
	draw_line(bl, bl + Vector2(inset, 0), color, width + 1.0)
	draw_line(bl, bl + Vector2(0, -inset), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width + 1.0)


func _draw_diamond(center: Vector2, radius: float, color: Color, width: float) -> void:
	var top := center + Vector2(0, -radius)
	var right := center + Vector2(radius, 0)
	var bottom := center + Vector2(0, radius)
	var left := center + Vector2(-radius, 0)
	draw_line(top, right, color, width)
	draw_line(right, bottom, color, width)
	draw_line(bottom, left, color, width)
	draw_line(left, top, color, width)


func _theme_font() -> Font:
	if _font_cache == null:
		var label := Label.new()
		_font_cache = label.get_theme_default_font()
		label.free()
	return _font_cache