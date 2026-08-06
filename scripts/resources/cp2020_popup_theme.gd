class_name CP2020PopupTheme
extends RefCounted

# Shared cyberpunk/neon styling for PopupMenu instances used across the
# world map, city grid, and datafort gameplay scenes.

const COLOR_BG := Color(0.03, 0.05, 0.09, 0.92)
const COLOR_BORDER := Color(0.0, 0.78, 0.92, 0.75)
const COLOR_TEXT := Color(0.75, 0.95, 1.0, 1.0)
const COLOR_HOVER := Color(1.0, 1.0, 0.35, 1.0)
const COLOR_DISABLED := Color(0.4, 0.45, 0.5, 0.7)
const COLOR_ACCELERATOR := Color(0.5, 0.65, 0.7, 0.8)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)
const OUTLINE_SIZE := 4


static func apply_cyberpunk_theme(popup: PopupMenu, font_size: int = 16) -> void:
	if popup == null:
		return

	# Dark, semi-transparent panel with a cyan neon border and soft glow.
	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_BG
	panel.border_color = COLOR_BORDER
	panel.border_width_left = 2
	panel.border_width_top = 2
	panel.border_width_right = 2
	panel.border_width_bottom = 2
	panel.corner_radius_top_left = 2
	panel.corner_radius_top_right = 2
	panel.corner_radius_bottom_left = 2
	panel.corner_radius_bottom_right = 2
	panel.shadow_color = Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.35)
	panel.shadow_size = 6
	popup.add_theme_stylebox_override("panel", panel)

	# Hover / selected highlight.
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.0, 0.35, 0.42, 0.65)
	popup.add_theme_stylebox_override("hover", hover)
	popup.add_theme_stylebox_override("selected", hover)
	popup.add_theme_stylebox_override("checked", hover)

	# Thin cyan separator line.
	var separator := StyleBoxLine.new()
	separator.color = Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.5)
	separator.thickness = 1
	separator.vertical = false
	popup.add_theme_stylebox_override("separator", separator)

	# Text colors and outline.
	popup.add_theme_color_override("font_color", COLOR_TEXT)
	popup.add_theme_color_override("font_hover_color", COLOR_HOVER)
	popup.add_theme_color_override("font_pressed_color", COLOR_HOVER)
	popup.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
	popup.add_theme_color_override("font_accelerator_color", COLOR_ACCELERATOR)
	popup.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	popup.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	popup.add_theme_font_size_override("font_size", font_size)


