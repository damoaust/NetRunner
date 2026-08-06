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
var mu_overlay_label: Label
var mu_overflow_badge: Label
var strength_label: Label
var interface_label: Label
var loaded_summary_label: Label
var meta_label: Label
var loaded_list: ItemList
var library_list: ItemList
var filter_option: OptionButton
var detail_name: Label

# Netrunner Status column
var runner_portrait_label: Label
var callsign_label: Label
var role_label: Label
var stat_ref_label: Label
var stat_luck_label: Label
var hp_label: Label
var wounds_label: Label
var trace_label: Label
var net_cred_label: Label
var run_label: Label
var tips_label: Label
var detail_cursor_label: Label
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
var destination_label: Label

# --- Shop panel references (built in code) ---
var credits_label: Label
var shop_buy_decks_list: ItemList
var shop_buy_programs_list: ItemList
var shop_sell_loot_list: ItemList
var shop_sell_files_list: ItemList
var buy_deck_button: Button
var buy_program_button: Button
var sell_loot_button: Button
var sell_file_button: Button
# --- Purchase Unlocks window (permanent MetaState blueprint unlocks) ---
var unlock_button: Button
var unlock_window: Window
var unlock_list: ItemList
var unlock_buy_button: Button
var unlock_credits_label: Label
var _selected_unlock_idx: int = -1
var _unlockable_decks: Array[String] = []
var _unlockable_programs: Array[String] = []
var _unlock_scanned: bool = false
var _selected_buy_deck_idx: int = -1
var _selected_buy_program_idx: int = -1
var _selected_sell_loot_idx: int = -1
var _selected_sell_file_idx: int = -1

# Shared monospace terminal font applied across the workbench UI.
var _mono_font: SystemFont

# Human-readable tags for each program effect type.
const EFFECT_TAGS: Dictionary = {
	NetProgram.EffectType.BYPASS_GATE: "Intrusion",
	NetProgram.EffectType.BREACH_WALL: "Breach",
	NetProgram.EffectType.DEREZ_ICE: "Anti-ICE",
	NetProgram.EffectType.DAMAGE_RUNNER: "Anti-Pers",
	NetProgram.EffectType.REVEAL_NODES: "Reveal",
	NetProgram.EffectType.MODIFY_MU: "Utility",
	NetProgram.EffectType.SHIELD: "Defense",
	NetProgram.EffectType.WORM: "Worm",
	NetProgram.EffectType.DETECTION: "Detect",
}

# Compact tag used inline in list rows where horizontal space is at a premium
# (the library column on a 1280px viewport). Falls back to the full EFFECT_TAGS
# entry on the detail card where there's more room.
const EFFECT_TAGS_COMPACT: Dictionary = {
	NetProgram.EffectType.BYPASS_GATE: "Intr",
	NetProgram.EffectType.BREACH_WALL: "Brch",
	NetProgram.EffectType.DEREZ_ICE: "A-ICE",
	NetProgram.EffectType.DAMAGE_RUNNER: "A-P",
	NetProgram.EffectType.REVEAL_NODES: "Rev",
	NetProgram.EffectType.MODIFY_MU: "Util",
	NetProgram.EffectType.SHIELD: "Def",
	NetProgram.EffectType.WORM: "Worm",
	NetProgram.EffectType.DETECTION: "Det",
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
	# First launch / after permadeath: ensure a life is in progress with
	# starting gear before building the loadout. RunState autoload already
	# attempts to load a saved run from the previous session.
	if RunState.owned_decks.is_empty():
		RunState.start_new_life()
	_build_ui()
	# Default active deck to the previously equipped deck if still owned,
	# else the first owned deck.
	var decks := _owned_decks()
	if RunState.selected_deck != null and decks.has(RunState.selected_deck):
		active_deck = RunState.selected_deck
	elif not decks.is_empty():
		active_deck = decks[0]
	_refresh_deck_selector()
	update_deck_ui()
	_refresh_shop()
	_start_cursor_blink()
	_start_jackin_pulse()
	_setup_drag_drop()

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_mono_font = _make_mono_font()
	# Margin frame around everything.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	# Title bar + credits readout.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	var title := _make_header_label("◢ CYBERDECK WORKBENCH ◣", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	credits_label = _make_label("CREDITS: 0 eb", COL_AMBER)
	credits_label.add_theme_font_size_override("font_size", 20)
	credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits_label.custom_minimum_size = Vector2(220, 0)
	title_row.add_child(credits_label)
	root.add_child(title_row)

	# Tabbed content: LOADOUT + SHOP, so every list gets full height.
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tab_container(tabs)
	root.add_child(tabs)

	# LOADOUT tab: deck stats | loaded programs | library+detail | netrunner status.
	# Stretch ratios widen the Library column (it hosts the biggest list) and
	# the Netrunner column (so its labels have room) without burning extra
	# width on the DECK STATS column.
	var loadout := HBoxContainer.new()
	loadout.name = "LOADOUT"
	loadout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loadout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout.add_theme_constant_override("separation", 8)
	var deck_col := _build_deck_column()
	deck_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_col.size_flags_stretch_ratio = 1.0
	loadout.add_child(deck_col)
	var loaded_col := _build_loaded_column()
	loaded_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loaded_col.size_flags_stretch_ratio = 1.0
	loaded_col.custom_minimum_size = Vector2(200, 0)
	loadout.add_child(loaded_col)
	var library_col := _build_library_column()
	library_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_col.size_flags_stretch_ratio = 1.0
	library_col.custom_minimum_size = Vector2(200, 0)
	loadout.add_child(library_col)
	var runner_col := _build_netrunner_column()
	runner_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	runner_col.size_flags_stretch_ratio = 1.0
	runner_col.custom_minimum_size = Vector2(280, 0)
	loadout.add_child(runner_col)
	tabs.add_child(loadout)
	tabs.tab_changed.connect(_on_tab_changed)

	# SHOP tab: 2x2 grid of buy/sell sections.
	tabs.add_child(_build_shop_tab())

	# MU overflow / status message + Jack In button row (always visible).
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	mu_message = _make_label("", COL_WARN)
	mu_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(mu_message)

	destination_label = _make_label("→ Last subnet: —", COL_DIM)
	destination_label.add_theme_font_size_override("font_size", 12)
	destination_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(destination_label)

	jack_button = Button.new()
	jack_button.text = "[ J ]  JACK IN"
	jack_button.add_theme_font_size_override("font_size", 18)
	jack_button.add_theme_color_override("font_color", COL_GREEN)
	jack_button.add_theme_color_override("font_hover_color", Color(0.6, 1.0, 0.7))
	var jb_style := _neon_style(COL_GREEN, 2, 6)
	jack_button.add_theme_stylebox_override("normal", jb_style)
	jack_button.add_theme_stylebox_override("hover", _neon_style(Color(0.4, 1.0, 0.6), 2, 6))
	jack_button.add_theme_stylebox_override("pressed", _neon_style(COL_GREEN, 2, 6))
	jack_button.tooltip_text = "Jack into the Net using the selected deck and loaded programs (Shortcut: J)"
	jack_button.pressed.connect(_on_button_pressed)
	footer.add_child(jack_button)
	root.add_child(footer)

	# Apply the monospace terminal font to every text control we built.
	_apply_terminal_theme(self)

	# CRT overlay on top of everything (non-interactive).
	add_child(_build_crt_overlay())

func _build_deck_column() -> Control:
	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	col.add_child(_make_header_label("DECK STATS"))
	deck_selector = OptionButton.new()
	deck_selector.item_selected.connect(_on_deck_selector_item_selected)
	deck_selector.tooltip_text = "Switch between owned cyberdecks this life"
	col.add_child(deck_selector)

	col.add_child(_make_rule())
	model_label = _make_label("Model:", COL_TEXT)
	speed_label = _make_label("Speed Bonus: +0", COL_TEXT)
	mu_label = _make_label("Memory Units (MU): 0 / 0", COL_TEXT)
	col.add_child(model_label)
	col.add_child(speed_label)
	col.add_child(mu_label)

	# Bar with overlaid MU numbers and OVER LIMIT badge. The bar fills the
	# column width; the numeric overlay is layered ON TOP using anchors.
	mu_bar = ProgressBar.new()
	mu_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mu_bar.custom_minimum_size = Vector2(0, 22)
	mu_bar.show_percentage = false
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
	mu_bar.add_theme_stylebox_override("fill", _build_gradient_fill())

	# Overlay sits ON TOP of the bar via a Control container with both children
	# anchored preset = full rect.
	var bar_overlay := Control.new()
	bar_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_overlay.custom_minimum_size = Vector2(0, 22)
	bar_overlay.add_child(mu_bar)
	mu_bar.set_anchors_preset(Control.PRESET_FULL_RECT)

	mu_overlay_label = _make_label("0 / 0", Color(0.95, 1.0, 0.95))
	mu_overlay_label.add_theme_font_size_override("font_size", 13)
	mu_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mu_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mu_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mu_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_overlay.add_child(mu_overlay_label)

	mu_overflow_badge = _make_label("", COL_WARN)
	mu_overflow_badge.add_theme_font_size_override("font_size", 12)
	mu_overflow_badge.visible = false
	mu_overflow_badge.tooltip_text = "You have more programs loaded than the active deck's MU allows."
	col.add_child(bar_overlay)
	col.add_child(mu_overflow_badge)

	strength_label = _make_label("Data Wall STR: 0", COL_TEXT)
	interface_label = _make_label("Interface Rank: 0", COL_TEXT)
	col.add_child(strength_label)
	col.add_child(interface_label)

	col.add_child(_make_rule())
	col.add_child(_make_header_label("LOADOUT SUMMARY"))
	loaded_summary_label = _make_label("No programs loaded.", COL_DIM)
	loaded_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(loaded_summary_label)
	col.add_child(_make_rule())
	meta_label = _make_label("// TOTAL KILLS: 0\n// DATAJACK: OFFLINE\n// SUBNETS CLEARED: 0", COL_DIM)
	meta_label.add_theme_font_size_override("font_size", 12)
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(meta_label)
	return panel

# Build a per-frame gradient fill (green → amber → red) for the MU bar.
# 0..50% green, 50..70% green→amber, 70..100% amber→red, and the red tail uses
# diagonal stripes to convey overflow state.
func _build_gradient_fill() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_GREEN
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb

# We re-color the fill each refresh based on ratio; solid color is fine.
func _set_mu_bar_color(ratio: float) -> void:
	if mu_bar == null:
		return
	var fill: StyleBoxFlat = mu_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null:
		# Older Godot 4 versions expose fill via override; rebuild if needed.
		fill = _build_gradient_fill()
		mu_bar.add_theme_stylebox_override("fill", fill)
	if ratio >= 1.0:
		fill.bg_color = Color(1.0, 0.25, 0.25)
	elif ratio >= 0.85:
		fill.bg_color = Color(1.0, 0.4, 0.2)
	elif ratio >= 0.6:
		fill.bg_color = Color(1.0, 0.7, 0.2)
	else:
		fill.bg_color = COL_GREEN
	fill = fill  # keep stylebox reference live

func _build_loaded_column() -> Control:
	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	col.add_child(_make_header_label("LOADED INTO MEMORY"))

	loaded_list = ItemList.new()
	loaded_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loaded_list.custom_minimum_size = Vector2(0, 180)
	loaded_list.add_theme_font_size_override("font_size", 12)
	loaded_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loaded_list.item_selected.connect(_on_loaded_item_selected)
	loaded_list.item_activated.connect(_on_loaded_item_activated)
	loaded_list.tooltip_text = "Programs currently loaded into the deck's MU. Double-click or [U] to unload."
	_style_list(loaded_list)
	col.add_child(loaded_list)

	# Controls row.
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	unload_button = _make_button("[U] ▶", COL_AMBER)
	unload_button.tooltip_text = "Unload the selected program from the deck [U]"
	unload_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unload_button.pressed.connect(_on_unload_pressed)
	btns.add_child(unload_button)

	load_button = _make_button("[L] LOAD ▶", COL_GREEN)
	load_button.tooltip_text = "Load the highlighted library program into the deck [L]"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_on_load_pressed)
	btns.add_child(load_button)

	clear_button = _make_button("[C] CLR", COL_WARN)
	clear_button.tooltip_text = "Clear ALL loaded programs from the deck [C]"
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.pressed.connect(_on_clear_pressed)
	btns.add_child(clear_button)

	col.add_child(btns)
	return panel

func _build_library_column() -> Control:
	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	# Header row: title on the left, inline filter on the right so the
	# dropdown does NOT steal a row of vertical space.
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	var title := _make_header_label("PROGRAM LIBRARY")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	col.add_child(header_row)

	# Build the filter row here so we can shrink-wrap the dropdown and tuck
	# it next to the title; keep the helper for the dropdown construction.
	var filter_inline := HBoxContainer.new()
	filter_inline.add_theme_constant_override("separation", 6)
	var fl := _make_label("Filter:", COL_DIM)
	filter_inline.add_child(fl)
	filter_option = OptionButton.new()
	filter_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_effects = [null]
	filter_option.add_item("All")
	for et in EFFECT_TAGS.keys():
		_filter_effects.append(et)
		filter_option.add_item(EFFECT_TAGS[et])
	filter_option.item_selected.connect(_on_filter_changed)
	filter_inline.add_child(filter_option)
	filter_inline.tooltip_text = "Limit the library to one program effect type"
	col.add_child(filter_inline)

	library_list = ItemList.new()
	library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_list.custom_minimum_size = Vector2(0, 180)
	library_list.add_theme_font_size_override("font_size", 12)
	library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_list.item_selected.connect(_on_library_item_selected)
	library_list.item_activated.connect(_on_library_item_activated)
	library_list.tooltip_text = "Programs available to load (owned this life). Double-click or [L] to load."
	_style_list(library_list)
	col.add_child(library_list)

	# Detail card.
	detail_card = _styled_panel(false)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 4)
	dcol.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_card.add_child(dcol)

	detail_name = _make_label("— select a program —", COL_HEADER)
	detail_name.add_theme_font_size_override("font_size", 16)
	detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dcol.add_child(detail_name)
	detail_cursor_label = _make_label("_", COL_GREEN)
	detail_cursor_label.add_theme_font_size_override("font_size", 14)
	dcol.add_child(detail_cursor_label)
	detail_type = _make_label("", COL_DIM)
	detail_effect = _make_label("", COL_DIM)
	detail_str = _make_label("", COL_DIM)
	detail_mu = _make_label("", COL_DIM)
	detail_price = _make_label("", COL_DIM)
	detail_type.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_str.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_mu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dcol.add_child(detail_type)
	dcol.add_child(detail_effect)
	dcol.add_child(detail_str)
	dcol.add_child(detail_mu)
	dcol.add_child(detail_price)
	dcol.add_child(_make_rule())
	detail_desc = _make_label("", COL_TEXT)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_desc.custom_minimum_size = Vector2(0, 40)
	dcol.add_child(detail_desc)
	col.add_child(detail_card)
	return panel

# 4th column: Netrunner Status (portrait + stats + where am I going?)
# Fills the previously-empty right half of the screen. Stretch ratio is set
# on the caller so other columns get fair share.
func _build_netrunner_column() -> Control:
	var panel := _styled_panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	col.add_child(_make_header_label("NETRUNNER"))
	var portrait_box := PanelContainer.new()
	var portrait_bg := StyleBoxFlat.new()
	portrait_bg.bg_color = Color(0.0, 0.02, 0.01, 0.9)
	portrait_bg.border_width_left = 1
	portrait_bg.border_width_top = 1
	portrait_bg.border_width_right = 1
	portrait_bg.border_width_bottom = 1
	portrait_bg.border_color = COL_BORDER_DIM
	portrait_box.add_theme_stylebox_override("panel", portrait_bg)

	runner_portrait_label = Label.new()
	runner_portrait_label.text = _runner_ascii_portrait("SHADOW")
	runner_portrait_label.add_theme_font_size_override("font_size", 11)
	runner_portrait_label.add_theme_color_override("font_color", COL_HEADER)
	runner_portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	runner_portrait_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	portrait_box.add_child(runner_portrait_label)
	col.add_child(portrait_box)

	callsign_label = _make_label("// CALLSIGN: ----", COL_HEADER)
	callsign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_label = _make_label("// ROLE: NETRUNNER", COL_DIM)
	role_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(callsign_label)
	col.add_child(role_label)
	col.add_child(_make_rule())

	stat_ref_label = _make_label("REF/INT/BODY: 0 / 0 / 0", COL_TEXT)
	stat_ref_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	stat_luck_label = _make_label("LUCK: 0", COL_TEXT)
	hp_label = _make_label("HP: 0 / 0", COL_TEXT)
	wounds_label = _make_label("WOUNDS: NONE", COL_TEXT)
	col.add_child(stat_ref_label)
	col.add_child(stat_luck_label)
	col.add_child(hp_label)
	col.add_child(wounds_label)
	col.add_child(_make_rule())

	trace_label = _make_label("TRACE: 0%", COL_TEXT)
	trace_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	net_cred_label = _make_label("EBANK: 0 eb", COL_AMBER)
	net_cred_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	run_label = _make_label("LAST RUN: —", COL_DIM)
	run_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(trace_label)
	col.add_child(net_cred_label)
	col.add_child(run_label)
	col.add_child(_make_rule())

	col.add_child(_make_header_label("TIPS"))
	tips_label = _make_label(
		"[1] Pick programs that match target.\n[2] Shields block; Armor eats hits.\n[3] Over-cap MU = crash.",
		COL_DIM)
	tips_label.add_theme_font_size_override("font_size", 11)
	tips_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips_label.custom_minimum_size = Vector2(140, 0)
	tips_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(tips_label)
	# Push the rest up so the column doesn't have weird dead space at the bottom.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	return panel

# Tiny ASCII face generated from the callsign initial. Cheap visual identity
# without depending on external sprites.
func _runner_ascii_portrait(handle: String) -> String:
	var ch := "?"
	if handle.length() > 0:
		ch = handle.substr(0, 1).to_upper()
	return "  ┏━━━━━━━━━━┓\n  ┃  ▄▀▀▀▀▄  ┃\n  ┃  █ %s █  ┃\n  ┃  ▀▄  ▄▀  ┃\n  ┃    ██    ┃\n  ┗━━━━━━━━━━┛" % ch

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
	mu_overlay_label.text = "%d / %d MU" % [used_mu, active_deck.max_mu]
	var ratio := float(used_mu) / float(max(active_deck.max_mu, 1))
	_set_mu_bar_color(ratio)
	if ratio > 1.0:
		var over := used_mu - active_deck.max_mu
		mu_overflow_badge.text = "▲ %d MU OVER LIMIT ▲" % over
		mu_overflow_badge.visible = true
		mu_overflow_badge.add_theme_color_override("font_color", COL_WARN)
	elif ratio >= 0.85:
		mu_overflow_badge.text = "● APPROACHING LIMIT"
		mu_overflow_badge.visible = true
		mu_overflow_badge.add_theme_color_override("font_color", COL_AMBER)
	else:
		mu_overflow_badge.visible = false
	strength_label.text = "Data Wall STR: %d" % active_deck.data_wall_strength
	interface_label.text = "Interface Rank: %d" % active_deck.interface_rank
	_refresh_loaded()
	_refresh_library()
	_refresh_summary()
	_refresh_netrunner_panel()
	_refresh_destination()
	_clear_message()

func _refresh_summary() -> void:
	var n := 0
	if active_deck:
		for p in active_deck.installed_programs:
			if p:
				n += 1
	if n == 0:
		loaded_summary_label.text = "No programs loaded.\nUse [L] to load from library."
		loaded_summary_label.add_theme_color_override("font_color", COL_DIM)
	else:
		loaded_summary_label.text = "%d program%s loaded (%d MU)." % [n, "s" if n != 1 else "", active_deck.get_used_mu()]
		loaded_summary_label.add_theme_color_override("font_color", COL_TEXT)

func _refresh_netrunner_panel() -> void:
	if not runner_portrait_label:
		return
	var callsign := _run_caller_id("SHADOW")
	callsign_label.text = "// CALLSIGN: %s" % callsign
	role_label.text = "// ROLE: NETRUNNER"
	runner_portrait_label.text = _runner_ascii_portrait(callsign)
	var kills := 0
	var runs := 0
	if MetaState.data != null:
		if "total_kills" in MetaState.data and MetaState.data.total_kills != null:
			kills = int(MetaState.data.total_kills)
		if "run_history" in MetaState.data:
			runs = (MetaState.data.run_history as Array).size()
	meta_label.text = "// TOTAL KILLS: %d\n// DATAJACK: OFFLINE\n// SUBNETS CLEARED: %d" % [kills, runs]
	# Stats are sourced from the active deck (interface_rank feeds INT for
	# initiative) plus standard CP2020 runner defaults: REF = deck speed + 2,
	# INT = interface_rank, BODY = static 6. Adjusted live if the player's
	# runner gets modified later.
	var ref := active_deck.speed_bonus + 2
	var int_val := active_deck.interface_rank
	var body := 6
	stat_ref_label.text = "REF/INT/BODY: %d / %d / %d" % [ref, int_val, body]
	stat_luck_label.text = "LUCK: %d" % active_deck.interface_rank
	var max_hp := 40 + active_deck.data_wall_strength * 2
	hp_label.text = "HP: %d / %d" % [max_hp, max_hp]
	wounds_label.text = "WOUNDS: NONE"
	trace_label.text = "TRACE: %d / 100" % int(RunState.accumulated_trace)
	net_cred_label.text = "EBANK: %d eb" % RunState.credits
	run_label.text = "LAST RUN: %s" % (RunState.last_run_summary.get("name", "—") if not RunState.last_run_summary.is_empty() else "—")

func _refresh_destination() -> void:
	if not destination_label:
		return
	if RunState.selected_subnet_path != "":
		var name_only := RunState.selected_subnet_path.get_file().get_basename()
		destination_label.text = "→ Will jack into: %s" % name_only.to_upper()
		destination_label.add_theme_color_override("font_color", COL_TEXT)
	elif MetaState.data != null and "last_subnet" in MetaState.data and MetaState.data.last_subnet != "":
		destination_label.text = "→ Will jack into: %s" % MetaState.data.last_subnet
		destination_label.add_theme_color_override("font_color", COL_AMBER)
	else:
		destination_label.text = "→ World Map → City Grid → Datafort"
		destination_label.add_theme_color_override("font_color", COL_DIM)

func _run_caller_id(fallback: String) -> String:
	if MetaState == null or MetaState.data == null:
		return fallback
	if "callsign" in MetaState.data and MetaState.data.callsign != "":
		return String(MetaState.data.callsign)
	return fallback

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
		# Row text now only includes: chip + name + [tag] + (MU). The
		# ProgramType short code (A-P / UTL etc.) lived in the Library list
		# only and made the rows too wide to read.
		loaded_list.add_item("%s  %s  [%s]  (%d MU)" % [String.chr(0x258E), prog.program_name, EFFECT_TAGS_COMPACT.get(prog.effect_type, "?"), prog.memory_cost], icon, false)
		loaded_list.set_item_custom_fg_color(loaded_list.item_count - 1, Color(col.r, col.g, col.b, 1.0))
	if unload_button:
		unload_button.disabled = (_selected_loaded_idx < 0)
	_selected_loaded_idx = -1

func _refresh_library() -> void:
	library_list.clear()
	var free_mu := active_deck.max_mu - active_deck.get_used_mu()
	var filter_et = _filter_effects[filter_option.selected] if filter_option else null
	for prog in _owned_programs():
		if not prog:
			continue
		if filter_et != null and prog.effect_type != filter_et:
			continue
		var tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
		var col: Color = EFFECT_COLORS.get(prog.effect_type, COL_TEXT)
		var icon := prog.icon as Texture2D
		var loaded := _is_loaded(prog)
		var fits := (free_mu >= prog.memory_cost) or loaded
		var suffix := ""
		if loaded:
			suffix = "  [L]"
		elif not fits:
			suffix = "  [—]"
		# Tighter row text — ProgramType short was eating horizontal space.
		library_list.add_item("%s  %s  [%s]  (%d MU)%s" % [String.chr(0x258E), prog.program_name, EFFECT_TAGS_COMPACT.get(prog.effect_type, "?"), prog.memory_cost, suffix], icon, false)
		var idx := library_list.item_count - 1
		library_list.set_item_metadata(idx, prog)
		if not fits:
			library_list.set_item_disabled(idx, true)
			library_list.set_item_custom_fg_color(idx, COL_GREY)
		else:
			library_list.set_item_custom_fg_color(idx, Color(col.r, col.g, col.b, 1.0))
	# Disable LOAD button if no selection or selection would overflow.
	if load_button:
		load_button.disabled = (_selected_library_idx < 0) \
			or (library_list.item_count > 0 and library_list.is_item_disabled(_selected_library_idx))
	_selected_library_idx = -1

func _type_short(t: NetProgram.ProgramType) -> String:
	match t:
		NetProgram.ProgramType.ANTI_PERSONNEL: return "A-P"
		NetProgram.ProgramType.ANTI_PROGRAM: return "A-PR"
		NetProgram.ProgramType.ANTI_SYSTEM: return "A-S"
		NetProgram.ProgramType.INTRUSION: return "INT"
		NetProgram.ProgramType.DECRYPTION: return "DEC"
		NetProgram.ProgramType.DETECTION: return "DET"
		NetProgram.ProgramType.UTILITY: return "UTL"
		NetProgram.ProgramType.ICE: return "ICE"
		_: return "?"

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
	var decks := _owned_decks()
	if index >= 0 and index < decks.size():
		active_deck = decks[index]
		RunState.equip_deck(active_deck)
		update_deck_ui()

func _on_filter_changed(_index: int) -> void:
	_refresh_library()

func _on_library_item_selected(index: int) -> void:
	_selected_library_idx = index
	var prog := library_list.get_item_metadata(index) as NetProgram
	_show_detail(prog)
	if load_button:
		load_button.disabled = (index < 0) or library_list.is_item_disabled(index)

func _on_library_item_activated(index: int) -> void:
	_load_program_at(index)

func _on_loaded_item_selected(index: int) -> void:
	_selected_loaded_idx = index
	var prog := active_deck.installed_programs[index] as NetProgram
	_show_detail(prog)
	if unload_button:
		unload_button.disabled = (index < 0)

# --- Drag-and-drop between library and loaded ---
# Library items can be dragged onto the loaded list (quick-load). Loaded
# items can be dragged onto the library list (quick-unload). Implementation
# follows the standard ItemList _get_drag_data / _can_drop_data hook pair.
func _setup_drag_drop() -> void:
	if library_list:
		library_list.set_drag_forwarding(_on_library_drag, _can_drop_from_loaded, _on_drop_into_library)
	if loaded_list:
		loaded_list.set_drag_forwarding(_on_loaded_drag, _can_drop_from_library, _on_drop_into_loaded)

func _on_library_drag(at_index: int) -> Variant:
	var prog := library_list.get_item_metadata(at_index) as NetProgram
	if prog == null or library_list.is_item_disabled(at_index):
		return null
	# Encode the source as a Dictionary so we don't depend on Godot's built-
	# in item metadata (which would lose the program identity if dropped).
	return {
		"type": "program",
		"program": prog,
		"source": "library",
		"index": at_index,
	}

func _on_loaded_drag(at_index: int) -> Variant:
	if at_index < 0 or at_index >= active_deck.installed_programs.size():
		return null
	var prog := active_deck.installed_programs[at_index] as NetProgram
	if prog == null:
		return null
	return {
		"type": "program",
		"program": prog,
		"source": "loaded",
		"index": at_index,
	}

func _can_drop_from_loaded(_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary): return false
	var d := data as Dictionary
	return d.get("type") == "program" and d.get("source") == "loaded"

func _can_drop_from_library(_pos: Vector2, data: Variant) -> bool:
	if not (data is Dictionary): return false
	var d := data as Dictionary
	return d.get("type") == "program" and d.get("source") == "library"

func _on_drop_into_library(_pos: Vector2, data: Variant) -> void:
	var d := data as Dictionary
	if d.get("type") != "program" or d.get("source") != "loaded":
		return
	_unload_program_at(int(d.get("index", -1)))

func _on_drop_into_loaded(_pos: Vector2, data: Variant) -> void:
	if not _can_drop_from_library(_pos, data): return
	var d := data as Dictionary
	# Need to find the library index for the program object because the
	# dragged payload comes from a specific row.
	var prog: NetProgram = d.get("program")
	if prog == null: return
	for i in range(library_list.item_count):
		if library_list.get_item_metadata(i) == prog:
			_load_program_at(i)
			return

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
	RunState.save_run()
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
	RunState.save_run()

func _unload_program_at(index: int) -> void:
	if index < 0 or index >= active_deck.installed_programs.size():
		return
	var prog := active_deck.installed_programs[index] as NetProgram
	if prog:
		active_deck.installed_programs.erase(prog)
		update_deck_ui()
		RunState.save_run()

func _on_button_pressed() -> void:
	if not active_deck:
		_show_message("Error: No active deck selected for neural link!")
		return
	if active_deck.installed_programs.is_empty():
		_show_message("WARNING: No programs loaded. Jack in anyway?", COL_AMBER)
		return
	print("Initiating neural link with %s... Jacking into the Net!" % active_deck.deck_name)
	RunState.selected_deck = active_deck
	RunState.save_run()
	get_tree().change_scene_to_file("res://scenes/ui/cp2020_world_net_map.tscn")

# Clear the persistent status banner when switching tabs so SHOP messages
# (e.g. "Select loot to sell.") don't bleed into LOADOUT.
func _on_tab_changed(_tab: int) -> void:
	_clear_message()

# Keyboard shortcuts: [L] load, [U] unload, [C] clear, [J] jack in. Case-
# insensitive so caps lock doesn't get in the way of n00bs.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	match k:
		KEY_L:
			_on_load_pressed()
		KEY_U:
			_on_unload_pressed()
		KEY_C:
			_on_clear_pressed()
		KEY_J:
			if jack_button and not jack_button.disabled:
				_on_button_pressed()

func _start_cursor_blink() -> void:
	# Blinking "_" cursor in the detail card to give the static UI some life.
	if detail_cursor_label == null:
		return
	var timer := Timer.new()
	timer.wait_time = 0.55
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if detail_cursor_label:
			detail_cursor_label.visible = not detail_cursor_label.visible)
	add_child(timer)

# Subtle pulse on the JACK IN button border to draw the eye. Loops forever.
func _start_jackin_pulse() -> void:
	if jack_button == null:
		return
	var tween := create_tween().set_loops()
	tween.tween_property(jack_button, "modulate", Color(1.0, 1.2, 1.4, 1.0), 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(jack_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------------------------------------------------------------------
# Loadout source helpers (owned gear this life, Inspector arrays as fallback)
# ---------------------------------------------------------------------------
func _owned_decks() -> Array[Cyberdeck]:
	if not RunState.owned_decks.is_empty():
		return RunState.owned_decks
	return available_decks

func _owned_programs() -> Array[NetProgram]:
	if not RunState.owned_programs.is_empty():
		return RunState.owned_programs
	return available_programs

func _refresh_deck_selector() -> void:
	deck_selector.clear()
	var decks := _owned_decks()
	var active_idx := -1
	for i in range(decks.size()):
		var d: Cyberdeck = decks[i]
		if d == null:
			continue
		deck_selector.add_item(d.deck_name)
		if d == active_deck:
			active_idx = deck_selector.item_count - 1
	if active_idx >= 0:
		deck_selector.select(active_idx)
	elif deck_selector.item_count > 0:
		deck_selector.select(0)

# ---------------------------------------------------------------------------
# Shop panel
# ---------------------------------------------------------------------------
func _build_shop_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "SHOP"
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 10)

	# PURCHASE UNLOCKS (opens a separate window — permanent catalogue unlocks)
	var unlock_row := HBoxContainer.new()
	unlock_row.add_theme_constant_override("separation", 12)
	unlock_button = _make_button("PURCHASE UNLOCKS", COL_HEADER)
	unlock_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unlock_button.pressed.connect(_open_unlock_window)
	unlock_row.add_child(unlock_button)
	tab.add_child(unlock_row)
	tab.add_child(_make_rule())

	# 2x2 grid of shop sections, each full-height with list + action button.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	tab.add_child(grid)

	var buy_decks := _build_shop_section("BUY DECKS",
		_on_buy_deck_selected, _on_buy_deck_pressed, "BUY DECK", COL_GREEN)
	shop_buy_decks_list = buy_decks["list"]
	buy_deck_button = buy_decks["button"]
	grid.add_child(buy_decks["panel"])

	var buy_progs := _build_shop_section("BUY PROGRAMS",
		_on_buy_program_selected, _on_buy_program_pressed, "BUY PROGRAM", COL_GREEN)
	shop_buy_programs_list = buy_progs["list"]
	buy_program_button = buy_progs["button"]
	grid.add_child(buy_progs["panel"])

	var sell_loot := _build_shop_section("SELL LOOT",
		_on_sell_loot_selected, _on_sell_loot_pressed, "SELL", COL_AMBER)
	shop_sell_loot_list = sell_loot["list"]
	sell_loot_button = sell_loot["button"]
	grid.add_child(sell_loot["panel"])

	var sell_files := _build_shop_section("SELL FILES",
		_on_sell_file_selected, _on_sell_file_pressed, "SELL FILE", COL_AMBER)
	shop_sell_files_list = sell_files["list"]
	sell_file_button = sell_files["button"]
	grid.add_child(sell_files["panel"])

	return tab


func _build_shop_section(header: String, selected_cb: Callable, pressed_cb: Callable, btn_label: String, btn_color: Color) -> Dictionary:
	var panel := _styled_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	col.add_child(_make_header_label(header))
	col.add_child(_make_rule())

	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(selected_cb)
	_style_list(list)
	col.add_child(list)

	var button := _make_button(btn_label, btn_color)
	button.pressed.connect(pressed_cb)
	col.add_child(button)

	return {"panel": panel, "list": list, "button": button}

func _refresh_credits() -> void:
	if credits_label:
		credits_label.text = "CREDITS: %d eb" % RunState.credits

func _refresh_shop() -> void:
	_refresh_shop_buy_decks()
	_refresh_shop_buy_programs()
	_refresh_shop_sell_loot()
	_refresh_shop_sell_files()
	_refresh_credits()

func _refresh_shop_buy_decks() -> void:
	shop_buy_decks_list.clear()
	_selected_buy_deck_idx = -1
	if MetaState.data == null:
		return
	for path in MetaState.data.unlocked_decks:
		var deck := load(path) as Cyberdeck
		if deck == null:
			continue
		if _is_deck_owned(deck, path):
			continue
		shop_buy_decks_list.add_item("%s — %d eb" % [deck.deck_name, deck.price], null, true)
		var idx := shop_buy_decks_list.item_count - 1
		shop_buy_decks_list.set_item_metadata(idx, deck)
		if RunState.credits < deck.price:
			shop_buy_decks_list.set_item_disabled(idx, true)
			shop_buy_decks_list.set_item_custom_fg_color(idx, COL_GREY)

func _refresh_shop_buy_programs() -> void:
	shop_buy_programs_list.clear()
	_selected_buy_program_idx = -1
	if MetaState.data == null:
		return
	for path in MetaState.data.unlocked_programs:
		var prog := load(path) as NetProgram
		if prog == null:
			continue
		if _is_program_owned(prog, path):
			continue
		var tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
		shop_buy_programs_list.add_item("%s [%s] %d MU — %d eb" % [prog.program_name, tag, prog.memory_cost, prog.price], null, true)
		var idx := shop_buy_programs_list.item_count - 1
		shop_buy_programs_list.set_item_metadata(idx, prog)
		if RunState.credits < prog.price:
			shop_buy_programs_list.set_item_disabled(idx, true)
			shop_buy_programs_list.set_item_custom_fg_color(idx, COL_GREY)

func _refresh_shop_sell_loot() -> void:
	shop_sell_loot_list.clear()
	_selected_sell_loot_idx = -1
	if RunState.loot.is_empty():
		shop_sell_loot_list.add_item("No loot to fence — jack in and download some files.", null, false)
		shop_sell_loot_list.set_item_custom_fg_color(0, COL_GREY)
		shop_sell_loot_list.set_item_disabled(0, true)
		return
	for prog in RunState.loot:
		if prog == null:
			continue
		var sell_price := int(prog.price * 0.5)
		var tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
		shop_sell_loot_list.add_item("%s [%s] — %d eb" % [prog.program_name, tag, sell_price], null, true)
		var idx := shop_sell_loot_list.item_count - 1
		shop_sell_loot_list.set_item_metadata(idx, prog)

func _refresh_shop_sell_files() -> void:
	shop_sell_files_list.clear()
	_selected_sell_file_idx = -1
	if RunState.carried_files.is_empty():
		shop_sell_files_list.add_item("No files carried — copy some from a datafort.", null, false)
		shop_sell_files_list.set_item_custom_fg_color(0, COL_GREY)
		shop_sell_files_list.set_item_disabled(0, true)
		return
	for file in RunState.carried_files:
		if file == null:
			continue
		shop_sell_files_list.add_item("%s — %d eb" % [file.file_name, file.credit_value], null, true)
		var idx := shop_sell_files_list.item_count - 1
		shop_sell_files_list.set_item_metadata(idx, file)

# Owned-vs-catalogue comparison. Owned items are duplicates whose
# resource_path may be cleared by duplicate(), so fall back to matching by
# name when the owned item's path is empty.
func _is_deck_owned(cat_deck: Cyberdeck, cat_path: String) -> bool:
	for d in RunState.owned_decks:
		if d == null:
			continue
		if cat_path != "" and d.resource_path == cat_path:
			return true
		if d.resource_path == "" and cat_deck.deck_name != "" and d.deck_name == cat_deck.deck_name:
			return true
	return false

func _is_program_owned(cat_prog: NetProgram, cat_path: String) -> bool:
	for p in RunState.owned_programs:
		if p == null:
			continue
		if cat_path != "" and p.resource_path == cat_path:
			return true
		if p.resource_path == "" and cat_prog.program_name != "" and p.program_name == cat_prog.program_name:
			return true
	return false

func _after_transaction() -> void:
	_refresh_shop()
	_refresh_deck_selector()
	update_deck_ui()
	RunState.save_run()

# --- Shop signal handlers ---
func _on_buy_deck_selected(index: int) -> void:
	_selected_buy_deck_idx = index

func _on_buy_deck_pressed() -> void:
	if _selected_buy_deck_idx < 0 or _selected_buy_deck_idx >= shop_buy_decks_list.item_count:
		_show_message("Select a deck to buy.", COL_AMBER)
		return
	var deck := shop_buy_decks_list.get_item_metadata(_selected_buy_deck_idx) as Cyberdeck
	if deck == null:
		return
	if RunState.credits < deck.price:
		_show_message("Insufficient credits for %s (%d eb)." % [deck.deck_name, deck.price])
		return
	if RunState.buy_deck(deck):
		_after_transaction()
		_show_message("Purchased %s for %d eb." % [deck.deck_name, deck.price], COL_GREEN)
	else:
		_show_message("Purchase failed: %s." % deck.deck_name)

func _on_buy_program_selected(index: int) -> void:
	_selected_buy_program_idx = index

func _on_buy_program_pressed() -> void:
	if _selected_buy_program_idx < 0 or _selected_buy_program_idx >= shop_buy_programs_list.item_count:
		_show_message("Select a program to buy.", COL_AMBER)
		return
	var prog := shop_buy_programs_list.get_item_metadata(_selected_buy_program_idx) as NetProgram
	if prog == null:
		return
	if RunState.credits < prog.price:
		_show_message("Insufficient credits for %s (%d eb)." % [prog.program_name, prog.price])
		return
	if RunState.buy_program(prog):
		_after_transaction()
		_show_message("Purchased %s for %d eb." % [prog.program_name, prog.price], COL_GREEN)
	else:
		_show_message("Purchase failed: %s." % prog.program_name)

func _on_sell_loot_selected(index: int) -> void:
	_selected_sell_loot_idx = index

func _on_sell_loot_pressed() -> void:
	if _selected_sell_loot_idx < 0 or _selected_sell_loot_idx >= shop_sell_loot_list.item_count:
		_show_message("Select loot to sell.", COL_AMBER)
		return
	var prog := shop_sell_loot_list.get_item_metadata(_selected_sell_loot_idx) as NetProgram
	if prog == null:
		return
	var proceeds := RunState.sell_loot_program(prog)
	if proceeds > 0:
		_after_transaction()
		_show_message("Fenced %s for %d eb." % [prog.program_name, proceeds], COL_GREEN)
	else:
		_show_message("Could not sell that item.")

func _on_sell_file_selected(index: int) -> void:
	_selected_sell_file_idx = index

func _on_sell_file_pressed() -> void:
	if _selected_sell_file_idx < 0 or _selected_sell_file_idx >= shop_sell_files_list.item_count:
		_show_message("Select a file to sell.", COL_AMBER)
		return
	var file := shop_sell_files_list.get_item_metadata(_selected_sell_file_idx) as NetFile
	if file == null:
		return
	var proceeds := RunState.sell_file(file)
	if proceeds > 0:
		_after_transaction()
		_show_message("Fenced %s for %d eb." % [file.file_name, proceeds], COL_GREEN)
	else:
		_show_message("Could not sell that file.")

# ---------------------------------------------------------------------------
# Purchase Unlocks window — permanent MetaState blueprint unlocks.
# Two-tier shop: buying a blueprint adds it to the persistent catalogue
# (survives death); the existing BUY DECKS / BUY PROGRAMS panels then let you
# buy-to-own it for the current life.
# ---------------------------------------------------------------------------
func _scan_data_catalogue() -> void:
	if _unlock_scanned:
		return
	_unlock_scanned = true
	_unlockable_decks.clear()
	_unlockable_programs.clear()
	var dir := DirAccess.open("res://data")
	if dir == null:
		push_error("Workbench: could not open res://data for unlock scan.")
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := "res://data/" + fname
			var res := load(path)
			if res is Cyberdeck:
				_unlockable_decks.append(path)
			elif res is NetProgram:
				_unlockable_programs.append(path)
		fname = dir.get_next()
	dir.list_dir_end()

func _open_unlock_window() -> void:
	_scan_data_catalogue()
	if unlock_window == null:
		_build_unlock_window()
	_refresh_unlock_list()
	add_child(unlock_window)
	unlock_window.popup_centered(Vector2i(420, 520))

func _build_unlock_window() -> void:
	unlock_window = Window.new()
	unlock_window.title = "◢ PURCHASE UNLOCKS ◣"
	unlock_window.min_size = Vector2i(360, 420)
	unlock_window.wrap_controls = true
	unlock_window.close_requested.connect(_close_unlock_window)
	# Transparent-ish backdrop matching the workbench theme.
	unlock_window.add_theme_color_override("embedded_border_bg", COL_BG)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	unlock_window.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(_make_header_label("◢ PURCHASE UNLOCKS ◣", true))
	unlock_credits_label = _make_label("CREDITS: 0 eb", COL_AMBER)
	unlock_credits_label.add_theme_font_size_override("font_size", 18)
	col.add_child(unlock_credits_label)
	col.add_child(_make_rule())

	unlock_list = ItemList.new()
	unlock_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unlock_list.custom_minimum_size = Vector2(0, 300)
	_style_list(unlock_list)
	unlock_list.item_selected.connect(_on_unlock_selected)
	col.add_child(unlock_list)

	unlock_buy_button = _make_button("UNLOCK", COL_HEADER)
	unlock_buy_button.pressed.connect(_on_unlock_pressed)
	unlock_buy_button.disabled = true
	col.add_child(unlock_buy_button)

	var close_btn := _make_button("CLOSE", COL_DIM)
	close_btn.pressed.connect(_close_unlock_window)
	col.add_child(close_btn)

	# Apply monospace font to everything in the window.
	_apply_terminal_theme(unlock_window)

func _close_unlock_window() -> void:
	if unlock_window != null and is_instance_valid(unlock_window):
		unlock_window.hide()
		if unlock_window.get_parent() != null:
			unlock_window.get_parent().remove_child(unlock_window)

func _refresh_unlock_list() -> void:
	unlock_list.clear()
	_selected_unlock_idx = -1
	unlock_buy_button.disabled = true
	if unlock_credits_label:
		unlock_credits_label.text = "CREDITS: %d eb" % RunState.credits
	# Decks first, then programs. Metadata: {"path": path, "is_deck": bool}.
	unlock_list.add_item("-- DECKS --", null, false)
	unlock_list.set_item_custom_fg_color(0, COL_HEADER)
	unlock_list.set_item_disabled(0, true)
	for path in _unlockable_decks:
		_add_unlock_row(path, true)
	unlock_list.add_item("-- PROGRAMS --", null, false)
	unlock_list.set_item_custom_fg_color(unlock_list.item_count - 1, COL_HEADER)
	unlock_list.set_item_disabled(unlock_list.item_count - 1, true)
	for path in _unlockable_programs:
		_add_unlock_row(path, false)

func _add_unlock_row(path: String, is_deck: bool) -> void:
	var res = load(path)
	if res == null:
		return
	var name_txt: String = ""
	var cost: int = 0
	if is_deck:
		var deck := res as Cyberdeck
		if deck == null:
			return
		name_txt = deck.deck_name
		cost = deck.price
	else:
		var prog := res as NetProgram
		if prog == null:
			return
		name_txt = prog.program_name
		cost = prog.price
	var already := false
	if is_deck:
		already = MetaState.has_deck(path)
	else:
		already = MetaState.has_program(path)
	if already:
		var idxu := unlock_list.add_item("%s — ✓ UNLOCKED" % name_txt, null, false)
		unlock_list.set_item_metadata(idxu, {"path": path, "is_deck": is_deck, "cost": cost})
		unlock_list.set_item_disabled(idxu, true)
		unlock_list.set_item_custom_fg_color(idxu, COL_GREY)
		return
	var idx := unlock_list.add_item("%s — %d eb" % [name_txt, cost], null, true)
	unlock_list.set_item_metadata(idx, {"path": path, "is_deck": is_deck, "cost": cost})
	if RunState.credits < cost:
		unlock_list.set_item_disabled(idx, true)
		unlock_list.set_item_custom_fg_color(idx, COL_GREY)

func _on_unlock_selected(index: int) -> void:
	if unlock_list.is_item_disabled(index):
		# Disabled rows shouldn't drive the button; reset selection cleanly.
		_selected_unlock_idx = -1
		unlock_buy_button.disabled = true
		return
	_selected_unlock_idx = index
	unlock_buy_button.disabled = false

func _on_unlock_pressed() -> void:
	if _selected_unlock_idx < 0 or _selected_unlock_idx >= unlock_list.item_count:
		return
	var meta: Dictionary = unlock_list.get_item_metadata(_selected_unlock_idx)
	var path: String = meta.get("path", "")
	var is_deck: bool = meta.get("is_deck", false)
	var cost: int = meta.get("cost", 0)
	if path == "":
		return
	if RunState.credits < cost:
		_show_message("Insufficient credits (%d eb)." % cost)
		return
	RunState.credits -= cost
	var unlocked := false
	var item_name := ""
	if is_deck:
		var deck := load(path) as Cyberdeck
		if deck != null:
			item_name = deck.deck_name
			MetaState.unlock_deck(path)
			unlocked = true
	else:
		var prog := load(path) as NetProgram
		if prog != null:
			item_name = prog.program_name
			MetaState.unlock_program(path)
			unlocked = true
	if unlocked:
		_refresh_unlock_list()
		_refresh_shop()
		_refresh_credits()
		RunState.save_run()
		_show_message("Unlocked %s blueprint for %d eb." % [item_name, cost], COL_GREEN)
	else:
		_show_message("Unlock failed: %s." % path)

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
func _styled_panel(with_border: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
		# Soft neon glow around bordered panels.
		sb.shadow_color = COL_BORDER
		sb.shadow_size = 6
		sb.shadow_offset = Vector2.ZERO
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

# ---------------------------------------------------------------------------
# CRT terminal theme helpers
# ---------------------------------------------------------------------------
func _make_mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "Menlo"])
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.generate_mipmaps = false
	return f

func _apply_terminal_theme(node: Node) -> void:
	if _mono_font == null:
		return
	if node is Label:
		(node as Label).add_theme_font_override("font", _mono_font)
	elif node is Button:
		(node as Button).add_theme_font_override("font", _mono_font)
	elif node is OptionButton:
		(node as OptionButton).add_theme_font_override("font", _mono_font)
	elif node is ItemList:
		(node as ItemList).add_theme_font_override("font", _mono_font)
	elif node is TabContainer:
		(node as TabContainer).add_theme_font_override("font", _mono_font)
	for child in node.get_children():
		_apply_terminal_theme(child)

func _style_tab_container(tabs: TabContainer) -> void:
	# Tab bar background + tab styling for a terminal look. Larger active-tab
	# font + thick underline draws the eye to the focused tab.
	var tab_selected := _neon_style(COL_GREEN, 2, 0)
	tab_selected.bg_color = Color(COL_GREEN.r * 0.18, COL_GREEN.g * 0.18, COL_GREEN.b * 0.18, 0.95)
	tab_selected.border_width_bottom = 3
	var tab_unselected := _neon_style(COL_BORDER_DIM, 1, 0)
	tab_unselected.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	tabs.add_theme_stylebox_override("tab_selected", tab_selected)
	tabs.add_theme_stylebox_override("tab_unselected", tab_unselected)
	tabs.add_theme_stylebox_override("tab_hovered", _neon_style(COL_BORDER, 1, 0))
	tabs.add_theme_stylebox_override("tab_focus", tab_selected)
	tabs.add_theme_stylebox_override("panel", _transparent_style())
	tabs.add_theme_color_override("font_selected_color", COL_GREEN)
	tabs.add_theme_color_override("font_unselected_color", COL_DIM)
	tabs.add_theme_color_override("font_hovered_color", COL_TEXT)
	tabs.add_theme_font_size_override("font_size", 17)
	# Larger font for the active (selected) tab label — easier to spot.
	# Godot doesn't expose per-state font size overrides in 4.x, but the bold
	# selected style + thicker underline already differentiates them.

func _style_list(list: ItemList) -> void:
	# Inset dark background panel for the list.
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
	list.add_theme_stylebox_override("panel", sb)

	# Selected item: neon green highlight.
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(COL_GREEN.r * 0.2, COL_GREEN.g * 0.2, COL_GREEN.b * 0.2, 0.8)
	sel.border_width_left = 0
	sel.border_width_top = 0
	sel.border_width_right = 0
	sel.border_width_bottom = 1
	sel.border_color = COL_GREEN
	list.add_theme_stylebox_override("selected", sel)
	list.add_theme_stylebox_override("selected_focus", sel)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(COL_BORDER.r * 0.3, COL_BORDER.g * 0.3, COL_BORDER.b * 0.3, 0.5)
	list.add_theme_stylebox_override("hover", hover)

	list.add_theme_color_override("font_color", COL_TEXT)
	list.add_theme_color_override("font_selected_color", COL_GREEN)
	list.add_theme_color_override("font_hover_color", Color(COL_TEXT.r * 1.2, COL_TEXT.g * 1.2, COL_TEXT.b * 1.2))
	list.add_theme_color_override("guide_color", COL_BORDER_DIM)
	list.add_theme_font_size_override("font_size", 14)
	list.add_theme_constant_override("h_separation", 6)
	list.add_theme_constant_override("v_separation", 3)
	# Scrollbars are created when the list enters the tree, so style them on ready.
	list.ready.connect(func() -> void: _style_scrollbars(list))

func _style_scrollbars(list: ItemList) -> void:
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = COL_GREEN
	grabber.corner_radius_top_left = 2
	grabber.corner_radius_top_right = 2
	grabber.corner_radius_bottom_left = 2
	grabber.corner_radius_bottom_right = 2
	var grabber_hl := StyleBoxFlat.new()
	grabber_hl.bg_color = Color(COL_GREEN.r * 1.3, COL_GREEN.g * 1.3, COL_GREEN.b * 1.3)
	grabber_hl.corner_radius_top_left = 2
	grabber_hl.corner_radius_top_right = 2
	grabber_hl.corner_radius_bottom_left = 2
	grabber_hl.corner_radius_bottom_right = 2
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	# ItemList's scrollbars are internal child ScrollBar nodes; style each one.
	for bar in list.find_children("*", "ScrollBar", true, false):
		bar.add_theme_stylebox_override("grabber", grabber)
		bar.add_theme_stylebox_override("grabber_highlight", grabber_hl)
		bar.add_theme_stylebox_override("scroll", scroll_bg)

func _build_crt_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(1, 1, 1, 1)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var shader := load("res://scripts/ui/crt_overlay.gdshader")
	if shader is Shader:
		mat.shader = shader as Shader
	overlay.material = mat
	return overlay
