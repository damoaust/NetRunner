extends Node

# Debug screenshot utility. Press F12 to save the current main viewport and,
# when in a gameplay scene, the 3D board SubViewport to user://screenshots/.
# Press F11 to toggle the 3D board's debug alignment helpers.
# Command-line flag --auto-screenshot captures once shortly after startup and
# then quits, useful for automated visual verification.
# Command-line flag --debug-3d enables the debug helpers on startup.

const SUBDIR := "user://screenshots/"

func _ready() -> void:
	if OS.get_cmdline_args().has("--auto-screenshot"):
		_auto_capture()
	if OS.get_cmdline_args().has("--debug-3d"):
		_toggle_debug_3d(true)


func _auto_capture() -> void:
	# Give the first frame time to render before capturing.
	await get_tree().create_timer(2.0).timeout
	# Explore a short corridor so walls/gates are visible in the capture.
	var moves: Array[String] = ["move_right", "move_right", "move_right", "move_right", "move_right",
								"move_down", "move_down", "move_down", "move_down", "move_down"]
	for a in moves:
		Input.action_press(a)
		await get_tree().create_timer(0.05).timeout
		Input.action_release(a)
		await get_tree().create_timer(0.15).timeout
	await get_tree().create_timer(0.5).timeout
	await _take_screenshot()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		_take_screenshot()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_debug_3d()


func _toggle_debug_3d(force_enable: bool = false) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var board_3d := current_scene.get_node_or_null("Board3D") as CP2020Board3D
	if board_3d == null:
		board_3d = current_scene.find_child("Board3D", true, false) as CP2020Board3D
	if board_3d:
		var show := force_enable if force_enable else not board_3d._debug_visible
		board_3d.set_debug_visible(show)
		print("3D debug helpers: %s" % ("ON" if show else "OFF"))


func _take_screenshot() -> void:
	await get_tree().process_frame

	var dir := DirAccess.open(SUBDIR)
	if dir == null:
		var err := DirAccess.make_dir_recursive_absolute(SUBDIR)
		if err != OK:
			push_warning("ScreenshotTool: failed to create screenshots directory: %d" % err)
			return

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var base_path := SUBDIR + "netrunner_" + timestamp

	# Main viewport capture.
	var main_viewport := get_viewport()
	if main_viewport:
		var main_tex := main_viewport.get_texture()
		if main_tex:
			var main_img := main_tex.get_image()
			if main_img:
				var err := main_img.save_png(base_path + ".png")
				if err != OK:
					push_warning("ScreenshotTool: failed to save main screenshot: %d" % err)

	# NOTE: with direct 3D rendering the 3D layer is captured by the main
	# viewport screenshot above. A separate _3d.png is only saved when the
	# legacy SubViewport path still exists.
	var current_scene := get_tree().current_scene
	if current_scene:
		var board_3d_viewport := current_scene.get_node_or_null("Board3D/Board3DViewport") as SubViewport
		if board_3d_viewport == null:
			board_3d_viewport = current_scene.find_child("Board3DViewport", true, false) as SubViewport
		if board_3d_viewport and board_3d_viewport.get_texture():
			var img_3d := board_3d_viewport.get_texture().get_image()
			if img_3d:
				var err := img_3d.save_png(base_path + "_3d.png")
				if err != OK:
					push_warning("ScreenshotTool: failed to save 3D screenshot: %d" % err)
