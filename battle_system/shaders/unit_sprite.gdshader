shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Atlas texture containing all animation frames
uniform sampler2D sprite_atlas : source_color, filter_nearest;

// Atlas grid dimensions
uniform int atlas_columns : hint_range(1, 32) = 13;
uniform int atlas_rows : hint_range(1, 16) = 8;

// Animation control
uniform int current_anim_start : hint_range(0, 32) = 0;
uniform int current_anim_frames : hint_range(1, 16) = 4;
uniform float anim_speed : hint_range(0.0, 20.0) = 8.0;

// Death animation (corpses on ground)
uniform int death_anim_start : hint_range(0, 32) = 11;
uniform int death_anim_frames : hint_range(1, 8) = 2;

// Magenta key color for transparency (RGB 255, 0, 255)
uniform vec3 chroma_key : source_color = vec3(1.0, 0.0, 1.0);
uniform float chroma_threshold : hint_range(0.0, 1.0) = 0.15;

// Debug: set to true to show solid red quads
uniform bool debug_mode = false;

// Per-instance custom_data layout:
// custom_data.r = animation time offset (0-1 for stagger)
// custom_data.g = direction index (0-7 for 8 directions)
// custom_data.b = visibility (1.0 = visible, 0.0 = hidden)
// custom_data.a = dead flag (0.0 = alive, 1.0 = dead corpse)

varying flat float v_direction;
varying flat float v_time_offset;
varying flat float v_visibility;
varying flat float v_is_dead;


void vertex() {
	// Read per-instance data from INSTANCE_CUSTOM
	v_time_offset = INSTANCE_CUSTOM.r;
	v_direction = INSTANCE_CUSTOM.g;
	v_visibility = INSTANCE_CUSTOM.b;
	v_is_dead = INSTANCE_CUSTOM.a;

	// Full billboard - always face camera completely
	// Extract camera vectors from view matrix
	mat4 inv_view = INV_VIEW_MATRIX;
	vec3 camera_right = normalize(vec3(inv_view[0].x, inv_view[0].y, inv_view[0].z));
	vec3 camera_up = normalize(vec3(inv_view[1].x, inv_view[1].y, inv_view[1].z));

	// Dead soldiers (corpses) lie flat on ground - rotate sprite to be horizontal
	bool is_corpse = v_is_dead > 0.5;
	if (is_corpse) {
		// For corpses: use world forward (camera-facing horizontal) instead of up
		vec3 camera_forward = normalize(vec3(inv_view[2].x, 0.0, inv_view[2].z));
		camera_right = normalize(cross(vec3(0.0, 1.0, 0.0), camera_forward));
		// Corpse lies flat - use forward as "up" direction, scaled down
		camera_up = camera_forward * 0.5;  // Corpse sprite is flatter
	} else {
		// Living soldiers: Y-axis billboard (stay upright)
		camera_up = vec3(0.0, 1.0, 0.0);
		vec3 camera_forward = normalize(vec3(inv_view[2].x, inv_view[2].y, inv_view[2].z));
		camera_right = normalize(cross(camera_up, camera_forward));
	}

	// Transform vertex position to face camera
	vec3 world_offset = camera_right * VERTEX.x + camera_up * VERTEX.y;

	// Get instance world position and apply offset
	vec4 world_pos = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	world_pos.xyz += world_offset;

	// Transform to clip space
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world_pos;
}


void fragment() {
	// Discard dead soldiers
	if (v_visibility < 0.5) {
		discard;
	}

	// Debug mode: show solid red quads to verify rendering
	if (debug_mode) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
		ALPHA = 1.0;
	} else {
		int current_frame;
		bool is_dead_soldier = v_is_dead > 0.5;

		// Dead soldiers show last frame of death animation (frozen corpse)
		// Direction: dead soldiers always use direction 0 (south) for consistent corpse rendering
		int direction;
		if (is_dead_soldier) {
			current_frame = death_anim_start + death_anim_frames - 1;  // Last death frame
			direction = 0;  // Force south-facing for corpses
		} else {
			// Calculate current animation frame for alive soldiers
			float anim_time = TIME * anim_speed + v_time_offset * float(current_anim_frames);
			int frame_in_anim = int(mod(anim_time, float(current_anim_frames)));
			current_frame = current_anim_start + frame_in_anim;
			direction = int(v_direction);
		}

		// Calculate UV coordinates for this frame in the atlas
		float frame_width = 1.0 / float(atlas_columns);
		float frame_height = 1.0 / float(atlas_rows);

		// Use UV directly
		vec2 local_uv = UV;

		// Calculate base position for this frame
		float frame_x = float(current_frame) * frame_width;
		float frame_y = float(direction) * frame_height;

		// Map the quad's UV to the frame's region in the atlas
		vec2 atlas_uv = vec2(
			frame_x + local_uv.x * frame_width,
			frame_y + local_uv.y * frame_height
		);

		// Sample texture
		vec4 tex_color = texture(sprite_atlas, atlas_uv);

		// Use alpha channel for transparency (PNG sprites)
		// Also support chroma key for legacy magenta backgrounds
		float chroma_dist = distance(tex_color.rgb, chroma_key);
		if (tex_color.a < 0.1 || chroma_dist < chroma_threshold) {
			discard;
		}

		// Show actual sprite color
		// Dead soldiers (corpses) get darker tint to show they're dead
		if (is_dead_soldier) {
			ALBEDO = tex_color.rgb * 0.6;  // Darken corpses
		} else {
			ALBEDO = tex_color.rgb;
		}
		ALPHA = 1.0;  // Force opaque for visible pixels
	}
}
