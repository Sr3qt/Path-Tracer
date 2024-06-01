class_name PTBVHSweepSAH
extends PTBVHTree


#func create_BVH_List(scene : PTScene):
	#"""Create"""
#
	#var start_time = Time.get_ticks_usec()
#
	#var flat_object_list : Array[PTObject] = []
#
	#var objects_to_include = [
		#scene.ObjectType.SPHERE
	#]
	#for object in objects_to_include:
		#flat_object_list += scene.objects.get_object_array(object)
#
	#object_count = flat_object_list.size()
#
#
	#creation_time = Time.get_ticks_usec() - start_time
