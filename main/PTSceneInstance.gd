@tool
extends PTScene

# TODO Is it possible to remove this class and implement the same functionality
#  in PTScene in a more godootian way?

func _ready():
	#var new_scene = PTScene.load_scene("res://main/sphere_scene1.txt")
	
	create_random_scene(0)
	
	
	#objects = new_scene.objects
	#materials = new_scene.materials
	camera = get_child(0) # NOTE: Unsecure way to get Camera
	
	set_camera_setting(camera_setting.corner)
	
	
	
