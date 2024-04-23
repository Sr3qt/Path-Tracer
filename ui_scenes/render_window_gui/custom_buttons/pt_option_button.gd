@tool
class_name PTOptionButton
extends OptionButton

"""The very advanced and high tech custom !option button! (tm pending)"""


var disabled_mask : ColorRect
var changed_mask : ColorRect

var size_margin = Vector2(4, 5)

# The value selected might not be the same as the one in effect, 
#  which this value represents
var previous_value:
	set(value):
		previous_value = value
		_item_selected(value)


func _ready():
	# Create disabled mask
	disabled_mask = ColorRect.new()
	
	disabled_mask.color = PTButtonController.DISABLED_COLOR
	disabled_mask.size = size + size_margin
	disabled_mask.position = Vector2(-2, -2)
	
	disabled_mask.visible = false
	disabled_mask.show_behind_parent = true
	disabled_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	add_child(disabled_mask)
	
	# Create changed mask
	changed_mask = disabled_mask.duplicate()
	
	changed_mask.color = PTButtonController.CHANGED_VALUE_COLOR
	#changed_mask.visible = true
	
	add_child(changed_mask)
	
	# Connect signals
	resized.connect(_on_resized)
	item_selected.connect(_item_selected)


func set_disable(_is_disabled):
	disabled = _is_disabled
	disabled_mask.visible = _is_disabled
	if is_disabled:
		changed_mask.visible = false
	else:
		_item_selected(selected)
		

func _on_resized():
	disabled_mask.size = size + size_margin
	changed_mask.size = size + size_margin


func _item_selected(index : int):
	if changed_mask:
		if index != previous_value:
			changed_mask.visible = true
		else:
			changed_mask.visible = false
	

