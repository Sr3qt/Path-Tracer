@tool
class_name PTOptionButton
extends OptionButton

"""The very advanced and high tech custom !check box button! (tm pending)"""


var disabled_mask

var size_margin = Vector2(4, 6)


func _ready():
	# Create disabled mask
	disabled_mask = ColorRect.new()
	
	disabled_mask.color = Color(170, 0, 0, 1)
	disabled_mask.size = size + size_margin
	disabled_mask.position = Vector2(-2, -2)
	
	add_child(disabled_mask)
	#disabled_mask.visible = false
	disabled_mask.show_behind_parent = true
	disabled_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Connect signals
	resized.connect(_on_resized)


func set_disable(is_disabled):
	disabled = is_disabled
	print("Disabled", is_disabled)
	disabled_mask.visible = is_disabled
		

func _on_resized():
	disabled_mask.size = size + size_margin

