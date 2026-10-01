shader_type canvas_item;

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.0;
uniform float vignette_radius : hint_range(0.1, 2.0) = 0.1;
uniform float glow_strength : hint_range(0.0, 0.5) = 0.0;
uniform float glow_radius : hint_range(0.1, 1.0) = 0.1;
uniform float brightness : hint_range(0.0, 2.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(0.1, 0.3, 0.1, 0.15);
uniform float alpha : hint_range(0.0, 1.0) = 0.4;
uniform float hue_shift : hint_range(-1.0, 1.0) = 0.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.0, 2.0) = 0.729;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0., -1./3., 2./3., -1.);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6. * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0., 2./3., 1./3.)) * 6. - 3.);
    return c.z * mix(vec3(1.), clamp(p - 1., 0., 1.), c.y);
}

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    vec2 center = vec2(0.5, 0.5);
    vec2 dist_vec = (UV - center) * vec2(1.2, 1.0);
    float dist = length(dist_vec);

    float vignette = 1.0 - smoothstep(vignette_radius * 0.5, vignette_radius, dist);
    vignette = mix(1.0 - vignette_strength, 1.0, vignette);

    float glow = exp(-dist * dist / (glow_radius * glow_radius)) * glow_strength;

    vec3 final_color = tex_color.rgb * brightness * vignette;
    final_color += vec3(glow * 0.3, glow, glow * 0.3);
    final_color = mix(final_color, tint_color.rgb, tint_color.a);

    vec3 hsv = rgb2hsv(final_color);
    hsv.x += hue_shift;
    final_color = hsv2rgb(hsv);

    float gray = dot(final_color, vec3(0.299, 0.587, 0.114));
    final_color = mix(vec3(gray), final_color, saturation);

    final_color = (final_color - 0.5) * contrast + 0.5;

    COLOR = vec4(final_color, tex_color.a * alpha);
}