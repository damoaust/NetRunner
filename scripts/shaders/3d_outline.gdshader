shader_type spatial;
render_mode depth_draw_opaque, cull_back, unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.1) = 0.01;

void fragment() {
    # Simple outline using a Fresnel-like effect on the edges
    float edge = 1.0 - dot(NORMAL, VIEW);
    edge = pow(edge, 4.0); # Sharpen the falloff
    
    ALBEDO = outline_color.rgb;
    EMISSION = outline_color.rgb * edge;
    ALPHA = edge;
}
