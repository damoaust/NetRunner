shader_type canvas_item;

// =============================================================================
// CRT SHADER SETTINGS
// Adjust these parameters in the Inspector or directly below to tweak the effect.
// =============================================================================

// --- SCANLINES ---
// Density of lines across the height of the texture.
// Try: 100.0 (low res arcade / 8-bit), 300.0 (standard CRT TV), 600.0 (high-res PC monitor)
uniform float scanline_count : hint_range(10.0, 1000.0) = 800.0;

// Opacity of the scanline darkness.
// Try: 0.1 (very subtle), 0.25 (balanced), 0.6 (heavy dark lines)
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.0;

// Scrolling speed of the scanline pattern over time (0.0 turns off scrolling).
// Try: 0.0 (static), 0.5 (slow drift), 2.0 (fast rolling lines)
uniform float scanline_speed : hint_range(0.0, 10.0) = 0.0;


// --- SCREEN CURVATURE (FISHEYE) ---
// Controls the roundness of the glass tube.
// NOTE: Higher numbers = flatter screen!
// Try: 1.5 (heavy fisheye bubble), 2.5 (classic TV bulge), 10.0 (nearly flat / subtle curve)
uniform float curvature : hint_range(0.5, 20.0) = 20.0;


// --- VIGNETTE ---
// Darkening around the screen corners and edges.
// Try: 0.0 (disabled), 0.3 (subtle corner shading), 0.8 (heavy shadow framing)
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.0;


// --- CHROMATIC ABERRATION (RGB SPLIT) ---
// Separates Red/Blue channels near the edges (emulates beam miscalibration).
// Try: 0.0 (off), 0.002 (realistic blur), 0.008 (glitchy / heavily degraded lens)
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.000;


// =============================================================================
// MATH & RENDERING LOGIC
// =============================================================================

// Distorts UV coordinates outward from center to mimic a convex CRT glass faceplate
vec2 curve_uv(vec2 uv) {
    uv = uv * 2.0 - 1.0; // Center origin to (0,0)
    vec2 offset = abs(uv.yx) / vec2(curvature, curvature);
    uv = uv + uv * offset * offset;
    uv = uv * 0.5 + 0.5; // Remap back to standard UV range (0.0 to 1.0)
    return uv;
}

void fragment() {
    // 1. Calculate curved UV coordinates
    vec2 uv = curve_uv(UV);

    // 2. Hide pixels pushed beyond the boundary by the curvature distortion
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0); // Render black/transparent outside curved glass bounds
    } else {
        // 3. Chromatic Aberration: Sample RGB channels at slightly offset UVs
        float r = texture(TEXTURE, uv + vec2(chromatic_aberration, 0.0)).r;
        float g = texture(TEXTURE, uv).g;
        float b = texture(TEXTURE, uv - vec2(chromatic_aberration, 0.0)).b;
        float a = texture(TEXTURE, uv).a; // Keep original alpha mask

        vec4 text_color = vec4(r, g, b, a);

        // 4. Scanline Pass: Generate a sine wave pattern along the Y axis
        float scanline = sin((uv.y + TIME * scanline_speed * 0.05) * scanline_count * 3.14159 * 2.0);
        scanline = (scanline + 1.0) * 0.5; // Convert wave from range [-1, 1] to [0, 1]
        scanline = mix(1.0, scanline, scanline_intensity); // Blend with scanline_intensity setting

        // 5. Vignette Pass: Darken pixels toward the frame borders
        vec2 uv_vignette = uv * (1.0 - uv.yx);
        float vig = uv_vignette.x * uv_vignette.y * 16.0;
        vig = pow(vig, vignette_intensity);

        // 6. Output Final Composite Color
        // Modulate RGB only — keep the original alpha mask intact so scanline
        // troughs and vignette corners darken the image instead of becoming
        // transparent (which would let the panel background bleed through).
        COLOR = vec4(text_color.rgb * scanline * vig, text_color.a);
    }
}