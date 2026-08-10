class_name CP2020Theme
extends RefCounted

# Single source of truth for the cyberpunk terminal look.
#
# This class pairs the `themes/cyberpunk_theme.tres` Theme resource (which
# styles scene-tree controls via Godot's native theme inheritance) with the
# palette + programmatic helpers that a Theme cannot express:
#   - named Color constants needed by code to set label/button text colors
#     at runtime (Themes hold default colors but not arbitrary named ones),
#   - the PopupMenu applier (PopupMenus are built at runtime and cannot
#     inherit a scene's Theme),
#   - the MU-bar fill color that is mutated per ratio at runtime,
#   - StyleBox factories for the few controls still built in code
#     (e.g. the workbench Purchase-Unlocks window, dynamic buttons).

# --- Palette (canonical; mirrored previously by game_over.gd) ---
const COL_BG := Color(0.0, 0.07, 0.04, 1.0)
const COL_PANEL := Color(0.02, 0.06, 0.04, 0.96)
const COL_BORDER := Color(0.0, 1.0, 0.35, 0.65)
const COL_BORDER_DIM := Color(0.0, 0.55, 0.3, 0.5)
const COL_TEXT := Color(0.72, 1.0, 0.78)
const COL_DIM := Color(0.42, 0.58, 0.5)
const COL_WARN := Color(1.0, 0.3, 0.3)
const COL_AMBER := Color(1.0, 0.75, 0.2)
const COL_HEADER := Color(0.25, 1.0, 0.6)
const COL_GREEN := Color(0.2, 1.0, 0.4)
const COL_RED := Color(1.0, 0.25, 0.25)
const COL_GREY := Color(0.38, 0.45, 0.42)

# PopupMenu-specific palette (kept for the runtime applier below).
const COLOR_BG := Color(0.03, 0.05, 0.09, 0.92)
const COLOR_BORDER := Color(0.0, 0.78, 0.92, 0.75)
const COLOR_TEXT := Color(0.75, 0.95, 1.0, 1.0)
const COLOR_HOVER := Color(1.0, 1.0, 0.35, 1.0)
const COLOR_DISABLED := Color(0.4, 0.45, 0.5, 0.7)
const COLOR_ACCELERATOR := Color(0.5, 0.65, 0.7, 0.8)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)
const OUTLINE_SIZE := 4


# --- StyleBox factories (for code-built controls) ---

static func neon_style(color: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r * 0.12, color.g * 0.12, color.b * 0.12, 0.9)
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.border_color = color
	sb.content_margin_left = 10
	sb.content_margin_top = 6
	sb.content_margin_right = 10
	sb.content_margin_bottom = 6
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	return sb


static func panel_stylebox(with_border: bool = true) -> StyleBoxFlat:
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


static func transparent_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	return sb


# --- Node factories (for code-built controls) ---

static func make_label(text: String, color: Color, font_size: int = 21, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func make_header_label(text: String, big: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COL_HEADER)
	l.add_theme_font_size_override("font_size", 30 if big else 24)
	return l


static func make_rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = COL_BORDER_DIM
	return r


static func make_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color(color.r * 1.3, color.g * 1.3, color.b * 1.3))
	b.add_theme_color_override("font_pressed_color", color)
	b.add_theme_stylebox_override("normal", neon_style(color, 1, 3))
	b.add_theme_stylebox_override("hover", neon_style(Color(color.r * 1.2, color.g * 1.2, color.b * 1.2), 1, 3))
	b.add_theme_stylebox_override("pressed", neon_style(color, 1, 3))
	b.add_theme_stylebox_override("disabled", neon_style(COL_GREY, 1, 3))
	return b


static func make_mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "Menlo"])
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.generate_mipmaps = false
	return f


# --- Runtime helpers ---

# MU-bar fill color based on the used/total ratio (mutated per refresh).
static func mu_bar_fill_color(ratio: float) -> Color:
	if ratio >= 1.0:
		return Color(1.0, 0.25, 0.25)
	elif ratio >= 0.85:
		return Color(1.0, 0.4, 0.2)
	elif ratio >= 0.6:
		return Color(1.0, 0.7, 0.2)
	return COL_GREEN


# Apply the cyberpunk PopupMenu styling (PopupMenus are runtime-built and
# cannot inherit a scene Theme). Font size is configurable per context.
static func apply_cyberpunk_theme(popup: PopupMenu, font_size: int = 24) -> void:
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
