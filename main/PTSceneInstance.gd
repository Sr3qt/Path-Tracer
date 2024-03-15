extends PTScene


func _ready():
	var new_scene = PTScene.load_scene("res://sphere_scene1.txt")
	
	objects = new_scene.objects
	materials = new_scene.materials
	camera = get_child(0) # NOTE: Unsecure way to get Camera
	
	create_BVH()
	
	
