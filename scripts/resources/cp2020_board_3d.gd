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
# Camera zoom multiplier shared with the 2D Camera2D. >1 = zoom in (smaller
# world region visible), <1 = zoom out. Applied in sync_camera_2d by dividing
# the orthographic size so the 3D scene scales in lock-step with the 2D board.
# Set from the game session via set_zoom_factor(); loose-clamped here, the
# session enforces the user-facing min/max.
var _zoom_factor: float = 1.0

# --- Custom tile meshes (optional) ---
# Assign a PackedScene (.glb / .tscn / .scn) here in the inspector to replace the
# default procedurally-generated BoxMesh for that tile type. Leave null to use
# the default box (neon material applied).
#
# When a PackedScene is assigned: the scene is instantiated AS-IS — your scale,
# rotation, and child positions from the .tscn are respected. The model is
# placed at the tile centre (X/Z) with its AABB bottom aligned to the floor.
# No material override is applied (the model keeps its own materials). Author
# a .tscn with the .glb as an inherited scene, set the scale/rotation/position
# in the editor, and drop it onto the slot.
@export_group("Tile Meshes")
@export var wall_mesh: PackedScene = null
@export var gate_mesh: PackedScene = null
@export var memory_unit_mesh: PackedScene = null
@export var control_node_mesh: PackedScene = null
@export var ice_proxy_mesh: PackedScene = null
@export var floor_mesh: PackedScene = null

# --- Custom entity meshes (optional) ---
# Replace the default 3D primitive used for each on-grid entity/glyph with a
# custom PackedScene (.glb). Leave null for the default neon primitive.
# The model's own scale/rotation/position from the .tscn are respected; no
# material override is applied (the model keeps its own materials).
@export_group("Entity Meshes")
@export var runner_mesh: PackedScene = null
@export var black_ice_mesh: PackedScene = null
@export var npc_mesh: PackedScene = null
@export var rezzed_mesh: PackedScene = null
# Per-effect-type default 3D models for rezzed attack programs. Each is an
# optional middle-tier default: a program's own `mesh_scene` (on its .tres)
# takes priority, then the matching slot here, then the generic `rezzed_mesh`.
# Leave null to fall through to `rezzed_mesh`. Author a .tscn from a .glb and
# drop it onto the slot in the editor.
@export var rezzed_derez_mesh: PackedScene = null   # DEREZ_ICE (Killer family)
@export var rezzed_damage_mesh: PackedScene = null  # DAMAGE_RUNNER (Hellhound/Flatline)
@export var rezzed_crash_mesh: PackedScene = null   # CRASH_CPU (Krash)
@export var rezzed_demon_mesh: PackedScene = null    # DEMON (Imp/Afreet/Succubus/Balron)
@export var worm_mesh: PackedScene = null
@export var entry_arrow_up_mesh: PackedScene = null
@export var entry_arrow_down_mesh: PackedScene = null
# When true, custom PackedScene models have their materials forced to opaque
# (transparency disabled, albedo alpha set to 1.0). Fixes semi-transparent
# Sketchfab .glb models that use alpha blending. Disable if your model
# intentionally uses transparency (e.g. glass, holograms).
@export var force_opaque_models: bool = true

var sub_viewport: SubViewport
var camera_3d: Camera3D
var world_root: Node3D
var texture_rect: TextureRect
var _floor_mesh: MeshInstance3D
var _floor_scene_root: Node3D
var _tile_meshes: Array[Node3D] = []
# Tile 3D proxies (walls/gates/MU/CPU) keyed by grid coord, so a single tile
# can be refreshed in place when its state changes mid-game (gate unlock,
# wall breach, worm open) without rebuilding the whole floor (which would
# also wipe ICE proxies). Cleared alongside _tile_meshes in clear_walls.
var _tile_proxy_by_coord: Dictionary = {}  # Vector2i -> Node3D
var _beacon_meshes: Array[MeshInstance3D] = []
var _ice_meshes: Dictionary = {}  # entity (Node) -> Node3D
# 3D proxies for on-grid entities (replace the 2D sprites/glyphs in 3D mode).
var _runner_proxy: Node3D = null
# Blue fresnel glow shell around the runner proxy, shown while a defensive
# program (Shield / Aegis SHIELD, or ARMOR) is active. A world_root child
# (NOT a child of _runner_proxy) so the custom .glb's authored scale doesn't
# distort the sphere; positioned manually to follow the runner.
var _runner_glow_mesh: MeshInstance3D = null
var _runner_glow_material: ShaderMaterial
var _npc_proxies: Dictionary = {}        # Node (entity) -> Node3D
var _rezzed_proxies: Dictionary = {}     # Node (entity) -> Node3D
var _worm_proxies: Dictionary = {}       # coord (Vector2i) -> Node3D
var _entry_arrow_proxies: Dictionary = {} # coord (Vector2i) -> Node3D
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

# Entity proxy materials (neon, matching the tile aesthetic).
var _runner_material: StandardMaterial3D
var _npc_netwatch_material: StandardMaterial3D
var _npc_runner_material: StandardMaterial3D
var _rezzed_material: StandardMaterial3D
var _entry_arrow_up_material: StandardMaterial3D
var _entry_arrow_down_material: StandardMaterial3D


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
	sub_viewport.transparent_bg = false
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
	light.light_energy = 1.5
	light.light_color = Color(0.7, 0.8, 1.0)
	world_root.add_child(light)

	# WorldEnvironment for the 3D scene inside the SubViewport.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.4)
	env.ambient_light_energy = 1.0
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

	# --- Entity proxy materials (neon, unshaded so they read top-down) ---
	_runner_material = _make_emissive_mat(Color(0.0, 0.9, 1.0), 1.6)
	_npc_netwatch_material = _make_emissive_mat(Color(1.0, 0.15, 0.1), 1.4)
	_npc_runner_material = _make_emissive_mat(Color(1.0, 0.85, 0.1), 1.2)
	_rezzed_material = _make_emissive_mat(Color(0.2, 0.9, 1.0), 1.5)
	_entry_arrow_up_material = _make_emissive_mat(Color(0.0, 0.9, 0.9), 1.3)
	_entry_arrow_down_material = _make_emissive_mat(Color(0.8, 0.4, 1.0), 1.3)

	# Runner defensive-buff glow shell (Shield / Aegis / Armor active). Fresnel
	# rim + additive blend + TIME pulse so it reads as a neon shield bubble
	# around the runner without hiding the model underneath.
	_runner_glow_material = _make_runner_glow_shader_mat(Color(0.25, 0.6, 1.0, 1.0))


# Build an unshaded emissive StandardMaterial3D (neon solid for entity proxies).
func _make_emissive_mat(col: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 1.0)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 0.3
	mat.metallic = 0.4
	return mat


func _make_edge_shader_mat(edge_col: Color, fill_col: Color, glow: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _wall_shader_code()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("edge_color", edge_col)
	mat.set_shader_parameter("fill_color", fill_col)
	mat.set_shader_parameter("edge_glow", glow)
	return mat


func _make_runner_glow_shader_mat(col: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _runner_glow_shader_code()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("glow_color", col)
	mat.set_shader_parameter("glow_strength", 1.4)
	mat.set_shader_parameter("fresnel_power", 2.5)
	mat.set_shader_parameter("pulse_speed", 3.0)
	return mat


# Fresnel-rim additive blue glow for the runner's defensive-buff shell. The
# rim falloff (1 - dot(NORMAL, VIEW)) keeps the shell transparent in the
# centre so the runner model shows through; additive blend + TIME pulse give
# a neon shield-bubble look. `no_depth_test` would let it show through walls;
# we keep depth so it occludes correctly behind 3D walls.
static func _runner_glow_shader_code() -> String:
	return "
shader_type spatial;
render_mode blend_add, depth_draw_opaque, unshaded, cull_back;

uniform vec4 glow_color : source_color;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.4;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;
uniform float pulse_speed : hint_range(0.0, 8.0) = 3.0;

void fragment() {
	float fres = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float pulse = 0.65 + 0.35 * sin(TIME * pulse_speed);
	float intensity = fres * pulse * glow_strength;
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * intensity;
	ALPHA = intensity;
}
"


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
	var mat := StandardMaterial3D.new()
	# Dark navy floor that reads as solid ground behind the 2D grid.
	mat.albedo_color = Color(0.01, 0.02, 0.04, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.05, 0.08)
	mat.emission_energy_multiplier = 0.3
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if floor_mesh != null:
		# Custom floor scene: instantiate and extract the first MeshInstance3D.
		_floor_scene_root = floor_mesh.instantiate()
		var mis := _floor_scene_root.find_children("*", "MeshInstance3D")
		if mis.size() > 0:
			_floor_mesh = mis[0] as MeshInstance3D
		elif _floor_scene_root is MeshInstance3D:
			_floor_mesh = _floor_scene_root as MeshInstance3D
		else:
			push_warning("CP2020Board3D._create_floor_plane: floor_mesh scene has no MeshInstance3D, falling back to default.")
			if is_instance_valid(_floor_scene_root):
				_floor_scene_root.queue_free()
			_floor_scene_root = null
			_floor_mesh = MeshInstance3D.new()
			_floor_mesh.mesh = BoxMesh.new()
			(_floor_mesh.mesh as BoxMesh).size = Vector3(1, 2, 1)
		if _floor_scene_root != null:
			world_root.add_child(_floor_scene_root)
		_apply_material_recursive(_floor_mesh if _floor_scene_root == null else _floor_scene_root, mat)
		if _floor_scene_root != null:
			_floor_scene_root.position.y = -1.0
		else:
			_floor_mesh.position.y = -1.0
	else:
		# Use a thin box instead of a plane to avoid one-sided mesh issues with
		# the top-down camera.
		_floor_mesh = MeshInstance3D.new()
		_floor_mesh.name = "FloorPlane"
		var box := BoxMesh.new()
		box.size = Vector3(1, 2, 1)
		_floor_mesh.mesh = box
		_floor_mesh.material_override = mat
		_floor_mesh.position.y = -1.0  # Slightly below the tile meshes
		world_root.add_child(_floor_mesh)


# Resize/reposition the floor plane to cover the current datafort grid area.
func _resize_floor_plane(layout: CP2020DatafortLayout) -> void:
	var target: Node3D = _floor_scene_root if _floor_scene_root != null else _floor_mesh
	if target == null or layout == null:
		return
	var box: BoxMesh = null
	if _floor_mesh != null and _floor_mesh.mesh != null:
		box = _floor_mesh.mesh as BoxMesh
	if box:
		# Default box floor: resize the mesh itself.
		box.size = Vector3(layout.columns * cell_size, 2.0, layout.rows * cell_size)
		target.scale = Vector3.ONE
	else:
		# Custom floor mesh: scale the instance so its AABB covers the grid.
		var aabb: AABB = _get_node_aabb(target)
		var sx: float = (layout.columns * cell_size) / aabb.size.x if aabb.size.x > 0.0 else 1.0
		var sz: float = (layout.rows * cell_size) / aabb.size.z if aabb.size.z > 0.0 else 1.0
		target.scale = Vector3(sx, 1.0, sz)
	# Center the plane over the grid: the grid's first cell is at (cs/2, cs/2)
	# and the grid spans columns*cs by rows*cs.
	target.position = Vector3(
		(layout.columns * cell_size) / 2.0,
		-1.0,
		(layout.rows * cell_size) / 2.0
	)


# Compute a combined AABB for a node subtree (used for custom floor scenes).
func _get_node_aabb(node: Node3D) -> AABB:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh.get_aabb()
	var aabb := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D"):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var child_aabb := mi.mesh.get_aabb()
		if first:
			aabb = child_aabb
			first = false
		else:
			aabb = aabb.merge(child_aabb)
	if first:
		return AABB(Vector3.ONE * -0.5, Vector3.ONE)
	return aabb


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
	# Apply the shared zoom factor: a smaller orthographic size shows a smaller
	# world region, which the full-screen TextureRect stretches up — so the 3D
	# scene visually zooms in lock-step with the 2D Camera2D.zoom. Clamp guards
	# against a divide-by-zero if the factor is ever set to 0.
	var zf: float = _zoom_factor if _zoom_factor > 0.01 else 1.0
	camera_3d.size = vp_h / zf
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
	_tile_proxy_by_coord.clear()
	# NOTE: ICE 3D proxies (_ice_meshes) are NOT cleared here. They are entity
	# proxies (like NPC/rezzed), positioned at their home-floor Y and gated by
	# refresh_entity_proxy_visibility. They must persist across floor changes
	# (sync_from_layout calls this on every floor switch) — clearing them here
	# wiped the ICE models immediately after spawn_black_ice created them, so
	# ICE 3D models never rendered. Use clear_ice_proxies() for a full reset
	# (called by spawn_black_ice on load).


# Spawn an extruded wall mesh at the given grid coordinate. Uses a BoxMesh
# with the neon-edge shader material. Called by the sync helper for every
# DATAWALL tile on the current floor.
func spawn_wall(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var mesh := _spawn_proxy(wall_mesh, Vector3(cell_size * 0.9, wall_height, cell_size * 0.9), _wall_material, coord, floor_idx)
	if mesh != null:
		_tile_meshes.append(mesh)
		_tile_proxy_by_coord[coord] = mesh


# Spawn a 3D code gate: a thinner box with red (locked) or green (unlocked)
# neon-edge shader. Locked gates are solid obstacles; unlocked gates are
# shorter (half height) to show they've been opened.
func spawn_gate(coord: Vector2i, locked: bool, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var h: float = gate_height if locked else gate_height * 0.5
	var mat: Material = _gate_locked_material if locked else _gate_unlocked_material
	var mesh := _spawn_proxy(gate_mesh, Vector3(cell_size * 0.85, h, cell_size * 0.85), mat, coord, floor_idx)
	if mesh != null:
		if gate_mesh != null and not locked:
			# Unlocked custom scene: squash Y to half height to read as "opened".
			mesh.scale.y = 0.5
		_tile_meshes.append(mesh)
		_tile_proxy_by_coord[coord] = mesh


# Spawn a 3D memory unit: a small extruded chip box with amber emission.
func spawn_memory_unit(coord: Vector2i, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var mesh := _spawn_proxy(memory_unit_mesh, Vector3(cell_size * 0.6, chip_height, cell_size * 0.5), _mu_material, coord, floor_idx)
	if mesh != null:
		_tile_meshes.append(mesh)
		_tile_proxy_by_coord[coord] = mesh


# Spawn a 3D control node (CPU): a diamond/pyramid mesh with purple glow.
# If crashed, uses the dimmed red material instead.
func spawn_control_node(coord: Vector2i, crashed: bool, floor_idx: int = 0) -> void:
	if world_root == null:
		return
	var mat: Material = _cpu_crashed_material if crashed else _cpu_material
	var mesh := _spawn_proxy(control_node_mesh, Vector3(cell_size * 0.5, cpu_height, cell_size * 0.5), mat, coord, floor_idx, 45.0)
	if mesh != null:
		_tile_meshes.append(mesh)
		_tile_proxy_by_coord[coord] = mesh


# Spawn a 3D ICE proxy for an ICE entity — the ICE's on-map visual in 3D
# mode (replaces the 2D sprite/glyph). A solid neon shape tinted with the
# program's colour (default red for killer ICE). Uses black_ice_mesh if
# assigned, else a default box. Keyed by the ICE node so it can follow moves.
func spawn_ice_proxy(entity: Node, coord: Vector2i, floor_idx: int = 0, color: Color = Color(1.0, 0.15, 0.05)) -> void:
	if world_root == null or _ice_meshes.has(entity):
		return
	# Per-instance emissive material so each ICE can take its program colour.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.9)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := _spawn_proxy(black_ice_mesh, Vector3(cell_size * 0.7, wall_height * 0.8, cell_size * 0.7), mat, coord, floor_idx)
	if mesh != null:
		mesh.set_meta("home_floor", floor_idx)
		_ice_meshes[entity] = mesh


# Remove a 3D ICE proxy when the ICE is derezzed/destroyed.
func remove_ice_proxy(entity: Node) -> void:
	if _ice_meshes.has(entity):
		var m = _ice_meshes[entity]
		if is_instance_valid(m):
			m.queue_free()
		_ice_meshes.erase(entity)


# Clear all ICE 3D proxies (full reset). Called by the game session's
# spawn_black_ice before re-spawning ICE on a fresh dive, so stale proxies
# from a previous dive (pointing to freed nodes) don't linger. NOT called by
# clear_walls / sync_from_layout — ICE proxies persist across floor changes.
func clear_ice_proxies() -> void:
	for key in _ice_meshes.keys():
		var m = _ice_meshes[key]
		if is_instance_valid(m):
			m.queue_free()
	_ice_meshes.clear()


# Move an existing ICE proxy to a new coord (ICE move). No-op if absent.
func update_ice_proxy(entity: Node, new_coord: Vector2i, floor_idx: int = 0) -> void:
	if not _ice_meshes.has(entity):
		return
	var mesh: Node3D = _ice_meshes[entity]
	if is_instance_valid(mesh):
		mesh.position = grid_to_3d(new_coord, floor_idx)
		mesh.position.y = floor_idx * floor_gap - mesh.get_meta("aabb_bottom", 0.0)


# Shared helper: build a Node3D from a custom PackedScene (.glb) or a default
# box, centre it on the tile, and add it to world_root.
#
# When scene is null: a BoxMesh of default_size is created, the neon material
# is applied, and rot_y rotates it (existing behaviour).
#
# When a PackedScene is provided: the scene is instantiated AS-IS — the user's
# scale, rotation, and child positions from the .tscn are respected. The model
# is placed at the tile centre (X/Z) and its AABB bottom is aligned to the
# floor (Y). No material override is applied (the model keeps its own
# materials). Author a .tscn with the .glb, adjust scale/rotation/position in
# the editor, and drop it onto the inspector slot.
func _spawn_proxy(scene: PackedScene, default_size: Vector3, material: Material, coord: Vector2i, floor_idx: int, rot_y: float = 0.0) -> Node3D:
	if world_root == null:
		return null
	var node: Node3D
	if scene == null:
		var box := BoxMesh.new()
		box.size = default_size
		var mi := MeshInstance3D.new()
		mi.mesh = box
		node = mi
		if material != null:
			node.material_override = material
		node.rotation_degrees.y = rot_y
		node.position = grid_to_3d(coord, floor_idx)
		node.position.y += default_size.y / 2.0
	else:
		node = scene.instantiate()
		if force_opaque_models:
			_force_materials_opaque(node)
		var aabb := _get_scene_aabb(node)
		# Store the AABB bottom Y so update functions can reposition correctly.
		node.set_meta("aabb_bottom", aabb.position.y)
		node.position = grid_to_3d(coord, floor_idx)
		# Raise the model so its AABB bottom sits on the floor surface.
		node.position.y = floor_idx * floor_gap - aabb.position.y
	world_root.add_child(node)
	return node


# Compute the combined AABB of a node subtree in the root's local space.
# Transforms each MeshInstance3D's mesh AABB by the child's own transform.
func _get_scene_aabb(node: Node3D) -> AABB:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh.get_aabb()
		return AABB(Vector3.ONE * -0.5, Vector3.ONE)
	var aabb := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D"):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := mi.mesh.get_aabb()
		# Transform all 8 corners by the child's local transform and merge.
		for i in range(8):
			var corner := local.position + Vector3(
				local.size.x if (i & 1) else 0.0,
				local.size.y if (i & 2) else 0.0,
				local.size.z if (i & 4) else 0.0,
			)
			var tc := mi.transform * corner
			if first:
				aabb = AABB(tc, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(tc)
	if first:
		return AABB(Vector3.ONE * -0.5, Vector3.ONE)
	return aabb


# Force all materials in a subtree to opaque: duplicate surface materials,
# disable transparency, and set albedo alpha to 1.0. Fixes Sketchfab .glb
# models that ship with alpha-blended materials.
func _force_materials_opaque(node: Node3D) -> void:
	for child in node.find_children("*", "MeshInstance3D", true):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(i)
			if mat == null:
				continue
			if mat is BaseMaterial3D:
				var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_color = Color(dup.albedo_color.r, dup.albedo_color.g, dup.albedo_color.b, 1.0)
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				dup.alpha_scissor_threshold = 0.01
				mi.set_surface_override_material(i, dup)


# Compute the vertical extent of a node — either directly (MeshInstance3D) or
# by scanning its MeshInstance3D children (instantiated .glb scene root).
func _get_node_height(node: Node3D) -> float:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh.get_aabb().size.y
		return 1.0
	var aabb := _get_scene_aabb(node)
	return aabb.size.y if aabb.size.y > 0.0 else 1.0


# Apply a material_override to every MeshInstance3D found in the subtree.
func _apply_material_recursive(node: Node3D, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
		return
	for child in node.find_children("*", "MeshInstance3D"):
		(child as MeshInstance3D).material_override = material


# --- Netrunner avatar (replaces the 2D _draw ring/diamond) ---
func spawn_runner_proxy(coord: Vector2i, floor_idx: int = 0) -> void:
	if _runner_proxy != null and is_instance_valid(_runner_proxy):
		_runner_proxy.queue_free()
	# Diamond top-down (box rotated 45°) like the 2D runner diamond.
	_runner_proxy = _spawn_proxy(runner_mesh, Vector3(cell_size * 0.5, 20.0, cell_size * 0.5), _runner_material, coord, floor_idx, 45.0)
	# Defensive-buff glow shell (Shield/Aegis/Armor). Sibling of the proxy
	# under world_root so the custom .glb's authored scale doesn't distort
	# the sphere; positioned manually to follow the runner. Hidden until a
	# buff is raised (toggled via set_runner_shield_glow).
	_create_runner_glow(coord, floor_idx)

func update_runner_proxy(coord: Vector2i, floor_idx: int = 0) -> void:
	if _runner_proxy == null or not is_instance_valid(_runner_proxy):
		spawn_runner_proxy(coord, floor_idx)
		return
	_runner_proxy.position = grid_to_3d(coord, floor_idx)
	_runner_proxy.position.y = floor_idx * floor_gap - _runner_proxy.get_meta("aabb_bottom", 0.0)
	# Keep the glow shell centred on the runner as it moves.
	_position_runner_glow(coord, floor_idx)

func remove_runner_proxy() -> void:
	if _runner_proxy != null and is_instance_valid(_runner_proxy):
		_runner_proxy.queue_free()
	_runner_proxy = null
	if _runner_glow_mesh != null and is_instance_valid(_runner_glow_mesh):
		_runner_glow_mesh.queue_free()
	_runner_glow_mesh = null


# Build the runner defensive-buff glow shell at a tile. The shell is a
# SphereMesh slightly larger than a tile, centred at the model's mid-height,
# using the fresnel additive glow shader. Hidden by default.
func _create_runner_glow(coord: Vector2i, floor_idx: int) -> void:
	if world_root == null or _runner_glow_material == null:
		return
	if _runner_glow_mesh != null and is_instance_valid(_runner_glow_mesh):
		_runner_glow_mesh.queue_free()
	var sphere := SphereMesh.new()
	sphere.radius = cell_size * 0.55
	sphere.height = cell_size * 1.1
	_runner_glow_mesh = MeshInstance3D.new()
	_runner_glow_mesh.mesh = sphere
	_runner_glow_mesh.material_override = _runner_glow_material
	_runner_glow_mesh.visible = false
	world_root.add_child(_runner_glow_mesh)
	_position_runner_glow(coord, floor_idx)


# Place the glow shell at the runner's tile, vertically centred on the proxy
# model (half the model height above the floor).
func _position_runner_glow(coord: Vector2i, floor_idx: int) -> void:
	if _runner_glow_mesh == null or not is_instance_valid(_runner_glow_mesh):
		return
	var base_pos := grid_to_3d(coord, floor_idx)
	var model_h: float = _get_node_height(_runner_proxy) if (_runner_proxy != null and is_instance_valid(_runner_proxy)) else 20.0
	_runner_glow_mesh.position = Vector3(base_pos.x, floor_idx * floor_gap + model_h * 0.5, base_pos.z)


# Toggle the runner's defensive-buff glow (Shield / Aegis SHIELD, or ARMOR).
# Called by the game session when a defensive program is raised or consumed.
func set_runner_shield_glow(active: bool) -> void:
	if _runner_glow_mesh != null and is_instance_valid(_runner_glow_mesh):
		_runner_glow_mesh.visible = active


# --- NPC netrunner proxy (replaces the 2D GlyphLabel "N"/"R") ---
func spawn_npc_proxy(entity: Node, coord: Vector2i, is_netwatch: bool, floor_idx: int = 0) -> void:
	if _npc_proxies.has(entity):
		return
	var mat: Material = _npc_netwatch_material if is_netwatch else _npc_runner_material
	# A capsule-ish box standing on the tile.
	var mesh := _spawn_proxy(npc_mesh, Vector3(cell_size * 0.45, 26.0, cell_size * 0.45), mat, coord, floor_idx)
	if mesh != null:
		mesh.set_meta("home_floor", floor_idx)
		_npc_proxies[entity] = mesh

func update_npc_proxy(entity: Node, coord: Vector2i, floor_idx: int = 0) -> void:
	if not _npc_proxies.has(entity):
		return
	var mesh: Node3D = _npc_proxies[entity]
	if is_instance_valid(mesh):
		mesh.position = grid_to_3d(coord, floor_idx)
		mesh.position.y = floor_idx * floor_gap - mesh.get_meta("aabb_bottom", 0.0)

func remove_npc_proxy(entity: Node) -> void:
	if _npc_proxies.has(entity):
		var mesh: Node3D = _npc_proxies[entity]
		if is_instance_valid(mesh):
			mesh.queue_free()
		_npc_proxies.erase(entity)


# --- Rezzed attack-program proxy (replaces the 2D "◆" glyph) ---
# Resolves the 3D PackedScene for a rezzed program: the program's own
# `mesh_scene` (per-program override) wins, then the Board3D per-effect-type
# default slot, then the generic `rezzed_mesh`. Returns null when nothing is
# assigned (spawn falls back to the default neon box + _rezzed_material).
func _resolve_rezzed_mesh(prog: NetProgram) -> PackedScene:
	if prog == null:
		return rezzed_mesh
	if prog.mesh_scene != null:
		return prog.mesh_scene
	match prog.effect_type:
		NetProgram.EffectType.DEREZ_ICE:
			if rezzed_derez_mesh != null:
				return rezzed_derez_mesh
		NetProgram.EffectType.DAMAGE_RUNNER:
			if rezzed_damage_mesh != null:
				return rezzed_damage_mesh
		NetProgram.EffectType.CRASH_CPU:
			if rezzed_crash_mesh != null:
				return rezzed_crash_mesh
		NetProgram.EffectType.DEMON:
			if rezzed_demon_mesh != null:
				return rezzed_demon_mesh
		_:
			pass
	return rezzed_mesh

func spawn_rezzed_proxy(entity: Node, coord: Vector2i, floor_idx: int = 0) -> void:
	if _rezzed_proxies.has(entity):
		return
	var prog: NetProgram = entity.get("program") as NetProgram
	var scene: PackedScene = _resolve_rezzed_mesh(prog)
	var mesh := _spawn_proxy(scene, Vector3(cell_size * 0.4, 12.0, cell_size * 0.4), _rezzed_material, coord, floor_idx, 45.0)
	if mesh != null:
		mesh.set_meta("home_floor", floor_idx)
		_rezzed_proxies[entity] = mesh

func update_rezzed_proxy(entity: Node, coord: Vector2i, floor_idx: int = 0) -> void:
	if not _rezzed_proxies.has(entity):
		return
	var mesh: Node3D = _rezzed_proxies[entity]
	if is_instance_valid(mesh):
		mesh.position = grid_to_3d(coord, floor_idx)
		mesh.position.y = floor_idx * floor_gap - mesh.get_meta("aabb_bottom", 0.0)

func remove_rezzed_proxy(entity: Node) -> void:
	if _rezzed_proxies.has(entity):
		var mesh: Node3D = _rezzed_proxies[entity]
		if is_instance_valid(mesh):
			mesh.queue_free()
		_rezzed_proxies.erase(entity)


# --- Worm proxy (replaces the 2D "W" worm overlay). Colour shifts with
# integrity (purple -> orange -> red) so the material is per-instance. ---
func spawn_worm_proxy(coord: Vector2i, color: Color, floor_idx: int = 0) -> void:
	if _worm_proxies.has(coord):
		update_worm_proxy(coord, color)
		return
	var mesh := _spawn_proxy(worm_mesh, Vector3(cell_size * 0.5, 8.0, cell_size * 0.5), null, coord, floor_idx)
	if mesh:
		if worm_mesh == null:
			_apply_material_recursive(mesh, _make_worm_mat(color))
		_worm_proxies[coord] = mesh

func update_worm_proxy(coord: Vector2i, color: Color) -> void:
	if not _worm_proxies.has(coord):
		return
	var mesh: Node3D = _worm_proxies[coord]
	if is_instance_valid(mesh) and worm_mesh == null:
		_apply_material_recursive(mesh, _make_worm_mat(color))

func remove_worm_proxy(coord: Vector2i) -> void:
	if _worm_proxies.has(coord):
		var mesh: Node3D = _worm_proxies[coord]
		if is_instance_valid(mesh):
			mesh.queue_free()
		_worm_proxies.erase(coord)

func _make_worm_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.95)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


# --- Entry travel arrows (replace the 2D ↑/↓ glyphs on ENTRY tiles) ---
func spawn_entry_arrow(coord: Vector2i, up: bool, floor_idx: int = 0) -> void:
	if _entry_arrow_proxies.has(coord):
		return
	var mat: Material = _entry_arrow_up_material if up else _entry_arrow_down_material
	# A thin tall prism reads as an arrow/portal marker top-down.
	var mesh := _spawn_proxy(entry_arrow_up_mesh if up else entry_arrow_down_mesh, Vector3(cell_size * 0.3, 30.0, cell_size * 0.3), mat, coord, floor_idx)
	if mesh:
		_entry_arrow_proxies[coord] = mesh

func clear_entry_arrows() -> void:
	for key in _entry_arrow_proxies.keys():
		var mesh: Node3D = _entry_arrow_proxies[key]
		if is_instance_valid(mesh):
			mesh.queue_free()
	_entry_arrow_proxies.clear()


# Toggle visibility of every 3D tile proxy (walls / gates / MU / CPU / entry
# arrows) based on the fog-of-war `is_explored` flag of its tile. The 3D
# compositing layer renders on top of the 2D fog overlay (additive blend), so
# without this gating the 3D geometry of unexplored tiles would shine through
# the fog. Explored tiles (seen before, even if not currently in LoS) stay
# visible, matching the 2D fog's "explored = revealed" semantics; unexplored
# tiles are hidden. Call after sync_from_layout, after recalculate_fog_of_war,
# and after Sensor/Probe fog lifts.
func refresh_tile_proxy_fog(layout: CP2020DatafortLayout, floor_idx: int) -> void:
	if layout == null:
		return
	for coord in _tile_proxy_by_coord.keys():
		var proxy: Node3D = _tile_proxy_by_coord[coord]
		if not is_instance_valid(proxy):
			continue
		var tile = layout.get_tile(coord, floor_idx)
		proxy.visible = tile != null and tile.is_explored
	for coord in _entry_arrow_proxies.keys():
		var proxy: Node3D = _entry_arrow_proxies[coord]
		if not is_instance_valid(proxy):
			continue
		var tile = layout.get_tile(coord, floor_idx)
		proxy.visible = tile != null and tile.is_explored


# Toggle visibility of every entity proxy (ICE / NPC / rezzed program) based on
# whether its home floor matches the current floor AND its tile is currently
# in line of sight (fog-of-war). Entity proxies are floor-bound (ICE/NPC/rezzed
# never follow the runner between floors), and the orthographic top-down
# camera would otherwise render every floor's proxies overlapping on screen;
# the 3D compositing layer also renders on top of the 2D fog overlay, so
# without the LoS gate an ICE/NPC behind a locked gate would shine through
# the fog. Matching the 2D glyph rule (update_visibility uses is_visible),
# the 3D proxy shows only when the entity's tile is_visible this turn. Call
# on load, floor change, and after every recalculate_fog_of_war / Sensor-Probe
# fog lift. The runner proxy is always on the current floor and is left
# visible (the runner can always see itself).
func refresh_entity_proxy_visibility(layout: CP2020DatafortLayout, current_floor_idx: int) -> void:
	_refresh_proxy_dict_visibility(_ice_meshes, layout, current_floor_idx)
	_refresh_proxy_dict_visibility(_npc_proxies, layout, current_floor_idx)
	_refresh_proxy_dict_visibility(_rezzed_proxies, layout, current_floor_idx)

func _refresh_proxy_dict_visibility(dict: Dictionary, layout: CP2020DatafortLayout, current_floor_idx: int) -> void:
	for key in dict.keys():
		var proxy: Node3D = dict[key]
		if not is_instance_valid(proxy):
			continue
		# Validate the key before the typed assignment: a queue_free()'d
		# entity still lingers in the dict as a key, and assigning a freed
		# instance to a typed `Node` variable raises "Trying to assign
		# invalid previously freed instance" before we can check it.
		if not is_instance_valid(key):
			proxy.visible = false
			continue
		var entity: Node = key
		var home_floor: int = entity.get("home_floor")
		if home_floor != current_floor_idx:
			proxy.visible = false
			continue
		if layout == null:
			proxy.visible = true
			continue
		var pos = entity.get("current_position")
		var tile = layout.get_tile(pos, home_floor)
		proxy.visible = tile != null and tile.is_visible


# Clear every entity proxy (runner, NPCs, rezzed programs, worm, entry arrows).
# ICE proxies are cleared in clear_walls(); beacons in clear_beacons().
func clear_entity_proxies() -> void:
	remove_runner_proxy()
	for key in _npc_proxies.keys():
		var m: Node3D = _npc_proxies[key]
		if is_instance_valid(m):
			m.queue_free()
	_npc_proxies.clear()
	for key in _rezzed_proxies.keys():
		var m: Node3D = _rezzed_proxies[key]
		if is_instance_valid(m):
			m.queue_free()
	_rezzed_proxies.clear()
	for key in _worm_proxies.keys():
		var m: Node3D = _worm_proxies[key]
		if is_instance_valid(m):
			m.queue_free()
	_worm_proxies.clear()
	clear_entry_arrows()


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
	clear_entry_arrows()
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
			CP2020DatafortLayout.TileType.ENTRY:
				# 3D entry travel arrows replace the 2D ↑/↓ glyphs.
				if tile.can_go_up:
					spawn_entry_arrow(coord, true, p_floor)
				if tile.can_go_down:
					spawn_entry_arrow(coord, false, p_floor)


# Attach the TextureRect to a CanvasLayer so it renders on top of the 2D
# board renderer. Uses additive blend mode so the 3D neon glow shines through
# the fog overlay without obscuring the 2D neon grid lines beneath.
func attach_to_canvas_layer(canvas_layer: CanvasLayer) -> void:
	if texture_rect and texture_rect.get_parent() == null:
		canvas_layer.add_child(texture_rect)


# Refresh a single tile's 3D proxy in place after its state changes mid-game
# (gate unlock, wall breach, worm open, CPU crash). Removes the existing proxy
# at `coord` (if any) and respawns it from the tile's current type/state. No-op
# for tile types with no 3D proxy (EMPTY / ENTRY / BLACK_ICE / NETWATCH /
# NETRUNNER). Only call for tiles on the current floor — proxies for other
# floors are not tracked here (they're rebuilt on floor change).
func refresh_tile_3d(coord: Vector2i, tile: CP2020TileData, floor_idx: int) -> void:
	if world_root == null or tile == null:
		return
	# Remove the existing proxy at this coord (wall/gate/MU/CPU).
	if _tile_proxy_by_coord.has(coord):
		var old: Node3D = _tile_proxy_by_coord[coord]
		_tile_meshes.erase(old)
		_tile_proxy_by_coord.erase(coord)
		if is_instance_valid(old):
			old.queue_free()
	match tile.tile_type:
		CP2020DatafortLayout.TileType.DATAWALL:
			spawn_wall(coord, floor_idx)
		CP2020DatafortLayout.TileType.CODE_GATE:
			spawn_gate(coord, not tile.is_unlocked, floor_idx)
		CP2020DatafortLayout.TileType.MEMORY_UNIT:
			spawn_memory_unit(coord, floor_idx)
		CP2020DatafortLayout.TileType.CONTROL_NODE:
			spawn_control_node(coord, tile.cpu_crashed_turns > 0, floor_idx)
		_:
			# EMPTY / removed wall: no proxy. Entry arrows are handled by
			# sync_from_layout on floor change; mid-game arrow changes are rare.
			pass
	# Match the freshly spawned proxy's visibility to the tile's fog state so
	# it never shines through the fog (e.g. a gate just unlocked out of LoS).
	var new_proxy: Node3D = _tile_proxy_by_coord.get(coord)
	if new_proxy != null and is_instance_valid(new_proxy):
		new_proxy.visible = tile.is_explored


# Resize the 3D camera's orthographic size to match the 2D rendering
# resolution so 1 world unit maps to 1 screen pixel vertically. This keeps the
# 3D grid aligned with the 2D board. The SubViewport texture is also resized to
# the root viewport so the 3D output fills the screen at the same resolution
# as the 2D render (the TextureRect uses STRETCH_SCALE over FULL_RECT); this
# fixes pre-existing non-1080p scale drift and keeps zoom correct on any
# window size. camera_3d.size is re-applied each frame by sync_camera_2d
# (which also applies the zoom factor), so the value set here is a fallback.
func resize_viewport(width: int, height: int) -> void:
	var h: int = height if height > 0 else 700
	var w: int = width if width > 0 else 1920
	if sub_viewport:
		sub_viewport.size = Vector2i(w, h)
	if camera_3d:
		camera_3d.size = float(h)


# Set the shared camera zoom factor (driven by the game session from the mouse
# wheel). Applied in sync_camera_2d each frame via _sync_3d_camera, so setting
# the field is enough — the new zoom takes effect on the very next frame.
func set_zoom_factor(z: float) -> void:
	_zoom_factor = clampf(z, 0.1, 10.0)
