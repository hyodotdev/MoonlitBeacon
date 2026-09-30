shader_type canvas_item;

// Lights the upright pieces on the floor (trees, rocks, tents, structures) the
// way the actors are lit: moonlight from the upper left.
//
//   * a pale rim on edges that face the moon, from the piece's own alpha;
//   * the crown a little brighter and the foot a little darker, so a tree reads
//     as a volume standing on the ground and not a flat cut-out;
//   * an optional slow sway of the crown, for the trees only.
//
// Every piece shares ONE material per sheet. A material per tile height would be
// tidier to write and would break the room's draw batches on every y-sorted
// neighbour, which on a phone is most of the frame. Instead the shader reads each
// sprite's own height off its quad: a non-centred sprite's top vertices sit at
// y = 0 and its bottom vertices below it, so a varying that is 0 at the top and 1
// at the bottom interpolates to "how far down the piece" at every fragment,
// whatever its size.

uniform vec4 rim_color : source_color = vec4(0.6, 0.76, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
// How much brighter the crown is and how much darker the foot is.
uniform float crown_lift : hint_range(0.0, 0.5) = 0.14;
uniform float foot_shade : hint_range(0.0, 0.6) = 0.2;
// Sway, in pixels at the tip of the crown. Zero on sheets that hold no trees.
uniform float sway : hint_range(0.0, 3.0) = 0.0;
uniform float sway_speed : hint_range(0.0, 4.0) = 0.9;
// Sprites whose region starts above this row of the sheet are trees. The nature
// sheet keeps every tree above row 128 and every rock, log and stump below it.
uniform float tree_rows_above = 128.0;

varying vec4 tint;
// 0 at the crown, 1 at the foot.
varying float down;

void vertex() {
	tint = COLOR;
	down = step(0.5, VERTEX.y);

	// Region top, in sheet pixels. A quad maps one texel to one pixel, so this is
	// the sprite's UV minus how far down the quad this vertex already is.
	float top_row = UV.y / TEXTURE_PIXEL_SIZE.y - VERTEX.y;
	float is_tree = step(top_row, tree_rows_above - 0.5);
	float crown = 1.0 - down;
	float lag = MODEL_MATRIX[3].x * 0.043 + MODEL_MATRIX[3].y * 0.021;
	VERTEX.x += sin(TIME * sway_speed + lag) * sway * crown * is_tree;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 own = texture(TEXTURE, UV);
	float up = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
	float left = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
	float up_left = texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
	float facing = own.a * (1.0 - step(0.5, max(max(up, left), up_left)));

	float shade = 1.0 + crown_lift * (1.0 - smoothstep(0.0, 0.55, down))
			- foot_shade * smoothstep(0.62, 1.0, down);

	vec3 body = own.rgb * tint.rgb * shade;
	vec3 rim = rim_color.rgb * mix(vec3(1.0), tint.rgb, 0.4);
	COLOR = vec4(mix(body, rim, rim_strength * facing), own.a * tint.a);
}
