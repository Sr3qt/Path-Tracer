@tool
class_name PTButton
extends Button

"""The very advanced and high tech custom !button! (tm pending)"""

const BUTTON_MINIMUM_WIDTH = 340

var disabled_mask : ColorRect

var size_margin := Vector2(4, 5)


func _ready():
	# Create disabled mask
	disabled_mask = ColorRect.new()

	disabled_mask.color = PTButtonController.DISABLED_COLOR
	disabled_mask.size = size + size_margin
	disabled_mask.position = Vector2(-2, -2)

	add_child(disabled_mask)
	disabled_mask.visible = disabled
	disabled_mask.show_behind_parent = true
	disabled_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Connect signals
	resized.connect(_on_resized)

	# Set minimum size
	custom_minimum_size.x = BUTTON_MINIMUM_WIDTH


func set_disable(_is_disabled : bool):
	disabled = _is_disabled
	if disabled_mask:
		disabled_mask.visible = _is_disabled


func _on_resized():
	disabled_mask.size = size + size_margin

