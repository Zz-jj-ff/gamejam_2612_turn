shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

// Portrait cyclorama: deep blue-black sweep with a soft halo behind the head.

uniform vec3 top_color : source_color = vec3(0.015, 0.018, 0.028);
uniform vec3 bottom_color : source_color = vec3(0.004, 0.005, 0.008);
uniform vec3 halo_color : source_color = vec3(0.080, 0.180, 0.280);
uniform vec3 rim_color : source_color = vec3(0.320, 0.130, 0.400);
uniform float halo_strength = 0.55;
uniform float rim_strength = 0.30;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(v_dir);
	vec3 col = mix(bottom_color, top_color, smoothstep(-0.55, 0.85, d.y));
	float halo = exp(-pow(d.x * 2.1, 2.0) * 2.2)
		* exp(-pow((d.y + 0.02) * 2.6, 2.0) * 1.8)
		* (1.0 - smoothstep(0.15, 0.95, abs(d.z)));
	col += halo_color * halo * halo_strength;
	float halo2 = exp(-pow(d.x * 2.6, 2.0) * 8.0)
		* exp(-pow((d.y + 0.10) * 3.4, 2.0) * 3.0);
	col += vec3(0.30, 0.42, 0.58) * halo2 * 0.20;
	// faint violet rim low left
	col += rim_color * exp(-pow((d.x + 0.55) * 1.9, 2.0) * 3.0)
		* exp(-pow((d.y + 0.35) * 2.2, 2.0) * 2.0) * rim_strength;
	ALBEDO = col;
}