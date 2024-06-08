@tool
class_name PTBVHTree
extends Node
# Can potentially be Refcounted

# TODO If i turn BVHNodes into actual nodes i can save and load BVHTrees
# TODO Alternatively look at inst_to_dict for serialization, or var_to_bytes

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

## Enum of different possible BVH algorithms, should be updated as more algortithms
##  are added. Only positive numbers (and zero) are allowed as values.
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
	"X-Axis Sorted" : PTBVHAxisSort.x_axis_sorted,
	"Y-Axis Sorted" : PTBVHAxisSort.y_axis_sorted,
	"Z-Axis Sorted" : PTBVHAxisSort.z_axis_sorted,
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

# TODO Implement transforms for bvhnodes

# TODO Fix support for multi order trees
var order : int

# BVHTrees can merge, parent_tree is the BVH this tree was merged with
var parent_tree : PTBVHTree
var is_sub_tree : bool:
	get:
		return is_instance_valid(parent_tree)

var root_node : BVHNode

var object_container : PTObjectContainer
var object_to_leaf := {}
var leaf_nodes : Array[BVHNode]

## Takes in a node gives its index in bvh_list
var _node_to_index := {}

# TODO Add bvh constructor with bvh_list as argument
var bvh_list : Array[BVHNode] = []

var leaf_count : int # Counts nodes with no child nodes
var inner_count : int # Counts nodes with child nodes, including root node
var object_count : int # Counts the number of objects stored in leaf nodes

# NOTE: how to handle meshes with different types
var type : BVHType
var creation_time : int # In usecs
var SAH_cost : float

var updated_nodes : Array[BVHNode] = [] # Nodes that need to update their buffer
# TODO MAke BVHBUffer abler to expand + have empty space


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
	var start_time : int = Time.get_ticks_usec()
	var bvh : PTBVHTree = tempt.call(objects, _order) # UNSTATIC
	bvh.creation_time = (Time.get_ticks_usec() - start_time)
	return bvh


func update_aabb(object : PTObject) -> void:
	if has(object):
		var node : BVHNode = object_to_leaf[object] # UNSTATIC
		node.update_aabb()
	else:
		push_warning("PT: Cannot update the aabb of an object that is not in BVH.\n",
				"object: ", object)


func has(object : PTObject) -> bool:
	return object_to_leaf.has(object)


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

	# TODO Change to local aabb when using meshes + transforms
	var fitting_node := find_aabb_spot(object.get_global_aabb())

	# If node is full, split and get non-full fitting node
	if fitting_node.is_full:
		split_node(fitting_node)
		fitting_node = find_aabb_spot(object.get_global_aabb(), fitting_node)

	# Add object to node
	if fitting_node.is_inner:
		var new_node := BVHNode.new(fitting_node, self)
		new_node.object_list.append(object)
		new_node.set_aabb()
		fitting_node.add_children([new_node])
		index_node(new_node)
	else:
		fitting_node.object_list.append(object)
		index_node(fitting_node)

	fitting_node.update_aabb()

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
	assert(node.tree == self)
	return _node_to_index[node] # UNSTATIC


## Sets tree indices of tree for newly created node
func index_node(node : BVHNode) -> void:
	assert(node.tree == self)
	if node.is_inner:
		for child in node.children:
			child.parent = node
	else:
		for object in node.object_list:
			object_to_leaf[object] = node # UNSTATIC
			if is_sub_tree:
				parent_tree.object_to_leaf[object] = node # UNSTATIC

		if not node in leaf_nodes:
			leaf_nodes.append(node)
			if is_sub_tree:
				parent_tree.leaf_nodes.append(node)

	if not node in _node_to_index:
		_node_to_index[node] = bvh_list.size() # UNSTATIC
		bvh_list.append(node)

		if is_sub_tree:
			parent_tree._node_to_index[node] = parent_tree.bvh_list.size() # UNSTATIC
			parent_tree.bvh_list.append(node)


## Sets the required indexes required for the BVHTree to work with the engine
func index_tree() -> void:
	bvh_list = []
	leaf_nodes = []
	object_to_leaf = {}
	_node_to_index = {}
	inner_count = 0
	leaf_count = 0
	object_count = 0

	_index_node(root_node)


## Recursively index whole tree/sub-tree under given node
func _index_node(node : BVHNode) -> void:
	assert(node.tree == self)
	_node_to_index[node] = bvh_list.size() # UNSTATIC
	bvh_list.append(node)
	inner_count += 1

	for child in node.children:
		if child.is_leaf:
			_node_to_index[child] = bvh_list.size()  # UNSTATIC
			bvh_list.append(child)
			leaf_nodes.append(child)

			leaf_count += 1
			object_count += child.object_list.size()
			for object in child.object_list:
				object_to_leaf[object] = child # UNSTATIC
			continue

		_index_node(child)


## Finds a non-full inner node
func find_inner_node(node : BVHNode) -> BVHNode:
	assert(node.tree == self)
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


## Splits a node in two, dividing its children/objects evenly among two new nodes.
## Returns these new nodes.
func split_node(node : BVHNode) -> Array[BVHNode]:
	assert(node.tree == self)
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
		if is_sub_tree:
			parent_tree.leaf_nodes.erase(node)
		node.is_inner = true

		inner_count += 1
		leaf_count += 1

	node.add_children([new_node_left, new_node_right])

	updated_nodes.append(node)
	updated_nodes.append(new_node_left)
	new_node_left.set_aabb()
	new_node_right.update_aabb() # Also calls updated_nodes.append

	index_node(new_node_left)
	index_node(new_node_right)

	return [new_node_left, new_node_right]


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
	_node_to_index.merge(other._node_to_index)
	leaf_nodes.append_array(other.leaf_nodes)

	# Reindexing
	for node : BVHNode in other._node_to_index: # UNSTATIC
		_node_to_index[node] += index_offset # UNSTATIC

	object_count += other.object_count
	leaf_count += other.leaf_count
	inner_count += other.inner_count

	other.parent_tree = self

	# TODO Add print/assert to verify succesfull merge


func _remove_node(node : BVHNode) -> void:
	assert(node.tree == self)
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
	assert(node.tree == self)
	# Remove from parent node
	node.parent.children.erase(node)

	var index : int = _node_to_index[node] # UNSTATIC
	_remove_node(node)

	# Reindex all nodes from index to end of bvh_list
	for i in range(index, bvh_list.size()):
		_node_to_index[bvh_list[i]] = i # UNTSTATIC


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
	## other BVHNodes, or a leaf node, where its object_list property point to
	## objects. Having a mixed node is technically supported, but is unadviced.
	## Rather, wrap the objects in the mixed node into a new leaf node child.

	var tree : PTBVHTree # Reference to the tree this node is a part of
	var parent : BVHNode # Reference to parent BVHNode
	var children : Array[BVHNode] # Reference to child BVHNodes
	var aabb : AABB

	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than tree.order
	var object_list : Array[PTObject] = []
	var is_leaf := false
	var is_inner : bool:
		get:
			return not is_leaf
		set(value):
			is_inner = value
			is_leaf = not value

	var is_full : bool:
		get:
			if is_inner:
				assert(children.size() <= tree.order,
						"BVHNode has more children than tree.order allows.")
				return children.size() == tree.order

			assert(object_list.size() <= tree.order,
						"BVHNode has more children than tree.order allows.")
			return object_list.size() == tree.order


	func _init(p_parent : BVHNode, p_tree : PTBVHTree) -> void:
		parent = p_parent
		tree = p_tree


	func size() -> int:
		"""Returns number of children and number of references to objects"""
		return children.size() + object_list.size()


	func set_aabb() -> void:
		if is_leaf and not object_list.is_empty():
			aabb = object_list[0].get_global_aabb()
			for object in object_list:
				aabb = aabb.merge(object.get_global_aabb())
			return

		if not children.is_empty():
			aabb = children[0].aabb
			for child in children:
				if child.aabb:
					aabb = aabb.merge(child.aabb)
				else:
					push_warning("Warning: Child node %s does not have aabb" % child)


	func update_aabb() -> void:
		var old_aabb = aabb
		set_aabb()
		# Intentional floating point inequality check
		if aabb != aabb:
			tree.updated_nodes.append(self)
			if is_instance_valid(parent):
				parent.update_aabb()


	func add_children(new_children : Array[BVHNode]) -> void:
		if size() + new_children.size() <= tree.order:
			children += new_children
			set_aabb() # Update aabb
		else:
			push_warning("Warning: Cannot fit child BVHNode(s) to node: ", self)


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


