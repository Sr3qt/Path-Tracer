#@tool
extends CenterContainer


var number_of_buttons = 0

func _enter_tree():
	print("COntain enterd trre")

func _exit_tree():
	number_of_buttons = 0
	if get_parent():
		var children = get_children()
		for i in range(get_child_count()):
			if i != 0:
				#if children[i]:
					#remove_child(children[i])
				pass
			
	print("COntain erxit trre")

func _ready():
	
	print("COntain is ready")

func _process(delta):
	#print("Button process step")
	
	if number_of_buttons < 5 and get_child_count() < 5:
		var new_button := Button.new()
		#new_button.position.x = 100 * number_of_buttons
		new_button.set_position(Vector2(100 * number_of_buttons, 100 * number_of_buttons))
		new_button.text = " NEw button"
		add_child(new_button)
		
		new_button.owner = get_tree().edited_scene_root
		
		print("added child")

		number_of_buttons += 1
