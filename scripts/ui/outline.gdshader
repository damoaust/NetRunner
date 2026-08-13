shader_type canvas_item;

// The color of the outline. Default is pure white.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// The thickness of the outline in pixels.
uniform float outline_width : hint_range(0.0, 10.0, 1.0) = 1.0;

void fragment() {
    // Get the exact size of a single pixel based on the texture resolution
    vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
    
    // Sample the alpha (transparency) in 8 directions around the current pixel
    float alpha = 0.0;
    alpha += texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
    alpha += texture(TEXTURE, UV + vec2(-size.x, 0.0)).a;
    alpha += texture(TEXTURE, UV + vec2(0.0, size.y)).a;
    alpha += texture(TEXTURE, UV + vec2(0.0, -size.y)).a;
    alpha += texture(TEXTURE, UV + vec2(size.x, size.y)).a;
    alpha += texture(TEXTURE, UV + vec2(-size.x, size.y)).a;
    alpha += texture(TEXTURE, UV + vec2(size.x, -size.y)).a;
    alpha += texture(TEXTURE, UV + vec2(-size.x, -size.y)).a;
    
    // Read the original color of the sprite
    vec4 original_color = texture(TEXTURE, UV);
    
    // Cap the alpha so overlapping neighbor samples don't blow out the opacity
    vec4 final_outline = outline_color;
    final_outline.a = min(alpha, 1.0) * outline_color.a;
    
    // Mix the outline and the sprite based on the sprite's original transparency
    COLOR = mix(final_outline, original_color, original_color.a);
}