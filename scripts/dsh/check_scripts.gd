extends Node

## Headless full-compile check: load()s every .gd in the project so any script
## with a parse/compile error fails here, even if the boot smoke test never
## touches that file. Run as a SCENE (not with -s) so autoloads resolve:
##   godot --headless --path . res://scripts/dsh/check_scripts.tscn
## Exit code 0 = all scripts compile, 1 = at least one failure.

var _checked: int = 0
var _failed: Array[String] = []


func _ready() -> void:
	_walk("res://")
	for path in _failed:
		printerr("COMPILE FAIL: %s" % path)
	print("check_scripts: %d script(s) checked, %d failed" % [_checked, _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


func _walk(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("check_scripts: cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."): # skip .git / .godot / hidden
				_walk(dir_path.path_join(name))
		elif name.ends_with(".gd"):
			_checked += 1
			var script: Script = load(dir_path.path_join(name))
			if script == null or not script is Script:
				_failed.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()