@tool
class_name PTCheckBox
extends CheckBox

"""The very advanced and high tech custom !check box button! (tm pending)"""


var disabled_mask : ColorRect


func _ready():
	# Create disabled mask
	disabled_mask = ColorRect.new()
	
	disabled_mask.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	
	disabled_mask.color = PTButtonController.DISABLED_COLOR
	disabled_mask.size = Vector2(16, 16)
	disabled_mask.position = Vector2(4, -8.5)
	
	add_child(disabled_mask)
	disabled_mask.visible = disabled
	disabled_mask.show_behind_parent = true
	disabled_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_disable(is_disabled):
	disabled = is_disabled
	if disabled_mask:
		disabled_mask.visible = is_disabled
