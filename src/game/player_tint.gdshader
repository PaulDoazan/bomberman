shader_type spatial;
render_mode cull_disabled;

// The character's palette texture, with one key colour (its pink) swapped for the player's colour.
uniform sampler2D palette : source_color, filter_nearest;
uniform vec3 key_color : source_color = vec3(0.89, 0.098, 0.557);
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec3 c = texture(palette, UV).rgb;
	ALBEDO = distance(c, key_color) < 0.1 ? tint : c;
	ROUGHNESS = 0.8;
}
