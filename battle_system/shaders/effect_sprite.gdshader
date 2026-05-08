shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Atlas texture containing all animation frames
uniform sampler2D sprite_atlas : source_color, filter_nearest;

// Atlas grid dimensions
uniform int atlas_columns : hint_range(1, 32) = 8;
uniform int atlas_rows : hint_range(1, 16) = 8;

// Animation control
uniform float anim_fps : hint_range(1.0, 30.0) = 12.0;
uniform bool anim_loop = false;
uniform float start_time = 0.0;

// Whether effect is directional (uses all 8 rows) or non-directional (row 0 only)
uniform bool directional = true;
uniform int forced_direction : hint_range(0, 7) = 0;

// Tint and alpha
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;

// Magenta key color for transparency
uniform vec3 chroma_key : source_color = vec3(1.0, 0.0, 1.0);
uniform float chroma_threshold : hint_range(0.0, 1.0) = 0.15;

// Per-instance custom_data:
// custom_data.r = animation start time (in seconds, same scale as TIME)
// custom_data.g = direction index (0-7)
// custom_data.b = visibility (1.0 = visible, 0.0 = hidden)
// custom_data.a = reserved

varying flat float v_start_time;
varying flat float v_direction;
varying flat float v_visibility;


void vertex() {
	// Read per-instance data
	v_start_time = INSTANCE_CUSTOM.r;
	v_direction = INSTANCE_CUSTOM.g;
	v_visibility = INSTANCE_CUSTOM.b;

	// Y-axis billboard (stays upright, rotates to face camera)
	mat4 inv_view = INV_VIEW_MATRIX;
	vec3 camera_up = vec3(0.0, 1.0, 0.0);
	vec3 camera_forward = normalize(vec3(inv_view[2].x, inv_view[2].y, inv_view[2].z));
	vec3 camera_right = normalize(cross(camera_up, camera_forward));

	// Transform vertex position to face camera
	vec3 world_offset = camera_right * VERTEX.x + camera_up * VERTEX.y;

	// Get instance world position and apply offset
	vec4 world_pos = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	world_pos.xyz += world_offset;

	// Transform to clip space
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world_pos;
}


void fragment() {
	// Discard hidden instances
	if (v_visibility < 0.5) {
		discard;
	}

	// Calculate animation frame
	// Note: v_start_time is in seconds (Time.get_ticks_msec() / 1000.0)
	// TIME is also in seconds since game start, so elapsed calculation works
	float elapsed = TIME - v_start_time;
	if (elapsed < 0.0) {
		// Handle time wrap-around or initial frame
		elapsed = 0.0;
	}
	float frame_duration = 1.0 / anim_fps;
	int total_frames = atlas_columns;

	int current_frame;
	if (anim_loop) {
		current_frame = int(mod(elapsed / frame_duration, float(total_frames)));
	} else {
		current_frame = int(elapsed / frame_duration);
		if (current_frame >= total_frames) {
			// Animation finished - show last frame or discard
			current_frame = total_frames - 1;
		}
	}

	// Get direction row
	int direction;
	if (directional) {
		direction = int(v_direction);
	} else {
		direction = forced_direction;
	}

	// Calculate UV coordinates for this frame in the atlas
	float frame_width = 1.0 / float(atlas_columns);
	float frame_height = 1.0 / float(atlas_rows);

	float frame_x = float(current_frame) * frame_width;
	float frame_y = float(direction) * frame_height;

	vec2 atlas_uv = vec2(
		frame_x + UV.x * frame_width,
		frame_y + UV.y * frame_height
	);

	// Sample texture
	vec4 tex_color = texture(sprite_atlas, atlas_uv);

	// Transparency handling
	float chroma_dist = distance(tex_color.rgb, chroma_key);
	if (tex_color.a < 0.1 || chroma_dist < chroma_threshold) {
		discard;
	}

	// Apply tint and alpha
	ALBEDO = tex_color.rgb * tint_color.rgb;
	ALPHA = tex_color.a * tint_color.a * alpha_multiplier;
}
