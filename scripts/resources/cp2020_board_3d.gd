class_name CP2020Board3D
extends Node3D

# 3D compositing layer for the datafort board. Renders extruded walls, 3D ICE
# models, volumetric beacons, and other 3D-styled elements behind the 2D neon
# overlay (CP2020BoardRenderer). The SubViewport output is displayed via a
# TextureRect on the background CanvasLayer. The 3D Camera3D syncs its position
# from the 2D RunnerCamera so panning stays aligned.
#
# Grid logic (Vector2i, AStarGrid2D, line_of_sight) is untouched — this layer
# only mirrors tile positions into 3D meshes. The 2D BoardRenderer draws on top
# for grid lines, fog-of-war, scanlines, vignette, hover, and text.

@export var cell_size: float = 40.0
@export var grid_offset_y: float = 90.0
@export var wall_height: float = 24.0
@export var gate_height: float = 16.0
@export var chip_height: float = 10.0
@export var cpu_height: float = 14.0
@export var beacon_height: float = 80.0
# Vertical separation between stacked floors in 3D. Each floor's mesh group
# is offset by floor_index * FLOOR_GAP on the Y axis so multi-floor dataforts
# show as a stacked tower behind the 2D overlay.
@export var floor_gap: float = 50.0

var sub_viewport: SubViewport
var camera_3d: Camera3D
var world_root: Node3D
var texture_rect: TextureRect
var _floor_mesh: MeshInstance3D
var _tile_meshes: Array[MeshInstance3D] = []
var _beacon_meshes: Array[MeshInstance3D] = []
var _ice_meshes: Dictionary = {}  # coord (Vector2i) -> MeshInstance3D
var _world_env: WorldEnvironment

# Neon-edge shader for extruded walls: dark fill with emissive cyan edges.
var _wall_material: ShaderMaterial
var _gate_locked_material: ShaderMaterial
var _gate_unlocked_material: ShaderMaterial
var _mu_material: StandardMaterial3D
var _cpu_material: StandardMaterial3D
var _cpu_crashed_material: StandardMaterial3D
var _ice_glow_material: StandardMaterial3D
var _beacon_material: ShaderMaterial


func _ready() -> void:
	_create_infrastructure()
	_create_materials()
	_create_floor_plane()


# Build the SubViewport + Camera3D + world root + output TextureRect. The
# SubViewport is sized to match the board area (columns * cell_size by
# rows * cell_size + grid_offset_y). The TextureRect goes on the parent
# CanvasLayer so it renders behind the 2D BoardRenderer.
func _create_infrastructure() -> void:
	sub_viewport = SubViewport.new()
	sub_viewport.name = "Board3DViewport"
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sub_viewport.transparent_bg = true
	sub_viewport.size = Vector2i(800, 700)
	add_child(sub_viewport)

	world_root = Node3D.new()
	world_root.name = "World3D"
	sub_viewport.add_child(world_root)

	camera_3d = Camera3D.new()
	camera_3d.name = "Camera3D"
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = 700.0
	camera_3d.position = Vector3(300, 500, 350)
	camera_3d.rotation_degrees = Vector3(-55, 0, 0)
	camera_3d.near = 0.1
	camera_3d.far = 2000.0
	camera_3d.current = true
	world_root.add_child(camera_3d)

	# Ambient light so meshes aren't pitch black.
	var light := DirectionalLight3D.new()
	light.position = Vector3(200, 400, 200)
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 0.6
	light.light_color = Color(0.4, 0.6, 0.8)
	world_root.add_child(light)

	# WorldEnvironment for the 3D scene inside the SubViewport.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.08, 0.12)
	env.ambient_light_energy = 0.4
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_strength = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	world_root.add_child(_world_env)

	# TextureRect on the bg CanvasLayer to display the 3D output. It sits
	# behind the 2D BoardRenderer (CanvasLayer -1 draws before the default
	# world 2D canvas).
	texture_rect = TextureRect.new()
	texture_rect.name = "Board3DOutput"
	texture_rect.texture = sub_viewport.get_texture()
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.anchors_preset = Control.PRESET_FULL_RECT
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Additive blend so the 3D neon glow shines through the 2D fog overlay.
	# Dark areas of the 3D output (floor plane) don't affect the 2D grid below.
	var tex_mat := CanvasItemMaterial.new()
	tex_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	texture_rect.material = tex_mat


# Create all shader/standard materials for 3D tile meshes.
func _create_materials() -> void:
	# Wall: cyan neon edges
	_wall_material = _make_edge_shader_mat(Color(0.0, 0.78, 0.92, 1.0), Color(0.02, 0.05, 0.08, 0.85), 2.0)
	# Locked gate: red neon edges
	_gate_locked_material = _make_edge_shader_mat(Color(1.0, 0.2, 0.15, 1.0), Color(0.08, 0.02, 0.02, 0.8), 2.5)
	# Unlocked gate: green neon edges, shorter
	_gate_unlocked_material = _make_edge_shader_mat(Color(0.0, 1.0, 0.4, 1.0), Color(0.02, 0.06, 0.03, 0.6), 1.5)

	# Memory unit: amber chip
	_mu_material = StandardMaterial3D.new()
	_mu_material.albedo_color = Color(0.3, 0.2, 0.05, 0.9)
	_mu_material.emission_enabled = true
	_mu_material.emission = Color(0.8, 0.6, 0.1)
	_mu_material.emission_energy_multiplier = 0.6
	_mu_material.roughness = 0.5
	_mu_material.metalness = 0.7

	# CPU: purple glow
	_cpu_material = StandardMaterial3D.new()
	_cpu_material.albedo_color = Color(0.15, 0.05, 0.25, 0.9)
	_cpu_material.emission_enabled = true
	_cpu_material.emission = Color(0.5, 0.1, 0.8)
	_cpu_material.emission_energy_multiplier = 0.8
	_cpu_material.roughness = 0.3
	_cpu_material.metalness = 0.6

	# Crashed CPU: dimmed red
	_cpu_crashed_material = StandardMaterial3D.new()
	_cpu_crashed_material.albedo_color = Color(0.2, 0.03, 0.03, 0.7)
	_cpu_crashed_material.emission_enabled = true
	_cpu_crashed_material.emission = Color(0.6, 0.05, 0.05)
	_cpu_crashed_material.emission_energy_multiplier = 0.3
	_cpu_crashed_material.roughness = 0.8

	# ICE glow: red-ish translucent
	_ice_glow_material = StandardMaterial3D.new()
	_ice_glow_material.albedo_color = Color(0.8, 0.1, 0.1, 0.4)
	_ice_glow_material.emission_enabled = true
	_ice_glow_material.emission = Color(1.0, 0.15, 0.05)
	_ice_glow_material.emission_energy_multiplier = 1.5
	_ice_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ice_glow_material.roughness = 0.2
	_ice_glow_material.metalness = 0.8

	# Beacon: volumetric additive column
	_beacon_material = _make_beacon_shader_mat(Color(1.0, 0.3, 0.1, 0.5))


func _make_edge_shader_mat(edge_col: Color, fill_col: Color, glow: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _wall_shader_code()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("edge_color", edge_col)
	mat.set_shader_parameter("fill_color", fill_col)
	mat.set_shader_parameter("edge_glow", glow)
	return mat


func _make_beacon_shader_mat(col: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, unshaded;

uniform vec4 beam_color : source_color;
uniform float pulse_speed = 3.0;

void fragment() {
	float pulse = 0.6 + 0.4 * sin(TIME * pulse_speed);
	EMISSION = beam_color.rgb * pulse * 2.0;
	ALBEDO = beam_color.rgb;
	ALPHA = beam_color.a * pulse;
}
"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("beam_color", col)
	return mat


static func _wall_shader_code() -> String:
	return "
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, unshaded;

uniform vec4 edge_color : source_color;
uniform vec4 fill_color : source_color;
uniform float edge_glow : hint_range(0.0, 10.0) = 2.0;

void fragment() {
	// Edge detection based on UV proximity to edges
	float edge = 0.0;
	edge = max(edge, smoothstep(0.92, 1.0, abs(UV.x - 0.5) * 2.0));
	edge = max(edge, smoothstep(0.92, 1.0, abs(UV.y - 0.5) * 2.0));

	vec3 color = mix(fill_color.rgb, edge_color.rgb, edge);
	float alpha = mix(fill_color.a, 1.0, edge);

	// Add emissive glow on edges
	EMISSION = edge_color.rgb * edge * edge_glow;
	ALBEDO = color;
	ALPHA = alpha;
}
"


# A dark floor plane at y=0 — the grid base. Scaled to cover a large area so
# the board sits on a surface. Uses a subtle grid shader for depth.
func _create_floor_plane() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.name = "FloorPlane"
	_floor_mesh.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.01, 0.02, 0.04, 1.0)
	mat.roughness = 0.9
	mat.metalness = 0.1
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.05, 0.08)
	mat.emission_energy_multiplier = 0.3
	_floor_mesh.material_override = mat
	_floor_mesh.position.y = -1.0  # Slightly below the tile meshes
	world_root.add_child(_floor_mesh)


# Convert a grid coordinate to a 3D world position. The grid maps to the XZ
# plane; Y is up (walls extrude on Y). When `floor_idx` is provided, the mesh
# is placed at that floor's height (offset by floor_idx * floor_gap on Y).
func grid_to_3d(coord: Vector2i, floor_idx: int = 0) -> Vector3:
	return Vector3(
		coord.x * cell_size + cell_size / 2.0,
		floor_idx * floor_gap,
		coord.y * cell_size + cell_size / 2.0
	)


# Sync the 3D camera position from the 2D RunnerCamera. The 2D camera follows
# the netrunner; the 3D camera mirrors that pan with a height + angle offset
# so the 3D elements sit behind the 2D overlay at the same grid position.
# `floor_idx` offsets the camera Y so deeper floors are viewed at their
# stacked position.
func sync_camera_2d(cam_2d_pos: Vector2, _layout_size: Vector2i, floor_idx: int = 0) -> void:
	if camera_3d == null:
		return
	var center_x := cam_2d_pos.x
	# 2D pixel Y includes the 90px header offset. The 3D grid starts at Z=0
	# (no header), so subtract grid_offset_y to get grid-space Y.
	var center_z := cam_2d_pos.y - grid_offset_y
	var floor_y: float = floor_idx * floor_gap
	# Match the 2D camera's visible area. The 2D Camera2D has no zoom, so its
	# visible height = window height in pixels. The SubViewport should match.
	# Use the SubViewport height as the orthographic size for 1:1 mapping.
	var vp_h: float = float(sub_viewport.size.y) if sub_viewport else 700.0
	camera_3d.size = vp_h
	# Position camera above the focus point, looking down at -55 degrees.
	# The camera Z is offset behind the focus so the -55 tilt frames the grid.
	camera_3d.position = Vector3(center_x, floor_y + vp_h * 0.7, center_z + vp_h * 0.5)
	camera_3d.rotation_degrees = Vector3(-55, 0, 0)


# Clear all 3D tile meshes (call before re-syncing on floor change / load).
func clear_walls() -> void:
	for w in _tile_meshes:
		if is_instance_valid(w):
			w.queue_free()
	_tile_meshes.clear()
	# Also clear ICE 3D proxies — they re-sync from entity spawns.
	for key in _ice_meshes.keys():
		var m = _ice_meshes[key]
		if is_instance_valid(m):
			m.queue_free()
	_ice_meshes.clear()


# Spawn an extruded wall mesh at the given grid coordinate. Uses a BoxMesh
# with the neon-edge shader material. Called by the sync helper for every
# DATAWALL tile on the current floor.
func spawn_wall(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var box := BoxMesh.new()
	box.size = Vector3(cell_size * 0.9, wall_height, cell_size * 0.9)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _wall_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += wall_height / 2.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D code gate: a thinner box with red (locked) or green (unlocked)
# neon-edge shader. Locked gates are solid obstacles; unlocked gates are
# shorter (half height) to show they've been opened.
func spawn_gate(coord: Vector2i, locked: bool, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var h: float = gate_height if locked else gate_height * 0.5
	var box := BoxMesh.new()
	box.size = Vector3(cell_size * 0.85, h, cell_size * 0.85)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _gate_locked_material if locked else _gate_unlocked_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += h / 2.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D memory unit: a small extruded chip box with amber emission.
func spawn_memory_unit(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var box := BoxMesh.new()
	box.size = Vector3(cell_size * 0.6, chip_height, cell_size * 0.5)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _mu_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += chip_height / 2.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D control node (CPU): a diamond/pyramid mesh with purple glow.
# If crashed, uses the dimmed red material instead.
func spawn_control_node(coord: Vector2i, crashed: bool, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	# Use a box rotated 45° on Y for a diamond top-down look.
	var box := BoxMesh.new()
	box.size = Vector3(cell_size * 0.5, cpu_height, cell_size * 0.5)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _cpu_crashed_material if crashed else _cpu_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += cpu_height / 2.0
	mesh.rotation_degrees.y = 45.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D ICE glow proxy at a grid coordinate. A translucent red box that
# pulses, representing the ICE's threat aura. The 2D glyph/label stays on the
# entity's Node2D for the actual skull/glyph visual.
func spawn_ice_proxy(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null or _ice_meshes.has(coord):
		return
	var box := BoxMesh.new()
	box.size = Vector3(cell_size * 0.7, wall_height * 0.8, cell_size * 0.7)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _ice_glow_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += wall_height * 0.4
	world_root.add_child(mesh)
	_ice_meshes[coord] = mesh


# Remove a 3D ICE proxy when the ICE is derezzed/destroyed.
func remove_ice_proxy(coord: Vector2i) -> void:
	if _ice_meshes.has(coord):
		var m = _ice_meshes[coord]
		if is_instance_valid(m):
			m.queue_free()
		_ice_meshes.erase(coord)


# Spawn a 3D beacon: a volumetric light column at a grid coordinate for
# watchdog trace markers. Uses a cylinder mesh with additive pulsing shader.
func spawn_beacon(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = cell_size * 0.15
	cyl.bottom_radius = cell_size * 0.15
	cyl.height = beacon_height
	var mesh := MeshInstance3D.new()
	mesh.mesh = cyl
	mesh.material_override = _beacon_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += beacon_height / 2.0
	world_root.add_child(mesh)
	_beacon_meshes.append(mesh)


# Clear all beacon meshes.
func clear_beacons() -> void:
	for b in _beacon_meshes:
		if is_instance_valid(b):
			b.queue_free()
	_beacon_meshes.clear()


# Sync beacons from a list of grid coordinates (watchdog trace positions).
func sync_beacons(coords: Array) -> void:
	clear_beacons()
	for c in coords:
		spawn_beacon(c)


# Full sync: clear + rebuild all 3D elements for the current floor. Called
# by the game session on load_subnet, floor change, and tile mutations.
func sync_from_layout(layout: CP2020DatafortLayout, p_floor: int) -> void:
	clear_walls()
	if layout == null:
		return
	var tiles := layout.get_floor_tiles(p_floor)
	for raw_key in tiles.keys():
		var coord := CP2020DatafortLayout.parse_coord(raw_key)
		var tile = layout.get_tile(coord, p_floor)
		if tile == null:
			continue
		match tile.tile_type:
			CP2020DatafortLayout.TileType.DATAWALL:
				spawn_wall(coord, p_floor)
			CP2020DatafortLayout.TileType.CODE_GATE:
				spawn_gate(coord, not tile.is_unlocked, p_floor)
			CP2020DatafortLayout.TileType.MEMORY_UNIT:
				spawn_memory_unit(coord, p_floor)
			CP2020DatafortLayout.TileType.CONTROL_NODE:
				spawn_control_node(coord, tile.cpu_crashed_turns > 0, p_floor)


# Attach the TextureRect to a CanvasLayer so it renders on top of the 2D
# board renderer. Uses additive blend mode so the 3D neon glow shines through
# the fog overlay without obscuring the 2D neon grid lines beneath.
func attach_to_canvas_layer(canvas_layer: CanvasLayer) -> void:
	if texture_rect and texture_rect.get_parent() == null:
		canvas_layer.add_child(texture_rect)


# Resize the SubViewport to match the actual on-screen area so the 3D
# camera's orthographic size maps 1:1 to screen pixels (matching the 2D camera).
func resize_viewport(_width: int, _height: int) -> void:
	if sub_viewport:
		# Use the window size, not the grid size, so the 3D camera sees the
		# same screen area as the 2D camera (which has no zoom).
		var win := DisplayServer.window_get_size()
		sub_viewport.size = Vector2i(maxi(win.x, 800), maxi(win.y, 600))