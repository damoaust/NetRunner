class_name WorkbenchSubroutinesWindow
extends Window

# Configure-Subroutines popup for Demon programs. Moved verbatim out of
# cyberdeck_workbench.gd (CODE_REVIEW §6.4): fully code-built UI themed via
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

var target_demon: DemonProgram = null
var _deck: Cyberdeck = null
var _candidates: Array[NetProgram] = []
var _selected_slot_idx: int = -1
var _selected_candidate_idx: int = -1
var slot_list: ItemList
var candidate_list: ItemList
var assign_button: Button
var clear_button: Button


func _init() -> void:
	title = "◢ CONFIGURE SUBROUTINES ◣"
	min_size = Vector2i(400, 460)
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

	col.add_child(THEME.make_header_label("◢ SUBROUTINE SLOTS ◣", true))
	col.add_child(THEME.make_label("Assigned subroutines fire at the Demon's STR.", COL_DIM, 22))

	slot_list = ItemList.new()
	slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot_list.custom_minimum_size = Vector2(0, 130)
	slot_list.item_selected.connect(_on_slot_selected)
	col.add_child(slot_list)

	col.add_child(THEME.make_rule())
	col.add_child(THEME.make_header_label("◢ AVAILABLE PROGRAMS ◣", true))

	candidate_list = ItemList.new()
	candidate_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	candidate_list.custom_minimum_size = Vector2(0, 160)
	candidate_list.item_selected.connect(_on_candidate_selected)
	col.add_child(candidate_list)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)

	assign_button = THEME.make_button("ASSIGN ▶", COL_HEADER)
	assign_button.pressed.connect(_on_assign_pressed)
	assign_button.disabled = true
	btns.add_child(assign_button)

	clear_button = THEME.make_button("◀ CLEAR", COL_WARN)
	clear_button.pressed.connect(_on_clear_pressed)
	clear_button.disabled = true
	btns.add_child(clear_button)

	var done_btn := THEME.make_button("DONE", COL_GREEN)
	done_btn.pressed.connect(_close_window)
	btns.add_child(done_btn)

	theme = THEME_RES


# Point the window at a Demon installed on `deck` and show it.
func open_for(demon: DemonProgram, deck: Cyberdeck) -> void:
	target_demon = demon
	_deck = deck
	refresh()


func _close_window() -> void:
	hide()
	if get_parent() != null:
		get_parent().remove_child(self)
	target_demon = null
	_selected_slot_idx = -1
	_selected_candidate_idx = -1


func refresh() -> void:
	if target_demon == null or _deck == null:
		return
	slot_list.clear()
	candidate_list.clear()
	_selected_slot_idx = -1
	_selected_candidate_idx = -1
	assign_button.disabled = true
	clear_button.disabled = true
	# Slots: show assigned subroutine names or "(empty)".
	var assigned: Array = target_demon.assigned_subroutines
	for i in range(target_demon.max_subroutines):
		var label_txt: String = "Slot %d — " % (i + 1)
		if i < assigned.size() and assigned[i] != null:
			var sub := assigned[i] as NetProgram
			label_txt += "%s (STR %d)" % [sub.program_name, target_demon.strength]
		else:
			label_txt += "(empty)"
			slot_list.set_item_custom_fg_color(i, COL_GREY)
		var idx := slot_list.add_item(label_txt, null, true)
		slot_list.set_item_metadata(idx, i)
	# Candidates: installed programs restricted to allowed executable effect
	# types, excluding the Demon itself and any other DemonProgram.
	_candidates.clear()
	for prog in _deck.installed_programs:
		if prog == target_demon:
			continue
		if prog is DemonProgram:
			continue
		# Eligible subroutines: allowed executable effect types only. The
		# slot-count gate is enforced by the Assign button state, not here,
		# so candidates remain visible when slots are full (for swapping).
		if prog.effect_type in DemonProgram.ALLOWED_SUB_EFFECTS:
			_candidates.append(prog)
			var cidx := candidate_list.add_item(
				"%s — %s (STR %d, MU %d)" % [
					prog.program_name,
					NetProgram.EFFECT_TAGS.get(prog.effect_type, "???"),
					prog.strength,
					prog.memory_cost,
				], null, true)
			candidate_list.set_item_metadata(cidx, _candidates.size() - 1)


func _on_slot_selected(index: int) -> void:
	_selected_slot_idx = index
	var slot_meta: int = slot_list.get_item_metadata(index)
	var assigned: Array = target_demon.assigned_subroutines
	clear_button.disabled = not (slot_meta < assigned.size() and assigned[slot_meta] != null)
	_update_assign_state()


func _on_candidate_selected(index: int) -> void:
	_selected_candidate_idx = index
	_update_assign_state()


func _update_assign_state() -> void:
	if assign_button == null or target_demon == null:
		return
	# Assign targets the selected slot if one is chosen, else the next free
	# slot. Disable if no candidate selected or no target slot available.
	var has_candidate := _selected_candidate_idx >= 0 and _selected_candidate_idx < _candidates.size()
	var slot_meta: int = -1
	if _selected_slot_idx >= 0:
		slot_meta = slot_list.get_item_metadata(_selected_slot_idx)
	var has_slot := false
	if slot_meta >= 0:
		var assigned: Array = target_demon.assigned_subroutines
		has_slot = slot_meta >= assigned.size() or assigned[slot_meta] == null
	else:
		has_slot = target_demon.assigned_subroutines.size() < target_demon.max_subroutines
	assign_button.disabled = not (has_candidate and has_slot)


func _on_assign_pressed() -> void:
	if target_demon == null or _selected_candidate_idx < 0:
		return
	var sub := _candidates[_selected_candidate_idx] as NetProgram
	if sub == null:
		return
	var slot_idx: int = -1
	if _selected_slot_idx >= 0:
		slot_idx = slot_list.get_item_metadata(_selected_slot_idx)
	if slot_idx < 0:
		slot_idx = target_demon.assigned_subroutines.size()
	# Grow the array to fit the slot, padding with nulls.
	while target_demon.assigned_subroutines.size() <= slot_idx:
		target_demon.assigned_subroutines.append(null)
	# Reject duplicates (a subroutine may only occupy one slot).
	if target_demon.assigned_subroutines.has(sub):
		message_requested.emit("%s is already assigned to a slot." % sub.program_name, COL_AMBER)
		return
	target_demon.assigned_subroutines[slot_idx] = sub
	refresh()
	RunState.save_run()
	changed.emit()
	message_requested.emit("Assigned %s to slot %d." % [sub.program_name, slot_idx + 1], COL_GREEN)


func _on_clear_pressed() -> void:
	if target_demon == null or _selected_slot_idx < 0:
		return
	var slot_idx: int = slot_list.get_item_metadata(_selected_slot_idx)
	if slot_idx < 0 or slot_idx >= target_demon.assigned_subroutines.size():
		return
	target_demon.assigned_subroutines[slot_idx] = null
	# Trim trailing nulls to keep the array tidy.
	while target_demon.assigned_subroutines.size() > 0:
		var last = target_demon.assigned_subroutines[target_demon.assigned_subroutines.size() - 1]
		if last == null:
			target_demon.assigned_subroutines.remove_at(target_demon.assigned_subroutines.size() - 1)
		else:
			break
	refresh()
	RunState.save_run()
	changed.emit()