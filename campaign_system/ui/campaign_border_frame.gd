# Campaign border frame overlay - decorative stone border around the viewport.
# Based on Catacombs of Gore UI pattern.
extends CanvasLayer

const BORDER_TEXTURE_PATH := "res://assets/ui/campaign_border_frame.png"

var border_rect: NinePatchRect = null


func _ready() -> void:
	# Set to highest layer so it draws on top of everything
	layer = 100
	_setup_border()


func _setup_border() -> void:
	# Create NinePatchRect for the border
	border_rect = NinePatchRect.new()
	border_rect.name = "BorderRect"

	# Load texture
	var tex: Texture2D = null
	if ResourceLoader.exists(BORDER_TEXTURE_PATH):
		tex = load(BORDER_TEXTURE_PATH)

	if not tex:
		# Try loading from absolute path
		var abs_path := ProjectSettings.globalize_path(BORDER_TEXTURE_PATH)
		if FileAccess.file_exists(abs_path):
			var image := Image.new()
			var err := image.load(abs_path)
			if err == OK:
				tex = ImageTexture.create_from_image(image)

	if not tex:
		push_warning("[CampaignBorderFrame] Could not load border texture: " + BORDER_TEXTURE_PATH)
		return

	border_rect.texture = tex

	# Set up NinePatch margins (adjust based on actual texture)
	# These values should match the border thickness in the texture
	var margin := 64  # Typical border margin
	border_rect.patch_margin_left = margin
	border_rect.patch_margin_right = margin
	border_rect.patch_margin_top = margin
	border_rect.patch_margin_bottom = margin

	# Fill the entire viewport
	border_rect.anchor_left = 0.0
	border_rect.anchor_top = 0.0
	border_rect.anchor_right = 1.0
	border_rect.anchor_bottom = 1.0
	border_rect.offset_left = 0
	border_rect.offset_top = 0
	border_rect.offset_right = 0
	border_rect.offset_bottom = 0

	# Don't block mouse input
	border_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(border_rect)


func set_border_visible(show: bool) -> void:
	if border_rect:
		border_rect.visible = show
