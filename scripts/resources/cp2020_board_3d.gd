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
# can be rebuilt per-floor.
@export var floor_gap: float = 50.0
# Height of the top-down Camera3D above the floor. Orthographic projection
# means the exact value only affects near/far clipping, not screen scale.
@export var camera_height: float = 1000.0

# --- Custom tile meshes (optional) ---
# Assign a Mesh resource here in the inspector to replace the default
# procedurally-generated BoxMesh for that tile type. Leave null to use the
# default box. The neon material (_wall_material / _gate_*_material /
# _mu_material / _cpu_material) is still applied via material_override, so the
# tile keeps its colour/edges while taking the new shape. Author the mesh at
# the desired world size (e.g. ~36x24x36 for a wall at cell_size 40); the
# instance is positioned/centred on the tile the same way as the default box.
@export_group("Tile Meshes")
@export var wall_mesh: Mesh = null
@export var gate_mesh: Mesh = null
@export var memory_unit_mesh: Mesh = null
@export var control_node_mesh: Mesh = null
@export var ice_proxy_mesh: Mesh = null
@export var floor_mesh: Mesh = null

var sub_viewport: SubViewport
var camera_3d: Camera3D
var world_root: Node3D
var texture_rect: TextureRect
var _floor_mesh: MeshInstance3D
var _tile_meshes: Array[MeshInstance3D] = []
var _beacon_meshes: Array[MeshInstance3D] = []
var _ice_meshes: Dictionary = {}  # coord (Vector2i) -> MeshInstance3D
var _world_env: WorldEnvironment

# Debug helpers for verifying 3D camera alignment. Can be toggled via
# ScreenshotTool F11 or --debug-3d flag.
var _debug_origin: MeshInstance3D
var _debug_axis_x: MeshInstance3D
var _debug_axis_z: MeshInstance3D
var _debug_boundary: MeshInstance3D
var _debug_visible: bool = false

# Picture-in-picture preview of the 3D camera output. Created in
# _create_infrastructure when show_pip is true.
var _pip_texture_rect: TextureRect = null
var _pip_enabled: bool = false

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
	# Create shared materials up front; actual SubViewport/camera/world setup
	# is deferred to setup_with_container() / setup_from_scene() so the
	# controller can live inside a scene-authored SubViewportContainer.
	_create_materials()


# Called when the 3D infrastructure is authored in the scene (.tscn). The
# camera, light and world environment are children of this Node3D; geometry is
# added directly as children so it renders behind the 2D board.
func setup_from_scene() -> void:
	world_root = self
	# Find or create the camera.
	camera_3d = get_node_or_null("Camera3D") as Camera3D
	if camera_3d == null:
		camera_3d = Camera3D.new()
		camera_3d.name = "Camera3D"
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		add_child(camera_3d)
	# Top-down orientation is authored in the scene's Camera3D transform
	# (looking down -Y, world +Z = screen down to match the 2D +Y-down grid).
	# Do NOT override rotation here — setting rotation_degrees resets the
	# authored basis and previously pointed the camera UP (showing only the
	# background). Only mark it current.
	camera_3d.current = true

	# Build floor plane and debug alignment helpers (hidden by default).
	_create_floor_plane()
	_create_debug_helpers()


# Called when no scene-authored SubViewport exists. Creates the SubViewport
# dynamically and adds it to the provided SubViewportContainer so Godot
# renders it correctly.
func setup_with_container(container: SubViewportContainer) -> void:
	if container == null:
		push_error("CP2020Board3D.setup_with_container: container is null.")
		return
	if sub_viewport == null:
		_create_infrastructure()
	# Reparent the dynamically created SubViewport into the container so the
	# 3D output is displayed automatically.
	if sub_viewport and sub_viewport.get_parent() != container:
		if sub_viewport.get_parent():
			sub_viewport.get_parent().remove_child(sub_viewport)
		container.add_child(sub_viewport)
	container.stretch = true
	# Build debug alignment helpers (hidden by default).
	_create_debug_helpers()


# SubViewport compositing: render the 3D world to a SubViewport and display
# it via a TextureRect on the given (background) CanvasLayer, so the 3D
# terrain appears behind the 2D neon overlay. Use this when the scene does
# not embed the 3D view in a SubViewportContainer. Any scene-authored direct
# Camera3D is disabled so it does not render an empty 3D pass over the
# TextureRect.
func setup_subviewport(canvas_layer: CanvasLayer) -> void:
	# Disable a scene-authored direct Camera3D (child of this node) so the
	# main viewport does not render an empty 3D world on top of the TextureRect.
	var direct_cam := get_node_or_null("Camera3D") as Camera3D
	if direct_cam:
		direct_cam.current = false
		direct_cam.visible = false
	if sub_viewport == null:
		_create_infrastructure()
	# Attach the output TextureRect to the background canvas layer.
	if canvas_layer:
		attach_to_canvas_layer(canvas_layer)


# Build the SubViewport + Camera3D + world root + output TextureRect. The
# SubViewport is sized to match the board area (columns * cell_size by
# rows * cell_size + grid_offset_y). The TextureRect goes on the parent
# CanvasLayer so it renders behind the 2D BoardRenderer.
func _create_infrastructure() -> void:
	sub_viewport = SubViewport.new()
	sub_viewport.name = "Board3DViewport"
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# Transparent background so the 3D terrain (floor + walls) occludes the
	# 2D city background only where geometry exists — the city stays visible
	# around the grid. The 3D meshes themselves are opaque, so walls/floor
	# fully cover the background behind them (no city bleeding through).
	sub_viewport.transparent_bg = true
	sub_viewport.size = Vector2i(1920, 1080)
	# Give the SubViewport its own 3D world so the Camera3D and
	# WorldEnvironment inside it actually render.
	sub_viewport.own_world_3d = true
	add_child(sub_viewport)

	world_root = Node3D.new()
	world_root.name = "World3D"
	sub_viewport.add_child(world_root)

	camera_3d = Camera3D.new()
	camera_3d.name = "Camera3D"
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = 1080.0
	# Top-down: -90 degree X rotation looks down -Y with world +Z mapping to
	# screen down (matching the 2D board's +Y-down grid).
	camera_3d.position = Vector3(0, camera_height, 0)
	camera_3d.rotation_degrees = Vector3(-90, 0, 0)
	camera_3d.near = 1.0
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

	# WorldEnvironment for the 3D scene inside the SubViewport. The
	# background is cleared (transparent) so the 2D city background stays
	# visible around the grid; the 3D floor/walls occlude it within the grid.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.08, 0.12)
	env.ambient_light_energy = 0.4
	env.glow_enabled = false
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	world_root.add_child(_world_env)

	# Opaque floor plane (sized per datafort in sync_from_layout) so the grid
	# area is solid ground that occludes the 2D city background. Without it the
	# city would show through between the 3D walls.
	_create_floor_plane()

	# TextureRect displays the SubViewport's 3D output on the background
	# CanvasLayer (layer -1) so it renders behind the 2D BoardRenderer. Normal
	# (alpha) blend so the opaque 3D floor/walls occlude the city background
	# (additive blend let the city bleed through the walls).
	texture_rect = TextureRect.new()
	texture_rect.name = "Board3DOutput"
	texture_rect.texture = sub_viewport.get_texture()
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.anchors_preset = Control.PRESET_FULL_RECT
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Normal (alpha) blend: opaque 3D geometry occludes the city background;
	# transparent SubViewport areas (around the grid) let the city show through.

	# Build debug alignment helpers (hidden by default).
	_create_debug_helpers()


# Create a small picture-in-picture preview so we can see what the 3D
# camera is rendering even when the main TextureRect is behind the 2D
# board. Call this after attach_to_canvas_layer if you need the PIP.
func create_pip_preview() -> void:
	if texture_rect == null or texture_rect.get_parent() == null:
		return
	if _pip_texture_rect != null:
		return
	_pip_texture_rect = TextureRect.new()
	_pip_texture_rect.name = "Board3DPiP"
	_pip_texture_rect.texture = sub_viewport.get_texture()
	_pip_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip_texture_rect.size = Vector2(400, 300)
	_pip_texture_rect.position = Vector2(20, 110)
	_pip_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Add a border so it is easy to spot on screen.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(1, 0, 0.8, 1)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	_pip_texture_rect.add_theme_stylebox_override("panel", style)
	texture_rect.get_parent().add_child(_pip_texture_rect)
	_pip_enabled = true


# Create all shader/standard materials for 3D tile meshes.
func _create_materials() -> void:
	# Wall: cyan neon edges on a visible teal block (top-down needs a
	# distinctly-coloured fill so walls read as solid blocks against the
	# dark floor, not just thin outlines).
	_wall_material = _make_edge_shader_mat(Color(0.0, 0.85, 1.0, 1.0), Color(0.0, 0.20, 0.30, 0.92), 3.5)
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
	_mu_material.metallic = 0.7

	# CPU: purple glow
	_cpu_material = StandardMaterial3D.new()
	_cpu_material.albedo_color = Color(0.15, 0.05, 0.25, 0.9)
	_cpu_material.emission_enabled = true
	_cpu_material.emission = Color(0.5, 0.1, 0.8)
	_cpu_material.emission_energy_multiplier = 0.8
	_cpu_material.roughness = 0.3
	_cpu_material.metallic = 0.6

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
	_ice_glow_material.metallic = 0.8

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
	// Edge detection based on UV proximity to edges (thick neon frame so
	// extruded walls read clearly under the top-down camera).
	float edge = 0.0;
	edge = max(edge, smoothstep(0.80, 1.0, abs(UV.x - 0.5) * 2.0));
	edge = max(edge, smoothstep(0.80, 1.0, abs(UV.y - 0.5) * 2.0));

	vec3 color = mix(fill_color.rgb, edge_color.rgb, edge);
	float alpha = mix(fill_color.a, 1.0, edge);

	// Add emissive glow on edges
	EMISSION = edge_color.rgb * edge * edge_glow;
	ALBEDO = color;
	ALPHA = alpha;
}
"


# A dark floor plane at y=0 — the grid base. Resized in sync_from_layout to
# match the loaded datafort so it acts as the visible ground behind the 2D
# overlay.
func _create_floor_plane() -> void:
	if world_root == null:
		push_warning("CP2020Board3D._create_floor_plane: world_root is null, skipping.")
		return
	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.name = "FloorPlane"
	if floor_mesh != null:
		# Custom floor mesh (author at unit size; _resize_floor_plane scales it
		# to cover the grid).
		_floor_mesh.mesh = floor_mesh
	else:
		# Use a thin box instead of a plane to avoid one-sided mesh issues with
		# the top-down camera.
		var box := BoxMesh.new()
		box.size = Vector3(1, 2, 1)
		_floor_mesh.mesh = box

	var mat := StandardMaterial3D.new()
	# Dark navy floor that reads as solid ground behind the 2D grid.
	mat.albedo_color = Color(0.01, 0.02, 0.04, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.05, 0.08)
	mat.emission_energy_multiplier = 0.3
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_floor_mesh.material_override = mat
	_floor_mesh.position.y = -1.0  # Slightly below the tile meshes
	world_root.add_child(_floor_mesh)


# Resize/reposition the floor plane to cover the current datafort grid area.
func _resize_floor_plane(layout: CP2020DatafortLayout) -> void:
	if _floor_mesh == null or layout == null:
		return
	var box: BoxMesh = _floor_mesh.mesh as BoxMesh
	if box:
		# Default box floor: resize the mesh itself.
		box.size = Vector3(layout.columns * cell_size, 2.0, layout.rows * cell_size)
		_floor_mesh.scale = Vector3.ONE
	else:
		# Custom floor mesh: scale the instance so its AABB covers the grid.
		var aabb: AABB = _floor_mesh.mesh.get_aabb()
		var sx: float = (layout.columns * cell_size) / aabb.size.x if aabb.size.x > 0.0 else 1.0
		var sz: float = (layout.rows * cell_size) / aabb.size.z if aabb.size.z > 0.0 else 1.0
		_floor_mesh.scale = Vector3(sx, 1.0, sz)
	# Center the plane over the grid: the grid's first cell is at (cs/2, cs/2)
	# and the grid spans columns*cs by rows*cs.
	_floor_mesh.position = Vector3(
		(layout.columns * cell_size) / 2.0,
		-1.0,
		(layout.rows * cell_size) / 2.0
	)


# Convert a grid coordinate to a 3D world position. The grid maps to the XZ
# plane; Y is up (walls extrude on Y). With the top-down camera, world +Z
# maps to screen down, matching 2D +Y, so no Z negation is needed.
func grid_to_3d(coord: Vector2i, floor_idx: int = 0) -> Vector3:
	return Vector3(
		coord.x * cell_size + cell_size / 2.0,
		floor_idx * floor_gap,
		coord.y * cell_size + cell_size / 2.0
	)


# Sync the 3D camera position from the 2D RunnerCamera. The 2D camera follows
# the netrunner; the 3D camera mirrors that pan with a fixed top-down
# rotation so the 3D elements sit behind the 2D overlay at the same grid
# position. `floor_idx` offsets the camera Y so the current floor is in view.
func sync_camera_2d(cam_2d_pos: Vector2, _layout_size: Vector2i, floor_idx: int = 0) -> void:
	if camera_3d == null:
		return
	var center_x := cam_2d_pos.x
	# 2D pixel Y includes the 90px header offset. The 3D grid starts at Z=0,
	# so subtract grid_offset_y to get grid-space Y. With the top-down camera
	# (rotation -90° around X), world +Z maps to screen down, matching 2D +Y.
	var center_z := cam_2d_pos.y - grid_offset_y
	var floor_y: float = floor_idx * floor_gap
	var vp_h: float = camera_3d.size
	if sub_viewport:
		vp_h = float(sub_viewport.size.y)
	elif get_tree() and get_tree().root:
		vp_h = float(get_tree().root.size.y)
	camera_3d.size = vp_h
	# For an orthogonal top-down camera, the camera position maps to the
	# screen centre. Keep the scene-authored rotation (looking down -Y);
	# only update position + ortho size so panning follows the 2D camera.
	camera_3d.position = Vector3(center_x, floor_y + camera_height, center_z)
	camera_3d.current = true


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
	# Keep debug helpers; their visibility is toggled separately.


# Spawn an extruded wall mesh at the given grid coordinate. Uses a BoxMesh
# with the neon-edge shader material. Called by the sync helper for every
# DATAWALL tile on the current floor.
func spawn_wall(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var m: Mesh = wall_mesh
	var h: float
	if m == null:
		var box := BoxMesh.new()
		box.size = Vector3(cell_size * 0.9, wall_height, cell_size * 0.9)
		m = box
		h = wall_height
	else:
		h = m.get_aabb().size.y
	var mesh := MeshInstance3D.new()
	mesh.mesh = m
	mesh.material_override = _wall_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += h / 2.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D code gate: a thinner box with red (locked) or green (unlocked)
# neon-edge shader. Locked gates are solid obstacles; unlocked gates are
# shorter (half height) to show they've been opened.
func spawn_gate(coord: Vector2i, locked: bool, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var h: float = gate_height if locked else gate_height * 0.5
	var m: Mesh = gate_mesh
	if m == null:
		var box := BoxMesh.new()
		box.size = Vector3(cell_size * 0.85, h, cell_size * 0.85)
		m = box
	elif not locked:
		# Unlocked custom gate: halve its height offset to read as "opened".
		h = m.get_aabb().size.y * 0.5
	else:
		h = m.get_aabb().size.y
	var mesh := MeshInstance3D.new()
	mesh.mesh = m
	mesh.material_override = _gate_locked_material if locked else _gate_unlocked_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += h / 2.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D memory unit: a small extruded chip box with amber emission.
func spawn_memory_unit(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var m: Mesh = memory_unit_mesh
	var h: float
	if m == null:
		var box := BoxMesh.new()
		box.size = Vector3(cell_size * 0.6, chip_height, cell_size * 0.5)
		m = box
		h = chip_height
	else:
		h = m.get_aabb().size.y
	var mesh := MeshInstance3D.new()
	mesh.mesh = m
	mesh.material_override = _mu_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += h / 2.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D control node (CPU): a diamond/pyramid mesh with purple glow.
# If crashed, uses the dimmed red material instead.
func spawn_control_node(coord: Vector2i, crashed: bool, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var m: Mesh = control_node_mesh
	var h: float
	if m == null:
		# Use a box rotated 45° on Y for a diamond top-down look.
		var box := BoxMesh.new()
		box.size = Vector3(cell_size * 0.5, cpu_height, cell_size * 0.5)
		m = box
		h = cpu_height
	else:
		h = m.get_aabb().size.y
	var mesh := MeshInstance3D.new()
	mesh.mesh = m
	mesh.material_override = _cpu_crashed_material if crashed else _cpu_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += h / 2.0
	mesh.rotation_degrees.y = 45.0
	world_root.add_child(mesh)
	_tile_meshes.append(mesh)


# Spawn a 3D ICE glow proxy at a grid coordinate. A translucent red box that
# pulses, representing the ICE's threat aura. The 2D glyph/label stays on the
# entity's Node2D for the actual skull/glyph visual.
func spawn_ice_proxy(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null or _ice_meshes.has(coord):
		return
	var m: Mesh = ice_proxy_mesh
	var h: float
	if m == null:
		var box := BoxMesh.new()
		box.size = Vector3(cell_size * 0.7, wall_height * 0.8, cell_size * 0.7)
		m = box
		h = wall_height * 0.8
	else:
		h = m.get_aabb().size.y
	var mesh := MeshInstance3D.new()
	mesh.mesh = m
	mesh.material_override = _ice_glow_material
	mesh.position = grid_to_3d(coord, floor_idx)
	mesh.position.y += h * 0.5
	world_root.add_child(mesh)
	_ice_meshes[coord] = mesh


# Remove a 3D ICE proxy when the ICE is derezzed/destroyed.
func remove_ice_proxy(coord: Vector2i) -> void:
	if _ice_meshes.has(coord):
		var m = _ice_meshes[coord]
		if is_instance_valid(m):
			m.queue_free()
		_ice_meshes.erase(coord)


# Build optional debug alignment helpers: a 5x5 neon marker at the grid
# origin, axis-aligned arrows on +X (red) and +Z (green), and a wireframe
# boundary box around the datafort area. Hidden by default.
func _create_debug_helpers() -> void:
	if world_root == null:
		return
	_debug_origin = _make_debug_marker(0, 0, 0, Color.MAGENTA, Vector3(60, 4, 60))
	_debug_axis_x = _make_debug_arrow(Vector3(1, 0, 0), Color.RED)
	_debug_axis_z = _make_debug_arrow(Vector3(0, 0, 1), Color.GREEN)
	_debug_boundary = _make_boundary_box()
	set_debug_visible(_debug_visible)


func _make_debug_marker(floor_idx: int, x: int, y: int, col: Color, size: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.position = grid_to_3d(Vector2i(x, y), floor_idx)
	mesh.position.y += size.y * 0.5
	world_root.add_child(mesh)
	return mesh


func _make_debug_arrow(dir: Vector3, col: Color) -> MeshInstance3D:
	var arrow_root := MeshInstance3D.new()
	arrow_root.name = "DebugArrow" + ("X" if dir.x > 0 else "Z")
	world_root.add_child(arrow_root)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 2.0
	shaft.bottom_radius = 2.0
	shaft.height = 80.0
	var shaft_mesh := MeshInstance3D.new()
	shaft_mesh.mesh = shaft
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	shaft_mesh.material_override = mat
	shaft_mesh.position = dir * 40.0
	# Orient the cylinder so its long axis points along dir. A cylinder's
	# default height axis is Y, so rotate it to lie along dir.
	shaft_mesh.rotation_degrees = Vector3(90, 0, 0) if dir.z != 0 else Vector3(0, 0, -90)
	arrow_root.add_child(shaft_mesh)
	return arrow_root


func _make_boundary_box() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW
	mat.emission_enabled = true
	mat.emission = Color.YELLOW
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	world_root.add_child(mesh)
	return mesh


# Resize and redraw the debug boundary box around the current datafort grid.
func _update_debug_boundary(layout: CP2020DatafortLayout) -> void:
	if _debug_boundary == null or layout == null:
		return
	var im := _debug_boundary.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var w: float = layout.columns * cell_size
	var h: float = layout.rows * cell_size
	var y: float = 2.0
	var corners: PackedVector3Array = PackedVector3Array([
		Vector3(0, y, 0),
		Vector3(w, y, 0),
		Vector3(w, y, 0),
		Vector3(w, y, h),
		Vector3(w, y, h),
		Vector3(0, y, h),
		Vector3(0, y, h),
		Vector3(0, y, 0),
	])
	for c in corners:
		im.surface_add_vertex(c)
	im.surface_end()


# Show/hide the debug alignment helpers.
func set_debug_visible(p_visible: bool) -> void:
	_debug_visible = p_visible
	if _debug_origin:
		_debug_origin.visible = p_visible
	if _debug_axis_x:
		_debug_axis_x.visible = p_visible
	if _debug_axis_z:
		_debug_axis_z.visible = p_visible
	if _debug_boundary:
		_debug_boundary.visible = p_visible


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
	_resize_floor_plane(layout)
	_update_debug_boundary(layout)
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


# Resize the 3D camera's orthographic size to match the 2D rendering
# resolution so 1 world unit maps to 1 screen pixel vertically. This keeps the
# 3D grid aligned with the 2D board.
func resize_viewport(_width: int, height: int) -> void:
	var h: int = height if height > 0 else 700
	if camera_3d:
		camera_3d.size = float(h)