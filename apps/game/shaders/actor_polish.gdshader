shader_type canvas_item;

// Lights a character the way the world is lit: moonlight from the upper left.
//
// The heroes and spirits are flat sheets. Three things make them read as small
// standing figures instead of stickers:
//
//   * a moonlit rim on the edges that face the light, inside the silhouette;
//   * an outline in the transparent pixel beside the art, coloured from the art it
//     surrounds (a purple hood gets a deep purple line, not a black one), dark on
//     the side away from the light and pale on the side toward it;
//   * bright, saturated pixels (a lantern, eyes, a flame, a moon badge) are lifted
//     past the night tint, so the things that should glow do.
//
// All of it comes from the sprite's own colour and alpha, so no sheet had to be
// redrawn and a new character gets the look for free. The neighbour taps stay
// inside the frame's transparent margin (every sheet keeps at least one clear
// pixel around its art), so a frame never picks up its neighbour's edge.
//
// The outline is darkened by the *night tint* but ignores a hit flash on purpose. A
// flash brightens the body; a bright outline around a bright body would erase the
// very silhouette the flash is meant to punch out. Its alpha does follow the
// modulate, so a spirit that perishes fades out whole.

uniform vec4 outline_base : source_color = vec4(0.03, 0.03, 0.12, 1.0);
uniform float outline_body : hint_range(0.0, 1.0) = 0.55;
uniform float outline_depth : hint_range(0.0, 1.0) = 0.5;
uniform float outline_alpha : hint_range(0.0, 1.0) = 0.94;
uniform float outline_lit_alpha : hint_range(0.0, 1.0) = 0.5;
uniform vec4 rim_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.36;
uniform float glow : hint_range(0.0, 1.0) = 0.5;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 own = texture(TEXTURE, UV);
	vec4 up = texture(TEXTURE, UV + vec2(0.0, -px.y));
	vec4 down = texture(TEXTURE, UV + vec2(0.0, px.y));
	vec4 left = texture(TEXTURE, UV + vec2(-px.x, 0.0));
	vec4 right = texture(TEXTURE, UV + vec2(px.x, 0.0));

	if (own.a < 0.5) {
		// Beside the art. The light comes from the upper left, so a pixel whose
		// art lies to its right or below faces the light.
		float toward = max(right.a, down.a);
		float away = max(left.a, up.a);
		float touching = step(0.5, max(toward, away));

		// The colour of the art this pixel touches, deepened toward the night.
		float weight = max(up.a + down.a + left.a + right.a, 0.001);
		vec3 art = (up.rgb * up.a + down.rgb * down.a + left.rgb * left.a + right.rgb * right.a) / weight;
		vec3 night = clamp(tint.rgb, 0.0, 0.6);
		vec3 deep = mix(outline_base.rgb, art * night, outline_body) * outline_depth * 2.0;

		if (toward > 0.5 && away < 0.5) {
			// Facing the moon: a pale edge, not a dark one.
			COLOR = vec4(mix(art, rim_color.rgb, 0.55), outline_lit_alpha * touching * tint.a);
		} else {
			COLOR = vec4(deep, outline_alpha * touching * tint.a);
		}
	} else {
		float up_left = texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
		float facing_light = 1.0 - step(0.5, max(max(up.a, left.a), up_left));
		vec3 body = own.rgb * tint.rgb;

		// Lantern, eyes, flame: bright and saturated. Added on top of the tint, so
		// they stay lit when the rest of the figure is in the dark.
		float peak = max(own.r, max(own.g, own.b));
		float span = peak - min(own.r, min(own.g, own.b));
		float lit = smoothstep(0.7, 0.95, peak) * smoothstep(0.32, 0.7, span / max(peak, 0.001));
		body += own.rgb * lit * glow;

		COLOR = vec4(mix(body, rim_color.rgb, rim_strength * facing_light), own.a * tint.a);
	}
}
