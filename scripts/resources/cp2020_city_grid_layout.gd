class_name CP2020CityGridLayout
extends Resource

# Serializable City Grid layout — the middle layer of the 3-level map model
# (World Map -> City Grid -> Datafort). Authored by the city grid designer
# and loaded at runtime by cp2020_city_grid.gd. The runner arrives on the
# `ldl_entry` tile from the world map, moves 5 tiles/turn, and dives into a
# datafort via its `subnet_path`.

@export var city_name: String = "New City"
@export var grid_cols: int = 20
@export var grid_rows: int = 12

@export var dataforts: Array[CP2020CityGridDatafort] = []

# Runner arrival tile from the world map (LDL icon).
@export var ldl_entry: Vector2i = Vector2i(10, 6)


func get_datafort(pos: Vector2i) -> CP2020CityGridDatafort:
	for df in dataforts:
		if df is CP2020CityGridDatafort and df.pos == pos:
			return df
	return null


func get_datafort_by_name(df_name: String) -> CP2020CityGridDatafort:
	for df in dataforts:
		if df is CP2020CityGridDatafort and df.name == df_name:
			return df
	return null