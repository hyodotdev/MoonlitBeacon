shader_type canvas_item;

// The colour grade over the world: what turns a flat teal night into a lit one.
//
// A pixel sprite on a flat dark floor reads as a small game. The same sprites under
// a real grade (deeper shadows with a cool cast, warm light kept warm, colour that
// has weight, and a far edge that sinks into the dark) read as a place. Nothing
// here changes what is where; it only changes how the frame is coloured.
//
// It sits first on the arena's UI layer, so it grades the world and nothing else:
// the HUD, the panels and the vignette are drawn after it and stay exactly as
// authored. It reads the screen once and does a handful of multiplies, so it costs
// one framebuffer copy and no extra passes.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

uniform float saturation : hint_range(0.5, 1.8) = 1.22;
uniform float contrast : hint_range(0.8, 1.6) = 1.14;
// The luminance the contrast pivots on. Low, because the whole scene is a night.
uniform float pivot : hint_range(0.1, 0.6) = 0.3;
// Cool cast in the darks, warm cast in the lights.
uniform vec3 shadow_tone : source_color = vec3(0.10, 0.17, 0.5);
uniform float shadow_amount : hint_range(0.0, 0.4) = 0.13;
uniform vec3 light_tone : source_color = vec3(1.0, 0.8, 0.52);
uniform float light_amount : hint_range(0.0, 0.4) = 0.09;
// Depth: the far (upper) part of the frame fades toward this colour.
uniform vec3 haze_tone : source_color = vec3(0.09, 0.15, 0.38);
uniform float haze_amount : hint_range(0.0, 0.6) = 0.26;
uniform float haze_falloff : hint_range(0.5, 4.0) = 1.7;

void fragment() {
	vec3 color = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));

	color = mix(vec3(luma), color, saturation);
	color = (color - pivot) * contrast + pivot;
	color += shadow_tone * shadow_amount * (1.0 - smoothstep(0.0, 0.34, luma));
	color += light_tone * light_amount * smoothstep(0.26, 0.85, luma);

	float far = pow(1.0 - SCREEN_UV.y, haze_falloff);
	color = mix(color, haze_tone, haze_amount * far);

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
