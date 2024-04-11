extends Button

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == 1:
		# NOTE: This script will grab all unhandled mouse button presses
		grab_focus()
		grab_click_focus()
		release_focus()
