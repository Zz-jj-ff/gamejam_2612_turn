shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// =============================================================================
// VESPER // blade aura
// Additive electric-blue envelope around the plasma core. Fresnel rims make
// the silhouette flare, faking volumetric bloom without post-process access.
// =============================================================================

uniform vec4 color : source_color = vec4(0.16, 0.44, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.70, 0.88, 1.0, 1.0);
uniform float strength = 1.35;
uniform float flicker = 0.10;
uniform float edge_power : hint_range(0.5, 6.0) = 2.2;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, edge_power);
	float along = smoothstep(0.0, 0.05, UV.y) * (1.0 - 0.55 * smoothstep(0.88, 1.0, UV.y));
	float flutter = 0.90 + flicker * sin(TIME * 34.0 + UV.y * 21.0);
	vec3 c = mix(color.rgb, edge_color.rgb, rim * 0.45);
	ALBEDO = c * strength * (0.30 + 1.25 * rim) * along * flutter * 2.0;
	ALPHA = clamp((0.08 + 0.30 * rim) * along * flutter * strength, 0.0, 1.0);
}