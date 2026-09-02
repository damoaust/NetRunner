@tool
class_name CP2020WorldMapRenderer
extends Node2D

# Shared renderer for the world net map (runtime scene) and the world map
# designer (@tool) — the single drawing implementation for the neon grid,
# region fills, hubs, header, and tech frame (CODE_REVIEW §5.1; the city-grid
# side already delegates the same way). Callers feed it state fields and call
# queue_redraw() (its _process also animates the pulse + redraws each frame).
# All pixel logic lives here; neither caller overrides _draw() anymore.
# @tool is REQUIRED — the designer instantiates this in the editor.

# Cyberpunk/neon palette. Single copy — both the runtime and the designer
# previously re-declared these exact values.
@export var color_bg: Color = Color(0.02, 0.03, 0.06, 1.0)
@export var color_grid: Color = Color(0.0, 0.78, 0.92, 0.22)
@export var color_grid_bright: Color = Color(0.0, 0.9, 1.0, 0.55)
@export var color_runner: Color = Color(0.0, 1.0, 1.0, 1.0)
@export var color_scanline: Color = Color(0.0, 0.0, 0.0, 0.12)
@export var color_text_header: Color = Color(0.85, 0.95, 1.0, 0.95)
@export var color_text_label: Color = Color(0.7, 0.9, 1.0, 0.9)

# Grid geometry + content. Hub entries may be CP2020WorldHub resources
# (designer) or plain dictionaries with the same keys (runtime) — both expose
# name / pos / security_tier through hub.get(...).
var grid_cols: int = 20
var grid_rows: int = 12
var grid_offset: Vector2 = Vector2(20, 60)
var regions: Array = []                 # [{name, color}]
var tile_region: Dictionary = {}        # Vector2i / "x,y" -> int region index
var hubs: Array = []
var runner_spawn_hub: String = ""       # rotating cyan ring drawn on this hub
var show_ldl_tag: bool = false          # runtime draws "LDL" under the spawn ring
var selected_hub: CP2020WorldHub = null # designer selection highlight (yellow)
var runner_pos: Variant = null          # Vector2i — runtime only; null hides the runner
var header_label: String = "WORLD NET MAP"
var header_color: Color = Color(0.85, 0.95, 1.0, 0.95)
# Runtime: full-canvas backdrop + 120px screen-edge vignette + horizon band.
# Designer: canvas-sized backdrop + 100px vignette bands hugging the grid.
var full_screen_vignette: bool = true
var canvas_size: Vector2 = Vector2(1920, 1080)

var pulse_time: float = 0.0

var _font_cache: Font = null

const CELL: int = 40


func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()


func _draw() -> void:
	if grid_cols <= 0 or grid_rows <= 0:
		return
	var font := _theme_font()
	var pulse := _pulse_value()

	_draw_background(pulse)
	_draw_scanlines()
	_draw_region_fills(pulse)
	_draw_grid(pulse)
	_draw_hubs(font, pulse)
	if runner_pos != null:
		_draw_runner(pulse)
	_draw_header(font, pulse)


func _pulse_value() -> float:
	return 0.5 + 0.5 * sin(pulse_time * 3.0)


func _draw_background(pulse: float) -> void:
	# Deep-space ocean fill.
	draw_rect(Rect2(Vector2.ZERO, canvas_size), color_bg, true)

	if full_screen_vignette:
		# Runtime vignette: darkens screen edges so the neon grid pops.
		var vignette := Color(0.0, 0.0, 0.0, 0.35)
		var top := Rect2(0, 0, canvas_size.x, 120)
		var bottom := Rect2(0, canvas_size.y - 120, canvas_size.x, 120)
		var left := Rect2(0, 0, 120, canvas_size.y)
		var right := Rect2(canvas_size.x - 120, 0, 120, canvas_size.y)
		draw_rect(top, vignette, true)
		draw_rect(bottom, vignette, true)
		draw_rect(left, vignette, true)
		draw_rect(right, vignette, true)

		# Decorative horizon scan band behind the grid.
		var band_alpha := 0.04 + 0.03 * pulse
		draw_rect(Rect2(0, grid_offset.y - 4, canvas_size.x, 4), Color(color_grid.r, color_grid.g, color_grid.b, band_alpha), true)
	else:
		# Designer vignette hugging the grid only.
		var total_w := grid_cols * CELL
		var total_h := grid_rows * CELL
		var vignette := Color(0.0, 0.0, 0.0, 0.3)
		draw_rect(Rect2(grid_offset.x, grid_offset.y, total_w, 100), vignette, true)
		draw_rect(Rect2(grid_offset.x, grid_offset.y + total_h - 100, total_w, 100), vignette, true)
		draw_rect(Rect2(grid_offset.x, grid_offset.y, 100, total_h), vignette, true)
		draw_rect(Rect2(grid_offset.x + total_w - 100, grid_offset.y, 100, total_h), vignette, true)


func _draw_scanlines() -> void:
	# Classic CRT scanline overlay across the whole screen.
	var y: float = 0.0
	while y < canvas_size.y:
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), color_scanline, 1.0)
		y += 4.0


func _draw_grid(pulse: float) -> void:
	# Neon grid lines. Major divisions every 5 cells get a brighter pulse.
	var origin := grid_offset
	var grid_w := grid_cols * CELL
	var grid_h := grid_rows * CELL
	var bright_alpha := color_grid_bright.a * (0.5 + 0.5 * pulse)

	for x in range(grid_cols + 1):
		var line_color := color_grid
		if x % 5 == 0:
			line_color = Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, bright_alpha)
		draw_line(origin + Vector2(x * CELL, 0), origin + Vector2(x * CELL, grid_h), line_color, 1.0 if x % 5 != 0 else 1.5)

	for y in range(grid_rows + 1):
		var line_color := color_grid
		if y % 5 == 0:
			line_color = Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, bright_alpha)
		draw_line(origin + Vector2(0, y * CELL), origin + Vector2(grid_w, y * CELL), line_color, 1.0 if y % 5 != 0 else 1.5)

	# Outer tech frame around the grid.
	_draw_tech_frame(origin, Vector2(grid_w, grid_h), color_grid_bright, 2.0)


func _draw_region_fills(pulse: float) -> void:
	# Dark neon region tiles with a soft inner glow.
	for raw_key in tile_region.keys():
		var coord: Vector2i = CP2020DatafortLayout.parse_coord(raw_key)
		var idx: int = int(tile_region[raw_key])
		if idx < 0 or idx >= regions.size():
			continue
		var base: Color = regions[idx].color
		var rect := Rect2(grid_offset + Vector2(coord.x * CELL, coord.y * CELL), Vector2(CELL, CELL))
		# Darkened fill so the grid still reads through it.
		var fill := Color(base.r * 0.35, base.g * 0.35, base.b * 0.35, 0.55)
		draw_rect(rect, fill, true)
		# Subtle top edge highlight.
		var highlight := Color(base.r, base.g, base.b, 0.35 + 0.15 * pulse)
		draw_line(rect.position, rect.position + Vector2(CELL, 0), highlight, 1.5)


func _draw_hubs(font: Font, pulse: float) -> void:
	for hub in hubs:
		var center := grid_offset + Vector2(hub.pos.x * CELL + CELL / 2.0, hub.pos.y * CELL + CELL / 2.0)
		var tier_raw: Variant = hub.get("security_tier")
		var tier: int = clampi(int(tier_raw) if tier_raw != null else 0, 0, CP2020SecurityTier.Tier.size() - 1)
		var tier_color: Color = CP2020SecurityTier.COLORS[tier]
		var glyph: String = CP2020SecurityTier.GLYPHS[tier]

		# Selection gets a strong yellow highlight (designer); otherwise the
		# tier colour.
		var hub_color := tier_color
		if selected_hub != null and hub == selected_hub:
			hub_color = Color(1.0, 1.0, 0.0, 1.0)

		# Tier-colored neon glow behind the hub.
		for i in range(3):
			var glow_radius := CELL * (0.55 + i * 0.18)
			var glow_alpha := (0.18 - i * 0.05) * (0.7 + 0.3 * pulse)
			draw_arc(center, glow_radius, 0, TAU, 32, Color(hub_color.r, hub_color.g, hub_color.b, glow_alpha), 3.0)

		# Tech corner brackets.
		_draw_corner_brackets(center, CELL * 0.55, hub_color, 2.0)

		# Central tier glyph.
		var glyph_size := 16
		var glyph_dims := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size)
		var glyph_pos := center - glyph_dims * 0.5 + Vector2(0, glyph_size * 0.35)
		draw_string(font, glyph_pos, glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size, hub_color)

		# City label below the marker.
		var label_pos := grid_offset + Vector2(hub.pos.x * CELL + 4, hub.pos.y * CELL + CELL + 4)
		draw_string(font, label_pos, hub.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color_text_label)

		# Spawn hub: rotating cyan ring (+ LDL tag at runtime).
		if hub.name == runner_spawn_hub:
			var ring_alpha := 0.6 + 0.4 * pulse
			draw_arc(center, CELL * 0.52, pulse_time * 2.0, pulse_time * 2.0 + TAU * 0.85, 32, Color(color_runner.r, color_runner.g, color_runner.b, ring_alpha), 2.5)
			if show_ldl_tag:
				draw_string(font, Vector2(center.x - 12, center.y + 26), "LDL", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, color_runner)


func _draw_runner(pulse: float) -> void:
	var center := grid_offset + Vector2(runner_pos.x * CELL + CELL / 2.0, runner_pos.y * CELL + CELL / 2.0)
	var size := CELL * 0.32 * (0.9 + 0.1 * pulse)

	# Outer rotating targeting ring.
	var ring_alpha := 0.5 + 0.3 * pulse
	draw_arc(center, CELL * 0.48, -pulse_time * 3.0, -pulse_time * 3.0 + TAU * 0.9, 32, Color(color_runner.r, color_runner.g, color_runner.b, ring_alpha), 2.0)

	# Neon glow.
	for i in range(3):
		var glow_size := size + i * 4.0
		var glow_alpha := 0.25 - i * 0.07
		_draw_diamond(center, glow_size, Color(color_runner.r, color_runner.g, color_runner.b, glow_alpha), true)

	# Solid diamond avatar.
	_draw_diamond(center, size, color_runner, true)
	_draw_diamond(center, size * 0.7, Color(0.0, 0.0, 0.0, 0.6), true)


func _draw_diamond(center: Vector2, size: float, color: Color, filled: bool) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(size, 0),
		center + Vector2(0, size),
		center + Vector2(-size, 0),
	])
	if filled:
		draw_polygon(points, PackedColorArray([color, color, color, color]))
	else:
		points.append(points[0])
		draw_polyline(points, color, 2.0)


func _draw_corner_brackets(center: Vector2, half_size: float, color: Color, width: float) -> void:
	var inset := half_size * 0.55
	var tl := center + Vector2(-half_size, -half_size)
	var top_r := center + Vector2(half_size, -half_size)
	var bl := center + Vector2(-half_size, half_size)
	var bottom_r := center + Vector2(half_size, half_size)
	# Top-left.
	draw_line(tl, tl + Vector2(inset, 0), color, width)
	draw_line(tl, tl + Vector2(0, inset), color, width)
	# Top-right.
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width)
	draw_line(top_r, top_r + Vector2(0, inset), color, width)
	# Bottom-left.
	draw_line(bl, bl + Vector2(inset, 0), color, width)
	draw_line(bl, bl + Vector2(0, -inset), color, width)
	# Bottom-right.
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width)


func _draw_tech_frame(origin: Vector2, size: Vector2, color: Color, width: float) -> void:
	var tl := origin
	var top_r := origin + Vector2(size.x, 0)
	var bl := origin + Vector2(0, size.y)
	var bottom_r := origin + size
	var inset := 18.0
	# Outer rectangle.
	draw_rect(Rect2(origin, size), color, false, width)
	# Corner accents.
	draw_line(tl, tl + Vector2(inset, 0), color, width + 1.0)
	draw_line(tl, tl + Vector2(0, inset), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(top_r, top_r + Vector2(0, inset), color, width + 1.0)
	draw_line(bl, bl + Vector2(inset, 0), color, width + 1.0)
	draw_line(bl, bl + Vector2(0, -inset), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(-inset, 0), color, width + 1.0)
	draw_line(bottom_r, bottom_r + Vector2(0, -inset), color, width + 1.0)


func _draw_header(font: Font, pulse: float) -> void:
	# Cyberpunk header bar with tech brackets, drawn below the HUD strip.
	var header_y := 48.0
	var title := header_label
	draw_string(font, Vector2(18, header_y), "[", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, 0.7 + 0.3 * pulse))
	draw_string(font, Vector2(30, header_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, header_color)
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(34 + title_width, header_y), "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(color_grid_bright.r, color_grid_bright.g, color_grid_bright.b, 0.7 + 0.3 * pulse))

	# Thin underline with a travelling pulse.
	var line_y := header_y + 8
	var pulse_x := 30 + fmod(pulse_time * 80.0, title_width + 20)
	draw_line(Vector2(18, line_y), Vector2(36 + title_width, line_y), color_grid_bright, 1.0)
	draw_circle(Vector2(30 + pulse_x, line_y), 3.0, color_runner)


func _theme_font() -> Font:
	if _font_cache == null:
		var label := Label.new()
		_font_cache = label.get_theme_default_font()
		label.free()
	return _font_cache