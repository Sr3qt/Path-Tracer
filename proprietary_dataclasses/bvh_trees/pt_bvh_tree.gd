@tool
class_name PTBVHTree
extends Node
# Can potentially be Refcounted

# TODO Turn my BVH Algorithm into a seperate file
# TODO If i turn BVHNodes into actual nodes i can save and load BVHTrees

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

# TODO add support for meshes
const objects_to_include : Array[PTObject.ObjectType] = [
	PTObject.ObjectType.SPHERE,
	PTObject.ObjectType.TRIANGLE,
]

# TODO Implement transforms for bvhnodes

var order : int

# BVHTrees can merge, parent_tree is the BVH this tree was merged with
var parent_tree : PTBVHTree

var root_node : BVHNode

var object_container : PTObjectContainer
var object_to_leaf := {}

var node_to_index := {}

# TODO Add bvh constructor with bvh_list as argument
var bvh_list : Array[BVHNode] = []

var leaf_count : int # Counts nodes with no child nodes
var inner_count : int # Counts nodes with child nodes, including root node
var object_count : int # Counts the number of objects stored in leaf nodes

# NOTE: how to handle meshes with different types
var type : BVHType
var creation_time : int # In usecs
var SAH_cost : float

var _index := 0 # Used to keep track of index when creating bvh_list
var updated_nodes : Array[BVHNode] = [] # Nodes that need to update their buffer


func _init(_order := 2) -> void:
	order = _order
	root_node = BVHNode.new(null, self)
	inner_count += 1

	bvh_list = [root_node]


static func create_bvh_with_function_name(
		objects : PTObjectContainer,
		_order : int,
		_name : String,
	) -> PTBVHTree:

	if _name not in bvh_functions.keys():
		print("Name: %s, not in list of callable bvh functions" % _name)
		return
	@warning_ignore("unsafe_cast")
	var tempt := bvh_functions[_name] as Callable # UNSTATIC
	return tempt.call(objects, _order) # UNSTATIC


static func x_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHTree:
	var temp := PTBVHTree.new(_order)
	temp.create_BVH(objects)
	temp.type = BVHType.X_SORTED
	return temp


static func y_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHTree:
	var temp := PTBVHTree.new(_order)
	temp.create_BVH(objects, "y")
	temp.type = BVHType.Y_SORTED
	return temp


static func z_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHTree:
	var temp := PTBVHTree.new(_order)
	temp.create_BVH(objects, "z")
	temp.type = BVHType.Z_SORTED
	return temp


# TODO Give a better name, and make a naming scheme to bvh classes with multiple
#  algorithms
func create_BVH(objects : PTObjectContainer, axis := "x") -> void:
	""" Takes in an PTObjectContainer and creates a BVH tree

	The result of this function will be stored in a bvh_list.
	The nodes in bvh_list will contain indices to scene's objects and
	object pointers.


	The bytes created can directly be passed to the GPU.

	"""

	object_container = objects

	print("Starting to create %s-axis sorted BVH tree with %s primitives" %
			[axis, objects.object_count])
	var start_time := Time.get_ticks_usec()


	var flat_object_list : Array[PTObject] = []

	for _type in objects_to_include:
		flat_object_list.append_array(objects.get_object_array(_type))

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
	bvh_list.resize(size())
	_index_node(root_node)

	creation_time = Time.get_ticks_usec() - start_time

	print("Finished creating %s-axis sorted BVH tree with %s inner nodes and \
%s leaf nodes in %s ms." % [axis, inner_count, leaf_count, creation_time / 1000.])


func update_aabb(object : PTObject) -> void:
	var node : BVHNode = object_to_leaf[object] # UNSTATIC
	node.update_aabb()


func has(object : PTObject) -> bool:
	return object_to_leaf.has(object)


func add_object(object : PTObject) -> void:
	if has(object):
		print("PT: Object is already in BVHTree.")
		return
	# TODO Implement actual algorithm later, for now just remake
	@warning_ignore("unsafe_cast")
	PTRendererAuto.create_bvh(order, enum_to_dict[type] as String) # UNSTATIC


func remove_object(object : PTObject) -> void:
	if has(object):
		var leaf : BVHNode = object_to_leaf[object] # UNSTATIC
		object_to_leaf.erase(object)

		var index : int = leaf.object_list.find(object)
		if index != -1:
			leaf.object_list.remove_at(index)
			if leaf.size() == 0:
				# TODO Remove BVH node
				pass

			leaf.update_aabb()
			return

	push_warning("Object: %s already removed from bvh tree" % object)


func get_node_index(node : BVHNode) -> int:
	return node_to_index[node]


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


## Finds a non-full inner node
func find_inner_node(node : BVHNode) -> BVHNode:
	if node.is_leaf:
		return null
	if node.size() < order:
		return node
	else:
		# If inner node is full, check its children
		for child in node.children:
			var temp := find_inner_node(child)
			if is_instance_valid(temp):
				return temp
	return null # If no inner nodes have room return null


## Inserts another tree at a node in the bvh.
## An optional argument root can be given, the insertion will
##  happen to one of its children
func merge_with(other : PTBVHTree, root := root_node) -> void:
	# Find inner to place other
	var inner_node := find_inner_node(root)

	if not is_instance_valid(inner_node):
		push_error("PT: BVH does not have vacant inner node. HELP.")

	var index_offset := bvh_list.size()
	bvh_list.append_array(other.bvh_list)

	# "Glue the seam"
	inner_node.add_children([other.root_node])
	inner_node.update_aabb()
	other.root_node.parent = inner_node

	object_to_leaf.merge(other.object_to_leaf)
	node_to_index.merge(other.node_to_index)

	# Reindexing
	for node : BVHNode in other.node_to_index:
		node_to_index[node] += index_offset

	object_count += other.object_count
	leaf_count += other.leaf_count
	inner_count += other.inner_count

	# TODO Add print/assert to verify succesfull merge
	# TODO Research assert use in editor


func _remove_node(node : BVHNode) -> void:
	bvh_list.remove_at(get_node_index(node))
	node_to_index.erase(node)
	if node.is_inner:
		for child in node.children:
			_remove_node(child)
		inner_count -= 1
	else:
		for object in node.object_list:
			object_to_leaf.erase(object)
			object_count -= 1
		leaf_count -= 1


## Remove all nodes that are descendants of a given node from the tree
func remove_subtree(node : BVHNode) -> void:
	# Remove from parent node
	node.parent.children.erase(node)

	var index : int = node_to_index[node] # UNSTATIC
	_remove_node(node)

	# Reindex all nodes from index to end of bvh_list
	for i in range(index, bvh_list.size()):
		node_to_index[bvh_list[i]] = i # UNTSTATIC


func to_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	for node in bvh_list:
		bytes += node.to_byte_array()
	return bytes


func _recursive_split(object_list : Array[PTObject], parent : BVHNode) -> Array[BVHNode]:
	# Will distriute objects evenly with first indices having slightly more
	@warning_ignore("integer_division")
	var even_division : int = object_list.size() / order
	var leftover : int = object_list.size() % order

	var new_children : Array[BVHNode] = []
	var start : int = 0
	var end : int = 0
	for i in range(order):
		start = end
		end += even_division + int(i < leftover)
		if not (start - end):
			break # Break if no nodes are left
		var new_node := BVHNode.new(parent, self)
		# NOTE: slice returns a new Array and loses the previous arrays type
		var split_objects := object_list.slice(start, end)

		# If all objects can fit in a single node, do it
		if split_objects.size() <= order:
			new_children.append(_set_leaf(new_node, split_objects))
			continue

		new_node.add_children(_recursive_split(split_objects, new_node))
		inner_count += 1
		new_children.append(new_node)

	return new_children


func _set_leaf(node : BVHNode, object_list : Array[PTObject]) -> BVHNode:
	node.is_leaf = true
	node.object_list = object_list

	for object in object_list:
		object_to_leaf[object] = node # UNSTATIC

	node.set_aabb()
	leaf_count += 1
	return node


func _index_node(parent : BVHNode) -> void:
	bvh_list[_index] = parent
	node_to_index[parent] = _index # UNSTATIC

	_index += 1
	for child in parent.children:
		if child.is_leaf:
			bvh_list[_index] = child
			node_to_index[child] = _index # UNSTATIC
			_index += 1
			continue

		_index_node(child)


class BVHNode:
	""" This class represents a Node in a bvh tree.

	Ideally all bvh trees would use the same Node class, since their only
	intention is to hold information.
	"""

	var tree : PTBVHTree # Reference to the tree this node is a part of
	var parent : BVHNode # Reference to parent BVHNode
	var children : Array[BVHNode] # Reference to child BVHNodes
	var aabb : AABB

	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than tree.order
	# TODO Change objects to object_list to remove confusion with PTOC
	var object_list : Array[PTObject] = []
	var is_leaf := false
	var is_inner : bool:
		get:
			return not is_leaf
		set(value):
			is_inner = value
			is_leaf = not value


	func _init(p_parent : BVHNode, p_tree : PTBVHTree) -> void:
		parent = p_parent
		tree = p_tree


	func size() -> int:
		"""Returns number of children and number of references to objects"""
		return children.size() + object_list.size()


	func set_aabb() -> void:
		if is_leaf and object_list:
			aabb = object_list[0].get_global_aabb()
			for object in object_list:
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
		if size() + new_children.size() <= tree.order:
			children += new_children
			set_aabb() # Update aabb
		else:
			push_warning("Warning: Cannot fit child node")


	func to_byte_array() -> PackedByteArray:
		var child_indices_array := []

		# Add children nodes and objects to children list
		for child in children:
			child_indices_array.append(tree.get_node_index(child))

		for object in object_list:
			var type : int = object.get_type()
			var _index : int = tree.object_container.get_object_index(object)
			child_indices_array.append(_index + (type << 24))

		# Needed for buffer alignement
		#child_indices_array.resize(tree.order)
		child_indices_array.resize(tree.order +
								   int((tree.order % 4) - 4) * -1)

		var bbox_bytes : PackedByteArray = PTObject.aabb_to_byte_array(aabb)

		return PackedInt32Array(child_indices_array).to_byte_array() + bbox_bytes


