extends Control

# GameOver screen — shown when a run ends in permadeath (Flatlined or Busted).
# The death cause + run summary are passed in via RunState transient fields
# (set by cp2020_game_session just before the scene change). The "New Life"
# button is the ONLY place that calls RunState.start_new_life() for the
# permadeath flow (besides first-life init in the workbench).

# Cyberpunk theme palette (mirrors cyberdeck_workbench.gd for visual consistency).
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

func _ready() -> void:
	# Base background colour.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = COL_BG
	bg.show_behind_parent = true
	add_child(bg)

	var cause: String = RunState.last_death_cause
	var summary: Dictionary = RunState.last_run_summary

	# Resolve header + flavour text from the death cause.
	var header_text: String = "GAME OVER"
	var flavour_text: String = "The run ended."
	if cause == "Flatlined":
		header_text = "FLATLINED"
		flavour_text = "Your neural link flatlined in the datafort. The Net claims another runner."
	elif cause == "Busted":
		header_text = "BUSTED"
		flavour_text = "NetWatch traced your signal and busted you on jack-out. They confiscated everything."

	# Outer margin frame.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	# Big header.
	var header := Label.new()
	header.text = "◢ %s ◣" % header_text
	header.add_theme_color_override("font_color", COL_RED if cause != "" else COL_WARN)
	header.add_theme_font_size_override("font_size", 42)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(header)

	root.add_child(_make_rule())

	# Flavour line.
	root.add_child(_make_label(flavour_text, COL_AMBER, 16, true))

	# Run summary card.
	var card := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	col.add_child(_make_header_label("RUN SUMMARY"))

	var trace_val: int = int(summary.get("trace", 0))
	var credits_val: int = int(summary.get("credits", 0))
	var loot_val: int = int(summary.get("loot_count", 0))
	var datafort_val: String = String(summary.get("datafort", ""))
	if datafort_val == "":
		datafort_val = "—"

	col.add_child(_make_label("Trace reached: %d" % trace_val, COL_TEXT))
	col.add_child(_make_label("Credits lost: %d eb" % credits_val, COL_TEXT))
	col.add_child(_make_label("Loot lost: %d program(s)" % loot_val, COL_TEXT))
	col.add_child(_make_label("Datafort: %s" % datafort_val, COL_DIM))
	root.add_child(card)

	# Catalogue-persists note.
	root.add_child(_make_label(
		"Your contacts keep your discovered software in the catalogue. Next life, you can rebuy it at the hub.",
		COL_HEADER, 14, true))

	# Spacer pushes the button toward the bottom.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	# New Life button.
	var new_life_btn := Button.new()
	new_life_btn.text = "[ NEW LIFE ]"
	new_life_btn.add_theme_font_size_override("font_size", 22)
	new_life_btn.add_theme_color_override("font_color", Color(0.0, 0.05, 0.02))
	new_life_btn.add_theme_color_override("font_hover_color", Color(0.0, 0.0, 0.0))
	var btn_style := _neon_style(COL_GREEN, 2, 6)
	new_life_btn.add_theme_stylebox_override("normal", btn_style)
	new_life_btn.add_theme_stylebox_override("hover", _neon_style(Color(0.4, 1.0, 0.6), 2, 6))
	new_life_btn.add_theme_stylebox_override("pressed", _neon_style(COL_GREEN, 2, 6))
	new_life_btn.pressed.connect(_on_new_life_pressed)
	# Center the button.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_child(new_life_btn)
	root.add_child(btn_row)


func _on_new_life_pressed() -> void:
	RunState.start_new_life()
	RunState.clear_run_save()
	get_tree().change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")


# --- UI helpers (minimal equivalents of cyberdeck_workbench.gd helpers) ---

func _styled_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = COL_BORDER
	sb.content_margin_left = 14
	sb.content_margin_top = 12
	sb.content_margin_right = 14
	sb.content_margin_bottom = 12
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _neon_style(color: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r * 0.12, color.g * 0.12, color.b * 0.12, 0.9)
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.border_color = color
	sb.content_margin_left = 12
	sb.content_margin_top = 8
	sb.content_margin_right = 12
	sb.content_margin_bottom = 8
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	return sb


func _make_label(text: String, color: Color, font_size: int = 14, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _make_header_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COL_HEADER)
	l.add_theme_font_size_override("font_size", 18)
	return l


func _make_rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = COL_BORDER_DIM
	return r