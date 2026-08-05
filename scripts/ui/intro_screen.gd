extends Control
## Boot/intro screen: typewriter-reveals the ASCII art logo with a blinking
## cursor, then advances to the CyberdeckWorkbench on any key/click.
##
## First input skips the typewriter reveal to the full image; the next input
## transitions to the workbench. Art is loaded at runtime from
## res://ascii-art.txt so it stays editable without touching this scene.

# --- Tunables ---
const ART_PATH := "res://ascii-art.txt"
const WORKBENCH_PATH := "res://scenes/ui/CyberdeckWorkbench.tscn"
const CHAR_DELAY := 0.012  # seconds per character reveal
const CURSOR_BLINK_INTERVAL := 0.5
const PROMPT_TEXT := "[ PRESS ANY KEY TO ENTER THE NET ]"
const TEXT_COLOR := Color(0.22, 1.0, 0.22)  # bright terminal green
const CURSOR_CHAR := "█"

# --- State ---
var _art_text := ""
var _revealed_chars := 0
var _reveal_done := false
var _cursor_visible := true
var _skipped := false

# --- Nodes ---
@onready var _art_label: Label = $ArtContainer/ArtLabel
@onready var _prompt_label: Label = $ArtContainer/PromptLabel
@onready var _reveal_timer: Timer = $RevealTimer
@onready var _blink_timer: Timer = $BlinkTimer


func _ready() -> void:
	_load_art()
	_art_label.text = ""
	_art_label.add_theme_color_override("font_color", TEXT_COLOR)
	_prompt_label.modulate.a = 0.0
	_prompt_label.text = PROMPT_TEXT
	_reveal_timer.wait_time = CHAR_DELAY
	_reveal_timer.timeout.connect(_on_reveal_tick)
	_blink_timer.wait_time = CURSOR_BLINK_INTERVAL
	_blink_timer.timeout.connect(_on_blink_tick)
	_reveal_timer.start()
	_blink_timer.start()


func _input(event: InputEvent) -> void:
	var is_advance: bool = false
	if event is InputEventKey and event.pressed and not event.echo:
		is_advance = true
	elif event is InputEventMouseButton and event.pressed:
		is_advance = true
	if not is_advance:
		return
	get_viewport().set_input_as_handled()
	if not _reveal_done:
		# First input: skip the rest of the typewriter and show full art.
		_skip_reveal()
	else:
		_advance_to_workbench()


func _load_art() -> void:
	var raw := FileAccess.get_file_as_string(ART_PATH)
	if raw == "" and not FileAccess.file_exists(ART_PATH):
		push_warning("IntroScreen: could not load ASCII art at %s" % ART_PATH)
	_art_text = raw.rstrip("\n")


func _on_reveal_tick() -> void:
	if _revealed_chars >= _art_text.length():
		_reveal_timer.stop()
		_reveal_done = true
		_update_art_display()
		_update_prompt_cursor()
		_fade_in_prompt()
		return
	_revealed_chars += 1
	_update_art_display()


func _on_blink_tick() -> void:
	_cursor_visible = not _cursor_visible
	_update_prompt_cursor()


# The art Label only ever holds the revealed art text — no cursor is ever
# appended here, so the centered art never shifts width and stays aligned
# with the prompt below it.
func _update_art_display() -> void:
	_art_label.text = _art_text.substr(0, _revealed_chars)


# The blinking cursor lives at the end of the prompt label, sharing its
# font size, so it never disturbs the art above.
func _update_prompt_cursor() -> void:
	var cursor := CURSOR_CHAR if _cursor_visible else " "
	_prompt_label.text = PROMPT_TEXT + " " + cursor


func _skip_reveal() -> void:
	_skipped = true
	_revealed_chars = _art_text.length()
	_reveal_timer.stop()
	_reveal_done = true
	_update_art_display()
	_update_prompt_cursor()
	_fade_in_prompt()


func _fade_in_prompt() -> void:
	var tween := create_tween()
	tween.tween_property(_prompt_label, "modulate:a", 1.0, 0.4)


func _advance_to_workbench() -> void:
	_blink_timer.stop()
	_reveal_timer.stop()
	get_tree().change_scene_to_file(WORKBENCH_PATH)