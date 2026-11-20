shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Silver hair.  Default PBR does the broad lighting; the polished-silver
// character comes from a controlled anisotropic band evaluated against a
// synthetic key in view space.  This keeps the highlight readable no matter
// how many real lights are in the studio (the previous version summed a broad
// highlight per light and went white).
//
// UV2.x = per-lock random, COLOR.rgb = per-lock tint, TANGENT = strand.

uniform vec3 root_color : source_color = vec3(0.055, 0.060, 0.075);
uniform vec3 tip_color : source_color = vec3(0.140, 0.152, 0.178);
uniform vec3 sheen_color : source_color = vec3(1.000, 0.985, 0.940);
uniform vec3 sheen_color2 : source_color = vec3(0.560, 0.700, 1.000);
uniform vec3 rim_color : source_color = vec3(0.620, 0.740, 1.000);
uniform float band_power = 200.0;
uniform float band_strength = 0.22;
uniform float band2_strength = 0.12;
uniform float rim_strength = 0.04;
uniform float root_dark = 0.72;
uniform float sway_amp = 0.0045;
uniform float sway_phase = 0.0;
uniform float hue_var = 0.10;
uniform float metallic_value = 0.0;
uniform float roughness_value = 0.55;

varying vec3 v_tan;
varying float v_along;
varying float v_rand;

void vertex() {
	v_tan = normalize((MODELVIEW_MATRIX * vec4(TANGENT.xyz, 0.0)).xyz);
	v_along = clamp(UV.y, 0.0, 1.0);
	v_rand = UV2.x;
	float w = pow(v_along, 2.1);
	float ph = sway_phase + v_rand * 6.28318;
	vec3 off = vec3(sin(ph) * 0.62 + sin(ph * 2.17) * 0.38,
		0.0, cos(ph * 0.83) * 0.34);
	VERTEX += off * sway_amp * w;
}

void fragment() {
	vec3 N = normalize(NORMAL);
	vec3 V = VIEW;
	vec3 T = normalize(v_tan);
	vec3 tint = COLOR.rgb;
	float root_mix = smoothstep(0.02, 0.62, v_along);
	vec3 base = mix(root_color, tip_color, root_mix);
	base *= tint * (1.0 + (v_rand - 0.5) * hue_var);

	// synthetic studio key: upper-front-left in view space
	vec3 L = normalize(vec3(-0.42, 0.62, 0.66));
	vec3 H = normalize(L + V);
	vec3 T1 = normalize(T + N * 0.14);
	vec3 T2 = normalize(T - N * 0.26);
	float d1 = dot(T1, H);
	float d2 = dot(T2, H);
	float b1 = pow(sqrt(max(0.0, 1.0 - d1 * d1)), band_power);
	float b2 = pow(sqrt(max(0.0, 1.0 - d2 * d2)), band_power * 0.52);
	// second cool fill from the right rim, so the mass has two silver bands
	vec3 L2 = normalize(vec3(0.72, 0.20, 0.60));
	vec3 H2 = normalize(L2 + V);
	float d3 = dot(T, H2);
	float b3 = pow(sqrt(max(0.0, 1.0 - d3 * d3)), band_power * 0.7);
	float fres = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.2);

	// fine strand grooves inside each lock + darker edges give the flat
	// lock a bundle-of-hairs read instead of a plastic shard
	float groove = 0.5 + 0.5 * sin(UV.x * 54.0 + v_rand * 17.0 + v_along * 9.0);
	float edge = smoothstep(0.0, 0.14, UV.x) * smoothstep(1.0, 0.86, UV.x);
	base *= mix(0.58, 1.0, edge) * (0.90 + 0.14 * groove);
	ALBEDO = base;
	METALLIC = metallic_value;
	ROUGHNESS = mix(roughness_value + 0.06, roughness_value, root_mix);
	SPECULAR_AMOUNT = 0.02;
	EMISSION = sheen_color * (b1 * band_strength + b2 * band2_strength)
		+ sheen_color2 * b3 * 0.10
		+ rim_color * fres * rim_strength;
}