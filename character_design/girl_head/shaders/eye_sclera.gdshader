shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Synthetic sclera: pearl-white ceramic lens, not wet tissue.  The blink is a
// shader-defined lid so no extra geometry has to move.

uniform vec3 pearl_top : source_color = vec3(0.075, 0.100, 0.145);
uniform vec3 pearl_bottom : source_color = vec3(0.400, 0.435, 0.495);
uniform vec3 pearl_tint : source_color = vec3(0.720, 0.820, 0.920);
uniform vec3 lid_color : source_color = vec3(0.760, 0.775, 0.810);
uniform vec3 lid_shadow : source_color = vec3(0.330, 0.370, 0.440);
uniform vec3 catch_tint : source_color = vec3(0.850, 0.930, 1.000);
uniform float lid_pos = 0.030;
uniform float lid_curve = 0.0024;
uniform float eye_a = 0.0250;
uniform float iris_glow = 1.0;
uniform float metallic_value = 0.12;
uniform float roughness_value = 0.30;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

float lid_line(float x) {
	return lid_pos + lid_curve * (1.0 - clamp(abs(x) / eye_a, 0.0, 1.0));
}

void fragment() {
	float x = v_local.x;
	float y = v_local.y;
	float ly = lid_line(x);
	float covered = smoothstep(ly - 0.0005, ly + 0.0005, y);
	float lash_vis = 1.0 - smoothstep(0.017, 0.022, lid_pos);
	float lash = smoothstep(0.0013, 0.00015, abs(y - ly)) * lash_vis;
	float low_y = -0.0118 + 0.0008 * clamp(abs(x) / eye_a, 0.0, 1.0);
	float lower = 0.0;
	float low_lash = smoothstep(0.0006, 0.0001, abs(y - low_y)) * 0.32;
	float lash_band = smoothstep(ly - 0.0030, ly - 0.0014, y)
		* (1.0 - smoothstep(ly - 0.0002, ly + 0.0002, y));
	lash_band *= 1.0 - smoothstep(0.019, 0.024, lid_pos);
	float lash_soft = smoothstep(ly - 0.0040, ly - 0.0010, y) * (1.0 - lash_band);

	float v = clamp((y + 0.0125) / 0.025, 0.0, 1.0);
	vec3 base = mix(pearl_bottom, pearl_top, smoothstep(0.20, 0.92, v));
	base = mix(base, pearl_tint, 0.10);
	// blue bounce around the iris
	float iris_d = length(vec2(x * 0.82, y - 0.001));
	base = mix(base, pearl_tint, (1.0 - smoothstep(0.004, 0.014, iris_d)) * 0.20);
	// soft shadow under the upper lid (even when open)
	base *= 1.0 - 0.50 * smoothstep(-0.004, 0.0125, y);
	// lower tear line
	float wet = smoothstep(0.0011, 0.0, abs(y + 0.0112)) * (1.0 - covered);
	base = mix(base, catch_tint, wet * 0.22);

	vec3 lid = mix(lid_shadow, lid_color, smoothstep(ly - 0.012, ly - 0.001, y));
	vec3 lid_m = lid_color * 0.88;
	ALBEDO = mix(base, lid, covered);
	ALBEDO = mix(ALBEDO, lid_m, lower);
	METALLIC = mix(metallic_value, 0.42, max(covered, lower));
	ROUGHNESS = mix(roughness_value, 0.34, max(covered, lower));
	EMISSION = base * 0.012 * iris_glow + catch_tint * wet * 0.02
		+ lid_color * covered * 0.0;
	// eyelid lash line
	ALBEDO = mix(ALBEDO, vec3(0.012, 0.014, 0.020), max(max(lash, low_lash), lash_band));
	ALBEDO *= 1.0 - lash_soft * 0.35;
	ROUGHNESS = mix(ROUGHNESS, 0.30, max(max(lash, low_lash), lash_band));
}