extends SceneTree

# One-off headless authoring pass: adds datafort entries to the Night City city
# grid (data/city_grids/night_city.tres) pointing at the file-bearing subnets
# (night_city_subnet, p2, p5) so Data Harvest missions are reachable via a
# normal world-map -> city-grid -> datafort dive. Idempotent: skips dataforts
# whose subnet_path is already present.

const GRID_PATH := "res://data/city_grids/night_city.tres"

func _init() -> void:
	var layout := load(GRID_PATH) as CP2020CityGridLayout
	if layout == null:
		print("ERROR: could not load %s as CP2020CityGridLayout" % GRID_PATH)
		quit()
		return

	# Build a set of already-present subnet paths so re-running is a no-op.
	var present := {}
	for df in layout.dataforts:
		if df != null:
			present[df.subnet_path] = true

	var to_add := [
		{"name": "Old Town Archive", "pos": Vector2i(3, 10), "subnet": "res://scenes/forts/night_city_subnet.tres", "tier": CP2020SecurityTier.Tier.LEVEL_2},
		{"name": "Pirate BBS", "pos": Vector2i(11, 10), "subnet": "res://scenes/forts/p2.tres", "tier": CP2020SecurityTier.Tier.LEVEL_1},
		{"name": "Warez Node", "pos": Vector2i(15, 10), "subnet": "res://scenes/forts/p5.tres", "tier": CP2020SecurityTier.Tier.LEVEL_1},
	]

	var added := 0
	for spec in to_add:
		if present.has(spec["subnet"]):
			print("  skip (already present): %s" % spec["subnet"])
			continue
		var df := CP2020CityGridDatafort.new()
		df.name = spec["name"]
		df.pos = spec["pos"]
		df.subnet_path = spec["subnet"]
		df.security_tier = spec["tier"]
		df.ldl_cost = 50
		df.security_code = 4
		df.trace_value = 5
		layout.dataforts.append(df)
		added += 1
		print("  added: %s @ %s -> %s" % [df.name, str(df.pos), df.subnet_path])

	if added == 0:
		print("Nothing to add — night_city.tres already wired.")
		quit()
		return

	var err := ResourceSaver.save(layout, GRID_PATH)
	if err != OK:
		print("ERROR: ResourceSaver failed (%d)" % err)
	else:
		print("Saved night_city.tres with %d new datafort(s)." % added)
	quit()