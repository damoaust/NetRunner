extends SceneTree

# One-shot generator. Run via:
#   godot --headless --script "res://tools/generate_city_grids.gd"
# Creates data/city_grids/*.tres for each hub in data/world_map_default.tres
# and writes hub.city_grid_path back into the world map layout.

const NIGHT: String = "res://scenes/forts/night_city_subnet.tres"
const LONDON: String = "res://scenes/forts/london_subnet.tres"
const TOKYO: String = "res://scenes/forts/tokyo_subnet.tres"

var _city_data: Dictionary = {
	"Night City": [
		["Arasaka Arcology", 4, TOKYO],
		["City Hall", 0, NIGHT],
		["Lucky 7 Mall", 1, NIGHT],
		["EBM", 3, LONDON],
		["NetWatch Office", 2, NIGHT],
	],
	"London": [
		["Royal Bank of Europe", 3, LONDON],
		["Scotland Yard", 2, LONDON],
		["Camden Underground", 1, LONDON],
		["MI6 Terminal", 4, LONDON],
	],
	"Tokyo": [
		["Arasaka Tower", 4, TOKYO],
		["Kendachi Industries", 3, TOKYO],
		["Imperial Palace", 0, NIGHT],
		["Sato Shipping", 2, TOKYO],
	],
	"Sao Paulo": [
		["Pedra Branca Bank", 2, NIGHT],
		["Favela Net", 0, NIGHT],
		["Brasilia Hub", 1, LONDON],
	],
	"Lagos": [
		["Lagos Stock Exchange", 2, LONDON],
		["Nigeria GovNet", 1, LONDON],
		["Petrol Corp", 3, LONDON],
	],
	"Sydney": [
		["Oz Defence", 3, TOKYO],
		["Harbour Trading", 1, TOKYO],
		["Outback Relay", 0, NIGHT],
	],
	"Chicago": [
		["Chicago Stock Exchange", 3, NIGHT],
		["Union Station Net", 1, NIGHT],
		["Contoso Holdings", 2, NIGHT],
	],
	"Mexico City": [
		["Mex GovNet", 2, NIGHT],
		["Aztec Oil", 1, NIGHT],
		["Cartel Relay", 4, LONDON],
	],
	"Moscow": [
		["Kremlin Terminal", 4, LONDON],
		["GazProm", 3, LONDON],
		["Red Square Bank", 1, LONDON],
	],
	"Cairo": [
		["Nile Bank", 2, LONDON],
		["Egypt GovNet", 1, LONDON],
		["Sphinx Holdings", 0, NIGHT],
	],
	"Seoul": [
		["Samsung Tower", 3, TOKYO],
		["Seoul Metro", 1, TOKYO],
		["KCIA Terminal", 4, LONDON],
	],
	"Manila": [
		["Manila Port Authority", 1, TOKYO],
		["Pearl Trading", 2, TOKYO],
		["StormFront Holdings", 0, NIGHT],
	],
}


func _init() -> void:
	var dir := DirAccess.open("res://")
	if dir.make_dir_recursive("data/city_grids") != OK:
		push_error("Could not create data/city_grids")
		quit(1)
		return
	var world_path := "res://data/world_map_default.tres"
	var layout := ResourceLoader.load(world_path) as CP2020WorldMapLayout
	if layout == null:
		push_error("Could not load world map layout")
		quit(1)
		return
	var count := 0
	for hub in layout.hubs:
		var city_name: String = hub.name
		if not _city_data.has(city_name):
			print("Skipping unknown hub: ", city_name)
			continue
		var slug := _slug(city_name)
		var path := "res://data/city_grids/%s.tres" % slug
		var grid := CP2020CityGridLayout.new()
		grid.city_name = city_name
		grid.grid_cols = 20
		grid.grid_rows = 12
		grid.ldl_entry = Vector2i(9, 5)
		var defs: Array = _city_data[city_name]
		var i := 0
		for entry in defs:
			var df := CP2020CityGridDatafort.new()
			df.name = String(entry[0])
			df.security_tier = int(entry[1])
			df.subnet_path = String(entry[2])
			df.ldl_cost = 50 + i * 10
			df.security_code = 3 + i
			df.trace_value = 5
			df.pos = Vector2i(3 + (i % 4) * 4, 2 + (i / 4) * 4)
			grid.dataforts.append(df)
			i += 1
		var err := ResourceSaver.save(grid, path)
		if err != OK:
			push_error("Failed to save %s: %d" % [path, err])
			continue
		hub.city_grid_path = path
		count += 1
		print("Saved city grid: ", path)
	var werr := ResourceSaver.save(layout, world_path)
	if werr != OK:
		push_error("Failed to save world map layout: %d" % werr)
	else:
		print("Updated world map layout with city_grid_path on %d hubs" % count)
	print("Done. Generated %d city grids." % count)
	quit(0)


func _slug(name: String) -> String:
	var s := name.to_lower()
	s = s.replace(" ", "_")
	s = s.replace(".", "")
	return s