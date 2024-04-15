@tool
extends Button

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == 1:
		# NOTE: This script will grab all unhandled mouse button presses
		grab_focus()
		grab_click_focus()
		release_focus()
		
		# NOTE: A little hacky, but the MaxSamplesButton focus_exited didnt work
		#  Because of this it has to run as a tool, ugh
		%ButtonController._on_max_samples_button_focus_exited()
