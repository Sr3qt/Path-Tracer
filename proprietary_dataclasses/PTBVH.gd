extends Node
## Nice reading summary:
## https://hackmd.io/@zOZhMrk6TWqOaocQT3Oa0A/HJUqrveG5 

class_name PTBVHTree
""" Base class for BVH trees. Inherit this object to make a specific 
algorithmic implemention. 

"""

var root_node : BVHNode

# A dictionary of objects in the bvh
var objects_dict


var BVH_list : Array[BVHNode] = []
var _index := 0 # Used to keep track of index when creating BVH_list

var max_children := 2 

var leaf_count : int # Counts nodes with no child nodes
var inner_count : int # Counts nodes with child nodes, including root node
var object_count : int # Counts the number of objects stored in leaf nodes


func _ready():
	var temp = PTAABB.new(Vector3(2,3,2), Vector3(4,2,1))
	var temp2 = PTAABB.new()
	#print(temp2.minimum)
	#print(temp.maximum)
	#print(temp.minimum)
	#print(temp.maximum.max_axis_index())


func create_BVH_List(scene : PTScene):
	""" Takes in a list of objects and creates a BVH tree in bytes
	
	The result of this function will be stored in BVH_list
	The nodes in BVH_list will contain indices to scene.objects and 
	object pointers.
	
	
	The bytes created can directly be passed to the GPU. 
	
	"""
	
	var flat_object_list = []
	
	for object_list in scene.objects.values():
		flat_object_list += object_list
	
	var axis_sort = func(a, b):
		return a.aabb.minimum[0] > b.aabb.minimum[0]
	
	flat_object_list.sort_custom(axis_sort)
	
	root_node = BVHNode.new(null, max_children)
	inner_count += 1
	
	#if root_node.aabb:
		#print("root_node.aabb is not null")
	#else:
		#print("root_node.aabb is null")
	#var number = 0
	#var temp = func(num):
		#num += 1
		#_index += 1
		#return num
	#var new_num = temp.call(_index)
	#print(_index)
	#print(new_num)
	
	root_node.add_children(_recursive_split(flat_object_list, root_node))
	root_node.set_aabb()
	
	_tree_to_list()
	return BVH_list
	

func _recursive_split(object_list, parent) -> Array[BVHNode]:
	""""""

	# Will distriute objects evenly with first indices having slightly more 
	var even_division = object_list.size() / max_children
	var leftover = object_list.size() % max_children
	
	var new_children : Array[BVHNode] = []
	var start = 0
	var end = 0
	for i in range(max_children):
		start = end
		var is_last_i = (i == max_children - 1)
		end = (i + 1) * even_division + int(i < leftover) + int(is_last_i)
		var new_node = BVHNode.new(parent, max_children)
		var split_objects = object_list.slice(start, end)
		
		# If all objects can fit in a single node, do it
		if split_objects.size() <= max_children:
			new_children.append(_set_leaf(new_node, split_objects))
			continue
		
		# _set_inner calls recursive_split
		new_children.append(_set_inner(new_node, split_objects))
		
	return new_children

func _set_inner(node : BVHNode, objects):
	node.add_children(_recursive_split(objects, node))
	node.set_aabb()
	inner_count += 1 
	return node

func _set_leaf(node : BVHNode, objects):
	node.is_leaf = true
	node.objects = objects
	# Transfer object indices from objects to nodes
	for object in objects:
		node.object_indices.append(object.object_index)
	
	node.set_aabb()
	leaf_count += 1
	return node

func _tree_to_list():
	"""Turn BVH tree with object references into a list with index references"""
	
	var new_root = BVHNode.new(null, max_children)
	
	var length = size()
	print(length)
	BVH_list.resize(length)
	
	_recursive_traversal(root_node)
	
	print("doen")
	
	

func _recursive_traversal(parent : BVHNode):
	BVH_list[_index] = parent
	parent.index = _index
	for child in parent.children:
		child.parent_index = _index
	
	_index += 1
	for child in parent.children:
		if child.is_leaf:
			parent.children_indices.append(_index)
			BVH_list[_index] = child
			child.index = _index
			_index += 1
			continue
		
		parent.children_indices.append(_index)
		_recursive_traversal(child)
		

func get_obj_type(object):
	"""Returns the relevant enum for given object"""
	if object is PTSphere:
		return PTObject.OBJECT_TYPE.SPHERE
	else:
		return PTObject.OBJECT_TYPE.NOT_OBJECT
	

func size():
	"""Returns the total bumber of nodes in the tree"""
	return inner_count + leaf_count
	

func to_byte_array():
	var bytes = PackedByteArray()
	for node in BVH_list:
		bytes += node.to_byte_array()
	return bytes


class BVHNode:
	var parent : BVHNode
	var parent_index : int # Index to parent
	var index : int # INdex of this node in BVH_list
	var children : Array[BVHNode]
	var children_indices : Array[int] # List of indices to children in the BVH_list
	var max_children : int
	var aabb : PTAABB
	
	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than max_children
	var is_leaf := false
	var objects := [] 
	# List of indices to objects in the objects_dict
	var object_indices : Array[int] = []
	
	
	func _init(parent_, max_children_):
		parent = parent_
		max_children = max_children_
	
	func set_parent():
		pass
	
	func add_child():
		pass
		
	
	func set_aabb():
		if is_leaf:
			aabb = objects[0].aabb
			if objects.size() == 1:
				return
			for object in objects:
				aabb.merge(object.aabb)
			return
		
		aabb = children[0].aabb
		for child in children:
			if child.aabb:
				aabb.merge(child.aabb)
			else:
				print("Child node does not have aabb")
	
	func add_children(new_children : Array[BVHNode]):
		if children.size() + new_children.size() + objects.size() <= max_children:
			children += new_children
		else:
			print("Cannot fit child node")

	func to_byte_array():
		var child_indices_array = []
		
		for i in children_indices:
			child_indices_array += [i, 0]
		
		for i in range(objects.size()):
			var type = PTObject.get_obj_type(objects[i])
			var index = object_indices[i]
			child_indices_array += [index, type]
		
		child_indices_array.resize(max_children * 2)
		
		var bbox_bytes = aabb.to_byte_array()
		
		var other_bytes = PackedInt32Array([children.size() + objects.size(), parent_index, index, 0]).to_byte_array()
		
		var child_indices_bytes = PackedInt32Array(child_indices_array).to_byte_array()
		
		print(child_indices_bytes)
		print(bbox_bytes)
		print(other_bytes)
		print()
		
		return child_indices_bytes + bbox_bytes + other_bytes

