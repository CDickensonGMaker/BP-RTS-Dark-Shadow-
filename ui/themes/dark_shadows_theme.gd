# Dark Shadows UI Theme Generator
# Creates a grim medieval fantasy theme with stone/iron aesthetic
class_name DarkShadowsTheme
extends RefCounted


## Color palette - grim dark fantasy
const COLOR_BG_DARK := Color(0.08, 0.07, 0.06, 0.95)
const COLOR_BG_MEDIUM := Color(0.12, 0.11, 0.10, 0.9)
const COLOR_BG_LIGHT := Color(0.18, 0.16, 0.14, 0.85)
const COLOR_BORDER := Color(0.25, 0.22, 0.18, 1.0)
const COLOR_BORDER_HIGHLIGHT := Color(0.45, 0.38, 0.28, 1.0)
const COLOR_TEXT := Color(0.85, 0.80, 0.70, 1.0)
const COLOR_TEXT_DIM := Color(0.55, 0.50, 0.45, 1.0)
const COLOR_TEXT_HIGHLIGHT := Color(1.0, 0.95, 0.80, 1.0)
const COLOR_ACCENT := Color(0.7, 0.55, 0.35, 1.0)  # Bronze/gold
const COLOR_ACCENT_DARK := Color(0.5, 0.38, 0.22, 1.0)
const COLOR_BLOOD := Color(0.6, 0.15, 0.12, 1.0)
const COLOR_HOVER := Color(0.22, 0.20, 0.17, 0.95)
const COLOR_PRESSED := Color(0.15, 0.13, 0.11, 1.0)
const COLOR_DISABLED := Color(0.3, 0.28, 0.25, 0.6)


static func create_theme() -> Theme:
	var theme := Theme.new()

	# Button styles
	_setup_button_styles(theme)

	# Panel styles
	_setup_panel_styles(theme)

	# Label styles
	_setup_label_styles(theme)

	# LineEdit styles
	_setup_lineedit_styles(theme)

	# ItemList styles
	_setup_itemlist_styles(theme)

	# OptionButton styles
	_setup_optionbutton_styles(theme)

	# Slider styles
	_setup_slider_styles(theme)

	# ScrollContainer styles
	_setup_scroll_styles(theme)

	# TabContainer styles
	_setup_tab_styles(theme)

	return theme


static func _setup_button_styles(theme: Theme) -> void:
	# Normal button
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_MEDIUM
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	# Hover
	var hover := normal.duplicate()
	hover.bg_color = COLOR_HOVER
	hover.border_color = COLOR_BORDER_HIGHLIGHT

	# Pressed
	var pressed := normal.duplicate()
	pressed.bg_color = COLOR_PRESSED
	pressed.border_color = COLOR_ACCENT

	# Disabled
	var disabled := normal.duplicate()
	disabled.bg_color = COLOR_BG_DARK
	disabled.border_color = COLOR_DISABLED

	# Focus
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = COLOR_ACCENT
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(2)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)

	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_TEXT_HIGHLIGHT)
	theme.set_color("font_pressed_color", "Button", COLOR_ACCENT)
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_DIM)

	theme.set_font_size("font_size", "Button", 16)


static func _setup_panel_styles(theme: Theme) -> void:
	# Panel
	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_BG_DARK
	panel.border_color = COLOR_BORDER
	panel.set_border_width_all(3)
	panel.set_corner_radius_all(4)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12

	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	# Popup panel
	var popup := panel.duplicate()
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 8
	theme.set_stylebox("panel", "PopupPanel", popup)


static func _setup_label_styles(theme: Theme) -> void:
	theme.set_color("font_color", "Label", COLOR_TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_font_size("font_size", "Label", 14)


static func _setup_lineedit_styles(theme: Theme) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_DARK
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	var focus := normal.duplicate()
	focus.border_color = COLOR_ACCENT

	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_color("font_color", "LineEdit", COLOR_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", COLOR_TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", COLOR_ACCENT)
	theme.set_color("selection_color", "LineEdit", COLOR_ACCENT_DARK)


static func _setup_itemlist_styles(theme: Theme) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_BG_DARK
	panel.border_color = COLOR_BORDER
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(2)

	var selected := StyleBoxFlat.new()
	selected.bg_color = COLOR_ACCENT_DARK
	selected.set_corner_radius_all(2)

	theme.set_stylebox("panel", "ItemList", panel)
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_color("font_color", "ItemList", COLOR_TEXT)
	theme.set_color("font_selected_color", "ItemList", COLOR_TEXT_HIGHLIGHT)


static func _setup_optionbutton_styles(theme: Theme) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_MEDIUM
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 12
	normal.content_margin_right = 24
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	var hover := normal.duplicate()
	hover.border_color = COLOR_BORDER_HIGHLIGHT

	theme.set_stylebox("normal", "OptionButton", normal)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", normal)
	theme.set_color("font_color", "OptionButton", COLOR_TEXT)


static func _setup_slider_styles(theme: Theme) -> void:
	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = COLOR_BG_DARK
	slider_style.border_color = COLOR_BORDER
	slider_style.set_border_width_all(1)
	slider_style.set_corner_radius_all(2)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = COLOR_ACCENT
	grabber.set_corner_radius_all(4)

	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = COLOR_ACCENT_DARK
	grabber_area.set_corner_radius_all(2)

	theme.set_stylebox("slider", "HSlider", slider_style)
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_area)


static func _setup_scroll_styles(theme: Theme) -> void:
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = COLOR_BG_DARK
	scroll_bg.set_corner_radius_all(2)

	var scroll_grabber := StyleBoxFlat.new()
	scroll_grabber.bg_color = COLOR_BORDER
	scroll_grabber.set_corner_radius_all(2)

	var scroll_grabber_hover := scroll_grabber.duplicate()
	scroll_grabber_hover.bg_color = COLOR_BORDER_HIGHLIGHT

	theme.set_stylebox("scroll", "VScrollBar", scroll_bg)
	theme.set_stylebox("grabber", "VScrollBar", scroll_grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", scroll_grabber_hover)
	theme.set_stylebox("grabber_pressed", "VScrollBar", scroll_grabber_hover)

	theme.set_stylebox("scroll", "HScrollBar", scroll_bg)
	theme.set_stylebox("grabber", "HScrollBar", scroll_grabber)
	theme.set_stylebox("grabber_highlight", "HScrollBar", scroll_grabber_hover)


static func _setup_tab_styles(theme: Theme) -> void:
	var tab_selected := StyleBoxFlat.new()
	tab_selected.bg_color = COLOR_BG_MEDIUM
	tab_selected.border_color = COLOR_BORDER_HIGHLIGHT
	tab_selected.set_border_width_all(2)
	tab_selected.border_width_bottom = 0
	tab_selected.set_corner_radius_all(4)
	tab_selected.corner_radius_bottom_left = 0
	tab_selected.corner_radius_bottom_right = 0

	var tab_unselected := tab_selected.duplicate()
	tab_unselected.bg_color = COLOR_BG_DARK
	tab_unselected.border_color = COLOR_BORDER

	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_BG_MEDIUM
	panel.border_color = COLOR_BORDER_HIGHLIGHT
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(4)
	panel.corner_radius_top_left = 0

	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_selected)
	theme.set_stylebox("panel", "TabContainer", panel)
	theme.set_color("font_selected_color", "TabContainer", COLOR_TEXT_HIGHLIGHT)
	theme.set_color("font_unselected_color", "TabContainer", COLOR_TEXT_DIM)


## Create a decorated panel with corner ornaments
static func create_ornate_panel() -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = COLOR_BG_DARK
	panel.border_color = COLOR_ACCENT_DARK
	panel.set_border_width_all(4)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	return panel


## Create title label style
static func create_title_style() -> Dictionary:
	return {
		"font_size": 32,
		"font_color": COLOR_ACCENT,
		"shadow_color": Color(0, 0, 0, 0.7),
		"shadow_offset": Vector2(2, 2)
	}


## Create subtitle label style
static func create_subtitle_style() -> Dictionary:
	return {
		"font_size": 18,
		"font_color": COLOR_TEXT_DIM,
		"shadow_color": Color(0, 0, 0, 0.5),
		"shadow_offset": Vector2(1, 1)
	}
