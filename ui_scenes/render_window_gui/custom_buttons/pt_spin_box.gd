@tool
class_name PTSpinBox
extends SpinBox

"""The very advanced and high tech custom !spin box button! (tm pending)"""

var disabled_mask : ColorRect
var changed_mask : ColorRect

var size_margin := Vector2(4, 5)

# TODO Make previous value optional, make instant updates possible
# The value selected might not be the same as the one in effect,
#  which this value represents
var previous_value := value:
	set(_value):
		previous_value = _value
		_value_changed(_value)


func _ready() -> void:
	# Create disabled mask
	disabled_mask = ColorRect.new()

	disabled_mask.color = PTButtonController.DISABLED_COLOR
	disabled_mask.size = size + size_margin
	disabled_mask.position = Vector2(-2, -2)

	disabled_mask.visible = not editable
	disabled_mask.show_behind_parent = true
	disabled_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(disabled_mask)

	# Create changed mask
	changed_mask = disabled_mask.duplicate() as ColorRect
	changed_mask.visible = false

	changed_mask.color = PTButtonController.CHANGED_VALUE_COLOR

	add_child(changed_mask)

	# Connect signals
	resized.connect(_on_resized)

	# NOTE: Apparently linedit focus is seperate from the spinbox,
	#  which doesn't have focus to begin with.
	#  Therefore we have to manually bind it.
	get_line_edit().connect("focus_exited", emit_wrapper)


func emit_wrapper() -> void:
	focus_exited.emit()


func set_disable(is_disabled : bool) -> void:
	editable = not is_disabled
	if disabled_mask:
		disabled_mask.visible = is_disabled
	if changed_mask and is_disabled:
		changed_mask.visible = false
	else:
		_value_changed(value)


func _on_resized() -> void:
	if disabled_mask:
		disabled_mask.size = size + size_margin
	if changed_mask:
		changed_mask.size = size + size_margin


func _value_changed(_value : float) -> void:
	if changed_mask:
		if _value != previous_value:
			changed_mask.visible = true
		else:
			changed_mask.visible = false

