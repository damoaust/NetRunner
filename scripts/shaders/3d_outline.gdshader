shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.1) = 0.02;

void fragment() {
    // Fresnel rim: 0 face-on -> 1 at the silhouette.
    float edge = 1.0 - dot(NORMAL, VIEW);
    // smoothstep over a tunable band gives a clean, anti-aliased falloff
    // (the previous pow(edge, 4.0) crushed the rim into ~1px and aliased).
    // outline_thickness is now actually used — it controls rim width and is
    // consistent across differently-sized proxies.
    float rim = smoothstep(1.0 - outline_thickness, 1.0, edge);
    vec3 col = outline_color.rgb * rim;
    ALBEDO = col;
    EMISSION = col;
    ALPHA = rim * outline_color.a;
}