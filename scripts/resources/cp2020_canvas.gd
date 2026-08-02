extends Control

@export var datafort_layout: CP2020DatafortLayout

# UI Grid dimensions & cell sizing in pixels
var cell_size: int = 40
@onready var grid_container = %GridContainer # Or a custom Control node for drawing

func _ready() -> void:
	if datafort_layout:
		render_grid(datafort_layout)
	else:
		print("No CP2020 Datafort Layout assigned!")

func render_grid(layout: CP2020DatafortLayout) -> void:
	print("Rendering CP2020 Matrix: " + layout.fort_name)
	print("Grid Size: %d x %d" % [layout.columns, layout.rows])
	
	# Here we will instantiate visual tile representations 
	# based on the layout.grid_tiles dictionary coordinates.
	for coord in layout.grid_tiles.keys():
		var tile_data = layout.grid_tiles[coord] as CP2020TileData
		if tile_data:
			# TODO: Spawn visual grid icon at (coord.x * cell_size, coord.y * cell_size)
			pass
