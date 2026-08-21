extends SceneTree

# One-off headless scan: walks scenes/forts/*.tres, reports for each datafort
# the MEMORY_UNIT tiles (with their file names) and CONTROL_NODE tiles, with
# their grid coordinates. Output is printed to stdout so the mission library
# can be authored against real, in-world targets.

func _init() -> void:
	var dir := DirAccess.open("res://scenes/forts")
	if dir == null:
		print("ERROR: could not open res://scenes/forts")
		quit()
		return
	var paths: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tres"):
			paths.append("res://scenes/forts/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	for path in paths:
		var res := load(path)
		if res == null:
			continue
		# Duck-typed: any layout with grid_tiles + get_tile.
		if not ("grid_tiles" in res):
			continue
		var fort_name: String = res.get("fort_name") if res.get("fort_name") != null else path.get_file()
		print("=== %s (%s) ===" % [fort_name, path])
		var gt: Dictionary = res.grid_tiles
		var mem_coords: Array = []
		var cpu_coords: Array = []
		for key in gt.keys():
			var tile = gt[key]
			if tile == null:
				continue
			var tt: int = tile.tile_type
			# TileType enum: MEMORY_UNIT=5, CONTROL_NODE=6
			if tt == 5:
				var fnames: Array = []
				for nfile in tile.files:
					if nfile != null:
						fnames.append(nfile.file_name)
				mem_coords.append({"coord": key, "files": fnames})
			elif tt == 6:
				cpu_coords.append(key)
		print("  MEMORY_UNIT (%d):" % mem_coords.size())
		for e in mem_coords:
			print("    %s  files=%s" % [str(e["coord"]), str(e["files"])])
		print("  CONTROL_NODE (%d):" % cpu_coords.size())
		for c in cpu_coords:
			print("    %s" % str(c))
	quit()