extends Control

# All selectable cyberdecks (assigned in the Inspector).
@export var available_decks: Array[Cyberdeck] = []

# The complete library of programs the runner can choose to load.
@export var available_programs: Array[NetProgram] = []

# Currently active deck selected from the dropdown.
var active_deck: Cyberdeck

# Selection state for the two lists.
var _selected_library_idx: int = -1
var _selected_loaded_idx: int = -1

# Library filter: maps filter OptionButton index -> EffectType (null = All).
var _filter_effects: Array = []

# --- UI references (built in code) ---
var deck_selector: OptionButton
var model_label: Label
var speed_label: Label
var mu_label: Label
var mu_bar: ProgressBar
var _mu_fill: StyleBoxFlat
var strength_label: Label
var interface_label: Label
var loaded_list: ItemList
var library_list: ItemList
var filter_option: OptionButton
var detail_name: Label
var detail_type: Label
var detail_effect: Label
var detail_str: Label
var detail_mu: Label
var detail_price: Label
var detail_desc: Label
var detail_card: PanelContainer
var load_button: Button
var unload_button: Button
var clear_button: Button
var jack_button: Button
var mu_message: Label

# Human-readable tags for each program effect type.
const EFFECT_TAGS: Dictionary = {
	NetProgram.EffectType.BYPASS_GATE: "Intrusion",
	NetProgram.EffectType.BREACH_WALL: "Breach",
	NetProgram.EffectType.DEREZ_ICE: "Anti-ICE",
	NetProgram.EffectType.DAMAGE_RUNNER: "Anti-Personnel",
	NetProgram.EffectType.REVEAL_NODES: "Reveal",
	NetProgram.EffectType.MODIFY_MU: "Utility",
	NetProgram.EffectType.SHIELD: "Defense",
}

# Neon color per effect type (used for list chips + detail).
const EFFECT_COLORS: Dictionary = {
	NetProgram.EffectType.BYPASS_GATE: Color(1.0, 0.6, 0.15),
	NetProgram.EffectType.BREACH_WALL: Color(1.0, 0.3, 0.3),
	NetProgram.EffectType.DEREZ_ICE: Color(0.25, 0.9, 1.0),
	NetProgram.EffectType.DAMAGE_RUNNER: Color(1.0, 0.35, 0.8),
	NetProgram.EffectType.REVEAL_NODES: Color(1.0, 0.9, 0.3),
	NetProgram.EffectType.MODIFY_MU: Color(0.4, 1.0, 0.45),
	NetProgram.EffectType.SHIELD: Color(0.35, 0.55, 1.0),
}

const PROGRAM_TYPE_NAMES: Dictionary = {
	NetProgram.ProgramType.INTRUSION: "Intrusion",
	NetProgram.ProgramType.DECRYPTION: "Decryption",
	NetProgram.ProgramType.DETECTION: "Detection",
	NetProgram.ProgramType.ANTI_PROGRAM: "Anti-Program",
	NetProgram.ProgramType.ANTI_PERSONNEL: "Anti-Personnel",
	NetProgram.ProgramType.ANTI_SYSTEM: "Anti-System",
	NetProgram.ProgramType.UTILITY: "Utility",
	NetProgram.ProgramType.ICE: "ICE",
}

# Cyberpunk theme palette.
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
	_build_ui()
	deck_selector.clear()
	for deck in available_decks:
		deck_selector.add_item(deck.deck_name)
	if not available_decks.is_empty():
		active_deck = available_decks[0]
		deck_selector.select(0)
	update_deck_ui()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	# Margin frame around everything.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# Title bar.
	root.add_child(_make_header_label("◢ CYBERDECK WORKBENCH ◣", true))

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)
	root.add_child(main)

	# --- LEFT: deck stats card ---
	main.add_child(_build_deck_column())

	# --- CENTER: loaded programs + controls ---
	main.add_child(_build_loaded_column())

	# --- RIGHT: library + filter + detail ---
	main.add_child(_build_library_column())

	# MU overflow / status message + Jack In button row.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	mu_message = _make_label("", COL_WARN)
	mu_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(mu_message)

	jack_button = Button.new()
	jack_button.text = "[ JACK IN ]"
	jack_button.add_theme_font_size_override("font_size", 18)
	jack_button.add_theme_color_override("font_color", Color(0.0, 0.05, 0.02))
	jack_button.add_theme_color_override("font_hover_color", Color(0.0, 0.0, 0.0))
	var jb_style := _neon_style(COL_GREEN, 2, 6)
	jack_button.add_theme_stylebox_override("normal", jb_style)
	jack_button.add_theme_stylebox_override("hover", _neon_style(Color(0.4, 1.0, 0.6), 2, 6))
	jack_button.add_theme_stylebox_override("pressed", _neon_style(COL_GREEN, 2, 6))
	jack_button.pressed.connect(_on_button_pressed)
	footer.add_child(jack_button)
	root.add_child(footer)

func _build_deck_column() -> Control:
	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	col.add_child(_make_header_label("DECK STATS"))
	deck_selector = OptionButton.new()
	deck_selector.item_selected.connect(_on_deck_selector_item_selected)
	col.add_child(deck_selector)

	col.add_child(_make_rule())
	model_label = _make_label("Model:", COL_TEXT)
	speed_label = _make_label("Speed Bonus: +0", COL_TEXT)
	mu_label = _make_label("Memory Units (MU): 0 / 0", COL_TEXT)
	col.add_child(model_label)
	col.add_child(speed_label)
	col.add_child(mu_label)

	_mu_fill = StyleBoxFlat.new()
	_mu_fill.bg_color = COL_GREEN
	_mu_fill.corner_radius_top_left = 2
	_mu_fill.corner_radius_top_right = 2
	_mu_fill.corner_radius_bottom_left = 2
	_mu_fill.corner_radius_bottom_right = 2
	mu_bar = ProgressBar.new()
	mu_bar.custom_minimum_size = Vector2(220, 22)
	mu_bar.show_percentage = false
	mu_bar.add_theme_stylebox_override("fill", _mu_fill)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.0, 0.18, 0.1, 1.0)
	bar_bg.border_width_bottom = 1
	bar_bg.border_width_top = 1
	bar_bg.border_width_left = 1
	bar_bg.border_width_right = 1
	bar_bg.border_color = COL_BORDER_DIM
	bar_bg.corner_radius_top_left = 2
	bar_bg.corner_radius_top_right = 2
	bar_bg.corner_radius_bottom_left = 2
	bar_bg.corner_radius_bottom_right = 2
	mu_bar.add_theme_stylebox_override("background", bar_bg)
	col.add_child(mu_bar)

	strength_label = _make_label("Data Wall STR: 0", COL_TEXT)
	interface_label = _make_label("Interface Rank: 6", COL_TEXT)
	col.add_child(strength_label)
	col.add_child(interface_label)
	return panel

func _build_loaded_column() -> Control:
	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	col.add_child(_make_header_label("LOADED INTO MEMORY"))

	loaded_list = ItemList.new()
	loaded_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loaded_list.item_selected.connect(_on_loaded_item_selected)
	loaded_list.item_activated.connect(_on_loaded_item_activated)
	loaded_list.add_theme_stylebox_override("panel", _transparent_style())
	loaded_list.add_theme_color_override("font_color", COL_TEXT)
	col.add_child(loaded_list)

	# Controls row.
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER

	unload_button = _make_button("◀ UNLOAD", COL_AMBER)
	unload_button.pressed.connect(_on_unload_pressed)
	btns.add_child(unload_button)

	load_button = _make_button("LOAD ▶", COL_GREEN)
	load_button.pressed.connect(_on_load_pressed)
	btns.add_child(load_button)

	clear_button = _make_button("CLEAR", COL_WARN)
	clear_button.pressed.connect(_on_clear_pressed)
	btns.add_child(clear_button)

	col.add_child(btns)
	return panel

func _build_library_column() -> Control:
	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.25
	panel.add_child(col)

	col.add_child(_make_header_label("PROGRAM LIBRARY"))

	# Filter row.
	var filter_row := HBoxContainer.new()
	_setup_filter_row(filter_row)
	col.add_child(filter_row)

	library_list = ItemList.new()
	library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_list.item_selected.connect(_on_library_item_selected)
	library_list.item_activated.connect(_on_library_item_activated)
	library_list.add_theme_stylebox_override("panel", _transparent_style())
	library_list.add_theme_color_override("font_color", COL_TEXT)
	col.add_child(library_list)

	# Detail card.
	detail_card = _styled_panel(false)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 4)
	detail_card.add_child(dcol)

	detail_name = _make_label("— select a program —", COL_HEADER)
	detail_name.add_theme_font_size_override("font_size", 16)
	dcol.add_child(detail_name)
	detail_type = _make_label("", COL_DIM)
	detail_effect = _make_label("", COL_DIM)
	detail_str = _make_label("", COL_DIM)
	detail_mu = _make_label("", COL_DIM)
	detail_price = _make_label("", COL_DIM)
	dcol.add_child(detail_type)
	dcol.add_child(detail_effect)
	dcol.add_child(detail_str)
	dcol.add_child(detail_mu)
	dcol.add_child(detail_price)
	dcol.add_child(_make_rule())
	detail_desc = _make_label("", COL_TEXT)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.custom_minimum_size = Vector2(0, 40)
	dcol.add_child(detail_desc)
	col.add_child(detail_card)
	return panel

func _setup_filter_row(row: HBoxContainer) -> void:
	row.add_theme_constant_override("separation", 8)
	var fl := _make_label("Filter:", COL_DIM)
	row.add_child(fl)
	filter_option = OptionButton.new()
	filter_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_effects = [null]
	filter_option.add_item("All")
	for et in EFFECT_TAGS.keys():
		_filter_effects.append(et)
		filter_option.add_item(EFFECT_TAGS[et])
	filter_option.item_selected.connect(_on_filter_changed)
	row.add_child(filter_option)

# ---------------------------------------------------------------------------
# Refresh / update
# ---------------------------------------------------------------------------
func update_deck_ui() -> void:
	if not active_deck:
		return
	model_label.text = "Model: " + active_deck.deck_name
	speed_label.text = "Speed Bonus: +%d" % active_deck.speed_bonus
	var used_mu := active_deck.get_used_mu()
	mu_label.text = "Memory Units (MU): %d / %d" % [used_mu, active_deck.max_mu]
	mu_bar.max_value = active_deck.max_mu
	mu_bar.value = used_mu
	var ratio := float(used_mu) / float(max(active_deck.max_mu, 1))
	if ratio >= 1.0:
		_mu_fill.bg_color = COL_RED
	elif ratio >= 0.7:
		_mu_fill.bg_color = COL_AMBER
	else:
		_mu_fill.bg_color = COL_GREEN
	strength_label.text = "Data Wall STR: %d" % active_deck.data_wall_strength
	interface_label.text = "Interface Rank: %d" % active_deck.interface_rank
	_refresh_loaded()
	_refresh_library()
	_clear_message()

func _refresh_loaded() -> void:
	loaded_list.clear()
	for prog in active_deck.installed_programs:
		if not prog:
			loaded_list.add_item("(empty slot)", null, false)
			loaded_list.set_item_custom_fg_color(loaded_list.item_count - 1, COL_GREY)
			continue
		var tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
		var col: Color = EFFECT_COLORS.get(prog.effect_type, COL_TEXT)
		var icon := prog.icon as Texture2D
		loaded_list.add_item("%s  [%s]  (%d MU)" % [prog.program_name, tag, prog.memory_cost], icon, false)
		loaded_list.set_item_custom_fg_color(loaded_list.item_count - 1, col)
	_selected_loaded_idx = -1

func _refresh_library() -> void:
	library_list.clear()
	var free_mu := active_deck.max_mu - active_deck.get_used_mu()
	var filter_et = _filter_effects[filter_option.selected] if filter_option else null
	for prog in available_programs:
		if not prog:
			continue
		if filter_et != null and prog.effect_type != filter_et:
			continue
		var tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
		var col: Color = EFFECT_COLORS.get(prog.effect_type, COL_TEXT)
		var icon := prog.icon as Texture2D
		var loaded := _is_loaded(prog)
		var fits := (free_mu >= prog.memory_cost) or loaded
		var suffix := "  [LOADED]" if loaded else ""
		library_list.add_item("%s  [%s]  (%d MU)%s" % [prog.program_name, tag, prog.memory_cost, suffix], icon, false)
		var idx := library_list.item_count - 1
		library_list.set_item_metadata(idx, prog)
		if not fits:
			library_list.set_item_disabled(idx, true)
			library_list.set_item_custom_fg_color(idx, COL_GREY)
		else:
			library_list.set_item_custom_fg_color(idx, col)
	_selected_library_idx = -1

func _is_loaded(prog: NetProgram) -> bool:
	for loaded in active_deck.installed_programs:
		if loaded == prog:
			return true
	return false

func _clear_message() -> void:
	if mu_message:
		mu_message.text = ""

func _show_message(text: String, color: Color = COL_WARN) -> void:
	if mu_message:
		mu_message.text = text
		mu_message.add_theme_color_override("font_color", color)

# ---------------------------------------------------------------------------
# Detail card
# ---------------------------------------------------------------------------
func _show_detail(prog: NetProgram) -> void:
	if not prog:
		detail_name.text = "— select a program —"
		detail_name.add_theme_color_override("font_color", COL_HEADER)
		detail_type.text = ""
		detail_effect.text = ""
		detail_str.text = ""
		detail_mu.text = ""
		detail_price.text = ""
		detail_desc.text = ""
		return
	var col: Color = EFFECT_COLORS.get(prog.effect_type, COL_TEXT)
	detail_name.text = prog.program_name
	detail_name.add_theme_color_override("font_color", col)
	detail_type.text = "Type: " + String(PROGRAM_TYPE_NAMES.get(prog.type, "?"))
	detail_effect.text = "Effect: " + String(EFFECT_TAGS.get(prog.effect_type, "?"))
	detail_str.text = "Strength: %d" % prog.strength
	detail_mu.text = "Memory Cost: %d MU" % prog.memory_cost
	detail_price.text = "Price: %d eb" % prog.price
	detail_desc.text = prog.description if prog.description != "" else "No data on file."

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
func _on_deck_selector_item_selected(index: int) -> void:
	if index >= 0 and index < available_decks.size():
		active_deck = available_decks[index]
		update_deck_ui()

func _on_filter_changed(_index: int) -> void:
	_refresh_library()

func _on_library_item_selected(index: int) -> void:
	_selected_library_idx = index
	var prog := library_list.get_item_metadata(index) as NetProgram
	_show_detail(prog)

func _on_library_item_activated(index: int) -> void:
	_load_program_at(index)

func _on_loaded_item_selected(index: int) -> void:
	_selected_loaded_idx = index
	var prog := active_deck.installed_programs[index] as NetProgram
	_show_detail(prog)

func _on_loaded_item_activated(index: int) -> void:
	_unload_program_at(index)

func _on_load_pressed() -> void:
	if _selected_library_idx >= 0:
		_load_program_at(_selected_library_idx)

func _on_unload_pressed() -> void:
	if _selected_loaded_idx >= 0:
		_unload_program_at(_selected_loaded_idx)
	else:
		_show_message("Select a loaded program to unload.")

func _on_clear_pressed() -> void:
	if not active_deck:
		return
	active_deck.installed_programs.clear()
	update_deck_ui()
	_show_message("Loadout cleared.", COL_AMBER)

func _load_program_at(index: int) -> void:
	if index < 0 or index >= library_list.item_count:
		return
	var prog := library_list.get_item_metadata(index) as NetProgram
	if not prog:
		return
	if _is_loaded(prog):
		_show_message("%s is already loaded." % prog.program_name, COL_AMBER)
		return
	var free_mu := active_deck.max_mu - active_deck.get_used_mu()
	if prog.memory_cost > free_mu:
		_show_message("MEMORY FULL: %s needs %d MU, only %d free." % [prog.program_name, prog.memory_cost, free_mu])
		return
	active_deck.installed_programs.append(prog)
	update_deck_ui()

func _unload_program_at(index: int) -> void:
	if index < 0 or index >= active_deck.installed_programs.size():
		return
	var prog := active_deck.installed_programs[index] as NetProgram
	if prog:
		active_deck.installed_programs.erase(prog)
		update_deck_ui()

func _on_button_pressed() -> void:
	if not active_deck:
		_show_message("Error: No active deck selected for neural link!")
		return
	if active_deck.installed_programs.is_empty():
		_show_message("WARNING: No programs loaded. Jack in anyway?", COL_AMBER)
		return
	print("Initiating neural link with %s... Jacking into the Net!" % active_deck.deck_name)
	RunState.selected_deck = active_deck
	get_tree().change_scene_to_file("res://scenes/ui/cp2020_world_net_map.tscn")

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
func _styled_panel(with_border: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	if with_border:
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = COL_BORDER
		sb.content_margin_left = 12
		sb.content_margin_top = 10
		sb.content_margin_right = 12
		sb.content_margin_bottom = 10
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
	sb.content_margin_left = 10
	sb.content_margin_top = 6
	sb.content_margin_right = 10
	sb.content_margin_bottom = 6
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	return sb

func _transparent_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	return sb

func _make_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 14)
	return l

func _make_header_label(text: String, big: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COL_HEADER)
	l.add_theme_font_size_override("font_size", 20 if big else 16)
	return l

func _make_rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = COL_BORDER_DIM
	return r

func _make_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color(color.r * 1.3, color.g * 1.3, color.b * 1.3))
	b.add_theme_color_override("font_pressed_color", color)
	b.add_theme_stylebox_override("normal", _neon_style(color, 1, 3))
	b.add_theme_stylebox_override("hover", _neon_style(Color(color.r * 1.2, color.g * 1.2, color.b * 1.2), 1, 3))
	b.add_theme_stylebox_override("pressed", _neon_style(color, 1, 3))
	b.add_theme_stylebox_override("disabled", _neon_style(COL_GREY, 1, 3))
	return b
