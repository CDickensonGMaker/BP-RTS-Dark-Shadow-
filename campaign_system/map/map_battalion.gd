# Player battalion token on the campaign map.
# Handles selection, movement, and visual representation.
extends Node2D


signal selected(battalion: Node2D)
signal deselected()
signal move_completed(new_position: Vector2)

@export var battalion_data: Resource  # BattalionData

@onready var sprite: Sprite2D = $Sprite2D
@onready var selection_indicator: Node2D = $SelectionIndicator
@onready var banner_label: Label = $BannerLabel

# Movement
var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
var move_speed: float = 200.0

# Selection
var is_selected: bool = false
var is_hovered: bool = false

# Colors matching UI theme
const COLOR_SELECTED := Color(0.85, 0.7, 0.4, 1.0)
const COLOR_HOVER := Color(0.6, 0.5, 0.3, 0.8)


func _ready() -> void:
	# Set up collision for hover effects (selection handled by campaign_map.gd)
	var area := $ClickArea as Area2D
	if area:
		area.mouse_entered.connect(_on_mouse_entered)
		area.mouse_exited.connect(_on_mouse_exited)

	# Initialize visuals
	if selection_indicator:
		selection_indicator.visible = false

	if battalion_data:
		position = battalion_data.map_position
		_update_display()


func _process(delta: float) -> void:
	if is_moving:
		var direction := (target_position - position).normalized()
		var distance := position.distance_to(target_position)

		if distance < 5.0:
			position = target_position
			is_moving = false
			battalion_data.map_position = position
			move_completed.emit(position)
			CampaignSignals.battalion_moved.emit(self, position)
		else:
			position += direction * move_speed * delta


func _update_display() -> void:
	if banner_label and battalion_data:
		banner_label.text = battalion_data.battalion_name

	# Update sprite color if no texture
	if sprite and battalion_data:
		sprite.modulate = battalion_data.battalion_color


func select() -> void:
	is_selected = true
	if selection_indicator:
		selection_indicator.visible = true
		selection_indicator.modulate = COLOR_SELECTED
	selected.emit(self)
	CampaignSignals.battalion_selected.emit(self)


func deselect() -> void:
	is_selected = false
	if selection_indicator:
		selection_indicator.visible = false
	deselected.emit()
	CampaignSignals.battalion_deselected.emit()


func move_to(target: Vector2) -> void:
	var distance := position.distance_to(target)

	# Check movement points
	if battalion_data and not battalion_data.can_move(distance * 0.1):
		# Not enough movement points
		return

	target_position = target
	is_moving = true

	# Deduct movement points (scaled by distance)
	if battalion_data:
		battalion_data.spend_movement(distance * 0.1)
		CampaignSignals.movement_points_changed.emit(self, battalion_data.movement_points)

	CampaignSignals.battalion_move_requested.emit(self, target)


func _on_mouse_entered() -> void:
	is_hovered = true
	if not is_selected and selection_indicator:
		selection_indicator.visible = true
		selection_indicator.modulate = COLOR_HOVER


func _on_mouse_exited() -> void:
	is_hovered = false
	if not is_selected and selection_indicator:
		selection_indicator.visible = false


func get_regiment_count() -> int:
	if battalion_data:
		return battalion_data.regiments.size()
	return 0


func get_soldier_count() -> int:
	if battalion_data:
		return battalion_data.get_total_soldiers()
	return 0
