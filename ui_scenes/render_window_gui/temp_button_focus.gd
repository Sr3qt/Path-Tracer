extends Button

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if ((event as InputEventMouseButton).is_pressed() and
			(event as InputEventMouseButton).button_index == 1):
			if Rect2(Vector2(), size).has_point(get_local_mouse_position()):
				# NOTE: This script will grab all unhandled mouse button presses in viewport
				grab_focus()
				grab_click_focus()
				release_focus()

