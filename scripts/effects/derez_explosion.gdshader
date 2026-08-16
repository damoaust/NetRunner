shader_type canvas_item;
render_mode unshaded;

// De-rez explosion shader — procedural noise-based explosion played when a
// rezzed program is de-rezzed (manually or destroyed by Killer ICE). The
// effect node (CP2020ExplosionEffect) drives the `progress` uniform 0→1
// over the animation duration and auto-frees when done.

// Animation progress 0→1, driven by the effect node's _process().
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// The program's identity color (from NetProgram.get_visual()["color"]).
uniform vec4 base_color : source_color = vec4(1.0, 0.3, 0.1, 1.0);

// Random per-spawn seed for noise variation.
uniform float seed = 0.0;

// Max explosion radius in UV space (0.5 = fills the drawn rect).
uniform float max_radius = 0.25;

// Overall brightness multiplier.
uniform float intensity = 1.5;

// --- Noise utilities ---

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise2d(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// Center UVs so (0,0) is the middle of the drawn rect.
	vec2 uv = UV - 0.5;
	float dist = length(uv);

	// Expanding shockwave radius.
	float radius = progress * max_radius;

	// Sharp ring edge with a soft inner falloff.
	float ring = smoothstep(radius + 0.02, radius - 0.04, dist);

	// Fragmentation noise — breaks the ring into jagged shards.
	float n = fbm(uv * 6.0 + vec2(seed * 17.0, seed * 31.0));
	float mask = ring * (0.55 + n * 0.45);

	// Inner residual glow (fading core).
	float core = smoothstep(radius * 0.5, 0.0, dist) * (1.0 - progress * 0.8);

	// Combine ring + core.
	float shape = max(mask, core * 0.6);

	// Alpha envelope: quick fade-in, hold, fade-out.
	float fade_in = smoothstep(0.0, 0.08, progress);
	float fade_out = 1.0 - smoothstep(0.65, 1.0, progress);
	float alpha = shape * fade_in * fade_out;

	// Color gradient: white-hot core → program color → dark edge.
	float t = clamp(dist / max(radius, 0.001), 0.0, 1.0);
	vec3 hot = vec3(1.0, 1.0, 0.9);
	vec3 mid = base_color.rgb;
	vec3 cool = base_color.rgb * 0.2;

	vec3 color = mix(hot, mid, smoothstep(0.0, 0.4, t));
	color = mix(color, cool, smoothstep(0.4, 1.0, t));

	// Brightness pulse — brightest early, dimming as it expands.
	float brightness = (1.0 - progress * 0.6) * intensity;
	color *= brightness;

	// Add sparkly noise highlights in the early phase.
	if (progress < 0.4) {
		float spark = fbm(uv * 12.0 + vec2(seed * 53.0, 0.0));
		spark = pow(spark, 3.0) * (1.0 - progress / 0.4);
		color += vec3(spark * 0.5);
	}

	COLOR = vec4(color, clamp(alpha, 0.0, 1.0));
}