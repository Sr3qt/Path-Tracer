extends PTBVHTree

class_name PTBVHSweepSAH


func create_BVH_List(scene : PTScene):
	"""Create"""
	
	var start_time = Time.get_ticks_usec()
	
	var flat_object_list : Array[PTObject] = []
	
	var objects_to_include = [
		scene.OBJECT_TYPE.SPHERE
	]
	for object in objects_to_include:
		flat_object_list += scene.objects[object]
	
	object_count = flat_object_list.size()
	
	
	creation_time = Time.get_ticks_usec() - start_time
