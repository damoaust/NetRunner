class_name WorkbenchUpgradesWindow
extends Window

# Deck-upgrades popup (hardware module install/uninstall). Moved verbatim out
# of cyberdeck_workbench.gd (CODE_REVIEW §6.4): fully code-built UI themed via
# CP2020Theme. The workbench owns open/close delegation only — it constructs
# this window once, connects `changed` (deck UI refresh) and
# `message_requested` (MU status label), and calls open_for().

signal message_requested(text: String, color: Color)
signal changed

const THEME := preload("res://scripts/resources/cp2020_theme.gd")
const THEME_RES := preload("res://themes/cyberpunk_theme.tres")

# Palette (same values the workbench keeps for its own UI; see the CP2020Theme
# note there — the authoritative copy lives in CP2020Theme).
const COL_BG := Color(0.0, 0.07, 0.04, 1.0)
const COL_DIM := Color(0.42, 0.58, 0.5)
const COL_HEADER := Color(0.25, 1.0, 0.6)
const COL_WARN := Color(1.0, 0.3, 0.3)
const COL_GREEN := Color(0.2, 1.0, 0.4)
const COL_GREY := Color(0.38, 0.45, 0.42)
const COL_AMBER := Color(1.0, 0.75, 0.2)

var _deck: Cyberdeck = null
var _selected_slot_idx: int = -1
var _selected_library_idx: int = -1
var slot_list: ItemList
var library_list: ItemList
var install_button: Button
var uninstall_button: Button


func _init() -> void:
	title = "◢ DECK UPGRADES ◣"
	min_size = Vector2i(460, 480)
	wrap_controls = true
	close_requested.connect(_close_window)
	add_theme_color_override("embedded_border_bg", COL_BG)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(THEME.make_header_label("◢ UPGRADE SLOTS ◣", true))
	col.add_child(THEME.make_label("Install hardware modules into the deck's upgrade slots.", COL_DIM, 22))

	slot_list = ItemList.new()
	slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot_list.custom_minimum_size = Vector2(0, 130)
	slot_list.item_selected.connect(_on_slot_selected)
	col.add_child(slot_list)

	col.add_child(THEME.make_rule())
	col.add_child(THEME.make_header_label("◢ OWNED MODULES ◣", true))

	library_list = ItemList.new()
	library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_list.custom_minimum_size = Vector2(0, 160)
	library_list.item_selected.connect(_on_library_selected)
	col.add_child(library_list)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)

	install_button = THEME.make_button("INSTALL ▶", COL_HEADER)
	install_button.pressed.connect(_on_install_pressed)
	install_button.disabled = true
	btns.add_child(install_button)

	uninstall_button = THEME.make_button("◀ UNINSTALL", COL_WARN)
	uninstall_button.pressed.connect(_on_uninstall_pressed)
	uninstall_button.disabled = true
	btns.add_child(uninstall_button)

	var done_btn := THEME.make_button("DONE", COL_GREEN)
	done_btn.pressed.connect(_close_window)
	btns.add_child(done_btn)

	theme = THEME_RES


# Point the window at a deck and show it.
func open_for(deck: Cyberdeck) -> void:
	_deck = deck
	refresh()
	popup_centered(Vector2i(520, 560))


func _close_window() -> void:
	hide()
	if get_parent() != null:
		get_parent().remove_child(self)
	_selected_slot_idx = -1
	_selected_library_idx = -1


func refresh() -> void:
	if _deck == null or slot_list == null:
		return
	slot_list.clear()
	library_list.clear()
	_selected_slot_idx = -1
	_selected_library_idx = -1
	install_button.disabled = true
	uninstall_button.disabled = true
	# Slots: show installed module or "(empty)".
	var slots: int = _deck.upgrade_slots
	var installed: Array[DeckModule] = _deck.installed_modules
	for i in range(slots):
		var label_txt: String = "Slot %d — " % (i + 1)
		if i < installed.size() and installed[i] != null:
			var mod := installed[i] as DeckModule
			label_txt += "%s [%s %s]" % [mod.module_name, DeckModule.effect_tag(mod.effect_type), mod.bonus_sign()]
		else:
			label_txt += "(empty)"
		var idx := slot_list.add_item(label_txt, null, true)
		slot_list.set_item_metadata(idx, i)
		if not (i < installed.size() and installed[i] != null):
			slot_list.set_item_custom_fg_color(idx, COL_GREY)
	# Library: owned-but-not-installed modules.
	for mod in RunState.owned_modules:
		if mod == null:
			continue
		var tag: String = DeckModule.effect_tag(mod.effect_type)
		var sign: String = mod.bonus_sign()
		var idx := library_list.add_item("%s [%s %s] — %d eb" % [mod.module_name, tag, sign, mod.price], null, true)
		library_list.set_item_metadata(idx, mod)


func _on_slot_selected(index: int) -> void:
	_selected_slot_idx = index
	var slot_meta: int = slot_list.get_item_metadata(index)
	var installed: Array[DeckModule] = _deck.installed_modules
	uninstall_button.disabled = not (slot_meta < installed.size() and installed[slot_meta] != null)
	_update_install_state()


func _on_library_selected(index: int) -> void:
	_selected_library_idx = index
	_update_install_state()


func _update_install_state() -> void:
	if install_button == null or _deck == null:
		return
	var has_module := _selected_library_idx >= 0 and _selected_library_idx < library_list.item_count
	install_button.disabled = not (has_module and _deck.free_upgrade_slots() > 0)


func _on_install_pressed() -> void:
	if _deck == null or _selected_library_idx < 0:
		return
	var mod := library_list.get_item_metadata(_selected_library_idx) as DeckModule
	if mod == null:
		return
	if RunState.install_module_to_deck(mod, _deck):
		refresh()
		RunState.save_run()
		changed.emit()
		message_requested.emit("Installed %s." % mod.module_name, COL_GREEN)
	else:
		message_requested.emit("Cannot install %s — no free slots." % mod.module_name)


func _on_uninstall_pressed() -> void:
	if _deck == null or _selected_slot_idx < 0:
		return
	var slot_idx: int = slot_list.get_item_metadata(_selected_slot_idx)
	if slot_idx < 0 or slot_idx >= _deck.installed_modules.size():
		return
	var mod := _deck.installed_modules[slot_idx] as DeckModule
	if mod == null:
		return
	if RunState.uninstall_module_from_deck(mod, _deck):
		refresh()
		RunState.save_run()
		changed.emit()
		message_requested.emit("Uninstalled %s." % mod.module_name, COL_AMBER)
	else:
		message_requested.emit("Cannot uninstall that module.")