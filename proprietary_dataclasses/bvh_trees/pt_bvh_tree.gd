@tool
class_name PTBVHTree
extends RefCounted

# TODO If i turn BVHNodes into actual nodes i can save and load BVHTrees
# TODO Alternatively look at inst_to_dict for serialization, or var_to_bytes

# TODO Make graph representation, maybe with graphEdit

## Base class for BVH trees.
##
##
## Nice reading summary:
## https://hackmd.io/@zOZhMrk6TWqOaocQT3Oa0A/HJUqrveG5
##
## Also really good overview
## https://meistdan.github.io/publications/bvh_star/paper.pdf
##
## The user can add their own algorithmic implementation of the creation code.
## After all BVHNodes point to their respective child nodes and objects, index_tree
## should be called to assure it will work properly with the rest of the Engine.
##
## If there is a function both with and without an underscore, the one with underscore
## probably doesn't handle bvh_list indexing.
##
## PTBVHTrees can have sub-trees within them, seen by the root node of the sub-tree having
## a different tree property. These root nodes will have only one child node which contains
## the rest of the tree.
## Will probably change policy so that only scene bvh can have sub-trees.
##
## Each PTBVHTree object has ownership of their sub-tree and they
## should control changes to their own branches and nodes. The super-trees will
## still have indices to nodes in the sub-trees and can only use get functions on them.

const NODE_BYTE_SIZE = 32

## Enum of different possible BVH algorithms, should be updated as more algortithms
##  are added. Only positive numbers (and zero) are allowed as values.
enum BVHType {
	X_SORTED,
	Y_SORTED,
	Z_SORTED,
	XYZ_SORTED,
}

const enum_to_dict := {
	BVHType.X_SORTED : "X-Axis Sorted",
	BVHType.Y_SORTED : "Y-Axis Sorted",
	BVHType.Z_SORTED : "Z-Axis Sorted",
	BVHType.XYZ_SORTED : "XYZ-Axis Sorted",
}

static var built_in_bvh_functions := {
	"X-Axis Sorted" : PTBVHAxisSort.x_axis_sorted,
	"Y-Axis Sorted" : PTBVHAxisSort.y_axis_sorted,
	"Z-Axis Sorted" : PTBVHAxisSort.z_axis_sorted,
	"XYZ-Axis Sorted" : PTBVHAxisSort.longest_axis_sort,
}

# TODO Should add config file where the user can specify functions and names
#  And they will be added to enum/dict either here or from a Autoload
## The user can add their of own bvh functions to the bvh_functions dict. The only
##  non-optional arguments needs to be a PTObjectContainer followed by a maximum child count.
##  Of course it also needs to return a PTBVHTree or subtype.
static var bvh_functions := built_in_bvh_functions

# TODO add support for meshes
const objects_to_exclude : Array[PTObject.ObjectType] = [
	PTObject.ObjectType.NOT_OBJECT,
	PTObject.ObjectType.PLANE,
	PTObject.ObjectType.MAX,
]

# TODO Fix support for multi order trees, now it crashes the whole program
var order : int

# BVHTrees can merge, parent_tree is the BVH this tree was merged with
var parent_tree : PTBVHTree

## The object that owns this bvh. Can be either PTScene, PTMesh or null
var bvh_owner : Variant:
	set(value):
		assert(value is PTMesh or value is PTScene or value == null,
				"bvh_owner can only be of type PTMesh, PTScene, or null; not " + str(value))
		bvh_owner = value

# TODO Give BVHTree aabb property similar to ptobjects to facilitate duck typing.
var root_node : BVHNode

var object_to_leaf := {}
var leaf_nodes : Array[BVHNode]

var object_ids : PackedInt32Array = []

## Takes in a node gives its index in bvh_list
var _node_to_index := {}

var _mesh_to_mesh_socket := {}

# TODO Add bvh constructor with bvh_list as argument
var bvh_list : Array[BVHNode] = []

var leaf_count : int # Counts nodes with no child nodes
var inner_count : int # Counts nodes with child nodes, including root node
var object_count : int # Counts the number of objects stored in leaf nodes

# NOTE: how to handle meshes with different types
var type : BVHType
var creation_time : int # In usecs
var sah_cost : float

# TODO Currently functions do not clean up the tree to work with engine. They have to run a full re-index.
# 	TODO Make all functions self contained.
var updated_indices : Array[int] = []

# TODO MAke BVHBUffer abler to expand + have empty space

# TODO Make a check for loops existing

## TEMP Only valid for scene bvh. Whether the bvh buffer needs to be rebuilt.
var tree_reindexing_needed := false
var needs_buffer_reset := false


func _init(_order := 2) -> void:
	order = _order
	root_node = BVHNode.new(null, self)
	_node_to_index[root_node] = 0
	inner_count += 1

	bvh_list = [root_node]


static func create_bvh_with_function_name(
		objects : PTObjectContainer,
		_order : int,
		_name : String,
		mesh_or_scene_owner : Variant,
	) -> PTBVHTree:

	if _name not in bvh_functions.keys():
		print("Name: %s, not in list of callable bvh functions" % _name)
		return

	assert(_order > 1, "BVH order has to be >= 2")

	assert(mesh_or_scene_owner is PTScene or mesh_or_scene_owner is PTMesh,
			"mesh_or_scene_owner should be PTMesh or PTScene, but was %s" % [mesh_or_scene_owner])

	@warning_ignore("unsafe_cast")
	var tempt := bvh_functions[_name] as Callable # UNSTATIC
	var start_time : int = Time.get_ticks_usec()
	var bvh : PTBVHTree = tempt.call(objects, _order) # UNSTATIC
	bvh.creation_time = (Time.get_ticks_usec() - start_time)

	bvh.bvh_owner = mesh_or_scene_owner

	return bvh


## Returns true if bvh_owner is a valid PTSMesh instance
func is_mesh_owned() -> bool:
	return is_instance_valid(bvh_owner) and bvh_owner is PTMesh


## Returns this bvhs valid mesh owner if it exists, otherwise return null
func get_mesh() -> PTMesh:
	if is_mesh_owned():
		return bvh_owner
	return null


## Returns true if bvh_owner is a valid PTScene instance
func is_scene_owned() -> bool:
	return is_instance_valid(bvh_owner) and bvh_owner is PTScene


## Returns this bvhs valid scene owner if it exists, otherwise return null
func get_scene() -> PTScene:
	if is_scene_owned():
		return bvh_owner
	return null


func is_sub_tree() -> bool:
	return is_instance_valid(parent_tree)


func update_aabb(object : PTObject) -> void:
	assert(has(object), "PT: Cannot update the aabb of an object that is not in BVH.\n" +
				"object: " + str(object))

	var node : BVHNode = object_to_leaf[object] # UNSTATIC
	node.update_aabb()


## Updates the aabb of the mesh socket of a given mesh
func update_mesh_socket_aabb(mesh : PTMesh) -> void:
	assert(_mesh_to_mesh_socket.has(mesh),
			"Given mesh is not found in _mesh_to_mesh_socket. Is it even a part of the tree?")

	var node : BVHNode = _mesh_to_mesh_socket[mesh] # UNSTATIC
	node.update_aabb()


## Mesh socket is a special node that only has a mesh subtree as a child
func create_mesh_socket(parent : BVHNode, mesh_tree : PTBVHTree) -> BVHNode:
	assert(not parent.is_full(), "Cannot create mesh socket on full node.")
	assert(parent.is_inner, "Cannto create mesh socket on leaf node.")
	assert(mesh_tree.is_mesh_owned(), "Cannot create mesh socket on non-mesh owned BVH tree")

	var mesh_socket := BVHNode.new(parent, self)
	mesh_socket.is_mesh_socket = true
	mesh_socket.is_inner = true
	inner_count += 1
	_mesh_to_mesh_socket[mesh_tree.get_mesh()] = mesh_socket
	_node_to_index[mesh_socket] = bvh_list.size()
	bvh_list.append(mesh_socket)

	parent.add_children([mesh_socket])
	mesh_socket.add_children([mesh_tree.root_node])
	mesh_socket.update_aabb()

	# Redundant bc of update_aabb?
	append_updated_node_index(get_node_index(parent))
	append_updated_node_index(get_node_index(mesh_socket))
	mesh_tree.root_node.parent = mesh_socket

	return mesh_socket


func queue_node_update(node : BVHNode) -> void:
	append_updated_node_index(get_node_index(node))


## Appends a node_index that needs to be updated in buffer
func append_updated_node_index(index : int) -> void:
	if index not in updated_indices:
		updated_indices.append(index)


func has(object : PTObject) -> bool:
	return object_to_leaf.has(object)


func _add_object_to_tree(object : PTObject) -> Array[BVHNode]:
	var fitting_node := find_aabb_spot(object.get_bvh_aabb())
	var new_nodes : Array[BVHNode] = []

	if fitting_node == null:
		fitting_node = root_node

	# If node is full, split and get non-full fitting node
	if fitting_node.is_full():
		if PTRendererAuto.is_debug:
			print("No vacant leaf node to add new object. Splitting node in two.")
		new_nodes.append_array(_split_node(fitting_node))
		fitting_node = find_aabb_spot(object.get_bvh_aabb(), fitting_node)
		if fitting_node == null:
			fitting_node = root_node

	# Add object to node
	if fitting_node.is_inner:
		var new_node := BVHNode.new(fitting_node, self)
		new_node.is_leaf = true
		new_node.object_list.append(object)
		new_node.set_aabb()
		fitting_node.add_children([new_node])
		new_nodes.append(new_node)
	else:
		fitting_node.object_list.append(object)
		object_to_leaf[object] = fitting_node # UNSTATIC
		if is_sub_tree():
			parent_tree.object_to_leaf[object] = fitting_node # UNSTATIC

	fitting_node.update_aabb()

	return new_nodes


func add_object(object : PTObject) -> void:
	if object.get_type() in objects_to_exclude:
		push_warning("PT: Cannot add object to BVH as it is explicitly excluded.\n",
				"object: ", object, "\ntype: ", object.get_type_name())
		return

	if has(object):
		print("PT: Object is already in BVHTree.")
		return

	if PTRendererAuto.is_debug:
		print("Adding object ", object, " to bvh")

	var new_nodes := _add_object_to_tree(object)
	for node in new_nodes:
		index_node(node)

	# TODO MAke BVHBUffer abler to expand + have empty space
	# Would set flag for buffer expansion here


func remove_object(object : PTObject) -> void:
	# TODO FIX, currently messes up order of bvh
	# TODO remove object from bvh_list and call back parent_tree
	if not has(object):
		push_warning("Object: %s already removed from bvh tree" % object)
		return

	if PTRendererAuto.is_debug:
		print("Removing object ", object, " from bvh")

	var leaf : BVHNode = object_to_leaf[object] # UNSTATIC
	object_to_leaf.erase(object)

	var index : int = leaf.object_list.find(object)
	if index != -1:
		leaf.object_list.remove_at(index)
		if leaf.size() == 0:
			# TODO Remove BVH node
			pass

		leaf.update_aabb()


func get_node_index(node : BVHNode) -> int:
	return _node_to_index[node] # UNSTATIC


## Returns an array of indexed nodes, based on the calling tree's node index.
func get_indices(node : BVHNode, indices : Array[int] = []) -> Array[int]:
	 # NOTE: Unlike python, an array as a default parameter is an unique instance
	if indices.is_empty() or node.is_leaf:
		indices.append(get_node_index(node))
	if node.is_inner:
		for child in node.children:
			get_indices(child, indices)

	return indices


## Returns an array of nodes that descend from a given node .
func get_subnodes(node : BVHNode, indices : Array[BVHNode] = []) -> Array[BVHNode]:
	 # NOTE: Unlike python, an array as a default parameter is an unique instance
	if indices.is_empty() or node.is_leaf:
		indices.append(node)
	if node.is_inner:
		for child in node.children:
			get_subnodes(child, indices)

	return indices


## Sets tree indices of tree for newly created node
func index_node(node : BVHNode) -> void:
	# I don't like this function
	# TODO Change to recursive indexing if we have nested sub-trees
	#assert(node.tree == self, "The given node is not a part of this tree or is in" +
			#"a sub-tree. Please use the sub-tree's methods instead.")
	if node.is_inner:
		for child in node.children:
			child.parent = node
	else:
		for object in node.object_list:
			object_to_leaf[object] = node # UNSTATIC
			if is_sub_tree():
				parent_tree.object_to_leaf[object] = node # UNSTATIC

		if not node in leaf_nodes:
			leaf_nodes.append(node)
			if is_sub_tree():
				parent_tree.leaf_nodes.append(node)

	if not node in _node_to_index:
		_node_to_index[node] = bvh_list.size() # UNSTATIC
		bvh_list.append(node)

		if is_sub_tree():
			parent_tree._node_to_index[node] = parent_tree.bvh_list.size() # UNSTATIC
			parent_tree.bvh_list.append(node)


## Sets the required indexes for the BVHTree to work with the engine
func index_tree() -> void:
	# NOTE: Should be used as little as possible for best performance
	print("bvhtree re-indexed")
	var start_time := Time.get_ticks_usec()
	bvh_list = []
	leaf_nodes = []
	object_to_leaf = {}
	_node_to_index = {}
	inner_count = 0
	leaf_count = 0
	object_count = 0

	_node_to_index[root_node] = bvh_list.size() # UNSTATIC
	bvh_list.append(root_node)
	inner_count += 1

	_index_node(root_node)
	print("Time taken: ", ((Time.get_ticks_usec() - start_time) / 1000.0), "ms")


## Recursively index whole tree/sub-tree under given node
func _index_node(node : BVHNode) -> void:
	for child in node.children:
		_node_to_index[child] = bvh_list.size() # UNSTATIC
		bvh_list.append(child)

		if child.is_leaf:
			leaf_nodes.append(child)
			leaf_count += 1
			object_count += child.object_list.size()
			for object in child.object_list:
				object_to_leaf[object] = child # UNSTATIC
		else:
			inner_count += 1

	for child in node.children:
		if child.is_inner:
			_index_node(child)


## Finds a non-full inner node recursively
func find_inner_node(node : BVHNode) -> BVHNode:
	assert(node.tree == self, "The given node is not a part of this tree or is in" +
			"a sub-tree. Please use the sub-tree's methods instead.")
	if node.is_leaf:
		return null
	if node.size() < order:
		return node
	else:
		# If inner node is full, check its children
		for child in node.children:
			var temp : BVHNode
			if child.tree != self:
				# TODO I don't think i should do this, just return
				temp = child.tree.find_inner_node(child)
			else:
				temp = find_inner_node(child)
			if is_instance_valid(temp):
				return temp
	return null # If no inner nodes have room return null


## If a node is empty add it to return list and recursively call parents.
## Returns an array of nodes that can be removed. They are not changed by the function
func node_cleanup(node : BVHNode, cleaned_nodes : Array[BVHNode] = []) -> Array[BVHNode]:
	if node.size() == 0:
		cleaned_nodes.append(node)
		return node_cleanup(node.parent)
	# If child is the empty node that called this function
	if node.is_inner and node.size() == 1 and node.children[0] in cleaned_nodes:
		cleaned_nodes.append(node)
		return node_cleanup(node.parent)

	return []


## Splits a node in two, dividing its children/objects evenly among two new nodes.
## If the given node is a leaf node so are the new nodes, else they are also inner nodes.
## Returns these new nodes.
func _split_node(node : BVHNode) -> Array[BVHNode]:
	# TODO Needs a lot of cleanup to work with new bvhnode continuity stuff
	assert(node.tree == self, "The given node is not a part of this tree or is in" +
			"a sub-tree. Please use the sub-tree's methods instead.")
	var new_node_left := BVHNode.new(node, self)
	var new_node_right := BVHNode.new(node, self)

	new_node_left.is_inner = node.is_inner
	new_node_right.is_inner = node.is_inner

	if node.is_inner:
		@warning_ignore("integer_division")
		var halfway := node.children.size() / 2
		new_node_left.add_children(node.children.slice(0, halfway))
		new_node_right.add_children(node.children.slice(halfway))

		node.children.clear()

		inner_count += 2
	else:
		@warning_ignore("integer_division")
		var halfway := node.object_list.size() / 2
		new_node_left.object_list.append_array(node.object_list.slice(0, halfway))
		new_node_left.object_list.append_array(node.object_list.slice(halfway))

		# Remove leaf node references in node
		node.object_list.clear()
		leaf_nodes.erase(node)
		if is_sub_tree():
			parent_tree.leaf_nodes.erase(node)
		node.is_inner = true

		inner_count += 1
		leaf_count += 1

	node.add_children([new_node_left, new_node_right])
	append_updated_node_index(get_node_index(node))

	return [new_node_left, new_node_right]


## Index the result of _split_node
func _split_node_index(nodes : Array[BVHNode]) -> Array[BVHNode]:
	var left := nodes[0]
	var right := nodes[1]

	append_updated_node_index(get_node_index(left))
	left.set_aabb()
	right.update_aabb()

	index_node(left)
	index_node(right)

	return nodes


## Splits a node in two, dividing its children/objects evenly among two new nodes.
## Returns these new nodes.
func split_node(node : BVHNode) -> Array[BVHNode]:
	return _split_node_index(_split_node(node))


## Based on an AABB, finds a spot in the tree where it is fully enclosed
## by a node's AABB if there is one. If not then return null.
## The function does not account for whether the found node is full or not.
## NOTE: This is a greedy search algorithm and it will return the first spot
##  that is good enough
func find_aabb_spot(aabb : AABB, node := root_node) -> BVHNode:
	if node.aabb.encloses(aabb):
		if node.is_inner:
			for child in node.children:
				var temp_node := find_aabb_spot(aabb, child)
				if is_instance_valid(temp_node):
					# Return the first child that encloses aabb
					return temp_node
		# node fits, but none of its children (if it has children) does
		return node

	# We found no nodes that fit
	return null



## Merge another BVHTree into this one.
## Return new nodes that need to be added to bvh_list.
func _merge_with(other : PTBVHTree, root := root_node) -> Array[BVHNode]:
	# Find inner node to place other
	var fitting_node := find_aabb_spot(other.root_node.aabb, root)
	var new_nodes : Array[BVHNode] = other.bvh_list.duplicate()

	if fitting_node == null:
		fitting_node = root_node

	# If node is full or a leaf, split and get non-full fitting node
	if fitting_node.is_full() or fitting_node.is_leaf:
		if PTRendererAuto.is_debug:
			print("No vacant leaf node to add new object. Splitting node in two.")
		#new_nodes.append_array(_split_node(fitting_node))
		split_node(fitting_node)
		fitting_node = find_aabb_spot(other.root_node.aabb, fitting_node)

		if fitting_node == null:
			fitting_node = root_node

	create_mesh_socket(fitting_node, other)

	# Update indices
	object_to_leaf.merge(other.object_to_leaf)
	leaf_nodes.append_array(other.leaf_nodes)
	# TODO FIX NOTE THis gets reindexed correctly in the public function
	_node_to_index.merge(other._node_to_index)

	object_count += other.object_count
	leaf_count += other.leaf_count
	inner_count += other.inner_count

	other.parent_tree = self

	return new_nodes
	# TODO Add print/assert to verify succesfull merge


## Inserts another tree at a node in the bvh.
## An optional argument root can be given, the insertion will
##  happen to one of its children
## Only a scene bvh can merge mesh bvhs. Scene bvhs cannot merge.
func merge_with(other : PTBVHTree, root := root_node) -> void:
	assert(not is_mesh_owned(), "A mesh BVH cannot merge with another BVH.")
	assert(other.is_mesh_owned(), "A scene BVH cannot merge with another scene BVH.")

	if order < other.order:
		push_error("PT: BVH order ", order, " of scene does not ",
		"allow for BVH order ", other.order, " of mesh.")
		return
	elif order > other.order:
		# TODO Add editor warning for mismatched bvh orders
		push_warning("PT: BVH order of mesh is ", other.order, ", ",
		"while BVH order of scene is ", order, ".\n Mesh BVH order ",
		"will be changed to ", order, ".")
		other.order = order

	var new_nodes := _merge_with(other, root)

	var index_offset := bvh_list.size()
	bvh_list.append_array(new_nodes)

	# Reindexing
	for node : BVHNode in new_nodes:
		_node_to_index[node] += index_offset # UNSTATIC


func _remove_node(node : BVHNode) -> void:
	#assert(node.tree == self, "The given node is not a part of this tree or is in" +
			#"a sub-tree. Please use the sub-tree's methods instead.")
	# TODO Remember to reindex / or fill hole with last node + fix indices
	bvh_list.remove_at(get_node_index(node))
	_node_to_index.erase(node)
	if node.is_inner:
		for child in node.children:
			_remove_node(child)
		inner_count -= 1
	else:
		leaf_nodes.erase(node)
		for object in node.object_list:
			object_to_leaf.erase(object)
			object_count -= 1
		leaf_count -= 1


## Remove all nodes that are descendants of a given node from the tree
func remove_subtree(node : BVHNode) -> void:
	# TODO Make recursive function to find any sub-trees that are removed in the process
	# TODO Also this function almost certainly doesn't work properly
	assert(node.tree == self or node == node.tree.root_node,
			"The given node is not a part of this tree or is the root node of a " +
			"sub-tree. Please use the sub-tree's methods instead.")
	# Remove from parent node
	node.parent.children.erase(node)

	var index : int = _node_to_index[node] # UNSTATIC
	_remove_node(node)

	# Reindex all nodes from index to end of bvh_list
	for i in range(index, bvh_list.size()):
		_node_to_index[bvh_list[i]] = i # UNTSTATIC


# TODO Make a test
func is_memory_contiguous() -> bool:
	if not is_children_contiguous(root_node):
		return false

	return _recursive_is_contiguous(root_node)


func _recursive_is_contiguous(node : BVHNode) -> bool:
	for child in node.children:
		if child.is_inner:
			if not is_children_contiguous(child):
				return false

	return true


func is_children_contiguous(node : BVHNode) -> bool:
	if node.is_leaf:
		return false

	var prev_child_index : int = _node_to_index[node.children[0]]
	for child in node.children:
		if _node_to_index[child] - prev_child_index in [0, 1]:
			return false

	return true


## Returns the total bumber of nodes in the tree
func size() -> int:
	return inner_count + leaf_count


## Returns the length of the longest path from the root to a leaf node
func get_depth() -> int:
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


func create_object_ids() -> void:
	assert(is_scene_owned(), "Cannot create_object_ids without a valid set scene.")

	var index := 0
	object_ids.resize(object_count)

	for leaf_node in leaf_nodes:
		leaf_node.object_id_index = index
		for object in leaf_node.object_list:
			var id := PTObject.make_object_id(get_scene().get_object_index(object), object.get_type())
			object_ids[index] = id
			index += 1


func to_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	for node in bvh_list:
		bytes += node.to_byte_array()
	return bytes


class BVHNode:
	## This class represents a Node in a bvh tree.
	##
	## Ideally all bvh trees would use the same Node class, since their only
	## intention is to hold information.
	##
	## A BVHNode is either an inner node, where the children property point to
	## other BVHNodes or is empty, or a leaf node, where its object_list property point to
	## objects. Having a mixed node is no longer supported.
	## Rather, wrap the objects in the mixed node into a new leaf node child.

	var tree : PTBVHTree # Reference to the tree this node is a part of
	var parent : BVHNode # Reference to parent BVHNode
	var children : Array[BVHNode] # Reference to child BVHNodes
	var aabb : AABB

	# A mesh socket is a special node that only has a subtree as a child.
	# It has special rules for its aabb
	var is_mesh_socket := false

	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than tree.order
	var object_list : Array[PTObject] = []

	## NOTE TODO This information should not be stored on node. It should be gotten
	## from tree / from parent tree. Or maybe it's fine. Just to remember to update.
	## Index to the leaf node's start position in the tree's object_ids
	var object_id_index := 0

	var is_inner := true
	var is_leaf : bool:
		get:
			return not is_inner
		set(value):
			is_leaf = value
			is_inner = not value


	func _init(p_parent : BVHNode, p_tree : PTBVHTree) -> void:
		parent = p_parent
		tree = p_tree


	## Returns number of children and number of references to objects
	func size() -> int:
		return children.size() + object_list.size()


	func is_full() -> bool:
		if is_inner:
			assert(children.size() <= tree.order,
					"BVHNode has more children than tree.order allows.")
			return children.size() == tree.order

		assert(object_list.size() <= tree.order,
					"BVHNode has more children than tree.order allows.")
		return object_list.size() == tree.order


	func set_aabb() -> void:
		if is_mesh_socket:
			assert(children[0].aabb != null and children[0].aabb.size != Vector3.ZERO)
			aabb =  children[0].tree.get_mesh().transform * children[0].aabb
			return

		if is_leaf and not object_list.is_empty():
			aabb = object_list[0].get_bvh_aabb()
			for object in object_list:
				aabb = aabb.merge(object.get_bvh_aabb())
			assert(aabb != null and aabb.size != Vector3.ZERO,
					"PT: Leaf node did not create aabb correctly")
			return

		if not children.is_empty():
			aabb = children[0].aabb
			for child in children:
				assert(aabb != null and aabb.size != Vector3.ZERO,
						"PT: Child node %s does not have aabb" % child)
				aabb = aabb.merge(child.aabb)


	func update_aabb() -> void:
		var old_aabb := aabb
		set_aabb()
		if not aabb.is_equal_approx(old_aabb):
			if tree.is_sub_tree():
				tree.parent_tree.queue_node_update(self)
			else:
				tree.queue_node_update(self)
			if is_instance_valid(parent):
				parent.update_aabb()


	func add_children(new_children : Array[BVHNode]) -> void:
		assert(is_inner, "Cannot give inner node objects.")
		if size() + new_children.size() <= tree.order:
			children += new_children
			set_aabb()
		else:
			push_warning("Warning: Cannot fit child BVHNode(s) to node: ", self)


	func to_byte_array() -> PackedByteArray:
		assert(size() > 0,
			"PT: Node does not have any children or objects and should be culled")

		var root_tree := tree

		if root_tree.is_sub_tree():
			root_tree = root_tree.parent_tree

		var check_node_index := func() -> bool:
			var temp : Array[int] = []
			for i in children:
				temp.append(root_tree.get_node_index(i))

			return root_tree.get_node_index(children[0]) == temp.min()

		var node_index := 0
		var node_size := 0
		if is_inner:
			# TODO FIX This shouldn't update every frame but it does
			assert(check_node_index.call(), "Node children are not in correct order. First child should be first index.")
			# FIrst child SHOULD be first index, maybe add assert
			node_index = root_tree.get_node_index(children[0])
			node_size  = children.size()

		# TODO Object_ids can be packed tightly or with fixed size for potential perf gain, check
		if is_leaf:
			# minus one to guarantee negative number because bit manip stuff
			node_index = -object_id_index - 1
			node_size = object_list.size() - 1

		assert(node_size <= 128, "BVHNode cannot contain more than 128 nodes/objects.")
		assert(abs(node_index) <= 16_777_216, "BVHNode cannot have index bigger than 16_777_216")
		node_index ^= node_size << 24

		var mesh_transform_index := -1
		if is_mesh_socket:
			var mesh := children[0].tree.get_mesh()
			mesh_transform_index = mesh.scene.get_mesh_index(mesh)
			assert(mesh_transform_index >= 0, "Mesh was not found in Scenes's meshes")

		var bbox_bytes : PackedByteArray = PTUtils.aabb_to_byte_array(aabb, node_index, mesh_transform_index)
		var bytes := bbox_bytes
		assert(bytes.size() == PTBVHTree.NODE_BYTE_SIZE,
				"Acutal byte size and set byte size do not match. set:" +
				str(PTBVHTree.NODE_BYTE_SIZE) +" actual " + str(bytes.size()))

		return bytes
