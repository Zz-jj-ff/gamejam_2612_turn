shader_type sky;

// Studio HDRI used only for reflections / ambient: a dark cyclorama with a warm
// key softbox, a cool fill strip and two neon kickers.  Keeps the silver hair
// and the titanium face alive without importing an environment map.

uniform vec3 top_color : source_color = vec3(0.020, 0.024, 0.038);
uniform vec3 horizon_color : source_color = vec3(0.055, 0.060, 0.082);
uniform vec3 ground_color : source_color = vec3(0.010, 0.010, 0.014);
uniform vec3 key_color : source_color = vec3(1.000, 0.940, 0.880);
uniform vec3 cool_color : source_color = vec3(0.520, 0.720, 1.000);
uniform vec3 warm_color : source_color = vec3(1.000, 0.340, 0.140);
uniform vec3 violet_color : source_color = vec3(0.560, 0.320, 1.000);

float lobe(vec3 d, vec3 dir, float tight) {
	float c = max(dot(d, normalize(dir)), 0.0);
	return pow(c, tight);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = mix(horizon_color, top_color, smoothstep(0.02, 0.85, d.y));
	col = mix(col, ground_color, smoothstep(0.05, -0.35, d.y));
	// broad key softbox up / front-left
	col += key_color * lobe(d, vec3(-0.55, 0.62, 0.56), 26.0) * 1.55;
	col += key_color * lobe(d, vec3(-0.55, 0.62, 0.56), 6.0) * 0.18;
	// cool fill strip front-right
	col += cool_color * lobe(d, vec3(0.72, 0.22, 0.62), 34.0) * 0.55;
	// rim kickers behind
	col += warm_color * lobe(d, vec3(0.62, 0.42, -0.66), 40.0) * 1.35;
	col += violet_color * lobe(d, vec3(-0.72, 0.38, -0.58), 34.0) * 1.05;
	// a faint top strip so hair crests catch a clean line
	col += vec3(0.42, 0.50, 0.68) * lobe(d, vec3(0.0, 1.0, 0.10), 12.0) * 0.55;
	COLOR = col;
}