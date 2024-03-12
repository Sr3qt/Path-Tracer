shader_type spatial;

render_mode unshaded, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform sampler2D image_buffer : filter_nearest;
uniform sampler2D preview_image_buffer : filter_nearest, source_color;

uniform float width = 64.;
uniform float height = 36.;

uniform float scale = 16.;

struct temp {
	float h;
};

float hallo(temp hal[10]) {
	return 0.;
}

void vertex() {
	POSITION = vec4(VERTEX, 1);
	
	bool a = false;
	
}



void fragment() {
//	vec4 original = texture(SCREEN_TEXTURE, SCREEN_UV);
//	ALBEDO = original.rgb;

//	mat3 ma = mat3([[0,0,0], [0,0,0], [0,0,0]]);

	vec2 new_pos; 
	vec2 pos = SCREEN_UV;
	new_pos = pos;
	vec4 color = texture(image_buffer, new_pos);
	vec4 c = texture(image_buffer, vec2(0.1,0));
	vec4 new_color = texture(preview_image_buffer, new_pos);
	
	temp ha[10];
	float haa[4] = float[](1., 0.0, 0.3, 0.3);
	hallo(ha);

	// COnvertion from srgb to rgb
//	ALBEDO = pow(color.rgb, vec3(2.2, 2.2, 2.2));	
	float gamma = 1.35;
	float gamma1 = 2.2;
	
	// If showing default texture, swap with image preview
	if (color.r == 1. && color.g == 0.0 && color.b == 1.) {
		color.rgb = pow(new_color.rgb, vec3(gamma, gamma, gamma));
	} else {
		color.rgb = pow(color.rgb, vec3(gamma1, gamma1, gamma1));
	} 
	ALBEDO = color.rgb;
}