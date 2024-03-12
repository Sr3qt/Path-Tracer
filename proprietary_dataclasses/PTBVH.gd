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

var max_children := 4

var leaf_count : int # Counts nodes with no child nodes
var inner_count : int # Counts nodes with child nodes, including root node
var object_count : int # Counts the number of objects stored in leaf nodes


func create_BVH_List(scene : PTScene):
	""" Takes in a list of objects and creates a BVH tree in bytes
	
	The result of this function will be stored in BVH_list
	The nodes in BVH_list will contain indices to scene.objects and 
	object pointers.
	
	
	The bytes created can directly be passed to the GPU. 
	
	"""
	
	var flat_object_list : Array[PTObject] = []
	
	var objects_to_include = [
		scene.OBJECT_TYPE.SPHERE
	]
	for object in objects_to_include:
		flat_object_list += scene.objects[object]
	
	object_count = flat_object_list.size()
	
	var axis_sort = func(a, b):
		return a.aabb.minimum[0] > b.aabb.minimum[0]
	
	flat_object_list.sort_custom(axis_sort)
	
	root_node = BVHNode.new(null, self)
	inner_count += 1
	
	# Creates tree recursively
	root_node.add_children(_recursive_split(flat_object_list, root_node))
	
	# Indexes tree recursively
	BVH_list.resize(size())
	_index_node(root_node)
	
	return BVH_list
	

func _recursive_split(object_list : Array[PTObject], parent) -> Array[BVHNode]:
	""""""

	# Will distriute objects evenly with first indices having slightly more
	@warning_ignore("integer_division")
	var even_division = object_list.size() / max_children
	var leftover = object_list.size() % max_children
	
	var new_children : Array[BVHNode] = []
	var start = 0
	var end = 0
	for i in range(max_children):
		start = end
		end += even_division + int(i < leftover) 
		var new_node = BVHNode.new(parent, self)
		var split_objects = object_list.slice(start, end)
		
		# If all objects can fit in a single node, do it
		if split_objects.size() <= max_children:
			new_children.append(_set_leaf(new_node, split_objects))
			continue
		
		new_node.add_children(_recursive_split(split_objects, new_node))
		inner_count += 1 
		new_children.append(new_node)
		
	return new_children


func _set_leaf(node : BVHNode, objects : Array[PTObject]):
	node.is_leaf = true
	node.objects = objects
	# Transfer object indices from objects to nodes
	for object in objects:
		node.object_indices.append(object.object_index)
	
	node.set_aabb()
	leaf_count += 1
	return node


func _index_node(parent : BVHNode):
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
		_index_node(child)
		

func size():
	"""Returns the total bumber of nodes in the tree"""
	return inner_count + leaf_count
	

func to_byte_array():
	var bytes = PackedByteArray()
	for node in BVH_list:
		bytes += node.to_byte_array()
	return bytes


class BVHNode:
	var _tree : PTBVHTree # Reference tothe tree this node is a part of
	var parent : BVHNode
	var parent_index : int # Index to parent
	var index : int # INdex of this node in BVH_list
	var children : Array[BVHNode]
	var children_indices : Array[int] # List of indices to children in the BVH_list
	var aabb : PTAABB
	
	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than _tree.max_children
	var is_leaf := false
	var objects : Array[PTObject] = [] 
	# List of indices to objects in the objects_dict
	var object_indices : Array[int] = []
	
	
	func _init(parent_, tree):
		parent = parent_
		_tree = tree
	
	func add_child():
		pass
	
	func size():
		"""Returns number of children and number of references to objects"""
		return children.size() + objects.size()
	
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
				print("Warning: Child node does not have aabb")
	
	func add_children(new_children : Array[BVHNode]):
		if size() + new_children.size() <= _tree.max_children:
			children += new_children
			set_aabb() # Update aabb
		else:
			print("Warning: Cannot fit child node")

	func to_byte_array():
		var child_indices_array = []
		
		# Add children nodes and objects to children list
		for i in children_indices:
			child_indices_array += [i, 0]
		
		for i in range(objects.size()):
			var type = objects[i].get_type()
			var _index = object_indices[i]
			child_indices_array += [_index, type]
		
		# Needed for buffer alignement
		child_indices_array.resize(_tree.max_children * 2 + 
								   int((_tree.max_children % 2) + 2) * 2)
		
		var bbox_bytes = aabb.to_byte_array()
		var other = [size(), parent_index, index, 0]
		var other_bytes = PackedInt32Array(other).to_byte_array()
		
		var child_indices_bytes = PackedInt32Array(child_indices_array).to_byte_array()
		
		#print(child_indices_bytes)
		#print(bbox_bytes)
		#print(other_bytes)
		#print()
		
		return child_indices_bytes + bbox_bytes + other_bytes

