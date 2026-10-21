shader_type canvas_item;
// 将作者的黑白 SCRT 图作为遮罩显示，不更改原始素材。
uniform vec4 logo_color : source_color = vec4(0.6, 1.0, 0.6, 1.0);
// 透明度：0 为不透明，1 为完全透明；指数控制沿图片纵向的渐变曲线。
uniform float top_transparency : hint_range(0.0, 1.0) = 0.0;
uniform float bottom_transparency : hint_range(0.0, 1.0) = 1.0;
uniform float gradient_power : hint_range(0.05, 10.0, 0.05) = 1.0;
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float ink = 1.0 - dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float gradient = pow(clamp(UV.y, 0.0, 1.0), max(gradient_power, 0.05));
	float opacity = 1.0 - mix(top_transparency, bottom_transparency, gradient);
	COLOR = vec4(logo_color.rgb, logo_color.a * source.a * ink * opacity);
}
