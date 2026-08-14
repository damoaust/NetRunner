@tool
extends Node

# One-shot generator: builds the cyberpunk Theme resource in code (so every
# StyleBox/font/color is valid Godot 4.7) and saves it to
# res://themes/cyberpunk_theme.tres. Run via the editor (open this scene,
# F6) or headless. Safe to re-run — overwrites the file.

const OUT_PATH := "res://themes/cyberpunk_theme.tres"

# Palette (mirrors CP2020Theme const class).
const COL_BG := Color(0.0, 0.07, 0.04, 1.0)
const COL_PANEL := Color(0.02, 0.06, 0.04, 0.96)
const COL_BORDER := Color(0.0, 1.0, 0.35, 0.65)
const COL_BORDER_DIM := Color(0.0, 0.55, 0.3, 0.5)
const COL_TEXT := Color(0.72, 1.0, 0.78)
const COL_DIM := Color(0.42, 0.58, 0.5)
const COL_GREEN := Color(0.2, 1.0, 0.4)
const COL_GREY := Color(0.38, 0.45, 0.42)

func _ready() -> void:
	var theme := Theme.new()

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "Menlo"])
	mono.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	mono.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	mono.generate_mipmaps = false
	theme.default_font = mono
	theme.default_font_size = 21

	# --- Label ---
	theme.set_color("font_color", "Label", COL_TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	theme.set_font("font", "Label", mono)
	theme.set_font_size("font_size", "Label", 21)
	theme.set_constant("outline_size", "Label", 0)

	# --- RichTextLabel (terminal log) ---
	theme.set_color("font_color", "RichTextLabel", COL_TEXT)
	theme.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.85))
	theme.set_font("font", "RichTextLabel", mono)
	theme.set_font_size("font_size", "RichTextLabel", 21)
	theme.set_constant("outline_size", "RichTextLabel", 0)

	# --- Button ---
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(st, "Button", _btn_style(st))
	theme.set_color("font_color", "Button", COL_GREEN)
	theme.set_color("font_hover_color", "Button", Color(0.6, 1.0, 0.7))
	theme.set_color("font_pressed_color", "Button", COL_GREEN)
	theme.set_color("font_disabled_color", "Button", COL_GREY)
	theme.set_font("font", "Button", mono)
	theme.set_font_size("font_size", "Button", 21)

	# --- PanelContainer ---
	theme.set_stylebox("panel", "PanelContainer", _panel_style(true))

	# --- ProgressBar ---
	theme.set_stylebox("background", "ProgressBar", _bar_bg_style())
	theme.set_stylebox("fill", "ProgressBar", _bar_fill_style())

	# --- ItemList ---
	theme.set_stylebox("panel", "ItemList", _list_panel_style())
	theme.set_stylebox("selected", "ItemList", _list_selected_style())
	theme.set_stylebox("selected_focus", "ItemList", _list_selected_style())
	theme.set_stylebox("hover", "ItemList", _list_hover_style())
	theme.set_color("font_color", "ItemList", COL_TEXT)
	theme.set_color("font_selected_color", "ItemList", COL_GREEN)
	theme.set_color("font_hover_color", "ItemList", Color(COL_TEXT.r * 1.2, COL_TEXT.g * 1.2, COL_TEXT.b * 1.2))
	theme.set_color("guide_color", "ItemList", COL_BORDER_DIM)
	theme.set_font("font", "ItemList", mono)
	theme.set_font_size("font_size", "ItemList", 21)
	theme.set_constant("h_separation", "ItemList", 6)
	theme.set_constant("v_separation", "ItemList", 3)

	# --- TabContainer ---
	theme.set_stylebox("tab_selected", "TabContainer", _tab_selected_style())
	theme.set_stylebox("tab_unselected", "TabContainer", _tab_unselected_style())
	theme.set_stylebox("tab_hovered", "TabContainer", _tab_hovered_style())
	theme.set_stylebox("tab_focus", "TabContainer", _tab_selected_style())
	theme.set_stylebox("panel", "TabContainer", _transparent_style())
	theme.set_color("font_selected_color", "TabContainer", COL_GREEN)
	theme.set_color("font_unselected_color", "TabContainer", COL_DIM)
	theme.set_color("font_hovered_color", "TabContainer", COL_TEXT)
	theme.set_font("font", "TabContainer", mono)
	theme.set_font_size("font_size", "TabContainer", 26)

	# --- OptionButton: inherits Button styles; just ensure font/size. ---
	theme.set_font("font", "OptionButton", mono)
	theme.set_font_size("font_size", "OptionButton", 21)

	# Ensure dir exists.
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("themes"):
		dir.make_dir("themes")

	var err := ResourceSaver.save(theme, OUT_PATH)
	if err == OK:
		print("THEME SAVED: ", OUT_PATH)
	else:
		push_error("Failed to save theme: %d" % err)
	get_tree().quit()


# --- StyleBox builders ---

func _panel_style(with_border: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.content_margin_left = 12
	sb.content_margin_top = 10
	sb.content_margin_right = 12
	sb.content_margin_bottom = 10
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	if with_border:
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = COL_BORDER
		sb.shadow_color = COL_BORDER
		sb.shadow_size = 6
		sb.shadow_offset = Vector2.ZERO
	return sb

func _btn_style(state: String) -> StyleBoxFlat:
	var c: Color = COL_GREEN
	var border_w := 1
	if state == "hover":
		c = Color(COL_GREEN.r * 1.2, COL_GREEN.g * 1.2, COL_GREEN.b * 1.2)
	elif state == "disabled":
		c = COL_GREY
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c.r * 0.12, c.g * 0.12, c.b * 0.12, 0.9)
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.border_color = c
	sb.content_margin_left = 10
	sb.content_margin_top = 6
	sb.content_margin_right = 10
	sb.content_margin_bottom = 6
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb

func _bar_bg_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.18, 0.1, 1.0)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_BORDER_DIM
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb

func _bar_fill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_GREEN
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb

func _list_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_BORDER_DIM
	sb.content_margin_left = 4
	sb.content_margin_top = 4
	sb.content_margin_right = 4
	sb.content_margin_bottom = 4
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb

func _list_selected_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_GREEN.r * 0.2, COL_GREEN.g * 0.2, COL_GREEN.b * 0.2, 0.8)
	sb.border_width_bottom = 1
	sb.border_color = COL_GREEN
	return sb

func _list_hover_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_BORDER.r * 0.3, COL_BORDER.g * 0.3, COL_BORDER.b * 0.3, 0.5)
	return sb

func _tab_selected_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_GREEN.r * 0.18, COL_GREEN.g * 0.18, COL_GREEN.b * 0.18, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 3
	sb.border_color = COL_GREEN
	return sb

func _tab_unselected_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_BORDER_DIM
	return sb

func _tab_hovered_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_BORDER.r * 0.12, COL_BORDER.g * 0.12, COL_BORDER.b * 0.12, 0.6)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_BORDER
	return sb

func _transparent_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	return sb