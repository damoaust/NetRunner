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

# CP2020Theme companion: palette consts + programmatic StyleBox/node factories
# for the few controls still built in code (dynamic
# buttons). The look itself comes from themes/cyberpunk_theme.tres set on the
# scene root.
const THEME := preload("res://scripts/resources/cp2020_theme.gd")
const THEME_RES := preload("res://themes/cyberpunk_theme.tres")
const UNLOCK_WINDOW_SCENE := preload("res://scenes/ui/PurchaseUnlocksWindow.tscn")

# Runner character roster. Auto-discovered at runtime from
# res://data/characters/ — drop a new character_*.tres in that folder and it
# becomes selectable on the workbench with no code change. Clicking the
# portrait cycles through these; the selected character's stats drive
# gameplay and its callsign/portrait/role are shown in the panel. The chosen
# character persists in MetaState.data.selected_character_path across deaths.
var _runner_characters: Array[NetrunnerCharacter] = []

# --- UI references (scene-tree nodes; static structure lives in
# CyberdeckWorkbench.tscn and is grabbed here via unique_name_in_owner) ---
@onready var deck_selector: OptionButton = get_node_or_null("%DeckSelector")
@onready var model_label: Label = get_node_or_null("%ModelLabel")
@onready var speed_label: Label = get_node_or_null("%SpeedLabel")
@onready var mu_label: Label = get_node_or_null("%MuLabel")
@onready var mu_bar: ProgressBar = get_node_or_null("%MuBar")
@onready var mu_overlay_label: Label = get_node_or_null("%MuOverlayLabel")
@onready var mu_overflow_badge: Label = get_node_or_null("%MuOverflowBadge")
@onready var strength_label: Label = get_node_or_null("%StrengthLabel")
@onready var interface_label: Label = get_node_or_null("%InterfaceLabel")
@onready var loaded_summary_label: Label = get_node_or_null("%LoadedSummaryLabel")
@onready var meta_label: Label = get_node_or_null("%MetaLabel")
@onready var loaded_list: ItemList = get_node_or_null("%LoadedList")
@onready var library_list: ItemList = get_node_or_null("%LibraryList")
@onready var filter_option: OptionButton = get_node_or_null("%FilterOption")
@onready var detail_name: Label = get_node_or_null("%DetailName")
# Netrunner Status column
@onready var runner_portrait: TextureRect = get_node_or_null("%RunnerPortrait")
@onready var callsign_label: Label = get_node_or_null("%CallsignLabel")
@onready var role_label: Label = get_node_or_null("%RoleLabel")
@onready var stat_ref_label: Label = get_node_or_null("%StatRefLabel")
@onready var stat_luck_label: Label = get_node_or_null("%StatLuckLabel")
@onready var hp_label: Label = get_node_or_null("%HpLabel")
@onready var wounds_label: Label = get_node_or_null("%WoundsLabel")
@onready var trace_label: Label = get_node_or_null("%TraceLabel")
@onready var net_cred_label: Label = get_node_or_null("%NetCredLabel")
@onready var run_label: Label = get_node_or_null("%RunLabel")
@onready var tips_label: Label = get_node_or_null("%TipsLabel")
@onready var detail_cursor_label: Label = get_node_or_null("%DetailCursorLabel")
@onready var detail_type: Label = get_node_or_null("%DetailType")
@onready var detail_effect: Label = get_node_or_null("%DetailEffect")
@onready var detail_str: Label = get_node_or_null("%DetailStr")
@onready var detail_mu: Label = get_node_or_null("%DetailMu")
@onready var detail_price: Label = get_node_or_null("%DetailPrice")
@onready var detail_desc: Label = get_node_or_null("%DetailDesc")
@onready var detail_card: PanelContainer = get_node_or_null("%DetailCard")
@onready var load_button: Button = get_node_or_null("%LoadButton")
@onready var unload_button: Button = get_node_or_null("%UnloadButton")
@onready var clear_button: Button = get_node_or_null("%ClearButton")
@onready var configure_subs_button: Button = get_node_or_null("%ConfigureSubroutinesButton")
@onready var upgrades_button: Button = get_node_or_null("%UpgradesButton")
@onready var jack_button: Button = get_node_or_null("%JackButton")
@onready var exit_button: Button = get_node_or_null("%ExitButton")
@onready var mu_message: Label = get_node_or_null("%MuMessage")
@onready var destination_label: Label = get_node_or_null("%DestinationLabel")
# --- Shop panel references (scene-tree nodes) ---
@onready var credits_label: Label = get_node_or_null("%CreditsLabel")
@onready var shop_buy_decks_list: ItemList = get_node_or_null("%ShopBuyDecksList")
@onready var shop_buy_programs_list: ItemList = get_node_or_null("%ShopBuyProgramsList")
@onready var shop_sell_loot_list: ItemList = get_node_or_null("%ShopSellLootList")
@onready var shop_sell_files_list: ItemList = get_node_or_null("%ShopSellFilesList")
@onready var buy_deck_button: Button = get_node_or_null("%BuyDeckButton")
@onready var buy_program_button: Button = get_node_or_null("%BuyProgramButton")
@onready var shop_buy_modules_list: ItemList = get_node_or_null("%ShopBuyModulesList")
@onready var buy_module_button: Button = get_node_or_null("%BuyModuleButton")
@onready var sell_loot_button: Button = get_node_or_null("%SellLootButton")
@onready var sell_file_button: Button = get_node_or_null("%SellFileButton")
@onready var sell_all_files_button: Button = get_node_or_null("%SellAllFilesButton")
@onready var unlock_button: Button = get_node_or_null("%UnlockButton")
# --- Purchase Unlocks window (scene-based popup: PurchaseUnlocksWindow.tscn) ---
var unlock_window: Window
var unlock_list: ItemList
var unlock_buy_button: Button
var unlock_credits_label: Label
var _selected_unlock_idx: int = -1
var _unlockable_decks: Array[String] = []
var _unlockable_programs: Array[String] = []
var _unlockable_modules: Array[String] = []
var _unlock_scanned: bool = false
var _selected_buy_deck_idx: int = -1
var _selected_buy_program_idx: int = -1
var _selected_buy_module_idx: int = -1
var _selected_sell_loot_idx: int = -1
var _selected_sell_file_idx: int = -1

# --- Configure Subroutines window (built in code — popup) ---
var subroutines_window: Window
var sub_slot_list: ItemList
var sub_candidate_list: ItemList
var sub_assign_button: Button
var sub_clear_button: Button
var _sub_target_demon: DemonProgram
var _sub_candidates: Array[NetProgram] = []
var _sub_selected_slot_idx: int = -1
var _sub_selected_candidate_idx: int = -1

# --- Upgrades window (built in code — popup) ---
var upgrades_window: Window
var upg_slot_list: ItemList
var upg_library_list: ItemList
var upg_install_button: Button
var upg_uninstall_button: Button
var _upg_selected_slot_idx: int = -1
var _upg_selected_library_idx: int = -1

# Human-readable tags for each program effect type.
const EFFECT_TAGS: Dictionary = {
	NetProgram.EffectType.BYPASS_GATE: "Intrusion",
	NetProgram.EffectType.BREACH_WALL: "Breach",
	NetProgram.EffectType.DEREZ_ICE: "Anti-ICE",
	NetProgram.EffectType.DAMAGE_RUNNER: "Anti-Pers",
	NetProgram.EffectType.REVEAL_NODES: "Reveal",
	NetProgram.EffectType.MODIFY_MU: "Utility",
	NetProgram.EffectType.SHIELD: "Defense",
	NetProgram.EffectType.CRASH_CPU: "Anti-System",
	NetProgram.EffectType.ARMOR: "Defense",
	NetProgram.EffectType.DEMON: "Demon",
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

# Cyberpunk theme palette. These mirror CP2020Theme (above) and are kept here
# only to avoid churning every call site that sets runtime text colors; the
# authoritative copy lives in CP2020Theme.
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

# Scan res://data/characters/ for NetrunnerCharacter .tres files and populate
# _runner_characters (sorted by filename for a stable cycle order). Any
# resource that fails to load or isn't a NetrunnerCharacter is skipped with a
# warning so one bad file can't blank the whole roster.
func _load_runner_characters() -> void:
	_runner_characters.clear()
	var dir := DirAccess.open("res://data/characters/")
	if dir == null:
		push_warning("CyberdeckWorkbench: could not open res://data/characters/ — roster empty.")
		return
	var paths: Array[String] = []
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".tres"):
			paths.append("res://data/characters/%s" % file)
		file = dir.get_next()
	dir.list_dir_end()
	paths.sort()  # deterministic order regardless of OS listing order
	for path in paths:
		var res: Resource = load(path)
		if res is NetrunnerCharacter:
			_runner_characters.append(res as NetrunnerCharacter)
		else:
			push_warning("CyberdeckWorkbench: '%s' is not a NetrunnerCharacter — skipped." % path)
	if _runner_characters.is_empty():
		push_warning("CyberdeckWorkbench: no character .tres found in res://data/characters/.")

func _ready() -> void:
	# Discover all character .tres in res://data/characters/ so newly added
	# roster entries are selectable without editing this script.
	
	_load_runner_characters()
	
	# First launch / after permadeath: ensure a life is in progress with
	# starting gear before building the loadout. RunState autoload already
	# attempts to load a saved run from the previous session.
	
	if RunState.owned_decks.is_empty():
		RunState.start_new_life()
		
	# Persist the current hub state whenever the workbench is entered (covers
	# returning from a run as well as the initial new-life setup).
	RunState.save_run()
	
	# The static UI structure lives in CyberdeckWorkbench.tscn (theme applied
	# at the root); here we only wire signals, populate the filter dropdown,
	# style the list scrollbars, and seed the dynamic content.
	
	_connect_signals()
	_populate_filter()
	for list in [loaded_list, library_list, shop_buy_decks_list, shop_buy_programs_list, shop_buy_modules_list, shop_sell_loot_list, shop_sell_files_list]:
		if list:
			_style_scrollbars(list)
			
	# Default active deck to the previously equipped deck if still owned,
	# else the first owned deck.
	var decks := _owned_decks()
	if RunState.selected_deck != null and decks.has(RunState.selected_deck):
		active_deck = RunState.selected_deck
	elif not decks.is_empty():
		active_deck = decks[0]
		
	# Ensure a character is equipped. A fresh life seeds one in start_new_life,
	# but guard against a null (e.g. older save) by defaulting to the MetaState
	# preferred character, then the first roster entry.
	if RunState.selected_character == null:
		var pref_path := MetaState.data.selected_character_path if MetaState.data != null else ""
		var ch: NetrunnerCharacter = null
		if pref_path != "":
			ch = load(pref_path) as NetrunnerCharacter
		if ch == null and not _runner_characters.is_empty():
			ch = _runner_characters[0]
		if ch != null:
			RunState.selected_character = ch
	
	# Grabs every node in the scene tree that you added to this group
	var buttons = get_tree().get_nodes_in_group("pulse_buttons")
	
	# Loop through the array and start the pulse for each one
	for btn in buttons:
		_start_pulse(btn)
			
	_refresh_deck_selector()
	update_deck_ui()
	_refresh_shop()
	_start_cursor_blink()
	_setup_drag_drop()

# Populate the library filter OptionButton (All + one entry per EffectType).
func _populate_filter() -> void:
	if filter_option == null:
		return
	filter_option.clear()
	_filter_effects = [null]
	filter_option.add_item("All")
	for et in EFFECT_TAGS.keys():
		_filter_effects.append(et)
		filter_option.add_item(EFFECT_TAGS[et])

# Connect every scene-tree control signal in one place. Idempotency isn't
# needed here because the nodes are fresh from the scene tree.
func _connect_signals() -> void:
	if deck_selector:
		deck_selector.item_selected.connect(_on_deck_selector_item_selected)
	if filter_option:
		filter_option.item_selected.connect(_on_filter_changed)
	if loaded_list:
		loaded_list.item_selected.connect(_on_loaded_item_selected)
		loaded_list.item_activated.connect(_on_loaded_item_activated)
	if library_list:
		library_list.item_selected.connect(_on_library_item_selected)
		library_list.item_activated.connect(_on_library_item_activated)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
	if unload_button:
		unload_button.pressed.connect(_on_unload_pressed)
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	if configure_subs_button:
		configure_subs_button.pressed.connect(_open_subroutines_window)
	if upgrades_button:
		upgrades_button.pressed.connect(_open_upgrades_window)
	if jack_button:
		jack_button.pressed.connect(_on_button_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
	if unlock_button:
		unlock_button.pressed.connect(_open_unlock_window)
	if buy_deck_button:
		buy_deck_button.pressed.connect(_on_buy_deck_pressed)
	if buy_program_button:
		buy_program_button.pressed.connect(_on_buy_program_pressed)
	if buy_module_button:
		buy_module_button.pressed.connect(_on_buy_module_pressed)
	if sell_loot_button:
		sell_loot_button.pressed.connect(_on_sell_loot_pressed)
	if sell_file_button:
		sell_file_button.pressed.connect(_on_sell_file_pressed)
	if sell_all_files_button:
		sell_all_files_button.pressed.connect(_on_sell_all_files_pressed)
	if shop_buy_decks_list:
		shop_buy_decks_list.item_selected.connect(_on_buy_deck_selected)
	if shop_buy_programs_list:
		shop_buy_programs_list.item_selected.connect(_on_buy_program_selected)
	if shop_buy_modules_list:
		shop_buy_modules_list.item_selected.connect(_on_buy_module_selected)
	if shop_sell_loot_list:
		shop_sell_loot_list.item_selected.connect(_on_sell_loot_selected)
	if shop_sell_files_list:
		shop_sell_files_list.item_selected.connect(_on_sell_file_selected)
	# TabContainer is in the scene tree; wire its tab_changed signal here.
	var tabs := get_node_or_null("%Tabs") as TabContainer
	if tabs:
		tabs.tab_changed.connect(_on_tab_changed)
	# Clicking the runner portrait cycles to the next character face and
	# persists the selection via MetaState so it survives across lives.
	if runner_portrait:
		runner_portrait.gui_input.connect(_on_runner_portrait_gui_input)

# ---------------------------------------------------------------------------
# MU bar
# ---------------------------------------------------------------------------
# Recolor the local fill StyleBox override (a per-instance SubResource in the
# scene) based on the used/total ratio. Mutates the shared override in place.
func _set_mu_bar_color(ratio: float) -> void:
	if mu_bar == null:
		return
	var fill: StyleBoxFlat = mu_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null:
		return
	fill.bg_color = THEME.mu_bar_fill_color(ratio)

# ---------------------------------------------------------------------------
# Refresh / update
# ---------------------------------------------------------------------------
# Refresh / update
# ---------------------------------------------------------------------------
func update_deck_ui() -> void:
	if not active_deck:
		return
	model_label.text = "Model: " + active_deck.deck_name
	speed_label.text = "Speed Bonus: +%d" % active_deck.effective_speed_bonus()
	var used_mu := active_deck.get_used_mu()
	var eff_mu := active_deck.effective_max_mu()
	mu_label.text = "Memory Units (MU): %d / %d" % [used_mu, eff_mu]
	mu_bar.max_value = eff_mu
	mu_bar.value = used_mu
	mu_overlay_label.text = "%d / %d MU" % [used_mu, eff_mu]
	var ratio := float(used_mu) / float(max(eff_mu, 1))
	_set_mu_bar_color(ratio)
	if ratio > 1.0:
		var over := used_mu - eff_mu
		mu_overflow_badge.text = "▲ %d MU OVER LIMIT ▲" % over
		mu_overflow_badge.visible = true
		mu_overflow_badge.add_theme_color_override("font_color", COL_WARN)
	elif ratio >= 0.85:
		mu_overflow_badge.text = "● APPROACHING LIMIT"
		mu_overflow_badge.visible = true
		mu_overflow_badge.add_theme_color_override("font_color", COL_AMBER)
	else:
		mu_overflow_badge.visible = false
	strength_label.text = "Data Wall STR: %d" % active_deck.effective_data_wall_strength()
	interface_label.text = "Interface Rank: %d" % active_deck.effective_interface_rank()
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
	var ch: NetrunnerCharacter = RunState.selected_character
	if ch == null and not _runner_characters.is_empty():
		ch = _runner_characters[0]
	if ch == null:
		# No character roster available — nothing to display.
		return
	if runner_portrait:
		runner_portrait.texture = ch.portrait_texture
	callsign_label.text = "// CALLSIGN: %s" % ch.callsign
	role_label.text = "// ROLE: %s" % ch.role
	var kills := 0
	var runs := 0
	if MetaState.data != null:
		if "total_kills" in MetaState.data and MetaState.data.total_kills != null:
			kills = int(MetaState.data.total_kills)
		if "run_history" in MetaState.data:
			runs = (MetaState.data.run_history as Array).size()
	meta_label.text = "// TOTAL KILLS: %d\n// DATAJACK: OFFLINE\n// SUBNETS CLEARED: %d" % [kills, runs]
	# Stats come from the equipped character (REF/INT/BODY/LUCK/HP/sight).
	# REF is the runner's meat-space reflexes; the deck's speed bonus is added
	# separately at initiative time (shown in Speed Bonus above). interface_rank
	# is a deck property, not a character stat, so it is not shown here.
	stat_ref_label.text = "REF/INT/BODY: %d / %d / %d" % [ch.reflex, ch.intelligence, ch.body]
	stat_luck_label.text = "LUCK: %d" % ch.luck
	hp_label.text = "HP: %d / %d" % [ch.max_health, ch.max_health]
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

# Click the portrait to cycle runner characters; persist the choice in
# MetaState so it carries across deaths and equip it into RunState for the
# current life (read by the game session at jack-in).
func _on_runner_portrait_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var count := _runner_characters.size()
	if count <= 0:
		return
	# Find the index of the currently equipped character (match by resource
	# path so it works across save/load cycles); default to 0 if not found.
	var cur_path := RunState.selected_character.resource_path if RunState.selected_character != null else ""
	var idx := 0
	for i in range(count):
		if _runner_characters[i].resource_path == cur_path:
			idx = i
			break
	var next_idx := (idx + 1) % count
	var ch: NetrunnerCharacter = _runner_characters[next_idx]
	RunState.selected_character = ch
	if MetaState.data != null:
		MetaState.data.selected_character_path = ch.resource_path
		MetaState.save()
	_refresh_netrunner_panel()

func _refresh_loaded() -> void:
	loaded_list.clear()
	for prog in active_deck.installed_programs:
		if not prog:
			loaded_list.add_item("(empty slot)", null, false)
			loaded_list.set_item_custom_fg_color(loaded_list.item_count - 1, COL_GREY)
			continue
		var _tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
		var col: Color = EFFECT_COLORS.get(prog.effect_type, COL_TEXT)
		var icon := prog.icon as Texture2D
		# Row text now only includes: chip + name + [tag] + (MU). The
		# ProgramType short code (A-P / UTL etc.) lived in the Library list
		# only and made the rows too wide to read.
		loaded_list.add_item("%s  %s  [%s]  (%d MU)" % [String.chr(0x258E), prog.program_name, EFFECT_TAGS_COMPACT.get(prog.effect_type, "?"), prog.memory_cost], icon, true)
		loaded_list.set_item_custom_fg_color(loaded_list.item_count - 1, Color(col.r, col.g, col.b, 1.0))
	if unload_button:
		unload_button.disabled = (_selected_loaded_idx < 0)
	_selected_loaded_idx = -1

func _refresh_library() -> void:
	library_list.clear()
	var free_mu := active_deck.effective_max_mu() - active_deck.get_used_mu()
	var filter_et = _filter_effects[filter_option.selected] if filter_option else null
	for prog in _owned_programs():
		if not prog:
			continue
		if filter_et != null and prog.effect_type != filter_et:
			continue
		var _tag: String = EFFECT_TAGS.get(prog.effect_type, "?")
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
		library_list.add_item("%s  %s  [%s]  (%d MU)%s" % [String.chr(0x258E), prog.program_name, EFFECT_TAGS_COMPACT.get(prog.effect_type, "?"), prog.memory_cost, suffix], icon, true)
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
	if configure_subs_button:
		configure_subs_button.disabled = not (prog is DemonProgram)

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
	var free_mu := active_deck.effective_max_mu() - active_deck.get_used_mu()
	if prog.memory_cost > free_mu:
		_show_message("MEMORY FULL: %s needs %d MU, only %d free." % [prog.program_name, prog.memory_cost, free_mu])
		return
	active_deck.installed_programs.append(prog)
	# Demons are duplicated on load so workbench subroutine assignment never
	# mutates the catalogue .tres or the owned-program copy. Non-Demon
	# programs keep the existing share-by-reference behavior.
	if prog is DemonProgram:
		var demon_copy := (prog as DemonProgram).duplicate() as DemonProgram
		if demon_copy != null:
			demon_copy.assigned_subroutines.clear()
			active_deck.installed_programs.erase(prog)
			active_deck.installed_programs.append(demon_copy)
			prog = demon_copy
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

func _on_exit_pressed() -> void:
	get_tree().quit()

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
		KEY_ESCAPE:
			_on_exit_pressed()

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

# The reusable pulse function
func _start_pulse(target_button: Control) -> void:
	if target_button == null:
		return
		
	var tween := create_tween().set_loops()
	
	tween.tween_property(target_button, "modulate", Color(1.0, 1.2, 1.4, 1.0), 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
	tween.tween_property(target_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)\
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
func _refresh_credits() -> void:
	if credits_label:
		credits_label.text = "CREDITS: %d eb" % RunState.credits

func _refresh_shop() -> void:
	_refresh_shop_buy_decks()
	_refresh_shop_buy_programs()
	_refresh_shop_buy_modules()
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

func _refresh_shop_buy_modules() -> void:
	if shop_buy_modules_list == null:
		return
	shop_buy_modules_list.clear()
	_selected_buy_module_idx = -1
	if MetaState.data == null:
		return
	for path in MetaState.data.unlocked_modules:
		var mod := load(path) as DeckModule
		if mod == null:
			continue
		if _is_module_owned(mod, path):
			continue
		var tag: String = DeckModule.effect_tag(mod.effect_type)
		var sign: String = mod.bonus_sign()
		shop_buy_modules_list.add_item("%s [%s %s] — %d eb" % [mod.module_name, tag, sign, mod.price], null, true)
		var idx := shop_buy_modules_list.item_count - 1
		shop_buy_modules_list.set_item_metadata(idx, mod)
		if RunState.credits < mod.price:
			shop_buy_modules_list.set_item_disabled(idx, true)
			shop_buy_modules_list.set_item_custom_fg_color(idx, COL_GREY)

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
		if cat_path != "" and (d.resource_path == cat_path or d.source_path == cat_path):
			return true
		if d.resource_path == "" and d.source_path == "" and cat_deck.deck_name != "" and d.deck_name == cat_deck.deck_name:
			return true
	return false

func _is_program_owned(cat_prog: NetProgram, cat_path: String) -> bool:
	for p in RunState.owned_programs:
		if p == null:
			continue
		if cat_path != "" and (p.resource_path == cat_path or p.source_path == cat_path):
			return true
		if p.resource_path == "" and p.source_path == "" and cat_prog.program_name != "" and p.program_name == cat_prog.program_name:
			return true
	return false

func _is_module_owned(cat_mod: DeckModule, cat_path: String) -> bool:
	for m in RunState.owned_modules:
		if m == null:
			continue
		if cat_path != "" and (m.resource_path == cat_path or m.source_path == cat_path):
			return true
		if m.resource_path == "" and m.source_path == "" and cat_mod.module_name != "" and m.module_name == cat_mod.module_name:
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

func _on_buy_module_selected(index: int) -> void:
	_selected_buy_module_idx = index

func _on_buy_module_pressed() -> void:
	if _selected_buy_module_idx < 0 or shop_buy_modules_list == null or _selected_buy_module_idx >= shop_buy_modules_list.item_count:
		_show_message("Select a module to buy.", COL_AMBER)
		return
	var mod := shop_buy_modules_list.get_item_metadata(_selected_buy_module_idx) as DeckModule
	if mod == null:
		return
	if RunState.credits < mod.price:
		_show_message("Insufficient credits for %s (%d eb)." % [mod.module_name, mod.price])
		return
	if RunState.buy_module(mod):
		_after_transaction()
		_show_message("Purchased %s for %d eb." % [mod.module_name, mod.price], COL_GREEN)
	else:
		_show_message("Purchase failed: %s." % mod.module_name)

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

func _on_sell_all_files_pressed() -> void:
	if RunState.carried_files.is_empty():
		_show_message("No files to sell.", COL_AMBER)
		return
	var proceeds := RunState.sell_all_files()
	_after_transaction()
	_show_message("Fenced all files for %d eb." % proceeds, COL_GREEN)

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
	_unlockable_modules.clear()
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
			elif res is DeckModule:
				_unlockable_modules.append(path)
		fname = dir.get_next()
	dir.list_dir_end()

func _open_unlock_window() -> void:
	_scan_data_catalogue()
	if unlock_window == null:
		_build_unlock_window()
	add_child(unlock_window)
	_refresh_unlock_list()
	unlock_window.popup_centered(Vector2i(420, 520))

func _build_unlock_window() -> void:
	unlock_window = UNLOCK_WINDOW_SCENE.instantiate()
	unlock_window.close_requested.connect(_close_unlock_window)
	unlock_credits_label = unlock_window.get_node("%CreditsLabel")
	unlock_list = unlock_window.get_node("%UnlockList")
	unlock_list.item_selected.connect(_on_unlock_selected)
	unlock_buy_button = unlock_window.get_node("%UnlockButton")
	unlock_buy_button.pressed.connect(_on_unlock_pressed)
	var close_btn: Button = unlock_window.get_node("%CloseButton")
	close_btn.pressed.connect(_close_unlock_window)

func _close_unlock_window() -> void:
	if unlock_window != null and is_instance_valid(unlock_window):
		unlock_window.hide()
		if unlock_window.get_parent() != null:
			unlock_window.get_parent().remove_child(unlock_window)

# ---------------------------------------------------------------------------
# Configure Subroutines window (for Demon programs)
# ---------------------------------------------------------------------------
func _open_subroutines_window() -> void:
	if active_deck == null or _selected_loaded_idx < 0:
		return
	if _selected_loaded_idx >= active_deck.installed_programs.size():
		return
	var prog := active_deck.installed_programs[_selected_loaded_idx] as NetProgram
	if not (prog is DemonProgram):
		return
	_sub_target_demon = prog as DemonProgram
	if subroutines_window == null:
		_build_subroutines_window()
	_refresh_subroutines_window()
	add_child(subroutines_window)
	subroutines_window.popup_centered(Vector2i(460, 560))

func _build_subroutines_window() -> void:
	subroutines_window = Window.new()
	subroutines_window.title = "◢ CONFIGURE SUBROUTINES ◣"
	subroutines_window.min_size = Vector2i(400, 460)
	subroutines_window.wrap_controls = true
	subroutines_window.close_requested.connect(_close_subroutines_window)
	subroutines_window.add_theme_color_override("embedded_border_bg", COL_BG)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	subroutines_window.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(THEME.make_header_label("◢ SUBROUTINE SLOTS ◣", true))
	col.add_child(THEME.make_label("Assigned subroutines fire at the Demon's STR.", COL_DIM, 22))

	sub_slot_list = ItemList.new()
	sub_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_slot_list.custom_minimum_size = Vector2(0, 130)
	sub_slot_list.item_selected.connect(_on_sub_slot_selected)
	col.add_child(sub_slot_list)

	col.add_child(THEME.make_rule())
	col.add_child(THEME.make_header_label("◢ AVAILABLE PROGRAMS ◣", true))

	sub_candidate_list = ItemList.new()
	sub_candidate_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_candidate_list.custom_minimum_size = Vector2(0, 160)
	sub_candidate_list.item_selected.connect(_on_sub_candidate_selected)
	col.add_child(sub_candidate_list)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)

	sub_assign_button = THEME.make_button("ASSIGN ▶", COL_HEADER)
	sub_assign_button.pressed.connect(_on_sub_assign_pressed)
	sub_assign_button.disabled = true
	btns.add_child(sub_assign_button)

	sub_clear_button = THEME.make_button("◀ CLEAR", COL_WARN)
	sub_clear_button.pressed.connect(_on_sub_clear_pressed)
	sub_clear_button.disabled = true
	btns.add_child(sub_clear_button)

	var done_btn := THEME.make_button("DONE", COL_GREEN)
	done_btn.pressed.connect(_close_subroutines_window)
	btns.add_child(done_btn)

	subroutines_window.theme = THEME_RES

func _close_subroutines_window() -> void:
	if subroutines_window != null and is_instance_valid(subroutines_window):
		subroutines_window.hide()
		if subroutines_window.get_parent() != null:
			subroutines_window.get_parent().remove_child(subroutines_window)
	_sub_target_demon = null
	_sub_selected_slot_idx = -1
	_sub_selected_candidate_idx = -1

func _refresh_subroutines_window() -> void:
	if _sub_target_demon == null:
		return
	sub_slot_list.clear()
	sub_candidate_list.clear()
	_sub_selected_slot_idx = -1
	_sub_selected_candidate_idx = -1
	if sub_assign_button:
		sub_assign_button.disabled = true
	if sub_clear_button:
		sub_clear_button.disabled = true
	# Slots: show assigned subroutine names or "(empty)".
	var assigned: Array = _sub_target_demon.assigned_subroutines
	for i in range(_sub_target_demon.max_subroutines):
		var label_txt: String = "Slot %d — " % (i + 1)
		if i < assigned.size() and assigned[i] != null:
			var sub := assigned[i] as NetProgram
			label_txt += "%s (STR %d)" % [sub.program_name, _sub_target_demon.strength]
		else:
			label_txt += "(empty)"
			sub_slot_list.set_item_custom_fg_color(i, COL_GREY)
		var idx := sub_slot_list.add_item(label_txt, null, true)
		sub_slot_list.set_item_metadata(idx, i)
	# Candidates: installed programs restricted to allowed executable effect
	# types, excluding the Demon itself and any other DemonProgram.
	_sub_candidates.clear()
	for prog in active_deck.installed_programs:
		if prog == _sub_target_demon:
			continue
		if prog is DemonProgram:
			continue
		# Eligible subroutines: allowed executable effect types only. The
		# slot-count gate is enforced by the Assign button state, not here,
		# so candidates remain visible when slots are full (for swapping).
		if prog.effect_type in DemonProgram.ALLOWED_SUB_EFFECTS:
			_sub_candidates.append(prog)
			var cidx := sub_candidate_list.add_item(
				"%s — %s (STR %d, MU %d)" % [
					prog.program_name,
					EFFECT_TAGS.get(prog.effect_type, "???"),
					prog.strength,
					prog.memory_cost,
				], null, true)
			sub_candidate_list.set_item_metadata(cidx, _sub_candidates.size() - 1)

func _on_sub_slot_selected(index: int) -> void:
	_sub_selected_slot_idx = index
	if sub_clear_button:
		var slot_meta: int = sub_slot_list.get_item_metadata(index)
		var assigned: Array = _sub_target_demon.assigned_subroutines
		sub_clear_button.disabled = not (slot_meta < assigned.size() and assigned[slot_meta] != null)
	_update_sub_assign_state()

func _on_sub_candidate_selected(index: int) -> void:
	_sub_selected_candidate_idx = index
	_update_sub_assign_state()

func _update_sub_assign_state() -> void:
	if sub_assign_button == null or _sub_target_demon == null:
		return
	# Assign targets the selected slot if one is chosen, else the next free
	# slot. Disable if no candidate selected or no target slot available.
	var has_candidate := _sub_selected_candidate_idx >= 0 and _sub_selected_candidate_idx < _sub_candidates.size()
	var slot_meta: int = -1
	if _sub_selected_slot_idx >= 0:
		slot_meta = sub_slot_list.get_item_metadata(_sub_selected_slot_idx)
	var has_slot := false
	if slot_meta >= 0:
		var assigned: Array = _sub_target_demon.assigned_subroutines
		has_slot = slot_meta >= assigned.size() or assigned[slot_meta] == null
	else:
		has_slot = _sub_target_demon.assigned_subroutines.size() < _sub_target_demon.max_subroutines
	sub_assign_button.disabled = not (has_candidate and has_slot)

func _on_sub_assign_pressed() -> void:
	if _sub_target_demon == null or _sub_selected_candidate_idx < 0:
		return
	var sub := _sub_candidates[_sub_selected_candidate_idx] as NetProgram
	if sub == null:
		return
	var slot_idx: int = -1
	if _sub_selected_slot_idx >= 0:
		slot_idx = sub_slot_list.get_item_metadata(_sub_selected_slot_idx)
	if slot_idx < 0:
		slot_idx = _sub_target_demon.assigned_subroutines.size()
	# Grow the array to fit the slot, padding with nulls.
	while _sub_target_demon.assigned_subroutines.size() <= slot_idx:
		_sub_target_demon.assigned_subroutines.append(null)
	# Reject duplicates (a subroutine may only occupy one slot).
	if _sub_target_demon.assigned_subroutines.has(sub):
		_show_message("%s is already assigned to a slot." % sub.program_name, COL_AMBER)
		return
	_sub_target_demon.assigned_subroutines[slot_idx] = sub
	_refresh_subroutines_window()
	RunState.save_run()
	_show_message("Assigned %s to slot %d." % [sub.program_name, slot_idx + 1], COL_GREEN)

func _on_sub_clear_pressed() -> void:
	if _sub_target_demon == null or _sub_selected_slot_idx < 0:
		return
	var slot_idx: int = sub_slot_list.get_item_metadata(_sub_selected_slot_idx)
	if slot_idx < 0 or slot_idx >= _sub_target_demon.assigned_subroutines.size():
		return
	_sub_target_demon.assigned_subroutines[slot_idx] = null
	# Trim trailing nulls to keep the array tidy.
	while _sub_target_demon.assigned_subroutines.size() > 0:
		var last = _sub_target_demon.assigned_subroutines[_sub_target_demon.assigned_subroutines.size() - 1]
		if last == null:
			_sub_target_demon.assigned_subroutines.remove_at(_sub_target_demon.assigned_subroutines.size() - 1)
		else:
			break
	_refresh_subroutines_window()
	RunState.save_run()

# ---------------------------------------------------------------------------
# Upgrades window (hardware module install/uninstall)
# ---------------------------------------------------------------------------
func _open_upgrades_window() -> void:
	if active_deck == null:
		return
	if upgrades_window == null:
		_build_upgrades_window()
	_refresh_upgrades_window()
	add_child(upgrades_window)
	upgrades_window.popup_centered(Vector2i(520, 560))

func _build_upgrades_window() -> void:
	upgrades_window = Window.new()
	upgrades_window.title = "◢ DECK UPGRADES ◣"
	upgrades_window.min_size = Vector2i(460, 480)
	upgrades_window.wrap_controls = true
	upgrades_window.close_requested.connect(_close_upgrades_window)
	upgrades_window.add_theme_color_override("embedded_border_bg", COL_BG)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	upgrades_window.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(THEME.make_header_label("◢ UPGRADE SLOTS ◣", true))
	col.add_child(THEME.make_label("Install hardware modules into the deck's upgrade slots.", COL_DIM, 22))

	upg_slot_list = ItemList.new()
	upg_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upg_slot_list.custom_minimum_size = Vector2(0, 130)
	upg_slot_list.item_selected.connect(_on_upg_slot_selected)
	col.add_child(upg_slot_list)

	col.add_child(THEME.make_rule())
	col.add_child(THEME.make_header_label("◢ OWNED MODULES ◣", true))

	upg_library_list = ItemList.new()
	upg_library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upg_library_list.custom_minimum_size = Vector2(0, 160)
	upg_library_list.item_selected.connect(_on_upg_library_selected)
	col.add_child(upg_library_list)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)

	upg_install_button = THEME.make_button("INSTALL ▶", COL_HEADER)
	upg_install_button.pressed.connect(_on_upg_install_pressed)
	upg_install_button.disabled = true
	btns.add_child(upg_install_button)

	upg_uninstall_button = THEME.make_button("◀ UNINSTALL", COL_WARN)
	upg_uninstall_button.pressed.connect(_on_upg_uninstall_pressed)
	upg_uninstall_button.disabled = true
	btns.add_child(upg_uninstall_button)

	var done_btn := THEME.make_button("DONE", COL_GREEN)
	done_btn.pressed.connect(_close_upgrades_window)
	btns.add_child(done_btn)

	upgrades_window.theme = THEME_RES

func _close_upgrades_window() -> void:
	if upgrades_window != null and is_instance_valid(upgrades_window):
		upgrades_window.hide()
		if upgrades_window.get_parent() != null:
			upgrades_window.get_parent().remove_child(upgrades_window)
	_upg_selected_slot_idx = -1
	_upg_selected_library_idx = -1

func _refresh_upgrades_window() -> void:
	if active_deck == null:
		return
	if upg_slot_list == null:
		return
	upg_slot_list.clear()
	upg_library_list.clear()
	_upg_selected_slot_idx = -1
	_upg_selected_library_idx = -1
	if upg_install_button:
		upg_install_button.disabled = true
	if upg_uninstall_button:
		upg_uninstall_button.disabled = true
	# Slots: show installed module or "(empty)".
	var slots: int = active_deck.upgrade_slots
	var installed: Array[DeckModule] = active_deck.installed_modules
	for i in range(slots):
		var label_txt: String = "Slot %d — " % (i + 1)
		if i < installed.size() and installed[i] != null:
			var mod := installed[i] as DeckModule
			label_txt += "%s [%s %s]" % [mod.module_name, DeckModule.effect_tag(mod.effect_type), mod.bonus_sign()]
		else:
			label_txt += "(empty)"
		var idx := upg_slot_list.add_item(label_txt, null, true)
		upg_slot_list.set_item_metadata(idx, i)
		if not (i < installed.size() and installed[i] != null):
			upg_slot_list.set_item_custom_fg_color(idx, COL_GREY)
	# Library: owned-but-not-installed modules.
	for mod in RunState.owned_modules:
		if mod == null:
			continue
		var tag: String = DeckModule.effect_tag(mod.effect_type)
		var sign: String = mod.bonus_sign()
		var idx := upg_library_list.add_item("%s [%s %s] — %d eb" % [mod.module_name, tag, sign, mod.price], null, true)
		upg_library_list.set_item_metadata(idx, mod)

func _on_upg_slot_selected(index: int) -> void:
	_upg_selected_slot_idx = index
	if upg_uninstall_button:
		var slot_meta: int = upg_slot_list.get_item_metadata(index)
		var installed: Array[DeckModule] = active_deck.installed_modules
		upg_uninstall_button.disabled = not (slot_meta < installed.size() and installed[slot_meta] != null)
	_update_upg_install_state()

func _on_upg_library_selected(index: int) -> void:
	_upg_selected_library_idx = index
	_update_upg_install_state()

func _update_upg_install_state() -> void:
	if upg_install_button == null or active_deck == null:
		return
	var has_module := _upg_selected_library_idx >= 0 and _upg_selected_library_idx < upg_library_list.item_count
	upg_install_button.disabled = not (has_module and active_deck.free_upgrade_slots() > 0)

func _on_upg_install_pressed() -> void:
	if active_deck == null or _upg_selected_library_idx < 0:
		return
	var mod := upg_library_list.get_item_metadata(_upg_selected_library_idx) as DeckModule
	if mod == null:
		return
	if RunState.install_module_to_deck(mod, active_deck):
		_refresh_upgrades_window()
		update_deck_ui()
		RunState.save_run()
		_show_message("Installed %s." % mod.module_name, COL_GREEN)
	else:
		_show_message("Cannot install %s — no free slots." % mod.module_name)

func _on_upg_uninstall_pressed() -> void:
	if active_deck == null or _upg_selected_slot_idx < 0:
		return
	var slot_idx: int = upg_slot_list.get_item_metadata(_upg_selected_slot_idx)
	if slot_idx < 0 or slot_idx >= active_deck.installed_modules.size():
		return
	var mod := active_deck.installed_modules[slot_idx] as DeckModule
	if mod == null:
		return
	if RunState.uninstall_module_from_deck(mod, active_deck):
		_refresh_upgrades_window()
		update_deck_ui()
		RunState.save_run()
		_show_message("Uninstalled %s." % mod.module_name, COL_AMBER)
	else:
		_show_message("Cannot uninstall that module.")

func _refresh_unlock_list() -> void:
	unlock_list.clear()
	_selected_unlock_idx = -1
	unlock_buy_button.disabled = true
	if unlock_credits_label:
		unlock_credits_label.text = "CREDITS: %d eb" % RunState.credits
	# Decks, then programs, then modules. Metadata: {"path": path, "category": String, "cost": int}.
	unlock_list.add_item("-- DECKS --", null, false)
	unlock_list.set_item_custom_fg_color(0, COL_HEADER)
	unlock_list.set_item_disabled(0, true)
	for path in _unlockable_decks:
		_add_unlock_row(path, "deck")
	unlock_list.add_item("-- PROGRAMS --", null, false)
	unlock_list.set_item_custom_fg_color(unlock_list.item_count - 1, COL_HEADER)
	unlock_list.set_item_disabled(unlock_list.item_count - 1, true)
	for path in _unlockable_programs:
		_add_unlock_row(path, "program")
	unlock_list.add_item("-- MODULES --", null, false)
	unlock_list.set_item_custom_fg_color(unlock_list.item_count - 1, COL_HEADER)
	unlock_list.set_item_disabled(unlock_list.item_count - 1, true)
	for path in _unlockable_modules:
		_add_unlock_row(path, "module")

func _add_unlock_row(path: String, category: String) -> void:
	var res = load(path)
	if res == null:
		return
	var name_txt: String = ""
	var cost: int = 0
	var already := false
	match category:
		"deck":
			var deck := res as Cyberdeck
			if deck == null:
				return
			name_txt = deck.deck_name
			cost = deck.price
			already = MetaState.has_deck(path)
		"program":
			var prog := res as NetProgram
			if prog == null:
				return
			name_txt = prog.program_name
			cost = prog.price
			already = MetaState.has_program(path)
		"module":
			var mod := res as DeckModule
			if mod == null:
				return
			name_txt = mod.module_name
			cost = mod.price
			already = MetaState.has_module(path)
		_:
			return
	if already:
		var idxu := unlock_list.add_item("%s — ✓ UNLOCKED" % name_txt, null, false)
		unlock_list.set_item_metadata(idxu, {"path": path, "category": category, "cost": cost})
		unlock_list.set_item_disabled(idxu, true)
		unlock_list.set_item_custom_fg_color(idxu, COL_GREY)
		return
	var idx := unlock_list.add_item("%s — %d eb" % [name_txt, cost], null, true)
	unlock_list.set_item_metadata(idx, {"path": path, "category": category, "cost": cost})
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
	var category: String = meta.get("category", "")
	var cost: int = meta.get("cost", 0)
	if path == "":
		return
	if RunState.credits < cost:
		_show_message("Insufficient credits (%d eb)." % cost)
		return
	RunState.credits -= cost
	var unlocked := false
	var item_name := ""
	match category:
		"deck":
			var deck := load(path) as Cyberdeck
			if deck != null:
				item_name = deck.deck_name
				MetaState.unlock_deck(path)
				unlocked = true
		"program":
			var prog := load(path) as NetProgram
			if prog != null:
				item_name = prog.program_name
				MetaState.unlock_program(path)
				unlocked = true
		"module":
			var mod := load(path) as DeckModule
			if mod != null:
				item_name = mod.module_name
				MetaState.unlock_module(path)
				unlocked = true
	if unlocked:
		_refresh_unlock_list()
		_refresh_shop()
		_refresh_credits()
		RunState.save_run()
		_show_message("Unlocked %s blueprint for %d eb." % [item_name, cost], COL_GREEN)
	else:
		_show_message("Unlock failed: %s." % path)

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
