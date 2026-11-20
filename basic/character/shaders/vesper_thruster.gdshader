shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// =============================================================================
// VESPER // thruster inner flame
// Additive blue plume for a cone/quad whose UV.y runs nozzle (0) -> tail (1)
// and UV.x wraps around the plume. White-hot at the nozzle, electric blue at
// the tail, with a two-frequency flicker.
// =============================================================================

uniform vec4 color : source_color = vec4(0.10, 0.34, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform float energy = 3.2;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float flicker_speed = 17.0;
uniform float length_power : hint_range(0.3, 4.0) = 1.7;
uniform float seed = 0.0;

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = 1.0 - UV.y; // 1 at the nozzle, 0 at the tail
	float plume = pow(max(across, 0.0), 1.35) * pow(max(along, 0.0), length_power);
	float core = pow(max(across, 0.0), 2.6) * pow(max(along, 0.0), 3.6);
	float fl = 0.72 + 0.28 * sin(TIME * flicker_speed + seed * 41.0)
			* sin(TIME * flicker_speed * 0.37 + seed * 13.0);
	vec3 c = mix(color.rgb, hot_color.rgb, clamp(core * 1.7, 0.0, 1.0));
	ALBEDO = c * energy * intensity * fl;
	ALPHA = clamp(plume * 1.35 * fl * intensity, 0.0, 1.0);
}