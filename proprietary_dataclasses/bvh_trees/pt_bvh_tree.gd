@tool
class_name PTBVHTree
extends Node
# Can potentially be Refcounted

## Nice reading summary:
## https://hackmd.io/@zOZhMrk6TWqOaocQT3Oa0A/HJUqrveG5

## Also really good overview
## https://meistdan.github.io/publications/bvh_star/paper.pdf


""" Base class for BVH trees. Inherit this object to make a specific
algorithmic implemention.

Such implementations should have a create_BVH function which creates the actual
tree. Creation time and SAH score should also be recorded after creation.
"""

# NOTE: Should only be used for exports. Also should not designate type but function
## Enum of different possible BVH algorithms, should be updated as more algortithms
##  are added. Only positive numbers (and zero) are allowed as values.
## The user can add their of own bvh functions to bvh_functions. The only
##  non-optional arguments needs to a PTScene object followed by a maximum child count.
enum BVHType {
	X_SORTED,
	Y_SORTED,
	Z_SORTED,
}

const enum_to_dict := {
	BVHType.X_SORTED : "X-Axis Sorted",
	BVHType.Y_SORTED : "Y-Axis Sorted",
	BVHType.Z_SORTED : "Z-Axis Sorted",
}

static var built_in_bvh_functions := {
	"X-Axis Sorted" : PTBVHTree.x_axis_sorted,
	"Y-Axis Sorted" : PTBVHTree.y_axis_sorted,
	"Z-Axis Sorted" : PTBVHTree.z_axis_sorted,
}

# TODO Add setter function for ease of use
static var bvh_functions := built_in_bvh_functions

const objects_to_include : Array[PTObject.ObjectType] = [
	PTObject.ObjectType.SPHERE,
	PTObject.ObjectType.TRIANGLE,
]

var root_node : BVHNode

var object_to_leaf := {}

var BVH_list : Array[BVHNode] = []

var max_children : int

var leaf_count : int # Counts nodes with no child nodes
var inner_count : int # Counts nodes with child nodes, including root node
var object_count : int # Counts the number of objects stored in leaf nodes

var type : BVHType
var creation_time : int # In usecs
var SAH_cost : float

var _index := 0 # Used to keep track of index when creating BVH_list
var updated_nodes : Array[BVHNode] = [] # Nodes that need to update their buffer


func _init(_max_children := 2) -> void:
	max_children = _max_children
	root_node = BVHNode.new(null, self)
	inner_count += 1

	BVH_list = [root_node]


static func create_bvh_with_function_name(
		scene : PTScene,
		_max_children : int,
		_name : String,
	) -> PTBVHTree:

	if _name not in bvh_functions.keys():
		print("Name: %s, not in list of callable bvh functions" % _name)
		return
	@warning_ignore("unsafe_cast")
	var tempt := bvh_functions[_name] as Callable # UNSTATIC
	return tempt.call(scene, _max_children) # UNSTATIC


static func x_axis_sorted(scene : PTScene, _max_children : int) -> PTBVHTree:
	var temp := PTBVHTree.new(_max_children)
	temp.create_BVH(scene)
	temp.type = BVHType.X_SORTED
	return temp


static func y_axis_sorted(scene : PTScene, _max_children : int) -> PTBVHTree:
	var temp := PTBVHTree.new(_max_children)
	temp.create_BVH(scene, "y")
	temp.type = BVHType.Y_SORTED
	return temp


static func z_axis_sorted(scene : PTScene, _max_children : int) -> PTBVHTree:
	var temp := PTBVHTree.new(_max_children)
	temp.create_BVH(scene, "z")
	temp.type = BVHType.Z_SORTED
	return temp


# TODO Give a better name, and make a naming scheme to bvh classes with multiple
#  algorithms
func create_BVH(scene : PTScene, axis := "x") -> void:
	""" Takes in a PTScene and creates a BVH tree

	The result of this function will be stored in a BVH_list.
	The nodes in BVH_list will contain indices to scene's objects and
	object pointers.


	The bytes created can directly be passed to the GPU.

	"""

	print("Starting to create %s-axis sorted BVH tree with %s primitives" %
			[axis, scene.object_count])
	var start_time := Time.get_ticks_usec()

	var flat_object_list : Array[PTObject] = []

	for object in objects_to_include:
		flat_object_list.append_array(scene.get_object_array(object))

	object_count = flat_object_list.size()

	# Sort according to given axis
	var _axis : int = 0
	match axis:
		"y":
			_axis = 1
		"z":
			_axis = 2
	var axis_sort := func(a : PTObject, b : PTObject) -> bool:
		return a.get_global_aabb().position[_axis] > b.get_global_aabb().end[_axis]

	flat_object_list.sort_custom(axis_sort)

	# Creates tree recursively
	root_node.add_children(_recursive_split(flat_object_list, root_node))

	# Indexes tree recursively
	BVH_list.resize(size())
	_index_node(root_node)

	creation_time = Time.get_ticks_usec() - start_time

	print("Finished creating %s-axis sorted BVH tree with %s inner nodes and \
%s leaf nodes in %s ms." % [axis, inner_count, leaf_count, creation_time / 1000.])


func update_aabb(object : PTObject) -> void:
	var node : BVHNode = object_to_leaf[object] # UNSTATIC
	node.update_aabb()


func add_object(_object : PTObject) -> void:
	# TODO Implement actual algorithm later, for now just remake
	@warning_ignore("unsafe_cast")
	PTRendererAuto.create_bvh(max_children, enum_to_dict[type] as String) # UNSTATIC


func remove_object(object : PTObject) -> void:
	if object_to_leaf.has(object):
		var leaf : BVHNode = object_to_leaf[object] # UNSTATIC
		object_to_leaf.erase(object)

		var index : int = leaf.objects.find(object)
		if index != -1:
			leaf.objects.remove_at(index)
			leaf.update_aabb()
			return

	push_warning("Object: %s already removed from bvh tree" % object)


func size() -> int:
	"""Returns the total bumber of nodes in the tree"""
	return inner_count + leaf_count


func depth() -> int:
	"""Returns the length of the longest path from the root to a leaf node"""
	var counter : int = 0
	var current_node := root_node
	# The default tree is created in a way in which the longest path will be
	#	along the first indices of each node
	while !current_node.is_leaf:
		current_node = current_node.children[0]
		counter += 1
	return counter


# TODO Implement sah_cost fucntion
func tree_sah_cost() -> void:
	"Calculates the SAH cost for the whole tree"


func to_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	for node in BVH_list:
		bytes += node.to_byte_array()
	return bytes


func _recursive_split(object_list : Array[PTObject], parent : BVHNode) -> Array[BVHNode]:
	""""""

	# Will distriute objects evenly with first indices having slightly more
	@warning_ignore("integer_division")
	var even_division : int = object_list.size() / max_children
	var leftover : int = object_list.size() % max_children

	var new_children : Array[BVHNode] = []
	var start : int = 0
	var end : int = 0
	for i in range(max_children):
		start = end
		end += even_division + int(i < leftover)
		if not (start - end):
			# Break if no nodes are left
			break
		var new_node := BVHNode.new(parent, self)
		# NOTE: slice returns a new Array and loses the previous arrays type
		var split_objects := object_list.slice(start, end)

		# If all objects can fit in a single node, do it
		if split_objects.size() <= max_children:
			new_children.append(_set_leaf(new_node, split_objects))
			continue

		new_node.add_children(_recursive_split(split_objects, new_node))
		inner_count += 1
		new_children.append(new_node)

	return new_children


func _set_leaf(node : BVHNode, objects : Array[PTObject]) -> BVHNode:
	node.is_leaf = true
	node.objects = objects
	# Transfer object indices from objects to nodes
	for object in objects:
		object_to_leaf[object] = node # UNSTATIC
		node.object_indices.append(object.object_index)

	node.set_aabb()
	leaf_count += 1
	return node


func _index_node(parent : BVHNode) -> void:
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


class BVHNode:
	""" This class represents a Node in a bvh tree.

	Ideally all bvh trees would use the same Node class, since their only
	intention is to hold information.
	"""

	var tree : PTBVHTree # Reference to the tree this node is a part of
	var parent : BVHNode # Reference to parent BVHNode
	var parent_index : int # Index to parent BVHNode in BVH_list
	var index : int # Index of this node in BVH_list
	var children : Array[BVHNode] # Reference to child BVHNodes
	var children_indices : Array[int] # List of indices to child BVHNodes in the BVH_list
	var aabb : AABB

	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than tree.max_children
	var is_leaf := false
	var objects : Array[PTObject] = []
	# List of indices to objects in their respective object lists
	var object_indices : Array[int] = []


	func _init(p_parent : BVHNode, p_tree : PTBVHTree) -> void:
		parent = p_parent
		tree = p_tree


	func size() -> int:
		"""Returns number of children and number of references to objects"""
		return children.size() + objects.size()


	func set_aabb() -> void:
		if is_leaf and objects:
			aabb = objects[0].get_global_aabb()
			for object in objects:
				aabb = aabb.merge(object.get_global_aabb())
			return

		if children.size() > 0:
			aabb = children[0].aabb
			for child in children:
				if child.aabb:
					aabb = aabb.merge(child.aabb)
				else:
					push_warning("Warning: Child node %s does not have aabb" % child)


	func update_aabb() -> void:
		tree.updated_nodes.append(self)
		set_aabb()
		if parent != null:
			parent.update_aabb()


	func add_children(new_children : Array[BVHNode]) -> void:
		if size() + new_children.size() <= tree.max_children:
			children += new_children
			set_aabb() # Update aabb
		else:
			push_warning("Warning: Cannot fit child node")


	func to_byte_array() -> PackedByteArray:
		var child_indices_array := []

		# Add children nodes and objects to children list
		for i in children_indices:
			child_indices_array.append(i)

		for i in range(objects.size()):
			var type : int = objects[i].get_type()
			var _index : int = object_indices[i]
			child_indices_array.append(_index + (type << 24))

		# Needed for buffer alignement
		#child_indices_array.resize(tree.max_children)
		child_indices_array.resize(tree.max_children +
								   int((tree.max_children % 4) - 4) * -1)

		var bbox_bytes : PackedByteArray = PTObject.aabb_to_byte_array(aabb)

		return PackedInt32Array(child_indices_array).to_byte_array() + bbox_bytes


