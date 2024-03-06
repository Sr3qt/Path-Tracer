extends Node
## Nice reading summary:
## https://hackmd.io/@zOZhMrk6TWqOaocQT3Oa0A/HJUqrveG5 

class_name BVHTree
""" Base class for BVH trees. Inherit this object to make a specific 
algorithmic implemention. 

"""

var root_node : BVHNode

var BVH_list

var max_children := 2 


func _ready():
	var temp = PTAABB.new(Vector3(2,3,2), Vector3(4,2,1))
	var temp2 = PTAABB.new()
	print(temp2.minimum)
	print(temp.maximum)
	print(temp.minimum)
	print(temp.maximum.max_axis_index())

	
	print("hello wordl")
	
	#PTObject3D.array2vec([1,1,1])


func create_BVH_List(objects_list):
	""" Takes in a list of objects and creates a BVH tree in bytes
	
	The objects_list is a nested list where the inner lists only have one 
	object type.
	
	The bytes created can directly be passed to the GPU. 
	
	
	
	"""
	
	var flat_object_list = []
	
	var current_type
	for object_list in objects_list:
		flat_object_list += object_list
	
	var axis_sort = func(a, b):
		return a.aabb.minimum[0] > b.aabb.minimum[0]
	
	flat_object_list.sort_custom(axis_sort)
	
	root_node = BVHNode.new(null)
	
	root_node.add_children(_recursive_split(flat_object_list, root_node))
	
	## Here a tree should already exist
	
	
	


func _recursive_split(object_list, parent) -> Array[BVHNode]:
	# If all objects can fit in a single node, do it
	if object_list.size() <= max_children:
		var new_node = BVHNode.new(parent)
		new_node.objects = object_list
		return [new_node]
		
	
	# Will distriute objects evenly with first indices having slightly more 
	var even_division = object_list.size() / max_children
	var leftover = object_list.size() % max_children
	
	var new_children = []
	var start = 0
	var end = 0
	for i in range(max_children):
		start = end
		end = i * even_division + (i < leftover)
		var new_node = BVHNode.new(parent)
		new_node.add_children(_recursive_split(object_list.slice(start, end), parent)) 
		new_children.append(new_node)
	
	return new_children


func _tree_to_list():
	"""Turn BVH tree with object references into a list with index references"""



func get_obj_type(object):
	"""Returns the relevant enum for given object"""
	if object is PTSphere:
		return PTObject.OBJECT_TYPE.SPHERE
	else:
		return PTObject.OBJECT_TYPE.NOT_OBJECT
	

func length():
	pass
	

func leaf_count():
	pass


func inner_count():
	pass
	


class BVHNode:
	var parent : BVHNode
	var children : Array[BVHNode]
	var max_children : int
	
	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than max_children
	var is_leaf : bool
	var objects

	func _init(parent):
		self.parent = parent
		
	
	func set_parent():
		pass
	
	func add_child():
		pass
		
	
	func add_children(new_children : Array[BVHNode]):
		if children.size() + new_children.size() <= max_children:
			children += new_children
		else:
			print("Cannot fit child node")



