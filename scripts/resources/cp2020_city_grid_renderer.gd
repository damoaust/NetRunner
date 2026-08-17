@tool
class_name CP2020CityGridRenderer
extends CP2020NeonGridRenderer

# @tool designer-side renderer for the City Grid designer. Extends the shared
# CP2020NeonGridRenderer and adapts the designer's resource-based layout
# (current_layout / selected_datafort) into the normalised fields the parent
# draws. The designer (cp2020_city_grid_designer.gd) pushes current_layout /
# selected_datafort / grid_offset_y here and calls queue_redraw(); _draw()
# syncs from the layout then defers to the parent renderer.

const GRID_OFFSET_X: int = 20
# Vertical offset of the grid from the top of the control. Derived at runtime
# from the designer's TopPanel bottom edge (see cp2020_city_grid_designer.gd
# _sync_renderer); 90 is the fallback used before the designer pushes the
# scene-driven value.
var grid_offset_y: int = 90

var current_layout: CP2020CityGridLayout = null
var selected_datafort: CP2020CityGridDatafort = null


func _draw() -> void:
	_sync_from_layout()
	super._draw()


# Push the designer's resource layout into the normalised fields the shared
# renderer consumes (dataforts become plain dicts so the parent stays
# data-source agnostic).
func _sync_from_layout() -> void:
	if current_layout == null:
		grid_cols = 0
		grid_rows = 0
		dataforts = []
		return
	grid_cols = current_layout.grid_cols
	grid_rows = current_layout.grid_rows
	grid_offset = Vector2(GRID_OFFSET_X, grid_offset_y)
	city_name = current_layout.city_name
	header_label = "CITY GRID DESIGNER"
	ldl_entry = current_layout.ldl_entry
	selected_datafort_pos = selected_datafort.pos if selected_datafort != null else null
	runner_pos = null
	var built: Array = []
	for df in current_layout.dataforts:
		built.append({
			"name": df.name,
			"pos": df.pos,
			"security_tier": int(df.security_tier),
		})
	dataforts = built