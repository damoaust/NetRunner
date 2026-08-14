@tool
extends Control
class_name CP2020GlyphPreview

## Live preview of a program glyph on a single tile, used inside the datafort
## designer's ICE editor panel. Draws the tile background + center crosshair
## via _draw(), and renders the glyph through a child Label that matches the
## BlackICE scene setup (whitrabt font, font_size 30, center alignment). The
## designer updates `program.glyph_offset` / `program.glyph_auto_center` and
## calls `refresh()` to redraw.

var program: NetProgram = null
const PREVIEW_CELL := 40
const PREVIEW_PAD := 20

var _label: Label = null
var _game_font: Font = null


func _ready() -> void:
	_game_font = load("res://whitrabt.ttf") as Font
	_ensure_label()
	custom_minimum_size = Vector2(PREVIEW_CELL + PREVIEW_PAD * 2, PREVIEW_CELL + PREVIEW_PAD * 2)
	queue_redraw()


func _ensure_label() -> void:
	if _game_font == null:
		_game_font = load("res://whitrabt.ttf") as Font
	if _label != null and is_instance_valid(_label):
		return
	for child in get_children():
		if child is Label and child.name == "PreviewGlyphLabel":
			_label = child
			return
	_label = Label.new()
	_label.name = "PreviewGlyphLabel"
	_label.size = Vector2(PREVIEW_CELL, PREVIEW_CELL)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font_size = 30
	ls.font = _game_font
	_label.label_settings = ls
	add_child(_label)


func refresh() -> void:
	_ensure_label()
	_update_label()
	queue_redraw()


func _update_label() -> void:
	if _label == null:
		return
	if program == null:
		_label.text = ""
		return
	var vis: Dictionary = program.get_visual()
	var glyph: String = vis.get("glyph", "\u2620")
	var col: Color = vis.get("color", Color.RED)
	_label.text = glyph
	_label.label_settings = _label.label_settings.duplicate()
	_label.label_settings.font_color = col
	# Same font/size resolution + centering as BlackIce.apply_visual_from_program.
	var font: Font = _label.label_settings.font
	var font_size: int = int(_label.label_settings.font_size)
	if font == null:
		font = _game_font
	if font == null:
		font = get_theme_default_font()
	if font_size <= 0:
		font_size = int(_label.get_theme_default_font_size())
	var auto_offset: Vector2 = NetProgram.compute_glyph_centering(glyph, font, font_size, PREVIEW_CELL)
	if auto_offset == Vector2.ZERO:
		var fb: Font = load("res://data/seguiemj.ttf") as Font
		if fb != null:
			var fb_offset: Vector2 = NetProgram.compute_glyph_centering(glyph, fb, font_size, PREVIEW_CELL)
			if fb_offset != Vector2.ZERO:
				auto_offset = fb_offset
				_label.label_settings.font = fb
	if not program.glyph_auto_center:
		auto_offset = Vector2.ZERO
	elif auto_offset == Vector2.ZERO:
		auto_offset = Vector2(-2, -4)
	var tile_center := Vector2(PREVIEW_PAD + PREVIEW_CELL / 2.0, PREVIEW_PAD + PREVIEW_CELL / 2.0)
	_label.position = tile_center + Vector2(-PREVIEW_CELL / 2.0, -PREVIEW_CELL / 2.0) + auto_offset + program.glyph_offset


func _draw() -> void:
	var tile_rect := Rect2(PREVIEW_PAD, PREVIEW_PAD, PREVIEW_CELL, PREVIEW_CELL)
	draw_rect(tile_rect, Color(0.05, 0.05, 0.05))
	draw_rect(tile_rect, Color(0.4, 0.4, 0.4), false)
	var center := Vector2(PREVIEW_PAD + PREVIEW_CELL / 2.0, PREVIEW_PAD + PREVIEW_CELL / 2.0)
	draw_line(center - Vector2(6, 0), center + Vector2(6, 0), Color(1, 1, 0, 0.5), 1)
	draw_line(center - Vector2(0, 6), center + Vector2(0, 6), Color(1, 1, 0, 0.5), 1)
