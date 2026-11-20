shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Dark optical body around the iris: smoked sapphire glass with concentric
// machined grooves and a cold fresnel rim.  This replaces the human sclera
// so the eye reads as an instrument, not a doll eye.

uniform vec3 body_color : source_color = vec3(0.030, 0.045, 0.062);
uniform vec3 rim_color : source_color = vec3(0.180, 0.420, 0.620);
uniform float rim_strength = 0.55;
uniform float groove_strength = 0.30;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 p = v_uv;
	float r = length(p);
	vec3 N = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(N, VIEW), 0.0, 1.0), 3.0);
	float groove = 0.5 + 0.5 * sin(r * 56.0);
	vec3 base = body_color * (0.82 + groove_strength * groove);
	ALBEDO = base;
	METALLIC = 0.62;
	ROUGHNESS = mix(0.10, 0.26, groove);
	EMISSION = rim_color * fres * rim_strength * 0.22
		+ rim_color * smoothstep(0.65, 1.0, r) * 0.05;
}