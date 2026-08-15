shader_type canvas_item;

// Screen-texture outline shader for hover highlighting on procedurally
// rendered content. Samples the back buffer (screen_texture) and detects
// luminance edges in 8 directions — unlike the alpha-based outline.gdshader,
// this works on opaque canvas-item drawing (draw_rect, draw_string, etc.)
// where there is no sprite alpha to sample.

// The color of the outline. Default is pure white.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// The thickness of the outline in screen pixels.
uniform float outline_width : hint_range(0.0, 10.0, 1.0) = 2.0;

// Minimum luminance difference between a pixel and a neighbour for the
// edge to be drawn. ~0.15 filters out subtle grid lines while still
// catching bright entity glyphs on dark tile backgrounds.
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.15;

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 size = SCREEN_PIXEL_SIZE * outline_width;

	// Sample the back buffer at the current pixel
	float center_lum = luminance(textureLod(screen_texture, SCREEN_UV, 0.0).rgb);

	// Sample 8 neighbours and track the maximum luminance difference
	float max_diff = 0.0;
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(size.x, 0.0), 0.0).rgb)));
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(-size.x, 0.0), 0.0).rgb)));
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(0.0, size.y), 0.0).rgb)));
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(0.0, -size.y), 0.0).rgb)));
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(size.x, size.y), 0.0).rgb)));
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(-size.x, size.y), 0.0).rgb)));
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(size.x, -size.y), 0.0).rgb)));
	max_diff = max(max_diff, abs(center_lum - luminance(textureLod(screen_texture, SCREEN_UV + vec2(-size.x, -size.y), 0.0).rgb)));

	// Draw the outline colour where an edge is detected; transparent elsewhere
	if (max_diff > edge_threshold) {
		COLOR = outline_color;
	} else {
		COLOR = vec4(0.0);
	}
}