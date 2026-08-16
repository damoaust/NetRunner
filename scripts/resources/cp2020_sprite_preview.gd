@tool
extends Control
class_name CP2020SpritePreview

## Live preview of a program sprite on a single tile, used inside the datafort
## designer's ICE editor panel. Draws the tile background + center crosshair
## via _draw(), and renders the sprite through a child Sprite2D that matches
## the BlackICE scene setup (centered, AtlasTexture frame extraction, scaled
## to cell_size). The designer updates `program.sprite_offset` and calls
## `refresh()` to redraw.

var program: NetProgram = null
const PREVIEW_CELL := 40
const PREVIEW_PAD := 20

var _sprite: Sprite2D = null


func _ready() -> void:
	_ensure_sprite()
	custom_minimum_size = Vector2(PREVIEW_CELL + PREVIEW_PAD * 2, PREVIEW_CELL + PREVIEW_PAD * 2)
	queue_redraw()


func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	for child in get_children():
		if child is Sprite2D and child.name == "PreviewSprite":
			_sprite = child
			return
	_sprite = Sprite2D.new()
	_sprite.name = "PreviewSprite"
	_sprite.centered = true
	_sprite.visible = false
	add_child(_sprite)


func refresh() -> void:
	_ensure_sprite()
	_update_sprite()
	queue_redraw()


func _update_sprite() -> void:
	if _sprite == null:
		return
	if program == null:
		_sprite.visible = false
		_sprite.texture = null
		return
	var sprite_tex: Texture2D = program.get_sprite()
	if sprite_tex == null:
		_sprite.visible = false
		_sprite.texture = null
		return
	var frame_size: int = program.sprite_frame_size
	if frame_size <= 0:
		frame_size = 128
	var atlas := AtlasTexture.new()
	atlas.atlas = sprite_tex
	atlas.region = Rect2(program.sprite_frame * frame_size, 0, frame_size, frame_size)
	_sprite.texture = atlas
	_sprite.scale = Vector2(PREVIEW_CELL / float(frame_size), PREVIEW_CELL / float(frame_size))
	var tile_center := Vector2(PREVIEW_PAD + PREVIEW_CELL / 2.0, PREVIEW_PAD + PREVIEW_CELL / 2.0)
	# sprite_offset is in screen pixels at cell_size=40 in-game. The preview
	# also uses 40px tiles, so the offset maps 1:1.
	_sprite.position = tile_center + program.sprite_offset
	_sprite.visible = true


func _draw() -> void:
	var tile_rect := Rect2(PREVIEW_PAD, PREVIEW_PAD, PREVIEW_CELL, PREVIEW_CELL)
	draw_rect(tile_rect, Color(0.05, 0.05, 0.05))
	draw_rect(tile_rect, Color(0.4, 0.4, 0.4), false)
	var center := Vector2(PREVIEW_PAD + PREVIEW_CELL / 2.0, PREVIEW_PAD + PREVIEW_CELL / 2.0)
	draw_line(center - Vector2(6, 0), center + Vector2(6, 0), Color(1, 1, 0, 0.5), 1)
	draw_line(center - Vector2(0, 6), center + Vector2(0, 6), Color(1, 1, 0, 0.5), 1)