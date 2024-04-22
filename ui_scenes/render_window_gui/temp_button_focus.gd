extends Button

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == 1:
		if Rect2(Vector2(), size).has_point(get_local_mouse_position()):
			# NOTE: This script will grab all unhandled mouse button presses in viewport
			grab_focus()
			grab_click_focus()
			release_focus()
			
