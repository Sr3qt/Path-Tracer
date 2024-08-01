shader_type spatial;

render_mode unshaded, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform sampler2D image_buffer : filter_nearest, source_color;
uniform sampler2D preview_image_buffer : filter_nearest, source_color;

uniform bool is_rendering = false;


void vertex() {
	if (is_rendering) {
		POSITION = vec4(VERTEX.xy, 1, 1);
	}
}


void fragment() {
	vec4 color = texture(image_buffer, SCREEN_UV);
	vec4 new_color = texture(preview_image_buffer, SCREEN_UV);

	// COnvertion from srgb to rgb
	float gamma = 1.35;
	float gamma1 = 2.2;

	// If showing default texture, swap with image preview
	if (is_rendering) {
		color.rgb = pow(color.rgb, vec3(gamma1, gamma1, gamma1));
	} else {
		color.rgb = pow(new_color.rgb, vec3(gamma, gamma, gamma));
	}

	ALBEDO = color.rgb;
}