shader_type canvas_item;
render_mode unshaded;

// Samples the screen below so the overlay composites over the whole UI
// (scanlines + vignette + flicker) instead of replacing it.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float scanline_density : hint_range(64.0, 1024.0) = 480.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.08;
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.28;
uniform float vignette_softness : hint_range(0.2, 8.0) = 2.2;
uniform float flicker_amplitude : hint_range(0.0, 0.1) = 0.015;
uniform float flicker_speed : hint_range(0.1, 20.0) = 6.0;

void fragment() {
	vec4 col = texture(screen_texture, SCREEN_UV);

	// Horizontal scanlines.
	float line = fract(SCREEN_UV.y * scanline_density);
	float scan = smoothstep(0.0, 0.5, line);
	col.rgb *= mix(1.0 - scanline_strength, 1.0, scan);

	// Radial vignette.
	vec2 centered = SCREEN_UV - 0.5;
	float dist = length(centered) * 1.41421;
	float vig = 1.0 - smoothstep(0.35, 0.85, dist * vignette_softness);
	col.rgb *= mix(1.0, clamp(vig, 0.0, 1.0), vignette_strength);

	// Subtle whole-screen brightness flicker via TIME.
	float flick = 1.0 + flicker_amplitude * sin(TIME * flicker_speed)
		+ flicker_amplitude * 0.5 * sin(TIME * flicker_speed * 2.7 + 1.3);
	col.rgb *= flick;

	COLOR = col;
}
